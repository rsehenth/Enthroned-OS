#!/bin/bash
# Enthroned OS - static validation of the F2 desktop layer.
# No KDE, no image build, no network: parses every shipped desktop file type
# (JSON, KConfig INI, QML/JS balance, PNG magic) and checks cross-references
# (color schemes, wallpapers, icons, look-and-feel ids). PASS/FAIL per check.
# Read-only: never modifies the repository or the host.
#
# Requirements: python3 (or python). Node is optional (runs the launcher
# regression tests: filter, pinned dedupe, app actions/shortcut commands).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Launcher regression tests (Node optional, same policy as validate-settings.sh).
if command -v node >/dev/null 2>&1; then
    for test in test-launcher-filter.mjs test-launcher-pinned-dedupe.mjs test-launcher-appactions.mjs; do
        node --check "$SCRIPT_DIR/$test" \
            && echo "PASS: node syntax: scripts/$test" \
            || { echo "FAIL: node syntax: scripts/$test"; exit 1; }
        node "$SCRIPT_DIR/$test"
        TEST_RC=$?
        if [ "$TEST_RC" -ne 0 ]; then
            echo "FAIL: node launcher test (scripts/$test)"
            exit 1
        fi
    done
else
    echo "WARN: node not found; launcher regression tests skipped (NOT RUN)"
fi

# Resolve a working Python. The Microsoft Store python3/python stubs exist in
# PATH but fail when the Store alias is disabled, so probe each candidate.
find_python() {
    local cand
    for cand in python3 python py; do
        if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import sys" >/dev/null 2>&1; then
            printf '%s' "$cand"
            return 0
        fi
    done
    return 1
}

if PYTHON="$(find_python)"; then
    :
else
    echo "FAIL: no working python3/python/py found; cannot run static validation" >&2
    exit 2
fi

exec "$PYTHON" - "$SCRIPT_DIR" <<'PYEOF'
import json
import os
import re
import sys

script_dir = sys.argv[1]
ROOT = os.path.dirname(script_dir)
USR = os.path.join(ROOT, "system_files", "usr")
SHARE = os.path.join(USR, "share")

failures = []


