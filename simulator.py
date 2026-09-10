import argparse
import struct

# Q4.14
# fixed 

# fixed point data
W = 18
F = 14
ARITH = "sat" #sat = saturate, wrap = two's complement wraparound



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




def main():

    