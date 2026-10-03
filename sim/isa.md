# SIMD Mandelbrot GPU — Frozen ISA Specification (v1.1)

Changelog: v1.1 — `MASKALL` moved to the top of the kernel. The mask persists
across launches, so the masked coordinate-setup instructions (`MUL`/`ADD`) must
run with the mask already asserted; otherwise a later strip computes stale
coordinates for lanes that escaped in the previous strip. Caught by the Phase 2
oracle. No encoding or opcode change.

Status: **FROZEN.** This document is the single source of truth for the
instruction set. The assembler, the Phase 2 lane-accurate simulator, and the
RTL decoder are all built against it and must agree bit-for-bit. Change it only
by bumping the version and updating all three consumers together.

The instruction set is deliberately application-specific: it does exactly what
the Mandelbrot kernel needs and nothing more.

---

## 1. Fixed-point format

- Word width `W = 18` bits, signed two's complement (fits the DSP48E1 18-bit port).
- Fractional bits `F = 14` → **Q4.14**, range [−8, +8), resolution 2⁻¹⁴.
- Real value of a raw word `r` is `r / 2¹⁴`.
- **Add / subtract: saturating.** On overflow, clamp to the signed 18-bit
  min/max — never wrap. (A wrapping adder lets an overflowing `x²+y²` fold back
  below the escape threshold, so the pixel never escapes. Saturation only ever
  triggers for already-escaping pixels, whose results are masked off, so
  surviving trajectories are unaffected.)
- **Multiply:** full 36-bit product, arithmetic shift right by `F` (truncate
  toward −∞), then saturate to 18 bits. One DSP48E1 signed multiply per lane-op.
- Constant `FOUR = 4.0 = 0x10000` (raw 65536) — the escape threshold.

---

## 2. Programmer-visible state

| State | Width | Notes |
|---|---|---|
| `V0`–`V15` | 16 registers × N lanes × 18 bits | Each register is a vector: one 18-bit word per lane. |
| Active mask `M` | N bits (1/lane) | Set = lane participates in masked writeback. |
| Loop counter `LC` | 14 bits, unsigned | Scalar, lives in the controller. |
| `PC` | 14 bits | Word-addressed into instruction memory. |
| Instruction memory | 32-bit words | Baked in via `$readmemh`. |
| Framebuffer | 8 bits/pixel | Written by `STORE`. |

`N` (lane count) is a **microarchitecture parameter, not part of the ISA** — the
same program binary runs unchanged for any `N`. Scoped to 2–4 lanes initially.

**Reset state:** `PC = 0`, `M = all active`, `LC` undefined (a program must
`SETLOOP` before its first `ENDLOOP`).

---

## 3. Instruction encoding

Fixed 32-bit word. Fields are placed at fixed bit positions; the encoder **sets
bits by masking, never by adding shifted values** (adding lets an oversized or
negative field carry into its neighbor — a known silent-corruption trap).

```
 31    26 25  22 21  18 17  14 13           0
+--------+------+------+------+--------------+
| opcode |  rd  |  ra  |  rb  |     imm      |
|  (6b)  | (4b) | (4b) | (4b) |    (14b)     |
+--------+------+------+------+--------------+
```

Fields are interpreted per opcode (unused fields must be 0):

- **Register-only ops** (`MOV, ADD, SUB, MUL, ESCAPE`): use `rd/ra/rb`, `imm=0`.
- **Wide-immediate op** (`LI`): carries a full 18-bit word. `value[13:0] → imm`,
  `value[17:14] → rb`, `ra = 0`. This is why `LI` can load `FOUR` (17 bits) even
  though the `imm` field is only 14 bits.
- **Small-immediate ops** (`SETLOOP, ENDLOOP, STORE`): use the 14-bit `imm` as
  an unsigned count / absolute word address / framebuffer base.
- **No-operand ops** (`NOP, LANEID, MASKALL, HALT`): `LANEID` uses `rd`; the rest
  use nothing.

### Immediate notations (assembler)

- Real constant, e.g. `4.0` or `-2.5` → `round(value × 2¹⁴)`, encoded as an
  18-bit two's-complement word (`LI` only).
- Raw integer, written `#1`, `#0` → placed directly as the raw word (used for
  the color counter and other integer values).

---

## 4. Opcode table