def check(name, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    line = f"{status}: {name}"
    if not cond and detail:
        line += f" -- {detail}"
    print(line)
    if not cond:
        failures.append(name)


def read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def balanced(text, pairs=(("{", "}"), ("(", ")"))):
    counts = {p: 0 for p in pairs}
    for ch in text:
        for pair in pairs:
            if ch == pair[0]:
                counts[pair] += 1
            elif ch == pair[1]:
                counts[pair] -= 1
    return all(v == 0 for v in counts.values())


def parse_ini(path):
    # Tiny KConfig-style parser. Handles single ([Section]) and nested
    # ([file][Section]) headers; keys are lower-cased for lookups.
    sections = {}
    current = None
    for raw in read(path).splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections.setdefault(current, {})
        elif "=" in line and current is not None:
            key, _, value = line.partition("=")
            sections[current][key.strip().lower()] = value.strip()
    return sections


# ---- 1. All JSON files parse -------------------------------------------------
for base, _dirs, files in os.walk(USR):
    for f in sorted(files):
        if not f.endswith(".json"):
            continue
        path = os.path.join(base, f)
        rel = os.path.relpath(path, ROOT)
        try:
            json.loads(read(path))
            check(f"json parses: {rel}", True)
        except Exception as exc:  # noqa: BLE001
            check(f"json parses: {rel}", False, str(exc))

# ---- 2. Color schemes --------------------------------------------------------
color_dir = os.path.join(SHARE, "color-schemes")
required_groups = {
    "ColorEffects:Disabled", "ColorEffects:Inactive",
    "Colors:Button", "Colors:Complementary", "Colors:Header",
    "Colors:Selection", "Colors:Tooltip", "Colors:View", "Colors:Window",
    "General", "WM",
}
for fname in sorted(os.listdir(color_dir)):
    if not fname.endswith(".colors"):
        continue
    rel = os.path.relpath(os.path.join(color_dir, fname), ROOT)
    ini = parse_ini(os.path.join(color_dir, fname))
    missing = required_groups - set(ini)
    check(f"scheme groups complete: {rel}", not missing, f"missing {sorted(missing)}")
    stem = fname[: -len(".colors")]
    got = ini.get("General", {}).get("colorscheme")
    check(f"scheme name matches file: {rel}", got == stem, f"got {got!r}")
    sel_bg = ini.get("Colors:Selection", {}).get("backgroundnormal")
    check(f"scheme selection color set: {rel}", bool(sel_bg and sel_bg.strip()))

# ---- 3. Look-and-feel packages ----------------------------------------------
laf_root = os.path.join(SHARE, "plasma", "look-and-feel")
allowed_widgets = {
    "org.enthroned.launcher", "org.kde.plasma.kickoff",
    "org.kde.plasma.icontasks", "org.kde.plasma.panelspacer",
    "org.kde.plasma.systemtray", "org.kde.plasma.digitalclock",
    "org.kde.plasma.pager", "org.kde.plasma.margins-separator",
    "org.kde.plasma.taskmanager", "org.kde.plasma.trash",
}
icon_refs = set()
laf_dirs = sorted(
    d for d in os.listdir(laf_root)
    if os.path.isdir(os.path.join(laf_root, d)) and d.startswith("org.enthroned.")
)
check("two Enthroned look-and-feel profiles exist", len(laf_dirs) == 2, str(laf_dirs))

for laf in laf_dirs:
    base = os.path.join(laf_root, laf)

    # metadata.json
    meta_path = os.path.join(base, "metadata.json")
    try:
        meta = json.loads(read(meta_path))
        check(f"L&F KPackageStructure: {laf}", meta.get("KPackageStructure") == "Plasma/LookAndFeel")
        kid = meta.get("KPlugin", {}).get("Id")
        check(f"L&F Id matches directory: {laf}", kid == laf, f"Id={kid!r}")
        check(f"L&F APIVersion present: {laf}", meta.get("X-Plasma-APIVersion") == "2")
    except Exception as exc:  # noqa: BLE001
        check(f"L&F metadata readable: {laf}", False, str(exc))
        continue

    # contents/defaults
    defaults_path = os.path.join(base, "contents", "defaults")
    check(f"L&F defaults exists: {laf}", os.path.isfile(defaults_path))
    if os.path.isfile(defaults_path):
        dini = parse_ini(defaults_path)
        scheme = dini.get("kdeglobals][General", {}).get("colorscheme")
        scheme_file = os.path.join(color_dir, f"{scheme}.colors")
        check(f"L&F color scheme exists: {laf}", bool(scheme) and os.path.isfile(scheme_file), f"{scheme}")
        wallpaper = dini.get("Wallpaper", {}).get("image")
        wall_dir = os.path.join(SHARE, "wallpapers", wallpaper or "_missing_")
        check(f"L&F wallpaper package exists: {laf}", bool(wallpaper) and os.path.isdir(wall_dir), f"{wallpaper}")
        laf_ref = dini.get("kdeglobals][KDE", {}).get("lookandfeelpackage")
        check(f"L&F self-reference correct: {laf}", laf_ref == laf, f"{laf_ref!r}")
        splash_theme = dini.get("KSplash", {}).get("theme")
        check(f"L&F splash theme correct: {laf}", splash_theme == laf, f"{splash_theme!r}")

    # Plasma runs the prelayout before creating the desktop containments.
    layout_dir = os.path.join(base, "contents", "layouts")
    layouts = sorted(f for f in os.listdir(layout_dir) if f.endswith(".js")) if os.path.isdir(layout_dir) else []
    layout_name = "org.kde.plasma.desktop-layout.js"
    prelayout_name = "org.kde.plasma.desktop-prelayout.js"
    check(f"L&F has canonical Plasma layout scripts: {laf}", layouts == [layout_name, prelayout_name], str(layouts))
    if prelayout_name in layouts:
        check(f"prelayout script balanced: {laf}", balanced(read(os.path.join(layout_dir, prelayout_name))))
    if layout_name in layouts:
        ltext = read(os.path.join(layout_dir, layout_name))
        check(f"layout script balanced: {laf}", balanced(ltext))
        widgets = set(re.findall(r'\.addWidget\("([^"]+)"\)', ltext))
        unknown = widgets - allowed_widgets
        check(f"layout uses stock widgets only: {laf}", not unknown, f"unknown {sorted(unknown)}")
        icon_refs |= set(re.findall(r'writeConfig\("icon", "([^"]+)"\)', ltext))
        check(f"layout sets panel location bottom: {laf}", 'panel.location = "bottom"' in ltext)
        check(f"layout sets desktop wallpaper plugin: {laf}", 'wallpaperPlugin = "org.kde.image"' in ltext)
        # F2.1: own launcher with working fallback, desktop trash widget and
        # per-profile panel/clock differentiation.
        check(
            f"layout uses Enthroned Launcher with kickoff fallback: {laf}",
            'org.enthroned.launcher' in ltext and 'org.kde.plasma.kickoff' in ltext,
        )
        check(f"layout adds stock trash widget to desktop: {laf}", 'org.kde.plasma.trash' in ltext)
        # Homologação 3: the Trash widget must be user-immutable (no
        # "Remove"/"Configure" in its context menu) and desktop icons must
        # stay freely movable without edit mode.
        check(f"layout locks the trash widget (no Remove option): {laf}", "trash.locked = true" in ltext)
        check(f"layout keeps desktop icons freely movable: {laf}",
              'writeConfig("locked", false)' in ltext and 'writeConfig("sortMode", 0)' in ltext)
        if laf == "org.enthroned.classic":
            check("classic panel non-floating", "panel.floating = false" in ltext)
            check("classic panel opaque", 'panel.opacity = "opaque"' in ltext)
            check("classic clock shows date", 'clock.writeConfig("showDate", true)' in ltext)
        elif laf == "org.enthroned.modern":
            check("modern panel floating", "panel.floating = true" in ltext)
            check("modern clock hides date", 'clock.writeConfig("showDate", false)' in ltext)
            # Lote 14: showDate is read from the digitalclock "Appearance" group.
            check("modern clock writes showDate in the Appearance group",
                  re.search(r'clock\.currentConfigGroup = \["Appearance"\]\s*\nclock\.writeConfig\("showDate", false\)', ltext) is not None
                  and 'clock.writeConfig("use24hFormat"' not in ltext
                  and 'clock.writeConfig("dateFormat"' not in ltext)

    # splash
    splash = os.path.join(base, "contents", "splash", "Splash.qml")
    check(f"L&F splash exists: {laf}", os.path.isfile(splash))
    if os.path.isfile(splash):
        stext = read(splash)
        check(f"splash balanced: {laf}", balanced(stext))
        check(f"splash has stage handling: {laf}", "property int stage" in stext)
        for img in re.findall(r'source:\s*"([^"]+)"', stext):
            ipath = os.path.join(base, "contents", "splash", img)
            check(f"splash image exists: {laf}/{img}", os.path.isfile(ipath))

# ---- 4. Icons referenced by layouts exist -----------------------------------
HICOLOR_SIZES = (16, 22, 24, 32, 48, 64, 128, 256, 512)


def icon_installed(name):
    """Installed as a scalable SVG or as the full PNG size set (Lote 13 brand icons)."""
    if os.path.isfile(os.path.join(SHARE, "icons", "hicolor", "scalable", "apps", f"{name}.svg")):
        return True
    return all(
        os.path.isfile(os.path.join(SHARE, "icons", "hicolor", f"{n}x{n}", "apps", f"{name}.png"))
        for n in HICOLOR_SIZES
    )


for icon in sorted(icon_refs):
    check(f"layout icon exists: {icon}", icon_installed(icon))

# Lote 13: each profile owns its start-menu icon and writes it on layout reset.
for laf, want in (("org.enthroned.classic", "org.enthroned.launcher-classic"),
                  ("org.enthroned.modern", "org.enthroned.launcher-modern")):
    ltext = read(os.path.join(SHARE, "plasma", "look-and-feel", laf, "contents", "layouts",
                              "org.kde.plasma.desktop-layout.js"))
    check(f"layout writes the profile start icon: {laf}",
          ltext.count(f'writeConfig("icon", "{want}")') == 2, want)

# ---- 4.5 Enthroned Launcher plasmoid ----------------------------------------
plasmoid_dir = os.path.join(SHARE, "plasma", "plasmoids", "org.enthroned.launcher")
check("launcher plasmoid directory exists", os.path.isdir(plasmoid_dir))
if os.path.isdir(plasmoid_dir):
    try:
        meta = json.loads(read(os.path.join(plasmoid_dir, "metadata.json")))
        check("launcher KPackageStructure is Plasma/Applet", meta.get("KPackageStructure") == "Plasma/Applet")
        kid = meta.get("KPlugin", {}).get("Id")
        check("launcher Id matches directory", kid == "org.enthroned.launcher", f"Id={kid!r}")
        check("launcher category is Application Launchers", meta.get("KPlugin", {}).get("Category") == "Application Launchers")
        provides = meta.get("X-Plasma-Provides")
        check("launcher provides launchermenu (alternative to kickoff)", isinstance(provides, list) and "org.kde.plasma.launchermenu" in provides, str(provides))
        check("launcher X-Plasma-API-Minimum-Version is 6.0", meta.get("X-Plasma-API-Minimum-Version") == "6.0")
        icon = meta.get("KPlugin", {}).get("Icon")
        check("launcher icon exists", bool(icon) and icon_installed(icon), f"{icon}")
    except Exception as exc:  # noqa: BLE001
        check("launcher metadata readable", False, str(exc))
    # Lote 11B (H4/H5): a plasmoid's translation domain is
    # "plasma_applet_" + KPlugin.Id (libplasma Plasma::Applet::translationDomain()).
    # The pt_BR catalog MUST be named after that domain or every i18n() call in
    # the launcher QML falls back to English ("Pinned", "All applications", ...).
    l10n_dir = os.path.join(ROOT, "build_files", "l10n", "pt_BR")
    check("launcher pt_BR catalog uses the plasma_applet_ domain",
          os.path.isfile(os.path.join(l10n_dir, "plasma_applet_org.enthroned.launcher.po")))
    check("launcher pt_BR catalog has no legacy-domain file",
          not os.path.isfile(os.path.join(l10n_dir, "org.enthroned.launcher.po")))
    ui_dir = os.path.join(plasmoid_dir, "contents", "ui")
    qmls = sorted(f for f in os.listdir(ui_dir) if f.endswith(".qml")) if os.path.isdir(ui_dir) else []
    check("launcher has main.qml", "main.qml" in qmls, str(qmls))
    for q in qmls:
        qtext = read(os.path.join(ui_dir, q))
        check(f"launcher QML balanced: {q}", balanced(qtext))
        # Visual identity comes from the color schemes; no hardcoded colors.
        check(f"launcher QML has no hardcoded colors: {q}", re.search(r'color:\s*"#[0-9A-Fa-f]{3,8}"', qtext) is None)
        # Homologação 3 (P0): PlasmaCore.DataSource was removed from
        # org.kde.plasma.core in Plasma 6; a single use breaks the whole
        # FullRepresentation/AppActions type chain when the popup opens.
        check(f"launcher QML has no removed Plasma 5 DataSource: {q}", "PlasmaCore.DataSource" not in qtext)
    if "main.qml" in qmls:
        mtext = read(os.path.join(ui_dir, "main.qml"))
        check("launcher uses kicker RootModel (real apps)", "Kicker.RootModel" in mtext)
        check("launcher uses kicker RunnerModel (search)", "Kicker.RunnerModel" in mtext)
        check("launcher uses kicker SystemModel (session actions)", "Kicker.SystemModel" in mtext)
        check("launcher favorites are per-instance persistent", "initForClient" in mtext)
        check("launcher ports initial favorites once", "portOldFavorites" in mtext and "favoritesPortedToKAstats" in mtext)
    cfg = os.path.join(plasmoid_dir, "contents", "config", "main.xml")
    check("launcher config main.xml exists", os.path.isfile(cfg))
    if os.path.isfile(cfg):
        ctext = read(cfg)
        check("launcher config has General group", '<group name="General">' in ctext)
        for key in ("icon", "favorites", "favoritesPortedToKAstats"):
            check(f"launcher config entry {key}", f'name="{key}"' in ctext)
        defaults = re.findall(r"<default>([^<]*)</default>", ctext)
        icon_default_ok = len(defaults) >= 1 and icon_installed(defaults[0])
        check("launcher config icon default exists", icon_default_ok, str(defaults[:1]))
        fav_ok = len(defaults) >= 2 and "preferred://" in defaults[1] and "/home/" not in defaults[1]
        check("launcher default favorites use resolvable entries", fav_ok, str(defaults[1:2]))

    # ---- 4.5.1 Launcher Lote 3 (menu Iniciar): structure and stability rules ----
    def strip_qml(text):
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        return re.sub(r"//[^\n]*", "", text)

    lq = {q: strip_qml(read(os.path.join(ui_dir, q))) for q in qmls}
    for needed in ("FullRepresentation.qml", "CompactRepresentation.qml", "AppListDelegate.qml",
                   "AppTileDelegate.qml", "AppActions.qml", "QuickLink.qml", "XdgFolders.qml", "ItemBackground.qml"):
        check(f"launcher L3 component present: {needed}", needed in lq)
    if "FullRepresentation.qml" in lq and "AppActions.qml" in lq:
        full = lq["FullRepresentation.qml"]
        acts = lq["AppActions.qml"]
        # Regression guards for the two historical failures.
        check("launcher L3: no Instantiator nested inside a PlasmaExtras.Menu (QMenuItem list)",
              re.search(r"PlasmaExtras\.Menu\s*\{[^{}]*Instantiator", full + acts, flags=re.S) is None)
        check("launcher L3: Menu is a property value, Instantiator is a sibling (AppActions)",
              re.search(r"readonly property PlasmaExtras\.Menu menu:\s*PlasmaExtras\.Menu", acts) is not None
              and "Instantiator {" in acts and "root.menu.addMenuItem(object)" in acts)
        check("launcher L3: FullRepresentation imports only QtQuick/Plasma/KDE modules available on 6.6 (no Qt.labs)",
              "Qt.labs" not in full)
        check("launcher L3: Qt.labs.platform isolated in XdgFolders.qml behind a Loader",
              "Qt.labs.platform" in lq.get("XdgFolders.qml", "") and 'source: "XdgFolders.qml"' in full)
        check("launcher L3: favorites use official model calls (isFavorite/addFavorite/removeFavorite/moveRow)",
              all(k in acts for k in ("isFavorite(", "addFavorite(", "removeFavorite(", "moveRow(")))
        check("launcher L3: session actions only via SystemModel.trigger (no custom commands)",
              "systemModel.trigger(" in full
              and not any(re.search(r"systemctl|loginctl|shutdown -|reboot -|executeCommand|createQmlObject|Qt\.createComponent", t)
                          for t in lq.values()))
        check("launcher L3: no absolute user paths or invented applications",
              not any(re.search(r"/home/|file:///(?!/)", t) for t in lq.values()))
        check("launcher L3: search/Escape/Enter handled (clear -> close, activate current)",
              "Keys.onEscapePressed" in full and "activateCurrent" in full and "Keys.forwardTo" in full)
        check("launcher L3: popup size bounded by the usable screen area",
              "Screen.desktopAvailableHeight" in full and "Screen.desktopAvailableWidth" in full)
        check("launcher L3: delegates take the shared AppActions (no per-row Loader)",
              "required property var actions" in lq["AppListDelegate.qml"]
              and "Loader" not in lq["AppListDelegate.qml"]
              and "required property var actions" in lq["AppTileDelegate.qml"])
        check("launcher L3: state resets when the popup closes",
              "resetState" in full and "onExpandedChanged" in full)
        # Homologação 3 (P0): the executable DataSource lives in the
        # plasma5support QML module on Plasma 6.
        acts_raw = read(os.path.join(ui_dir, "AppActions.qml"))
        check("launcher uses plasma5support DataSource (Plasma 6 API)",
              "import org.kde.plasma.plasma5support" in acts_raw and "P5Support.DataSource" in acts_raw
              and "PlasmaCore.DataSource" not in acts_raw)

# ---- 5. Wallpaper packages ---------------------------------------------------
wall_root = os.path.join(SHARE, "wallpapers")
OFFICIAL_WALLPAPERS = {
    "EnthronedSoberania": ("wall1.png", "Enthroned — Soberania"),
    "EnthronedAscensao": ("wall2.png", "Enthroned — Ascensão"),
    "EnthronedVigilia": ("wall3.png", "Enthroned — Vigília"),
}
for official in OFFICIAL_WALLPAPERS:
    check(f"official wallpaper package present: {official}", os.path.isdir(os.path.join(wall_root, official)))
# wall3 (Vigilia) is the default everywhere a default is declared.
for laf in ("org.enthroned.classic", "org.enthroned.modern"):
    dtext = read(os.path.join(SHARE, "plasma", "look-and-feel", laf, "contents", "defaults"))
    check(f"default wallpaper is Vigilia: {laf}", re.search(r"^Image=EnthronedVigilia\s*$", dtext, re.M) is not None)
for rel in (("etc", "xdg", "kscreenlockerrc"), ("etc", "plasmalogin.conf.d", "10-enthroned.conf")):
    check(f"lock/login default wallpaper is Vigilia: {rel[-1]}",
          "wallpapers/EnthronedVigilia/" in read(os.path.join(ROOT, "system_files", *rel)))
for wall in sorted(d for d in os.listdir(wall_root) if os.path.isdir(os.path.join(wall_root, d))):
    base = os.path.join(wall_root, wall)
    try:
        meta = json.loads(read(os.path.join(base, "metadata.json")))
        check(f"wallpaper Id matches directory: {wall}", meta.get("KPlugin", {}).get("Id") == wall)
    except Exception as exc:  # noqa: BLE001
        check(f"wallpaper metadata readable: {wall}", False, str(exc))
        continue
    images = os.path.join(base, "contents", "images")
    pngs = sorted(f for f in os.listdir(images) if f.endswith(".png")) if os.path.isdir(images) else []
    if wall in OFFICIAL_WALLPAPERS:
        # Lote 13: the official art ships as the owner's original bytes at the
        # original size (never resampled), plus a picker thumbnail.
        source = os.path.join(ROOT, "assets", OFFICIAL_WALLPAPERS[wall][0])
        check(f"official wallpaper ships one original-size PNG: {wall}", len(pngs) == 1, str(pngs))
        if os.path.isfile(source) and pngs:
            with open(source, "rb") as a, open(os.path.join(images, pngs[0]), "rb") as b:
                check(f"official wallpaper is byte-identical to assets/{OFFICIAL_WALLPAPERS[wall][0]}: {wall}",
                      a.read() == b.read())
        check(f"official wallpaper has a picker thumbnail: {wall}",
              os.path.isfile(os.path.join(base, "contents", "screenshot.png")))
        check(f"official wallpaper picker name: {wall}",
              meta.get("KPlugin", {}).get("Name") == OFFICIAL_WALLPAPERS[wall][1],
              str(meta.get("KPlugin", {}).get("Name")))
    else:
        check(f"wallpaper has 3 resolutions: {wall}", len(pngs) >= 3, str(pngs))
    for png in pngs:
        with open(os.path.join(images, png), "rb") as fh:
            magic = fh.read(8)
        check(f"wallpaper PNG magic: {wall}/{png}", magic == b"\x89PNG\r\n\x1a\n")

# ---- 6. System-wide XDG defaults ---------------------------------------------
etc = os.path.join(ROOT, "system_files", "etc", "xdg")
for fname in ("dolphinrc", "kdeglobals"):
    path = os.path.join(etc, fname)
    ok = os.path.isfile(path)
    check(f"xdg default exists: {fname}", ok)
    if ok:
        ini = parse_ini(path)
        check(f"xdg default parses: {fname}", len(ini) > 0)
laf_default = parse_ini(os.path.join(etc, "kdeglobals")).get("KDE", {}).get("lookandfeelpackage")
check("xdg kdeglobals points at a shipped L&F", laf_default in laf_dirs, f"{laf_default!r}")
dini = parse_ini(os.path.join(etc, "dolphinrc"))
check("dolphinrc keeps GlobalViewProps", dini.get("General", {}).get("globalviewprops") == "true")
check("dolphinrc opens external folders in new tabs", dini.get("General", {}).get("openexternallycalledfolderinnewtab") == "true")

# ---- 6.2 Enthroned File Experience (Lote 2) -----------------------------------
dgen = dini.get("General", {})
check("dolphinrc: breadcrumb (not editable) + always-visible tab bar",
      dgen.get("editableurl") == "false" and dgen.get("alwaysshowtabbar") == "true")
check("dolphinrc: full-width status bar", dgen.get("showstatusbar") == "FullWidth")
check("dolphinrc: destructive confirmations untouched",
      not any(k.startswith("confirm") for k in dgen))
kg = parse_ini(os.path.join(etc, "kdeglobals"))
check("kdeglobals: double click opens (SingleClick=false)", kg.get("KDE", {}).get("singleclick") == "false")
for prof in ("classic", "modern"):
    pd = parse_ini(os.path.join(SHARE, "plasma", "look-and-feel", f"org.enthroned.{prof}", "contents", "defaults"))
    check(f"L&F {prof}: SingleClick lives in kdeglobals, not kcminputrc",
          pd.get("kdeglobals][KDE", {}).get("singleclick") == "false" and "singleclick" not in pd.get("kcminputrc][KDE", {}))
files_setup = os.path.join(USR, "libexec", "enthroned-files-setup")
check("enthroned-files-setup exists", os.path.isfile(files_setup))
if os.path.isfile(files_setup):
    ftext = read(files_setup)
    check("files-setup is valid Python", compile(ftext, files_setup, "exec") is not None)
    check("files-setup never touches root paths or other homes",
          "sudo" not in ftext and "shutil.rmtree" not in ftext and "os.remove" not in ftext and "unlink" not in ftext)
    check("files-setup refuses to overwrite user files", "if not target.exists()" in ftext and "xbel.exists()" in ftext)
    check("files-setup invents no drive letters", not re.search(r'[\"\'][C-F]:[\"\'\\\\/]', ftext))
autostart = os.path.join(etc, "autostart", "org.enthroned.files-setup.desktop")
check("files-setup autostart entry exists", os.path.isfile(autostart))
if os.path.isfile(autostart):
    atext = read(autostart)
    check("files-setup autostart runs the libexec script once, hidden",
          "Exec=/usr/libexec/enthroned-files-setup" in atext and "NoDisplay=true" in atext)
check("build.sh makes enthroned-files-setup executable",
      "chmod 0755 /usr/libexec/enthroned-files-setup" in read(os.path.join(ROOT, "build_files", "build.sh")))
# Titlebar must use the same colors whichever of [WM] / [Colors:Header] KWin reads.
for scheme in ("EnthronedLight", "EnthronedDark"):
    cs = parse_ini(os.path.join(SHARE, "color-schemes", f"{scheme}.colors"))
    wm, hdr, hin = cs["WM"], cs["Colors:Header"], cs["Colors:Header][Inactive"]
    check(f"{scheme}: active titlebar == Header",
          wm["activebackground"] == hdr["backgroundnormal"] == wm["activeblend"])
    check(f"{scheme}: inactive titlebar == Header[Inactive]",
          wm["inactivebackground"] == hin["backgroundnormal"] == wm["inactiveblend"])

# ---- 6.5 Profile switching tool ----------------------------------------------
profile_tool = os.path.join(USR, "bin", "enthroned-profile")
check("enthroned-profile tool exists", os.path.isfile(profile_tool))
if os.path.isfile(profile_tool):
    ptext = read(profile_tool)
    check("enthroned-profile uses official plasma-apply-lookandfeel", "plasma-apply-lookandfeel" in ptext)
    check("enthroned-profile references both Enthroned profiles", "org.enthroned.classic" in ptext and "org.enthroned.modern" in ptext)
    check("enthroned-profile records previous look-and-feel", "PREVIOUS_FILE" in ptext and "previous-lookandfeel" in ptext)
    check("enthroned-profile never elevates privileges", "sudo" not in ptext)

# ---- 7. Branding tokens -------------------------------------------------------
tokens_path = os.path.join(SHARE, "enthroned-os", "branding", "design-tokens.json")
try:
    tokens = json.loads(read(tokens_path))
    for key in ("logo", "launcher_icon_classic", "launcher_icon_modern", "wordmark", "wordmark_mono"):
        ref = tokens.get("brand", {}).get(key)
        ref_path = os.path.join(ROOT, "system_files", ref.lstrip("/")) if ref else None
        check(f"branding {key} exists", bool(ref) and os.path.isfile(ref_path), f"{ref}")
    for scheme in ("light", "dark"):
        ref = tokens.get("color_schemes", {}).get(scheme, {}).get("file")
        ref_path = os.path.join(ROOT, "system_files", ref.lstrip("/")) if ref else None
        check(f"branding {scheme} scheme exists", bool(ref) and os.path.isfile(ref_path), f"{ref}")
except Exception as exc:  # noqa: BLE001
    check("design tokens readable", False, str(exc))

# ---- 8. Hygiene: no user-home paths in shipped files --------------------------
bad = []
for base, _dirs, files in os.walk(USR):
    for f in files:
        ext = f.rsplit(".", 1)[-1].lower()
        if ext in {"json", "colors", "js", "qml", "rc", "xml", "desktop", "directory"} or f == "defaults":
            if "/home/" in read(os.path.join(base, f)):
                bad.append(os.path.relpath(os.path.join(base, f), ROOT))
check("no /home/ paths in shipped configs", not bad, str(bad))

# ---- 8.5 Branding: no Aurora in user-visible shipped strings ------------------
# Homologação 3 (P0): nothing the user can see may carry upstream branding.
# Scope: visible desktop-entry keys, non-comment lines of shipped configs,
# comment-stripped QML/JS and the Name/Description of KPackage metadata.
# Technical provenance files (identity.json, release-channel.json) are
# deliberately out of scope (ADR-0003: developer/terminal diagnostics only).


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"(^|\s)//[^\n]*", r"\1", text)


