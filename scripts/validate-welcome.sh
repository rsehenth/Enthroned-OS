#!/bin/bash
# Enthroned OS - static validation of the F4 applications & welcome phase.
# No Qt/KDE, no image build, no network: JSON parsing, spec consistency,
# QML balance/i18n/hardcoded-color checks, C++ safety greps (no sudo/pkexec,
# no curl|bash, installer gate + SHA-256 verification present, no system
# mutation), first-run policy checks (autostart, single instance, atomic
# persistence), image integration checks (firstboot flatpak unit/timer,
# mimeapps defaults, build.sh, active Containerfile stage, launcher
# favorites untouched) and the node logic tests.
# Read-only: never modifies the repository or the host.
#
# Requirements: python3 (or python). Node is optional (runs the logic tests).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

if command -v node >/dev/null 2>&1; then
    node --check "$SCRIPT_DIR/../welcome/tests/run-tests.mjs" \
        && echo "PASS: node syntax: welcome/tests/run-tests.mjs" \
        || { echo "FAIL: node syntax: welcome/tests/run-tests.mjs"; exit 1; }
    node "$SCRIPT_DIR/../welcome/tests/run-tests.mjs"
    TEST_RC=$?
    if [ "$TEST_RC" -ne 0 ]; then
        echo "FAIL: node logic tests (welcome/tests/run-tests.mjs)"
        exit 1
    fi
else
    echo "WARN: node not found; logic tests skipped (NOT RUN)"
fi

exec "$PYTHON" - "$SCRIPT_DIR" <<'PYEOF'
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

script_dir = sys.argv[1]
ROOT = os.path.dirname(script_dir)
WELCOME = os.path.join(ROOT, "welcome")
SRC = os.path.join(WELCOME, "src")
QML = os.path.join(WELCOME, "qml")
DATA = os.path.join(WELCOME, "data")
TESTS = os.path.join(WELCOME, "tests")
SYSFILES = os.path.join(ROOT, "system_files")
USR = os.path.join(SYSFILES, "usr")

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


def balanced(text):
    pairs = {"{": "}", "(": ")", "[": "]"}
    counts = {}
    for ch in text:
        if ch in pairs:
            counts[ch] = counts.get(ch, 0) + 1
        elif ch in pairs.values():
            opening = next((k for k, v in pairs.items() if v == ch), None)
            if opening:
                counts[opening] = counts.get(opening, 0) - 1
    return all(v == 0 for v in counts.values())


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


# ---- 1. Spec + scenario fixtures ---------------------------------------------
spec_path = os.path.join(SRC, "welcome-state-spec.json")
spec = json.loads(read(spec_path))
check("spec: json parses", True)

states = set(spec["states"])
check("spec: 8 walkthrough phases", spec["states"] == [
    "never-started", "started", "interrupted", "completed", "dismissed",
    "optional-pending", "optional-done", "optional-failed"])
check("spec: initial in states", spec["initial"] in states)
event_types = set(spec["event_types"])
bad = [t for t in spec["transitions"]
       if t["from"] not in states or t["to"] not in states or t["event"] not in event_types]
check("spec: all transitions reference known states/events", not bad, str(bad[:3]))
check("spec: consent not implied by absence",
      spec["installer"]["consent_required"] is True
      and spec["installer"]["default_checkbox"] is False)
check("spec: installer gate declared",
      spec["installer"]["env_gate"] == "ENTHRONED_WELCOME_ALLOW_INSTALL"
      and spec["installer"]["default_when_gate_closed"] == "blocked")
check("spec: no silent install",
      spec["installer"]["no_silent_install"] is True
      and spec["installer"]["checksums"].startswith("SHA256SUMS.txt"))
check("spec: apps policy honest",
      spec["apps_policy"]["launch_action_requires_available"] is True
      and spec["apps_policy"]["no_fake_controls"] is True)
check("spec: profile apply needs explicit action",
      spec["profile_policy"]["apply_requires_explicit_action"] is True)

