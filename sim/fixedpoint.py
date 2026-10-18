"""Shared fixed-point loigc <core -- the single source of truth for the numeric model.
Imported by the golden model, the assembler, and the simulator so all three
compute bit-for-bit identically."""

W = 18            # word width
F = 14            # fractional bits -> Q4.14
ARITH = "sat"     # "sat" or "wrap"


def set_mode(w=18, f=14, arith="sat"):
    global W, F, ARITH
    W, F, ARITH = w, f, arith
    _recompute()


def _recompute():
    global INT_MIN, INT_MAX, ONE, FOUR
    INT_MIN = -(1<<(W-1))       # 2^(W-1) = -2^17
    INT_MAX = (1<<(W-1))-1      # 2^(W-1) -1 = 2^17 - 1
    ONE = 1 << F                # 1.00000000000000
    FOUR = 4 << F               # 4.00000000000000


_recompute()

# clamp() is applied after every operation to force the result back into 18 bits, 
# the same way the hardware does. There are two possible ways, and the ARITH setting picks one:
# "sat"	131071 (stuck at the max)	6.1 + 6.1 -> 7.99

def clamp(v):
    if ARITH == "sat":
        if v > INT_MAX:
            return INT_MAX
        if v < INT_MIN:
            return INT_MIN
        return v
    v &= (1<<W)-1
    return v-(1<<W) if (v &(1<<(W-1))) else v


def to_fixed(real):
    #real -> raw-fixed point 
    # done at compile time ???
    # datapath never does this ???????
    return clamp(int(round(real * ONE)))

# to_fixed(1.0)    -> 16384
# to_fixed(-0.75)  -> -12288
# to_fixed(0.5)    -> 8192
# 0.75 in binary  =  0.11
# × 2¹⁴ →  shift the point 14 places  →  11 0000 0000 0000  =  12288

def fadd(a, b):
    return clamp(a + b)


def fsub(a, b):
    return clamp(a - b)


def fmul(a, b):
    # full product, arithmetic shift right by F (truncate toward -inf), saturate
    return clamp((a * b) >> F)