def visible_lines(text):
    return "\n".join(
        line.strip()
        for line in text.splitlines()
        if line.strip() and not line.strip().startswith(("#", ";"))
    )


SYS = os.path.join(ROOT, "system_files")
aurora_hits = []
for base, _dirs, files in os.walk(SYS):
    for f in sorted(files):
        ext = f.rsplit(".", 1)[-1].lower()
        path = os.path.join(base, f)
        rel = os.path.relpath(path, ROOT)
        try:
            if ext in {"qml", "js"}:
                text = strip_comments(read(path))
            elif ext in {"rc", "conf", "desktop", "directory"} or f == "defaults":
                text = visible_lines(read(path))
                if ext == "desktop":
                    text = "\n".join(
                        line for line in text.splitlines()
                        if line.lower().startswith(("name", "genericname", "comment"))
                    )
            elif f == "metadata.json":
                kp = json.loads(read(path)).get("KPlugin", {})
                text = " ".join(
                    str(v) for k, v in kp.items()
                    if k in {"Name", "Description"}
                    or k.startswith("Name[")
                    or k.startswith("Description[")
                )
            else:
                continue
        except Exception:  # noqa: BLE001
            continue
        if re.search(r"aurora", text, flags=re.I):
            aurora_hits.append(rel)
check("no Aurora branding in user-visible shipped strings", not aurora_hits, str(aurora_hits))
check("dead Plasma 5 kded5rc config removed", not os.path.isfile(os.path.join(ROOT, "system_files", "etc", "xdg", "kded5rc")))

