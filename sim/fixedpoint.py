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
    INT_MIN = -(1<<(W-1))
    INT_MAX = (1<<(W-1))-1
    ONE = 1 << F
    FOUR = 4 << F


_recompute()


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


def fadd(a, b):
    return clamp(a + b)


def fsub(a, b):
    return clamp(a - b)


def fmul(a, b):
    # full product, arithmetic shift right by F (truncate toward -inf), saturate
    return clamp((a * b) >> F)