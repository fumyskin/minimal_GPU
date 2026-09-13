"""Shared image output. Palette is display-side only; the raw framebuffer holds
the iteration count that STORE writes."""

import struct
import zlib


def palette(v, max_iter):
    """Smooth palette. v == max_iter (inside the set) falls out as black."""
    t = v / max_iter
    r = int(9 * (1 - t) * t * t * t * 255)
    g = int(15 * (1 - t) * (1 - t) * t * t * 255)
    b = int(8.5 * (1 - t) * (1 - t) * (1 - t) * t * 255)
    return (min(r, 255), min(g, 255), min(b, 255))


def write_raw(path, fb):
    with open(path, "wb") as f:
        f.write(fb)


def write_png(path, fb, width, height, max_iter):
    raw = bytearray()
    for py in range(height):
        raw.append(0)
        base = py * width
        for px in range(width):
            raw += bytes(palette(fb[base + px], max_iter))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def write_rgb_png(path, rgb, width, height):
    """Write a truecolor PNG from a flat RGB888 byte buffer (width*height*3)."""
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)
        raw += rgb[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))