# ---- 8.6 Desktop context menu (Lote 7.1) --------------------------------------
# The Enthroned ContainmentActions plugin wraps the stock Plasma menu and
# prepends the "Configurações do Enthroned" entry; a per-login user unit
# applies the type-keyed binding ([ActionPlugins][0], 0 = Desktop — the group
# libplasma reads when a desktop containment is created, first login
# included), preserves the native middle-click default and closes the
# separator gaps in the per-trigger subgroup the stock menu reads.
plugin_root = os.path.join(ROOT, "desktop-actions")
check("desktop-actions plugin project exists", os.path.isdir(plugin_root))
if os.path.isdir(plugin_root):
    cpp_path = os.path.join(plugin_root, "src", "enthronedcontextmenu.cpp")
    check("desktop-actions plugin source exists", os.path.isfile(cpp_path))
    if os.path.isfile(cpp_path):
        ctext = read(cpp_path)
        check("desktop-actions delegates to the stock Plasma menu plugin",
              "plasma/containmentactions/org.kde.contextmenu" in ctext)
        check("desktop-actions prepends the Enthroned Settings entry",
              "Configurações do Enthroned" in ctext)
        check("desktop-actions launches enthroned-settings with systemsettings fallback",
              "enthroned-settings" in ctext and "systemsettings" in ctext)
        check("desktop-actions forwards stock restore/save/actions",
              all(k in ctext for k in ("m_stock->restore(", "m_stock->save(", "m_stock->contextualActions()")))
        check("desktop-actions uses only public plugin API (no plasma sources patched)",
              "K_PLUGIN_CLASS_WITH_JSON" in ctext and "#include <Plasma/ContainmentActions>" in ctext)
    meta_path = os.path.join(plugin_root, "src", "org.enthroned.contextmenu.json")
    check("desktop-actions metadata exists", os.path.isfile(meta_path))
    if os.path.isfile(meta_path):
        try:
            meta = json.loads(read(meta_path))
            kp = meta.get("KPlugin", {})
            check("desktop-actions metadata Id correct", kp.get("Id") == "org.enthroned.contextmenu", str(kp.get("Id")))
            check("desktop-actions has no configuration UI", meta.get("X-Plasma-HasConfigurationInterface") is False)
            visible = " ".join(str(v) for k, v in kp.items()
                               if k.startswith("Name") or k.startswith("Description"))
            check("desktop-actions metadata has no Aurora branding", "aurora" not in visible.lower())
        except Exception as exc:  # noqa: BLE001
            check("desktop-actions metadata parses", False, str(exc))
    cmake_path = os.path.join(plugin_root, "CMakeLists.txt")
    check("desktop-actions CMake project exists", os.path.isfile(cmake_path))
    if os.path.isfile(cmake_path):
        cmake_text = read(cmake_path)
        check("desktop-actions installs under plasma/containmentactions",
              'INSTALL_NAMESPACE "plasma/containmentactions"' in cmake_text)
        check("desktop-actions output name is the plugin id",
              "OUTPUT_NAME org.enthroned.contextmenu" in cmake_text)
        check("desktop-actions links KF6::ConfigCore for KConfigGroup",
              "KF6::ConfigCore" in cmake_text)