| # | Mnemonic | Form | Semantics | Masked? |
|---|---|---|---|---|
| 0x00 | `NOP` | `NOP` | no effect | — |
| 0x01 | `LI` | `LI rd, imm18` | `rd[k] = imm18` for all lanes (broadcast) | no |
| 0x02 | `LANEID` | `LANEID rd` | `rd[k] = k << 14` (lane index as Q4.14 integer) | no |
| 0x03 | `MOV` | `MOV rd, ra` | `rd[k] = ra[k]` | yes |
| 0x04 | `ADD` | `ADD rd, ra, rb` | `rd[k] = sat(ra[k] + rb[k])` | yes |
| 0x05 | `SUB` | `SUB rd, ra, rb` | `rd[k] = sat(ra[k] − rb[k])` | yes |
| 0x06 | `MUL` | `MUL rd, ra, rb` | `rd[k] = sat((ra[k]·rb[k]) >> 14)` | yes |
| 0x07 | `ESCAPE` | `ESCAPE ra, rb` | for each active lane `k`: if `ra[k] > rb[k]` (signed) then `M[k] ← 0` | special |
| 0x08 | `MASKALL` | `MASKALL` | `M[k] = 1` for all lanes | no |
| 0x09 | `SETLOOP` | `SETLOOP imm` | `LC = imm` (unsigned) | no |
| 0x0A | `ENDLOOP` | `ENDLOOP imm` | `LC ← LC − 1`; if `LC ≠ 0` **and** any lane active, `PC ← imm`; else fall through | no |
| 0x0B | `STORE` | `STORE ra, imm` | for all lanes `k`: `FB[imm + k] = ra[k][7:0]` | no |
| 0x0C | `HALT` | `HALT` | stop execution | — |

**Two mask rules** (the whole design rests on these):
1. *Predicated writeback* — a masked op updates lane `k` only if `M[k] = 1`.
   An escaped lane therefore freezes automatically.
2. *Monotonic escape* — `ESCAPE` only ever clears mask bits (until `MASKALL`
   resets them for the next tile). Combined with the "any lane active" test in
   `ENDLOOP`, this is what lets divergent per-pixel loops run under one PC.

**Execution:** fetch word at `PC`, execute, `PC ← PC + 1` unless a branch
retargets it, until `HALT`.

---

## 5. Frozen reference kernel

One launch computes a strip of `N` adjacent pixels (lane `k` → column `k`). The
host sets `CX0`, `DX`, `CY0`, `FB_BASE` per strip and relaunches. Symbols in
CAPS are host-provided constants; `#n` is a raw integer.

```
addr                                     ; comment
 0:  MASKALL                             ; all lanes active BEFORE any masked op
 1:  LANEID  V9                          ; V9 = lane index (Q4.14 integer)
 2:  LI      V0, CX0                     ; cx0
 3:  LI      V8, DX                      ; dx
 4:  MUL     V8, V9, V8                  ; V8 = lane * dx  (masked -> mask must be set)
 5:  ADD     V0, V0, V8                  ; V0 = cx = cx0 + lane*dx  (per-lane)
 6:  LI      V1, CY0                     ; cy (uniform for this strip)
 7:  LI      V2, #0                      ; x = 0
 8:  LI      V3, #0                      ; y = 0
 9:  LI      V7, #0                      ; color = 0
10:  LI      V10, 4.0                    ; escape threshold (raw 65536)
11:  LI      V12, #1                     ; integer 1 for the color counter
12:  SETLOOP MAX_ITER                    ; controller counter
13:  MUL     V4, V2, V2                  ; x2 = x*x        <-- loop top
14:  MUL     V5, V3, V3                  ; y2 = y*y
15:  ADD     V11, V4, V5                 ; mag = x2 + y2   (saturating)
16:  ADD     V7, V7, V12                 ; color++ (masked: frozen lanes hold)
17:  ESCAPE  V11, V10                    ; deactivate lanes where mag > 4
18:  MUL     V6, V2, V3                  ; xy = x*y
19:  ADD     V6, V6, V6                  ; 2xy
20:  SUB     V8, V4, V5                  ; x2 - y2
21:  ADD     V8, V8, V0                  ; new x = x2 - y2 + cx
22:  ADD     V6, V6, V1                  ; new y = 2xy + cy
23:  MOV     V2, V8                      ; commit x (masked)
24:  MOV     V3, V6                      ; commit y (masked)
25:  ENDLOOP 13                          ; loop while iters left AND any active
26:  STORE   V7, FB_BASE                 ; write each lane's color to the FB
27:  HALT
```

