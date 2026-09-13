"""Palette ROM -- the single source of truth for the display palette.

256 entries indexed by the 8-bit iteration count, each a 12-bit RGB value
(4 bits per channel = the Zedboard's onboard VGA DAC depth). Used to colour the
software preview AND exported to a $readmemh file so the hardware palette ROM is
byte-identical. Colour is display-side: it never touches the framebuffer, which
holds raw iteration counts."""


def _smooth12(v, max_iter):
    """Smooth palette evaluated directly at 4-bit-per-channel depth (0..15)."""
    if max_iter <= 0:
        return (0, 0, 0)
    t = min(v, max_iter) / max_iter
    r = int(9 * (1 - t) * t * t * t * 15)
    g = int(15 * (1 - t) * (1 - t) * t * t * 15)
    b = int(8.5 * (1 - t) * (1 - t) * (1 - t) * t * 15)
    return (min(r, 15), min(g, 15), min(b, 15))


def build_rom(max_iter):
    """256-entry ROM. Index == iteration count; index >= max_iter is inside the
    set -> black. Entries above max_iter are unused (also black)."""
    return [_smooth12(i, max_iter) if i < max_iter else (0, 0, 0) for i in range(256)]


def rgb12_to_rgb888(r, g, b):
    """Expand each 4-bit channel to 8-bit by nibble replication (v*17 = v<<4|v),
    so the PNG shows exactly the colour the 4-bit DAC produces -- not a richer
    8-bit version the monitor could never display."""
    return (r * 17, g * 17, b * 17)


def export_mem(rom, path):
    """One 12-bit hex value per line, loadable by $readmemh into the HW ROM."""
    with open(path, "w") as f:
        for (r, g, b) in rom:
            f.write(f"{(r << 8) | (g << 4) | b:03X}\n")