unit_path = os.path.join(SYS, "usr", "lib", "systemd", "user", "enthroned-desktop-actions.service")
check("desktop-actions user unit exists", os.path.isfile(unit_path))
if os.path.isfile(unit_path):
    utext = read(unit_path)
    check("desktop-actions unit runs before plasmashell", "Before=plasma-plasmashell.service" in utext)
    check("desktop-actions unit is wanted by plasma-core.target", "WantedBy=plasma-core.target" in utext)
    check("desktop-actions unit runs the libexec script", "ExecStart=/usr/libexec/enthroned-desktop-actions" in utext)

script_path = os.path.join(SYS, "usr", "libexec", "enthroned-desktop-actions")
check("desktop-actions config script exists", os.path.isfile(script_path))
if os.path.isfile(script_path):
    stext = read(script_path)
    check("desktop-actions script binds the desktop right button",
          "RightButton;NoModifier" in stext and "org.enthroned.contextmenu" in stext)
    check("desktop-actions script keys the binding by containment type (first-login safe)",
          'DESKTOP_TYPE=0' in stext and '--group ActionPlugins --group "$DESKTOP_TYPE"' in stext)
    check("desktop-actions script preserves the native middle-click default",
          "MiddleButton;NoModifier" in stext and "org.kde.paste" in stext)
    # Lote 9.2 (H4-008): defaults seed ONLY absent keys (sentinel probe), and
    # only until the per-user migration marker exists; later removals stick.
    check("desktop-actions script seeds only absent keys, once per user (respects user config)",
          '--default "${ABSENT}"' in stext
          and '[[ "$value" == "${ABSENT}" ]] || continue' in stext
          and "desktop-actions.done" in stext)
    check("desktop-actions script heals a stale binding to the stock menu",
          "org.kde.contextmenu" in stext)
    check("desktop-actions script closes the empty-gap separators in the stock menu group",
          all(sep in stext for sep in ("_sep1", "_sep3", "_sep4"))
          and '--group "$TRIGGER"' in stext and "org.kde.plasma.folder" not in stext)
    check("desktop-actions script never elevates privileges", "sudo" not in stext)
    check("desktop-actions script always exits zero", "exit 0" in stext)