Ordering that must be preserved in RTL: `color++` (16) precedes `ESCAPE` (17),
so the escaping iteration is counted; `ESCAPE` (17) precedes the commits (23–24),
so escaped lanes don't advance. This matches the Phase 0 golden model.
Constraint: `MAX_ITER ≤ 255` so the color fits the 8-bit framebuffer.


to remember the registers better: 

| Register | Variable | Purpose within the Kernel |
| --- | --- | --- |
| **V0** | `cx` | The starting X-coordinate (real part of the constant $C$) specific to that lane's pixel.
 |
| **V1** | `cy` | The starting Y-coordinate (imaginary part of $C$), which is uniform for the entire horizontal strip.
 |
| **V2** | `x` | The current real part of the iterative calculation ($Z$), initially set to 0.
 |
| **V3** | `y` | The current imaginary part of the iterative calculation ($Z$), initially set to 0.
 |
| **V4, V5** | `x2`, `y2` | Temporary storage for $x^2$ and $y^2$ during the loop.
 |
| **V6** | `xy`, `new y` | Temporary storage for calculating $x \times y$, $2xy$, and ultimately the updated `y` coordinate for the next iteration.
 |
| **V7** | `color` | A raw integer counter that increments each loop; this becomes the final 8-bit color value written to the framebuffer.
 |
| **V8** | `dx`, `new x` | Initially holds the horizontal step size, and later holds temporary math ($x^2 - y^2$) to calculate the updated `x` coordinate.
 |
| **V9** | `lane index` | The physical lane number (e.g., 0, 1, 2) formatted as a Q4.14 integer to calculate initial pixel offsets.
 |
| **V10** | `4.0` | The constant escape threshold (raw 65536).
 |
| **V11** | `mag` | The magnitude ($x^2 + y^2$) which is compared against the 4.0 threshold to determine if the pixel escapes.
 |
| **V12** | `#1` | The raw integer 1, used to increment the `color` counter (`V7`) in every iteration.
 |
| **V13–V15** | — | Unused in the current reference kernel.
 |

---

## 6. Encoding worked examples

| Instruction | opcode/rd/ra/rb/imm | 32-bit hex |
|---|---|---|
| `LI V10, 4.0` | 0x01 / 10 / 0 / (18-bit 65536 → rb=4, imm=0) | `0x06810000` |
| `MUL V4, V2, V2` | 0x06 / 4 / 2 / 2 / 0 | `0x19088000` |
| `ENDLOOP 13` | 0x0A / 0 / 0 / 0 / 13 | `0x2800000D` |

---

## 7. Type-check (Phase 1 gate)

Every kernel instruction validated against the table: opcode defined, register
indices in 0–15, immediate fits its field (via the 18-bit wide form for `LI`),
branch target in range, and semantic completeness (mask asserted before masked
ops; loop bounded; output stored; `HALT` present).

Field-range summary — all pass:
- Opcodes: all in `{0x00..0x0C}`. ✓
- Register indices: max `V12` (12) ≤ 15. ✓
- `LI` constants: `4.0` (65536) fits 18 bits via the wide form; `#0`, `#1` trivial. ✓
- `SETLOOP MAX_ITER`, `ENDLOOP 13`, `STORE FB_BASE`: all ≤ 14-bit range. ✓
- Completeness: `MASKALL` (0) before the first masked op — the coordinate
  `MUL` (4), not just the loop body; loop bounded by both `LC` and the
  active-mask reduction; `STORE` then `HALT`. ✓
  (v1.0 placed `MASKALL` after the coordinate setup; the by-hand check missed
  that those setup ops are masked. The executable oracle caught it — noted here
  as the reason the Phase 2 gate is run even after Phase 1 passes.)

Gate satisfied — the ISA is sufficient to express the renderer and is frozen.

---

## 8. Explicitly out of scope (microarchitecture, decided later)

Lane count `N`; one multiplier per lane vs. a shared/pipelined multiplier;
pipeline depth and any stalls; register-file port count; VGA scan-out timing;
how the host sequences strips. None of these change the ISA or the binary.