scenario_files = sorted(f for f in os.listdir(os.path.join(TESTS, "scenarios")) if f.endswith(".json"))
check("scenarios: 20 fixtures present", len(scenario_files) == 20, str(len(scenario_files)))
names = set()
for f in scenario_files:
    s = json.loads(read(os.path.join(TESTS, "scenarios", f)))
    check(f"scenario: {f} coherent", bool(s.get("name")) and bool(s.get("kind")))
    names.add(s["name"])
check("scenarios: unique names", len(names) == len(scenario_files))

demo_dir = os.path.join(SRC, "demo", "scenarios")
demo_files = sorted(f for f in os.listdir(demo_dir) if f.endswith(".json"))
check("demo: 4 installer scenarios", len(demo_files) == 4, str(demo_files))
for f in demo_files:
    d = json.loads(read(os.path.join(demo_dir, f)))
    check(f"demo: {f} steps within contract",
          all(step.get("state") in spec["installer"]["states"] for step in d["steps"]))

# ---- 2. QML files -------------------------------------------------------------
qml_files = []
for base, _dirs, files in os.walk(QML):
    for f in sorted(files):
        if f.endswith(".qml"):
            qml_files.append(os.path.join(base, f))
check("qml: 9 files exist", len(qml_files) == 9, str(len(qml_files)))

for path in qml_files:
    rel = os.path.relpath(path, WELCOME).replace("\\", "/")
    text = read(path)
    check(f"qml: braces balanced: {rel}", balanced(text))
    hex_colors = re.findall(r"#[0-9a-fA-F]{3,8}\b", text)
    check(f"qml: no hardcoded colors: {rel}", not hex_colors, str(hex_colors[:3]))
    raw_text_literals = [
        m for m in re.findall(r"\btext:\s*\"([^\"]*)\"", text)
        if re.search(r"[A-Za-zÀ-ÿ]", m)
    ]
    check(f"qml: every text uses i18n(): {rel}", not raw_text_literals,
          str(raw_text_literals[:3]))
    if "/components/" not in rel:
        check(f"qml: i18n used: {rel}", "i18n(" in text)
    check(f"qml: WebView not used: {rel}", "WebView" not in text)

qml_names = {os.path.basename(p) for p in qml_files}
check("qml: five wizard pages + roadmap page exist",
      {"WelcomePage.qml", "StylePage.qml", "AppsPage.qml", "ArtcraftPage.qml",
       "FinishPage.qml", "RoadmapPage.qml"} <= qml_names)

main_qml = read(os.path.join(QML, "Main.qml"))
check("qml: closing marks the walkthrough", "markClosed" in main_qml)
check("qml: five steps wired", main_qml.count("Component { id:") == 5)
check("qml: roadmap tab wired", "RoadmapPage" in main_qml and 'i18n("Roadmap")' in main_qml)

roadmap_qml = read(os.path.join(QML, "pages", "RoadmapPage.qml"))
# Lote 6.1: source strings are English msgids; the pt_BR catalog translates them.
for needle in ("The Enthroned OS vision", "Interface and experience",
               "Intelligent Device Manager", "Performance and optimization",
               "Simplified updates", "Enthroned Compatibility Engine",
               "Profiles and personalization", "Classic", "Modern",
               "headphones with spatial audio", "universal support"):
    check(f"qml: roadmap contains '{needle}'", needle in roadmap_qml)

artcraft_qml = read(os.path.join(QML, "pages", "ArtcraftPage.qml"))
check("qml: consent checkbox exists", "I want to install ArtCraft Launcher" in artcraft_qml)
check("qml: no pre-checked consent",
      re.search(r'checked:\s*true', artcraft_qml) is None)
check("qml: explicit confirm dialog before install", "Install ArtCraft Launcher?" in artcraft_qml)
check("qml: honest skip action", "Not now" in artcraft_qml)