build_sh_text = read(os.path.join(ROOT, "build_files", "build.sh"))
check("build.sh makes enthroned-desktop-actions executable",
      "chmod 0755 /usr/libexec/enthroned-desktop-actions" in build_sh_text)
check("build.sh enables the desktop-actions user unit",
      "--global enable enthroned-desktop-actions.service" in build_sh_text)
check("build.sh normalizes desktop-actions file permissions",
      "/usr/lib/systemd/user/enthroned-*" in build_sh_text)
container_text = read(os.path.join(ROOT, "Containerfile"))
check("Containerfile compiles the desktop-actions plugin", "/src/desktop-actions" in container_text)
check("Containerfile installs libplasma-devel for the plugin", "libplasma-devel" in container_text)

# Settings must be presented as "Configurações do Enthroned" in every
# favorites entry point; the native System Settings stays as infrastructure
# (launcher Tools column keeps its own honest fallback).
favorites_paths = [
    os.path.join(SHARE, "plasma", "plasmoids", "org.enthroned.launcher", "contents", "config", "main.xml"),
    os.path.join(SHARE, "plasma", "look-and-feel", "org.enthroned.classic", "contents", "layouts", "org.kde.plasma.desktop-layout.js"),
    os.path.join(SHARE, "plasma", "look-and-feel", "org.enthroned.modern", "contents", "layouts", "org.kde.plasma.desktop-layout.js"),
    os.path.join(SYS, "etc", "xdg", "kicker-extra-favoritesrc"),
]
for fav_path in favorites_paths:
    fav_rel = os.path.relpath(fav_path, ROOT)
    ok = os.path.isfile(fav_path)
    check(f"favorites file exists: {fav_rel}", ok)
    if ok:
        ftext = read(fav_path)
        check(f"favorites pin Enthroned Settings: {fav_rel}",
              "org.enthroned.settings.desktop" in ftext and "systemsettings.desktop" not in ftext)

