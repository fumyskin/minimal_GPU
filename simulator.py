import argparse
import struct

# Q4.14
# fixed 

# fixed point data
W = 18
F = 14
ARITH = "sat" #sat = saturate, wrap = two's complement wraparound

INT_MIN = -(1<<(W-1)) 
INT_MAX = (1<<(W-1)) - 1
ONE = 1 << F
FOUR = 4 << F # python interpets 4 as binary !

def _reconfig(w, f, arith):
    global W, F, ARITH, INT_MIN, INT_MAX, ONE, FOUR
    W = w
    F = f
    ARITH = arith
    INT_MIN = -(1<<(W-1))
    INT_MAX = (1<<(W-1)) - 1
    ONE = 1 << F
    FOUR = 4 << F


def clamp(v):
    if ARITH == "sat":
        if v > INT_MAX:
            return INT_MAX
        if v < INT_MIN:
            return INT_MIN
        return v
    v &= (1 << W) - 1
    return v - (1 << W) if (v & (1 << (W-1))) else v

def to_fixed(real):
    # real -> raw fixed-point. Done at 'compile time' by the host, so rounding a constant here is fine
    # the datapath never does this.
    return clamp(int(round(real * ONE)))

def fadd(a, b):
    return clamp(a + b)

def fsub(a, b):
    return clamp(a - b)

def fmul(a, b):
    return clamp((a * b) >> F)


# Mandelbrot escape-time kernel, written to match the SIMD ISA kernel
def escape_iterations(cx, cy, max_iter):
    x = 0
    y = 0
    color = 0
    escaped = False

    for _ in range(max_iter):
        x2 = fmul(x, x)                 # MUL V4, V2, V2
        y2 = fmul(y, y)                 # MUL V5, V3, V3
        mag = fadd(x2, y2)              # ADD V11, V4, V5
        color += 1                      # ADD V7, V7, 1
        if mag > FOUR:                  # ESCAPE V11, V10
            escaped = True              
            break
        xy = fmul(x, y)                 # MUL V6, V2, V3
        two_xy = fadd(xy, xy)           # ADD V6, V6, V6 (2xy)
        x_new = fadd(fsub(x2, y2), cx)  # SUB then ADD cx (x^2 - y^2 + cx)
        y_new = fadd(two_xy, cy)        # ADD cy (2xy + cy)
        x, y = x_new, y_new             # MOV V2/V3 (masked commit)
    return color, escaped



def render(width, height, max_iter, view):
    x0, x1, y0, y1 = view
    dx = (x1-x0) / width
    dy = (y1-y0) / height
    fb = bytearray(width*height) #framebuffer
    for py in range(height):
        cy = to_fixed(y0 + py * dy)
        base = py * width
        for px in range(width):
            cx = to_fixed(x0 + px * dx)
            color, escaped = escape_iterations(cx, cy, max_iter)
            fb[base + px] = (color & 0xFF) if escaped else 0   # inside set -> 0
    return fb


def palette(v, max_iter):
    """Smooth display palette. v==0 (inside the set) -> black."""
    if v == 0:
        return (0, 0, 0)
    t = v / max_iter
    r = int(9 * (1 - t) * t * t * t * 255)
    g = int(15 * (1 - t) * (1 - t) * t * t * 255)
    b = int(8.5 * (1 - t) * (1 - t) * (1 - t) * t * 255)
    return (min(r, 255), min(g, 255), min(b, 255))
 


def write_raw(path, fb):
    """The raw 8-bit framebuffer -- this is what you'll diff RTL output against."""
    with open(path, "wb") as f:
        f.write(fb)
 
 
def write_png(path, fb, width, height, max_iter):
    """Minimal zlib+PNG writer (no third-party deps) for a quick visual check."""
    import zlib
    raw = bytearray()
    for py in range(height):
        raw.append(0)                      # filter type 0 for the scanline
        base = py * width
        for px in range(width):
            raw += bytes(palette(fb[base + px], max_iter))
 
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
 
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))
 
 
def main():
    ap = argparse.ArgumentParser(description="Fixed-point Mandelbrot golden model")
    ap.add_argument("--width", type=int, default=320)
    ap.add_argument("--height", type=int, default=240)
    ap.add_argument("--max-iter", type=int, default=100)
    ap.add_argument("--bits", type=int, default=18, help="total word width W")
    ap.add_argument("--frac", type=int, default=14, help="fractional bits F")
    ap.add_argument("--arith", choices=["sat", "wrap"], default="sat")
    ap.add_argument("--out", default="mandelbrot")
    args = ap.parse_args()
 
    _reconfig(args.bits, args.frac, args.arith)
 
    # Classic full view, aspect-matched to the image
    x0, x1 = -2.5, 1.0
    span_y = (x1 - x0) * args.height / args.width
    y0, y1 = -span_y / 2, span_y / 2
    view = (x0, x1, y0, y1)
 
    fb = render(args.width, args.height, args.max_iter, view)
    write_raw(args.out + ".bin", fb)
    write_png(args.out + ".png", fb, args.width, args.height, args.max_iter)
    print(f"Q{args.bits - args.frac}.{args.frac}  arith={args.arith}  "
          f"{args.width}x{args.height}  max_iter={args.max_iter}")
    print(f"wrote {args.out}.bin (raw 8-bit framebuffer) and {args.out}.png")
 
 
if __name__ == "__main__":
    main()
 

