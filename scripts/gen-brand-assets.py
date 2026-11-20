#!/usr/bin/env python3
"""Derive the shipped brand resources from the owner's originals in assets/.

The originals are never modified. Everything written here is a technical
derivative (crop to the artwork, square canvas, Lanczos downscale, thumbnails);
the artwork itself is not redrawn. The official wallpapers are copied
byte-for-byte (no resampling) so Plasma scales them at runtime.

Writes under system_files/usr/share/:
  icons/hicolor/<N>x<N>/apps/org.enthroned.launcher-classic.png  (E Logo-2)
  icons/hicolor/<N>x<N>/apps/org.enthroned.launcher-modern.png   (Enthroned Throne-2)
  icons/hicolor/<N>x<N>/apps/org.enthroned.enthroned-os.png      (E Logo-2)
Gate 13.1 - application icons, shipped by each app's own CMake install:
  settings/data/icons/hicolor/<N>x<N>/apps/org.enthroned.settings.png  (E Logo-2)
  welcome/data/icons/hicolor/<N>x<N>/apps/org.enthroned.welcome.png    (Enthroned Throne-2)
  enthroned-os/branding/enthroned-wordmark.png / -mono.png       (EnthronedLogo-2 / EnthronedLogo)
  wallpapers/Enthroned{Soberania,Ascensao,Vigilia}/              (wall1 / wall2 / wall3)
  plasma/look-and-feel/org.enthroned.{classic,modern}/contents/splash/images/enthroned-wordmark.png (720 px)

Usage: python scripts/gen-brand-assets.py
Requires Pillow.
"""
import hashlib
import json
import os
import shutil
import sys

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
SHARE = os.path.join(ROOT, "system_files", "usr", "share")
SIZES = [16, 22, 24, 32, 48, 64, 128, 256, 512]

ICONS = {
    "org.enthroned.launcher-classic": "E Logo-2.png",
    "org.enthroned.launcher-modern": "Enthroned Throne-2.png",
    "org.enthroned.enthroned-os": "E Logo-2.png",
}
APP_ICONS = {
    "org.enthroned.settings": ("E Logo-2.png", "settings"),
    "org.enthroned.welcome": ("Enthroned Throne-2.png", "welcome"),
}
WORDMARKS = {"enthroned-wordmark.png": "EnthronedLogo-2.png", "enthroned-wordmark-mono.png": "EnthronedLogo.png"}
WALLPAPERS = [
    # (id, source, English name, pt_BR name, description EN, description pt_BR)
    ("EnthronedSoberania", "wall1.png", "Enthroned — Soberania",
     "Enthroned OS official wallpaper: Soberania", "Papel de parede oficial do Enthroned OS: Soberania"),
    ("EnthronedAscensao", "wall2.png", "Enthroned — Ascensão",
     "Enthroned OS official wallpaper: Ascensão", "Papel de parede oficial do Enthroned OS: Ascensão"),
    ("EnthronedVigilia", "wall3.png", "Enthroned — Vigília",
     "Enthroned OS official wallpaper: Vigília (default)", "Papel de parede oficial do Enthroned OS: Vigília (padrão)"),
]


def load(name):
    return Image.open(os.path.join(ASSETS, name)).convert("RGBA")


def square_icon(img, size):
    """Crop to the artwork, centre on a square canvas, premultiplied Lanczos."""
    bbox = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    art = img.crop(bbox)
    side = max(art.size)
    pad = 0.03 if size <= 32 else 0.06  # tiny sizes: let the glyph fill the cell
    canvas_side = round(side * (1 + 2 * pad))
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.alpha_composite(art, ((canvas_side - art.width) // 2, (canvas_side - art.height) // 2))
    out = canvas.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")
    if size <= 48:  # restore the edge contrast the downscale removes
        r, g, b, a = out.split()
        rgb = Image.merge("RGB", (r, g, b)).filter(ImageFilter.UnsharpMask(radius=0.7, percent=70, threshold=0))
        out = Image.merge("RGBA", (*rgb.split(), a))
    return out


def write_png(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG", optimize=True)


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def main():
    for name, source in ICONS.items():
        src = load(source)
        for size in SIZES:
            write_png(square_icon(src, size), os.path.join(SHARE, "icons", "hicolor", f"{size}x{size}", "apps", f"{name}.png"))
    for name, (source, app) in APP_ICONS.items():
        src = load(source)
        for size in SIZES:
            write_png(square_icon(src, size), os.path.join(ROOT, app, "data", "icons", "hicolor", f"{size}x{size}", "apps", f"{name}.png"))
    for target, source in WORDMARKS.items():
        img = load(source)
        img = img.crop(img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
        width = 1000
        img = img.convert("RGBa").resize((width, round(img.height * width / img.width)), Image.LANCZOS).convert("RGBA")
        write_png(img, os.path.join(SHARE, "enthroned-os", "branding", target))
    splash = load("EnthronedLogo-2.png")
    splash = splash.crop(splash.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
    splash = splash.convert("RGBa").resize((720, round(splash.height * 720 / splash.width)), Image.LANCZOS).convert("RGBA")
    for profile in ("classic", "modern"):
        write_png(splash, os.path.join(SHARE, "plasma", "look-and-feel", f"org.enthroned.{profile}", "contents", "splash", "images", "enthroned-wordmark.png"))
    for wid, source, name, d_en, d_pt in WALLPAPERS:
        pkg = os.path.join(SHARE, "wallpapers", wid)
        img_dir = os.path.join(pkg, "contents", "images")
        os.makedirs(img_dir, exist_ok=True)
        src_path = os.path.join(ASSETS, source)
        w, h = Image.open(src_path).size
        dest = os.path.join(img_dir, f"{w}x{h}.png")
        shutil.copyfile(src_path, dest)  # original bytes, never resampled
        assert sha(dest) == sha(src_path), f"{dest} differs from the original"
        thumb = Image.open(src_path).convert("RGB")
        thumb.thumbnail((640, 360), Image.LANCZOS)
        write_png(thumb, os.path.join(pkg, "contents", "screenshot.png"))
        meta = {"KPlugin": {
            "Authors": [{"Name": "Enthroned OS Project"}],
            "Id": wid,
            "License": "LicenseRef-Enthroned-Artwork",
            "Name": name,
            "Name[pt_BR]": name,
            "Description": d_en,
            "Description[pt_BR]": d_pt,
        }}
        with open(os.path.join(pkg, "metadata.json"), "w", encoding="utf-8", newline="\n") as fh:
            json.dump(meta, fh, ensure_ascii=False, indent=4)
            fh.write("\n")
    print("brand assets written; originals in assets/ untouched")


if __name__ == "__main__":
    sys.exit(main())