# ---- Lote 9: shipped systemd units (boot audit static checks) ----------------
# No systemd on this host: parse the unit files ourselves and assert the boot
# invariants (types, shipped ExecStart targets, no boot-chain wiring, valid
# timer targets, user unit ordering). Read-only.
systemd_sys_dir = os.path.join(SYS, "usr", "lib", "systemd", "system")
systemd_user_dir = os.path.join(SYS, "usr", "lib", "systemd", "user")

VALID_SERVICE_TYPES = {"oneshot", "simple", "exec", "notify", "dbus", "forking"}
# ExecStart targets that legitimately come from the Aurora base; each one must
# be guarded by a matching ConditionPathExists in the same unit.
BASE_EXEC_TARGETS = {
    "/usr/bin/uupd": "/usr/bin/uupd",
    "/usr/bin/bootc": "/usr/bin/bootc",
    "/usr/bin/flatpak": "/usr/bin/flatpak",
}
# Targets that gate the machine boot chain: no Enthroned unit may be enabled
# into them (background work must ride timers or the Plasma user session).
BOOT_CHAIN_TARGETS = {"sysinit.target", "basic.target", "multi-user.target", "graphical.target"}


def parse_unit(path):
    # Minimal systemd unit parser: sections -> list of raw (case-sensitive) lines.
    sections = {}
    current = None
    for raw in read(path).splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections.setdefault(current, [])
        elif current is not None:
            sections[current].append(line)
    return sections


def unit_value(sections, section, key):
    # systemd semantics: within a section, the last assignment of a key wins.
    value = None
    for line in sections.get(section, []):
        k, _, v = line.partition("=")
        if k.strip() == key:
            value = v.strip()
    return value


def misplaced_conditions(sections):
    # systemd honors Condition* only in [Unit]; elsewhere the key is ignored
    # with a warning and the unit runs unguarded (Lote 9 boot audit finding).
    return [(sec, line) for sec, lines in sections.items() if sec != "Unit"
            for line in lines if line.startswith("Condition")]


shipped_units = []
for unit_dir in (systemd_sys_dir, systemd_user_dir):
    if os.path.isdir(unit_dir):
        for fname in sorted(os.listdir(unit_dir)):
            if fname.endswith((".service", ".timer")):
                shipped_units.append((unit_dir, fname))

