#!/usr/bin/env python3
"""Generate the Enthroned folder-<color>[-open].svg family (Lote 15).

Dolphin's native "Set folder icon" action (dolphin-libs setfoldericonitemaction)
writes Icon=folder-<color> into <folder>/.directory. Without these files the
colours fall through to Breeze's flat folders and clash with the Enthroned
violet folder. Each colour reuses the exact geometry and the three-tone
structure of folder.svg / folder-open.svg (back, front, highlight); only the
hue (and for neutrals, saturation/lightness) changes. Violet is the Enthroned
default, so folder-violet is byte-compatible with the base palette.

Usage: python scripts/gen-folder-colors.py   (idempotent, rewrites 44 files)
"""
import colorsys
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = ["Enthroned", "EnthronedDark"]
PLACES = "scalable/places"

# Names are the Breeze set Dolphin's action offers (no white in KDE 26.08).
# name: (hue degrees or None=keep, saturation multiplier, lightness delta or
#        absolute (back, front, hi) override for neutrals)
COLORS = {
    "red": (355, 1.05, 0.0, None),
    "orange": (24, 1.15, 0.03, None),
    "yellow": (46, 1.10, 0.09, None),
    "green": (140, 0.80, -0.02, None),
    "cyan": (187, 0.95, -0.01, None),
    "blue": (218, 1.00, 0.0, None),
    "violet": (None, 1.0, 0.0, None),
    "magenta": (312, 1.0, 0.0, None),
    "brown": (26, 0.50, -0.05, None),
    "grey": (None, 0.0, 0.0, (0.40, 0.82)),
    "black": (None, 0.0, 0.0, (0.14, 0.50)),
}

HEX = re.compile(r"#[0-9A-Fa-f]{6}")
L_DARK, L_LIGHT = 0.36, 0.80  # lightness of #5E2596 / #C79BEA in the base palette


def hex_to_hls(value):
    r, g, b = (int(value[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return colorsys.rgb_to_hls(r, g, b)


def hls_to_hex(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h % 1.0, min(max(l, 0), 1), min(max(s, 0), 1))
    return "#%02X%02X%02X" % (round(r * 255), round(g * 255), round(b * 255))


def recolor(svg, spec):
    """Shift every fill of the base SVG: hue/saturation/lightness for chromatic
    colours, a lightness remap with near-zero saturation (violet-tinted, like the brand neutrals) for neutrals."""
    hue, sat_mul, l_delta, neutral = spec

    def shift(match):
        h, l, s = hex_to_hls(match.group(0))
        if neutral:
            lo, hi = neutral
            return hls_to_hex(0.75, lo + (l - L_DARK) * (hi - lo) / (L_LIGHT - L_DARK), 0.04)
        return hls_to_hex(hue / 360 if hue is not None else h, l + l_delta, s * sat_mul)

    return HEX.sub(shift, svg)


def main():
    written = 0
    for theme in THEMES:
        directory = os.path.join(ROOT, "system_files", "usr", "share", "icons", theme, PLACES)
        for variant, suffix in (("folder.svg", ""), ("folder-open.svg", "-open")):
            with open(os.path.join(directory, variant), encoding="utf-8", newline="") as handle:
                source = handle.read()
            if "#5E2596" not in source:
                raise SystemExit(f"{theme}/{variant}: base palette not found; refusing to recolour")
            for name, spec in COLORS.items():
                target = os.path.join(directory, f"folder-{name}{suffix}.svg")
                with open(target, "w", encoding="utf-8", newline="") as handle:
                    handle.write(recolor(source, spec))
                written += 1
    print(f"wrote {written} files")


if __name__ == "__main__":
    main()
