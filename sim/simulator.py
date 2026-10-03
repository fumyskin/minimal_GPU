"""Lane-accurate SIMD simulator for the frozen ISA. Executes the actual machine
code across N masked lanes, exactly as the RTL will. This is the golden
reference the Phase 3 hardware gets diffed against.

Run:  python simulator.py
"""

import argparse
import fixedpoint as fp
import isa
import image
import palette

# The frozen reference kernel (see isa_spec.md sec.5). CX0/CY0/FB_BASE are
# per-launch parameters; DX and MAX_ITER are assemble-time defines.
KERNEL = """
        MASKALL
        LANEID  V9
        LI      V0, CX0
        LI      V8, DX
        MUL     V8, V9, V8
        ADD     V0, V0, V8
        LI      V1, CY0
        LI      V2, #0
        LI      V3, #0
        LI      V7, #0
        LI      V10, 4.0
        LI      V12, #1
        SETLOOP MAX_ITER
loop:   MUL     V4, V2, V2
        MUL     V5, V3, V3
        ADD     V11, V4, V5
        ADD     V7, V7, V12
        ESCAPE  V11, V10
        MUL     V6, V2, V3
        ADD     V6, V6, V6
        SUB     V8, V4, V5
        ADD     V8, V8, V0
        ADD     V6, V6, V1
        MOV     V2, V8
        MOV     V3, V6
        ENDLOOP loop
        STORE   V7, FB_BASE
        HALT
"""


class GPU:
    def __init__(self, n_lanes, fb_size):
        self.N = n_lanes
        self.V = [[0] * n_lanes for _ in range(16)]
        self.M = [1] * n_lanes
        self.LC = 0
        self.PC = 0
        self.fb = bytearray(fb_size)
        self.halted = False

    def run(self, code, max_steps=5_000_000):
        self.PC, self.halted, steps = 0, False, 0
        while not self.halted:
            if self.PC >= len(code):
                raise RuntimeError("PC ran past the program without HALT")
            self._exec(code[self.PC])
            steps += 1
            if steps > max_steps:
                raise RuntimeError("step limit exceeded -- runaway loop?")

    def _exec(self, word):
        O = isa.OPCODES
        opc, rd, ra, rb, imm = isa.decode(word)
        N, V, M = self.N, self.V, self.M
        advance = True

        if opc == O["NOP"]:
            pass
        elif opc == O["LI"]:
            raw = isa.decode_li_raw(word)
            for k in range(N):
                V[rd][k] = raw
        elif opc == O["LANEID"]:
            for k in range(N):
                V[rd][k] = k << fp.F
        elif opc == O["MOV"]:
            for k in range(N):
                if M[k]:
                    V[rd][k] = V[ra][k]
        elif opc == O["ADD"]:
            for k in range(N):
                if M[k]:
                    V[rd][k] = fp.fadd(V[ra][k], V[rb][k])
        elif opc == O["SUB"]:
            for k in range(N):
                if M[k]:
                    V[rd][k] = fp.fsub(V[ra][k], V[rb][k])
        elif opc == O["MUL"]:
            for k in range(N):
                if M[k]:
                    V[rd][k] = fp.fmul(V[ra][k], V[rb][k])
        elif opc == O["ESCAPE"]:
            for k in range(N):
                if M[k] and V[ra][k] > V[rb][k]:
                    M[k] = 0
        elif opc == O["MASKALL"]:
            for k in range(N):
                M[k] = 1
        elif opc == O["SETLOOP"]:
            self.LC = imm
        elif opc == O["ENDLOOP"]:
            self.LC = (self.LC - 1) & 0x3FFF
            if self.LC != 0 and any(M):
                self.PC, advance = imm, False
        elif opc == O["STORE"]:
            for k in range(N):
                self.fb[imm + k] = V[ra][k] & 0xFF
        elif opc == O["HALT"]:
            self.halted = True
        else:
            raise RuntimeError(f"bad opcode {opc:#x} at PC={self.PC}")

        if advance and not self.halted:
            self.PC += 1