for unit_dir, fname in shipped_units:
    unit_path = os.path.join(unit_dir, fname)
    unit_rel = os.path.relpath(unit_path, ROOT)
    try:
        sections = parse_unit(unit_path)
    except Exception as exc:  # noqa: BLE001
        check(f"unit file parses: {unit_rel}", False, str(exc))
        continue
    check(f"unit has [Unit] Description: {unit_rel}", bool(unit_value(sections, "Unit", "Description")))
    stray = misplaced_conditions(sections)
    check(f"unit conditions live in [Unit] (systemd ignores them elsewhere): {unit_rel}",
          not stray, f"stray: {stray}")
    wanted_by = unit_value(sections, "Install", "WantedBy") or ""
    wired = [t for t in re.split(r"[ ,]+", wanted_by) if t in BOOT_CHAIN_TARGETS]
    check(f"unit is not enabled into the boot chain: {unit_rel}", not wired, f"WantedBy={wanted_by}")
    if fname.endswith(".service"):
        service_type = unit_value(sections, "Service", "Type")
        check(f"service Type is standard: {unit_rel}", service_type in VALID_SERVICE_TYPES, f"Type={service_type}")
        exec_start = unit_value(sections, "Service", "ExecStart")
        check(f"service has ExecStart: {unit_rel}", bool(exec_start))
        if exec_start:
            exe = exec_start.lstrip("+!-").split()
            exe_path = exe[0] if exe else ""
            if exe_path.startswith("/usr/libexec/enthroned-"):
                check(f"ExecStart target is shipped in the image: {unit_rel}",
                      os.path.isfile(os.path.join(SYS, exe_path.lstrip("/"))), exe_path)
            else:
                condition = unit_value(sections, "Unit", "ConditionPathExists")
                check(f"base-image ExecStart is guarded by ConditionPathExists: {unit_rel}",
                      BASE_EXEC_TARGETS.get(exe_path) == condition,
                      f"ExecStart={exe_path} ConditionPathExists={condition}")
    else:
        trigger = unit_value(sections, "Timer", "OnBootSec") \
            or unit_value(sections, "Timer", "OnCalendar") \
            or unit_value(sections, "Timer", "OnUnitActiveSec")
        check(f"timer has a time trigger: {unit_rel}", bool(trigger))
        unit_ref = unit_value(sections, "Timer", "Unit")
        if unit_ref:
            check(f"timer references a shipped unit: {unit_rel}",
                  os.path.isfile(os.path.join(systemd_sys_dir, unit_ref)), unit_ref)
        check(f"timer installs into timers.target only: {unit_rel}", wanted_by == "timers.target", f"WantedBy={wanted_by}")

user_unit = os.path.join(systemd_user_dir, "enthroned-desktop-actions.service")
if os.path.isfile(user_unit):
    user_rel = os.path.relpath(user_unit, ROOT)
    sections = parse_unit(user_unit)
    check("user unit orders Before plasmashell: enthroned-desktop-actions.service",
          "plasma-plasmashell.service" in (unit_value(sections, "Unit", "Before") or ""))
    check("user unit is wanted by plasma-core.target (valid Plasma 6 workspace target): enthroned-desktop-actions.service",
          unit_value(sections, "Install", "WantedBy") == "plasma-core.target")

files_setup = os.path.join(SYS, "usr", "libexec", "enthroned-files-setup")
if os.path.isfile(files_setup):
    check("first-boot files-setup keeps a state marker (idempotent)",
          "MARKER" in read(files_setup))
firstboot_flatpaks = os.path.join(SYS, "usr", "libexec", "enthroned-firstboot-flatpaks")
if os.path.isfile(firstboot_flatpaks):
    flatpak_text = read(firstboot_flatpaks)
    check("first-boot flatpaks records progress in a marker file", "MARKER_FILE" in flatpak_text)
    check("first-boot flatpaks defers with exit 75 when offline",
          bool(re.search(r'write_status offline "reason=no-network"\s+exit 75', flatpak_text)))
check("build.sh normalizes shipped system unit permissions",
      "/usr/lib/systemd/system/enthroned-*" in build_sh_text)
check("boot audit script exists for in-VM collection", os.path.isfile(os.path.join(ROOT, "scripts", "boot-audit-vm.sh")))

# ---- Lote 15: Dolphin menu, folder colours, personalization ---------------------
import xml.etree.ElementTree as ET
ksm = parse_ini(os.path.join(SYS, "etc", "xdg", "kservicemenurc")).get("Show", {})
check("kservicemenurc hides the Filelight disk-usage entry", ksm.get("filelight") == "false")
check("kservicemenurc hides the folder-colour swatch strip", ksm.get("setfoldericonitemaction") == "false")
check("kservicemenurc touches nothing else", set(ksm) == {"filelight", "setfoldericonitemaction"}, str(sorted(ksm)))
FOLDER_COLOURS = ["black", "blue", "brown", "cyan", "green", "grey", "magenta", "orange", "red", "violet", "yellow"]
for theme in ("Enthroned", "EnthronedDark"):
    places = os.path.join(SHARE, "icons", theme, "scalable", "places")
    for suffix in ("", "-open"):
        files = [os.path.join(places, f"folder-{c}{suffix}.svg") for c in FOLDER_COLOURS]
        ok = all(os.path.isfile(f) for f in files)
        check(f"{theme}: folder-<colour>{suffix}.svg for the 11 KDE folder colours", ok)
        if ok:
            for f in files:
                ET.parse(f)  # raises on malformed SVG
            base = read(os.path.join(places, f"folder{suffix}.svg"))
            check(f"{theme}: folder-violet{suffix} equals the base violet folder",
                  read(os.path.join(places, f"folder-violet{suffix}.svg")) == base)
            check(f"{theme}: every other colour{suffix} differs from the base",
                  all(read(f) != base for f in files if "violet" not in f))
frep = read(os.path.join(SHARE, "plasma", "plasmoids", "org.enthroned.launcher", "contents", "ui", "FullRepresentation.qml"))
check("launcher L15: wider popup + places column collapses before squeezing the app list",
      "gridUnit * 50" in frep and "placesCompact" in frep and "Layout.minimumWidth: Kirigami.Units.gridUnit * 14" in frep
      and "Layout.fillWidth: false" in frep)
eprof = read(os.path.join(USR, "bin", "enthroned-profile"))
check("enthroned-profile keeps desktop icon size and accent across a switch",
      all(x in eprof for x in ("iconsize_snapshot", "iconsize_restore", "accent_restore")) and eprof.count("accent_restore\n") >= 2)
pers_cpp15 = strip_comments(read(os.path.join(ROOT, "settings", "src", "personalizationcontroller.cpp")))
check("personalization passes the colour-scheme FILE id to plasma-apply-colorscheme",
      '"EnthronedLight"' in pers_cpp15 and '"EnthronedDark"' in pers_cpp15 and '"Enthroned Light"' not in pers_cpp15)

# ---- summary -----------------------------------------------------------------
print()
if failures:
    print(f"RESULT: {len(failures)} FAILURES")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("RESULT: ALL CHECKS PASSED")
PYEOF