# ---- 3. C++ sources: safety invariants ---------------------------------------
cpp_files = []
for base, _dirs, files in os.walk(SRC):
    for f in sorted(files):
        if f.endswith((".cpp", ".h")):
            cpp_files.append(os.path.join(base, f))
check("cpp: 9 files exist", len(cpp_files) == 9, str(len(cpp_files)))

for path in cpp_files:
    rel = os.path.relpath(path, SRC).replace("\\", "/")
    code = strip_comments(read(path))
    for forbidden in ("sudo ", "pkexec", "system(", "popen("):
        check(f"cpp: no '{forbidden.strip()}': {rel}", forbidden not in code)
    check(f"cpp: no curl pipe: {rel}", "curl" not in code)

controller = read(os.path.join(SRC, "welcomecontroller.cpp"))
check("cpp: atomic persistence (QSaveFile)", "QSaveFile" in controller and "commit()" in controller)
check("cpp: invalid state resets to initial", "coherent" in controller)
check("cpp: launch policy implemented", "shouldShowOnLaunch" in controller)
check("cpp: XDG state home persistence",
      "StateLocation" in controller and "enthroned-os" in controller)

installer = read(os.path.join(SRC, "artcraftinstaller.cpp"))
check("cpp: installer gate enforced", "ENTHRONED_WELCOME_ALLOW_INSTALL" in installer)
check("cpp: gate closed blocks without network", "blocked" in installer)
check("cpp: official source only",
      "api.github.com/repos/storytold/craft-launcher" in installer
      and installer.count("http") == 1)
check("cpp: SHA-256 verification", "QCryptographicHash::Sha256" in installer
      and "SHA256SUMS" in installer)
check("cpp: user-level flatpak only",
      '"install"' in installer and '"--user"' in installer
      and "--system" not in strip_comments(installer)
      and "rpm-ostree" not in installer)
check("cpp: user agent declared", "User-Agent" in installer and "enthroned-welcome/" in installer)
check("cpp: app id verified after install", "ai.storyteller.artcraft-launcher" in installer)
check("cpp: no auto-start of install", "Q_INVOKABLE void install()" in
      read(os.path.join(SRC, "artcraftinstaller.h")))

main_cpp = read(os.path.join(SRC, "main.cpp"))
check("cpp: single instance lock", "QLockFile" in main_cpp and "tryLock" in main_cpp)
check("cpp: autostart honored", "--autostart" in main_cpp
      and "shouldShowOnLaunch" in main_cpp)
check("cpp: demo mode exists", "demoOption" in main_cpp)

# ---- 4. Packaging / data ------------------------------------------------------
cmake = read(os.path.join(WELCOME, "CMakeLists.txt"))
check("cmake: references Kirigami/KI18n/Network",
      all(x in cmake for x in ("KF6::Kirigami", "KF6::I18n", "Qt6::Network")))
qml_in_cmake = set(re.findall(r"qml/[\w/]+\.qml", cmake))
on_disk = {os.path.relpath(p, WELCOME).replace("\\", "/") for p in qml_files}
check("cmake: all QML files declared", on_disk <= qml_in_cmake, str(on_disk - qml_in_cmake))
check("cmake: declared QML files exist", qml_in_cmake <= on_disk, str(qml_in_cmake - on_disk))
check("cmake: spec + 4 demo scenarios embedded",
      "welcome-state-spec.json" in cmake and cmake.count("scenarios/") >= 4)
check("cmake: autostart installed", "xdg/autostart" in cmake)

desktop = read(os.path.join(DATA, "org.enthroned.welcome.desktop"))
check("desktop: valid entry", "[Desktop Entry]" in desktop and "Type=Application" in desktop)
check("desktop: Exec matches binary", "Exec=enthroned-welcome" in desktop)
check("desktop: icon declared", "Icon=org.enthroned.welcome" in desktop)
_sizes = (16, 22, 24, 32, 48, 64, 128, 256, 512)
_icons = [os.path.join(DATA, "icons", "hicolor", f"{n}x{n}", "apps", "org.enthroned.welcome.png") for n in _sizes]
check("desktop: official icon set (hicolor PNG 16-512) exists", all(os.path.isfile(f) for f in _icons))
check("cmake: installs the hicolor icon directory", "install(DIRECTORY data/icons/hicolor" in cmake)
check("desktop: no leftover scalable placeholder icon",
      not os.path.exists(os.path.join(DATA, "icons", "org.enthroned.welcome.svg")))