def oracle(cx0_raw, cy_raw, lane, dx_raw, max_iter):
    """Independent per-pixel reference using the SAME hardware coordinate gen:
    cx = cx0 + lane*dx in fixed point. Proves the interpreter, not the math."""
    cx = fp.fadd(cx0_raw, fp.fmul(lane << fp.F, dx_raw))
    cy = cy_raw
    x = y = color = 0
    for _ in range(max_iter):
        x2, y2 = fp.fmul(x, x), fp.fmul(y, y)
        mag = fp.fadd(x2, y2)
        color += 1
        if mag > fp.FOUR:
            break
        xy2 = fp.fadd(fp.fmul(x, y), fp.fmul(x, y))
        x, y = fp.fadd(fp.fsub(x2, y2), cx), fp.fadd(xy2, cy)
    return color & 0xFF


def render(width, height, view, n_lanes, max_iter, verify=True):
    assert width % n_lanes == 0, "width must be a multiple of the lane count"
    assert width * height <= (1 << 14), "framebuffer exceeds 14-bit STORE address"
    fp.set_mode(18, 14, "sat")
    x0, x1, y0, y1 = view
    dx, dy = (x1 - x0) / width, (y1 - y0) / height
    dx_raw = fp.to_fixed(dx)

    code, params, _ = isa.assemble(KERNEL, defines={"MAX_ITER": max_iter, "DX": dx})
    gpu = GPU(n_lanes, width * height)

    mismatches = 0
    for row in range(height):
        cy = y0 + row * dy
        cy_raw = fp.to_fixed(cy)
        for col0 in range(0, width, n_lanes):
            cx0_raw = fp.to_fixed(x0 + col0 * dx)
            isa.patch(code, params["CX0"], cx0_raw)
            isa.patch(code, params["CY0"], cy_raw)
            isa.patch(code, params["FB_BASE"], row * width + col0)
            gpu.run(code)
            if verify:
                for k in range(n_lanes):
                    if gpu.fb[row * width + col0 + k] != oracle(cx0_raw, cy_raw, k, dx_raw, max_iter):
                        mismatches += 1
    return gpu.fb, mismatches


def scanout(fb, cw, ch, scale, rom):
    """Model the VGA scan-out hardware: 5x pixel replication + palette ROM.
    Display pixel (X,Y) shows framebuffer pixel (X//scale, Y//scale) -- in RTL
    that's two mod-scale counters, no divider. Returns the exact RGB888 the
    monitor shows (4-bit channels expanded for the PNG)."""
    dw, dh = cw * scale, ch * scale
    out = bytearray(dw * dh * 3)
    for Y in range(dh):
        srow = (Y // scale) * cw
        for X in range(dw):
            r, g, b = palette.rgb12_to_rgb888(*rom[fb[srow + (X // scale)]])
            o = (Y * dw + X) * 3
            out[o], out[o + 1], out[o + 2] = r, g, b
    return out, dw, dh


def main():
    ap = argparse.ArgumentParser(description="SIMD sim + Approach A VGA preview")
    ap.add_argument("--width", type=int, default=128, help="compute width")
    ap.add_argument("--height", type=int, default=96, help="compute height")
    ap.add_argument("--scale", type=int, default=5, help="pixel-replication factor")
    ap.add_argument("--max-iter", type=int, default=100)
    ap.add_argument("--lanes", type=int, default=4)
    ap.add_argument("--out", default="sim_render")
    args = ap.parse_args()

    x0, x1 = -2.5, 1.0
    span_y = (x1 - x0) * args.height / args.width      # 4:3 to match 640x480
    view = (x0, x1, -span_y / 2, span_y / 2)

    fb, mismatches = render(args.width, args.height, view, args.lanes, args.max_iter)
    rom = palette.build_rom(args.max_iter)
    rgb, dw, dh = scanout(fb, args.width, args.height, args.scale, rom)

    image.write_raw(args.out + ".bin", fb)                                  # golden FB
    image.write_png(args.out + "_fb.png", fb, args.width, args.height, args.max_iter)
    image.write_rgb_png(args.out + "_vga.png", rgb, dw, dh)                 # monitor preview
    palette.export_mem(rom, args.out + "_palette.mem")                      # for the HW ROM

    print(f"compute {args.width}x{args.height} -> display {dw}x{dh} ({args.scale}x)  "
          f"lanes={args.lanes}  max_iter={args.max_iter}")
    print(f"interpreter vs oracle mismatches: {mismatches}")
    print(f"wrote {args.out}.bin, {args.out}_fb.png, {args.out}_vga.png, {args.out}_palette.mem")


if __name__ == "__main__":
    main()