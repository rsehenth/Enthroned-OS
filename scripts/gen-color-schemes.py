#!/usr/bin/env python3
"""Regenerate the Enthroned KDE color schemes (Lote 13: violet identity) and
audit WCAG contrast for every foreground/background pair.

Palette source: colors measured from the owner's assets in assets/ (deep
violet-black #070113..#2A0C50 from wall3.png, magenta-violet accent #8922B8 /
#932EBF from the E logo and throne, silver neutrals #E0D4E5 / #A996B3).

The ColorEffects / General / KDE sections of the existing files are preserved;
only the Colors:* sets and the [WM] section are rewritten.

Usage: python scripts/gen-color-schemes.py [--check]
  --check  audit only, write nothing, exit 1 on a failing pair.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMES = os.path.join(ROOT, "system_files", "usr", "share", "color-schemes")


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lum(c):
    def f(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (f(x) for x in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


FG_KEYS = ["ForegroundNormal", "ForegroundInactive", "ForegroundActive", "ForegroundLink",
           "ForegroundVisited", "ForegroundNegative", "ForegroundNeutral", "ForegroundPositive"]

# fg: shared foreground colors of a scheme; each set overrides what it needs.
DARK = {
    "fg": dict(ForegroundNormal="#ECE7F4", ForegroundInactive="#ADA2BF", ForegroundActive="#BC8EEA",
               ForegroundLink="#BC8EEA", ForegroundVisited="#E39BCB", ForegroundNegative="#F28A9B",
               ForegroundNeutral="#E8A64A", ForegroundPositive="#45CB93"),
    "deco": "#B684EA",
    "sets": {
        "Window": ("#17111F", "#120D1A"),
        "View": ("#1C1626", "#17111F"),
        "Button": ("#241D32", "#2C2440"),
        "Header": ("#1F1830", "#261E38"),
        "Header][Inactive": ("#1A1428", "#17111F"),
        "Tooltip": ("#241D32", "#2C2440"),
        "Complementary": ("#0F0B16", "#140F1C"),
    },
    # The Selection background is also the Breeze "highlight" (progress bars,
    # switches, sliders, the navigation accent bar), so it must reach 3:1 on the
    # surfaces it sits on while still carrying white text at >= 4.5:1. The
    # secondary selection foregrounds are therefore pale tints of their hue.
    "selection": dict(bg="#9A3DD6", alt="#8B33C4", fgs=dict(
        ForegroundNormal="#FFFFFF", ForegroundInactive="#F9F1FE", ForegroundActive="#FFFFFF",
        ForegroundLink="#FFF6D2", ForegroundVisited="#FEF4FF", ForegroundNegative="#FFEEF1",
        ForegroundNeutral="#FFF3DD", ForegroundPositive="#EAFBF3")),
    "wm": ("#1F1830", "#ECE7F4", "#1A1428", "#ADA2BF"),
}
LIGHT = {
    "fg": dict(ForegroundNormal="#1E162C", ForegroundInactive="#5A5070", ForegroundActive="#6A25A6",
               ForegroundLink="#6A25A6", ForegroundVisited="#8A2F78", ForegroundNegative="#A8344A",
               ForegroundNeutral="#855210", ForegroundPositive="#17693F"),
    "deco": "#7A32BE",
    "sets": {
        "Window": ("#F6F3FA", "#ECE7F3"),
        "View": ("#FDFCFF", "#F4F0F9"),
        "Button": ("#EFEAF6", "#E6DFF0"),
        "Header": ("#E9E2F2", "#E0D8EC"),
        "Header][Inactive": ("#F0EBF6", "#EBE5F2"),
        "Tooltip": ("#FCFBFE", "#F1EDF7"),
        "Complementary": ("#241B33", "#1C1528"),
    },
    "selection": dict(bg="#6F26A8", alt="#5F1E93", fgs=dict(
        ForegroundNormal="#FFFFFF", ForegroundInactive="#EBDDF8", ForegroundActive="#FFFFFF",
        ForegroundLink="#FFE9A6", ForegroundVisited="#F3E4FA", ForegroundNegative="#FFE0E5",
        ForegroundNeutral="#FFE6BF", ForegroundPositive="#D3F5E3")),
    "wm": ("#E9E2F2", "#1E162C", "#F0EBF6", "#5A5070"),
}
# The Complementary set of the light scheme is dark (as in Breeze Light).
LIGHT_COMPL_FG = dict(ForegroundNormal="#EEE9F6", ForegroundInactive="#A79CBA", ForegroundActive="#BC8EEA",
                      ForegroundLink="#BC8EEA", ForegroundVisited="#E39BCB", ForegroundNegative="#F28A9B",
                      ForegroundNeutral="#E8A64A", ForegroundPositive="#45CB93")


def build_sets(spec, light):
    sets = {}
    for name, (bn, ba) in spec["sets"].items():
        fgs = dict(spec["fg"])
        if light and name == "Complementary":
            fgs = dict(LIGHT_COMPL_FG)
        deco = "#BC8EEA" if (light and name == "Complementary") else spec["deco"]
        sets[name] = dict(BackgroundNormal=bn, BackgroundAlternate=ba,
                          DecorationFocus=deco, DecorationHover=deco, **fgs)
    sel = spec["selection"]
    sets["Selection"] = dict(BackgroundNormal=sel["bg"], BackgroundAlternate=sel["alt"],
                             DecorationFocus="#FFFFFF", DecorationHover="#FFFFFF", **sel["fgs"])
    return sets


def audit(sets, label):
    fails = 0
    pairs = 0
    for name, s in sets.items():
        for bk in ("BackgroundNormal", "BackgroundAlternate"):
            for fk in FG_KEYS:
                # Selection BackgroundAlternate is a hover tint, used with ForegroundNormal only
                if name == "Selection" and bk == "BackgroundAlternate" and fk != "ForegroundNormal":
                    continue
                r = ratio(rgb(s[fk]), rgb(s[bk]))
                pairs += 1
                if r < 4.5:
                    fails += 1
                    print(f"  FAIL {label} {name}.{fk} on {bk}: {r:.2f}:1 ({s[fk]} on {s[bk]})")
        # non-text: focus ring needs 3:1 against the set's own backgrounds
        for bk in ("BackgroundNormal",):
            r = ratio(rgb(s["DecorationFocus"]), rgb(s[bk]))
            pairs += 1
            if r < 3.0:
                fails += 1
                print(f"  FAIL {label} {name}.DecorationFocus on {bk}: {r:.2f}:1")
    sel_bg = rgb(sets["Selection"]["BackgroundNormal"])
    for name in ("Window", "View", "Button", "Header", "Tooltip"):
        r = ratio(sel_bg, rgb(sets[name]["BackgroundNormal"]))
        pairs += 1
        if r < 3.0:
            fails += 1
            print(f"  FAIL {label} highlight (Selection bg) on {name}: {r:.2f}:1 (non-text 3:1)")
    print(f"{label}: {pairs} pairs audited, {fails} below threshold (text 4.5:1, focus ring and highlight 3:1)")
    return fails


def render(path, template_lines, sets, wm):
    # Keep ColorEffects / General / KDE untouched; rewrite Colors:* and WM.
    out, i = [], 0
    text = "".join(template_lines)
    blocks, cur = [], None
    for line in text.splitlines():
        if line.startswith("["):
            cur = [line]
            blocks.append(cur)
        elif cur is not None:
            cur.append(line)
        else:
            out.append(line)
    def fmt(c):
        return "%d,%d,%d" % rgb(c)
    for b in blocks:
        sec = b[0][1:-1] if b[0].endswith("]") else b[0][1:]
        sec = b[0][1:b[0].rindex("]")] if b[0].count("]") >= 1 else sec
        if sec.startswith("Colors:"):
            key = sec[len("Colors:"):]
            data = sets[key]
            out.append(b[0])
            for k in sorted(data):
                out.append(f"{k}={fmt(data[k])}")
            out.append("")
        elif sec == "WM":
            ab, af, ib, inf = wm
            out += [b[0], f"activeBackground={fmt(ab)}", f"activeBlend={fmt(ab)}", f"activeForeground={fmt(af)}",
                    f"inactiveBackground={fmt(ib)}", f"inactiveBlend={fmt(ib)}", f"inactiveForeground={fmt(inf)}"]
        else:
            out += b
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out).rstrip("\n") + "\n")


def main():
    check = "--check" in sys.argv
    total = 0
    for fname, spec, light in (("EnthronedDark.colors", DARK, False), ("EnthronedLight.colors", LIGHT, True)):
        sets = build_sets(spec, light)
        total += audit(sets, fname)
        if not check:
            path = os.path.join(SCHEMES, fname)
            with open(path, encoding="utf-8") as fh:
                tpl = fh.readlines()
            render(path, tpl, sets, spec["wm"])
            print(f"wrote {path}")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