autostart = read(os.path.join(DATA, "org.enthroned.welcome.autostart.desktop"))
check("autostart: valid entry", "[Desktop Entry]" in autostart and "Type=Application" in autostart)
check("autostart: uses the autostart flag", "Exec=enthroned-welcome --autostart" in autostart)
check("autostart: restricted to the Plasma session", "OnlyShowIn=KDE;" in autostart)
check("autostart: no system service behind it", "systemd" not in autostart.lower())
# Lote 11B (H5 P2-6): the resume condition must be self-contained. A
# X-KDE-autostart-after dependency defers the start until the referenced app
# registers with the session manager; if that registration never lands, the
# assistant silently never opens on a later login even with a "started" state.
check("autostart: resume condition is self-contained (no X-KDE-autostart-after)",
      "X-KDE-autostart-after" not in autostart)

try:
    ET.parse(os.path.join(DATA, "org.enthroned.welcome.appdata.xml"))
    check("appdata: xml parses", True)
except ET.ParseError as exc:
    check("appdata: xml parses", False, str(exc))

check("packaging: no dead welcome shortcut in system_files",
      not os.path.exists(os.path.join(USR, "share", "applications", "org.enthroned.welcome.desktop")))

# ---- 5. Image integration ------------------------------------------------------
unit_path = os.path.join(USR, "lib", "systemd", "system", "enthroned-firstboot-flatpaks.service")
check("unit: firstboot flatpaks exists", os.path.isfile(unit_path))
unit = read(unit_path)
check("unit: guarded by flatpak + list file",
      "ConditionPathExists=/usr/bin/flatpak" in unit
      and "ConditionFileNotEmpty=/usr/share/enthroned-os/firstboot-flatpaks.txt" in unit)
check("unit: runs the provisioning script", "ExecStart=/usr/libexec/enthroned-firstboot-flatpaks" in unit)
check("unit: not per-user first-run control", "[Install]" not in unit)

timer_path = os.path.join(USR, "lib", "systemd", "system", "enthroned-firstboot-flatpaks.timer")
check("timer: exists and is installable", os.path.isfile(timer_path)
      and "WantedBy=timers.target" in read(timer_path))

script_path = os.path.join(USR, "libexec", "enthroned-firstboot-flatpaks")
check("script: provisioning script exists", os.path.isfile(script_path))
script = read(script_path)
check("script: installs only from the shipped list",
      "firstboot-flatpaks.txt" in script and 'done <"${LIST_FILE}"' in script)
check("script: idempotent + offline-safe", "--noninteractive" in script and "exit 0" in script)
check("script: no script execution", "bash <" not in script and "| bash" not in script)
check("script: no remote manipulation",
      "remote-add" not in script and "remote-delete" not in script)

flatpak_list = read(os.path.join(USR, "share", "enthroned-os", "firstboot-flatpaks.txt"))
flatpak_entries = [l.strip() for l in flatpak_list.splitlines()
                   if l.strip() and not l.strip().startswith("#")]
check("list: brave is the only default flatpak",
      flatpak_entries == ["com.brave.Browser"], str(flatpak_entries))

mimeapps = read(os.path.join(ROOT, "system_files", "etc", "xdg", "mimeapps.list"))
check("mimeapps: brave is the http/https/html default",
      all(v in mimeapps for v in
          ("x-scheme-handler/http=com.brave.Browser.desktop",
           "x-scheme-handler/https=com.brave.Browser.desktop",
           "text/html=com.brave.Browser.desktop")))
check("mimeapps: defaults only (no Added/Removed associations)",
      "[Added Associations]" not in mimeapps and "[Removed Associations]" not in mimeapps)

build_sh = read(os.path.join(ROOT, "build_files", "build.sh"))
# Lote 11B: check updated to the current build.sh (P2-2 follow-up): Discover is
# still guaranteed, with the RPM/PackageKit and offline-update backends
# excluded so Discover cannot offer atomic-system updates.
check("build.sh: discover guaranteed",
      "plasma-discover plasma-discover-flatpak" in build_sh
      and "--exclude=plasma-discover-packagekit" in build_sh
      and "--exclude=plasma-discover-offline-updates" in build_sh)
check("build.sh: flatpak provisioning timer enabled",
      "systemctl enable enthroned-firstboot-flatpaks.timer" in build_sh)
check("build.sh: provisioning script executable bit",
      "chmod 0755 /usr/libexec/enthroned-firstboot-flatpaks" in build_sh)

containerfile = read(os.path.join(ROOT, "Containerfile"))
check("containerfile: welcome compiled and installed through shared builder",
      "FROM runtime AS apps-builder" in containerfile
      and "cmake -S /src/welcome" in containerfile
      and "DESTDIR=/out cmake --install /build/welcome" in containerfile
      and "COPY --from=apps-builder /out/ /" in containerfile)
check("containerfile: final stage intact", "bootc container lint" in containerfile)

# F4.10: launcher favorites keep using resolvable system defaults.
launcher_cfg = read(os.path.join(USR, "share", "plasma", "plasmoids", "org.enthroned.launcher",
                                 "contents", "config", "main.xml"))
check("launcher: favorites resolve via preferred://browser", "preferred://browser" in launcher_cfg)
check("launcher: favorites not hardcoded to a browser id",
      "com.brave.Browser" not in launcher_cfg)
for laf in ("org.enthroned.classic", "org.enthroned.modern"):
    layout = read(os.path.join(USR, "share", "plasma", "look-and-feel", laf,
                               "contents", "layouts", "org.kde.plasma.desktop-layout.js"))
    check(f"layout {laf}: favorites resolvable", "preferred://browser" in layout
          and "com.brave.Browser" not in layout)

justfile = read(os.path.join(ROOT, "Justfile"))
check("justfile: verify-welcome recipe", "verify-welcome" in justfile)

# ---- 6. Settings integration (F4.9) --------------------------------------------
apps_page = read(os.path.join(ROOT, "settings", "qml", "pages", "AppsPage.qml"))
check("settings: discover entry point", "launchApp(\"plasma-discover\")" in apps_page)
check("settings: welcome reopen entry point", "launchApp(\"enthroned-welcome\")" in apps_page)
check("settings: artcraft information without dead shortcut",
      "ai.storyteller.artcraft-launcher" in apps_page and "ArtCraft Launcher (optional)" in apps_page)
kcmlauncher = read(os.path.join(ROOT, "settings", "src", "kcmlauncher.cpp"))
check("settings: honest availability helpers", "hasExecutable" in kcmlauncher
      and "hasFlatpakApp" in kcmlauncher and "launchApp" in kcmlauncher)

# ---- 7. Documentation ----------------------------------------------------------
for doc in ("docs/phases/F4-APPLICATIONS-WELCOME.md",
            "docs/architecture/ENTHRONED-FIRST-RUN-ARCHITECTURE.md",
            "docs/operations/DEFAULT-APPLICATIONS.md",
            "docs/operations/WELCOME-INTEGRATION.md",
            "docs/validation/F4-STATIC-VALIDATION.md",
            "docs/architecture/ADR-0006-default-applications.md"):
    check(f"docs: {doc} exists", os.path.isfile(os.path.join(ROOT, doc.replace("/", os.sep))))

# ---- Report --------------------------------------------------------------------
print()
if failures:
    print(f"VALIDATION FAILED: {len(failures)} check(s) failed:")
    for name in failures:
        print(f"  - {name}")
    sys.exit(1)
print("All welcome validation checks passed.")
PYEOF
