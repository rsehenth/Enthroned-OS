#!/bin/bash
# Enthroned OS - static validation of the F3 settings & update center.
# No Qt/KDE, no image build, no network: JSON/XML parsing, spec consistency,
# QML balance/i18n/hardcoded-color checks, C++ safety greps (no sudo/pkexec,
# mutation gate present), image integration checks (unit, polkit, desktop
# entry, Containerfile multi-stage installation) and the node logic tests.
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
    node --check "$SCRIPT_DIR/../settings/tests/run-tests.mjs" \
        && echo "PASS: node syntax: settings/tests/run-tests.mjs" \
        || { echo "FAIL: node syntax: settings/tests/run-tests.mjs"; exit 1; }
    node "$SCRIPT_DIR/../settings/tests/run-tests.mjs"
    TEST_RC=$?
    if [ "$TEST_RC" -ne 0 ]; then
        echo "FAIL: node logic tests (settings/tests/run-tests.mjs)"
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
SETTINGS = os.path.join(ROOT, "settings")
SRC = os.path.join(SETTINGS, "src")
QML = os.path.join(SETTINGS, "qml")
DATA = os.path.join(SETTINGS, "data")
UPDATE = os.path.join(SRC, "update")
SCENARIOS = os.path.join(UPDATE, "demo", "scenarios")
SYSFILES = os.path.join(ROOT, "system_files", "usr")

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
    # Remove // line comments and /* */ block comments (no string awareness;
    # adequate for these safety greps).
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


# ---- 1. Spec + scenarios parse and self-consistency --------------------------
spec_path = os.path.join(UPDATE, "update-state-spec.json")
spec = json.loads(read(spec_path))
check("spec: json parses", True)

states = set(spec["states"])
check("spec: initial in states", spec["initial"] in states)
event_types = set(spec["event_types"])
bad_transitions = [
    t for t in spec["transitions"]
    if t["from"] not in states or t["to"] not in states or t["event"] not in event_types
]
check("spec: all transitions reference known states/events", not bad_transitions,
      str(bad_transitions[:3]))
check("spec: journal_mapping has rules", len(spec["journal_mapping"]) >= 5)
check("spec: journal_mapping events known",
      all(r.get("event") in (event_types | {"ignore"}) for r in spec["journal_mapping"]))
bp = spec["bootc_progress"]["phases"]
check("spec: bootc_progress windows valid",
      all("phase" in w and "start" in w and "length" in w for w in bp.values())
      and set(bp) == {"pulling", "importing", "staging", "unknown"})

scenario_files = sorted(f for f in os.listdir(SCENARIOS) if f.endswith(".json"))
# Lote 8: 12 fixtures originais + 8 novos (system-update, apps-update,
# rollback-success, rollback-failed, preflight-blocked, download-interrupted,
# origin-unauthorized, staged-recovery).
check("scenarios: 20 fixtures present", len(scenario_files) == 20, str(scenario_files))
scenario_names = set()
for f in scenario_files:
    s = json.loads(read(os.path.join(SCENARIOS, f)))
    ok = bool(s.get("name")) and bool(s.get("steps")) and s.get("finalState") in states
    check(f"scenario: {f} coherent", ok)
    scenario_names.add(s.get("name"))
check("scenarios: unique names", len(scenario_names) == len(scenario_files))

# Lote 8: the spec must expose the new states/events used by the engine.
lote8_states = {"rollingBack"}
lote8_events = {"engine-rollback-started", "rollback-success", "rollback-failed",
                "flatpak-progress", "flatpak-update-success", "flatpak-update-failed",
                "preflight-blocked", "staged-origin-blocked", "update-rejected",
                "concurrent-operation-detected", "spec-error"}
check("spec: lote8 states declared", lote8_states <= states)
check("spec: lote8 events declared", lote8_events <= event_types)
rollback_transitions = [t for t in spec["transitions"]
                        if t["event"] == "engine-rollback-started"]
check("spec: rollback requires mutation + previous deployment",
      rollback_transitions
      and all(set(t["requires"]) == {"mutationAllowed", "rollbackAvailable"}
              for t in rollback_transitions))
check("spec: journal_mapping parses raw bootc --progress-fd lines",
      any(r.get("payloadFromMessage") for r in spec["journal_mapping"]))

# ---- 2. QML files ------------------------------------------------------------
qml_files = []
for base, _dirs, files in os.walk(QML):
    for f in sorted(files):
        if f.endswith(".qml"):
            qml_files.append(os.path.join(base, f))
check("qml: files exist", len(qml_files) >= 10, str(len(qml_files)))

for path in qml_files:
    rel = os.path.relpath(path, SETTINGS).replace("\\", "/")
    text = read(path)
    check(f"qml: braces balanced: {rel}", balanced(text))
    hex_colors = re.findall(r"#[0-9a-fA-F]{3,8}\b", text)
    check(f"qml: no hardcoded colors: {rel}", not hex_colors, str(hex_colors[:3]))
    # Only flag literals that actually contain letters (symbols such as
    # "• " and "[" are not translatable text).
    raw_text_literals = [
        m for m in re.findall(r"\btext:\s*\"([^\"]*)\"", text)
        if re.search(r"[A-Za-zÀ-ÿ]", m)
    ]
    check(f"qml: every text uses i18n(): {rel}", not raw_text_literals,
          str(raw_text_literals[:3]))
    if "/components/" not in rel:
        check(f"qml: i18n used: {rel}", "i18n(" in text)

qml_names = {os.path.basename(p) for p in qml_files}
check("qml: page ids referenced by navigation exist",
      {"HomePage.qml", "FocusPage.qml", "SystemPage.qml", "AppearancePage.qml", "AppsPage.qml",
       "DevicesPage.qml", "UpdatesPage.qml", "AboutPage.qml", "NetworkPage.qml",
       "AccountsPage.qml", "TimeLanguagePage.qml", "AccessibilityPage.qml",
       "PrivacyPage.qml"} <= qml_names)
check("qml: reusable module/shortcut components exist",
      {"ModuleCard.qml", "ModuleList.qml", "ShortcutTile.qml", "SearchIndex.qml"} <= qml_names)
check("qml: search.js exists", os.path.isfile(os.path.join(QML, "search.js")))
nav_ids = re.findall(r'\{ id: "(\w+)", title: i18n', read(os.path.join(QML, "Main.qml")))
# Lote 6: 12 original areas + the 3 Modo Simples focus areas.
check("qml: navigation exposes the 15 settings areas", len(nav_ids) == 15, str(nav_ids))
check("qml: pages do not fake data (no hardcoded hardware strings)",
      not any(re.search(r"(GeForce|Ryzen|Intel\(R\)|Core i[3579]|\bGB\b)", read(p)) for p in qml_files))

# Every spec state handled in UpdatesPage switch
updates_qml = read(os.path.join(QML, "pages", "UpdatesPage.qml"))
missing_states = [s for s in states if f'"{s}"' not in updates_qml]
check("qml: UpdatesPage handles every spec state", not missing_states, str(missing_states))
main_qml = read(os.path.join(QML, "Main.qml"))
# Lote 6.1: source strings are English msgids; the pt_BR catalog translates them.
check("qml: demo banner present in Main", "Demo mode" in main_qml)

# ---- 3. C++ sources: safety invariants ---------------------------------------
cpp_files = []
for base, _dirs, files in os.walk(SRC):
    for f in sorted(files):
        if f.endswith((".cpp", ".h")):
            cpp_files.append(os.path.join(base, f))
check("cpp: files exist", len(cpp_files) >= 25, str(len(cpp_files)))

for path in cpp_files:
    rel = os.path.relpath(path, SETTINGS)
    code = strip_comments(read(path))
    for forbidden in ("sudo ", "pkexec", "system(", "popen("):
        check(f"cpp: no '{forbidden.strip()}': {rel}", forbidden not in code)

engine_cpp = strip_comments(read(os.path.join(UPDATE, "updateengine.cpp")))
check("cpp: mutation gate present", "ENTHRONED_SETTINGS_ALLOW_MUTATION" in engine_cpp)
check("cpp: rejection event implemented", "update-rejected" in engine_cpp)
check("cpp: demo mode flag present", "ENTHRONED_SETTINGS_DEMO" in engine_cpp)
check("cpp: no direct uupd invocation",
      "uupd " not in engine_cpp and "/usr/bin/uupd" not in engine_cpp)
check("cpp: manual update only via systemd unit",
      "uupd-manual.service" in engine_cpp
      and "StartUnit" in strip_comments(read(os.path.join(UPDATE, "systemdcalls.cpp"))))
machine_cpp = read(os.path.join(UPDATE, "updatestatemachine.cpp"))
check("cpp: state machine interpreter present", "loadSpec" in machine_cpp
      and "step(" in machine_cpp)
check("cpp: engine loads shared spec from resources",
      ":/src/update/update-state-spec.json" in engine_cpp)

# Lote 4: image-origin guard, update separation, async device info.
all_cpp = "\n".join(strip_comments(read(p)) for p in cpp_files)
check("cpp: app never switches/rebases the bootc image",
      not re.search(r'bootc["\s,]+(switch|rebase|upgrade|usr-overlay)|"(switch|rebase)"', all_cpp))
check("cpp: app never calls dnf/rpm-ostree/pkexec for the base system",
      not re.search(r'"(dnf|dnf5|rpm-ostree|yum)"|dnf (upgrade|install)', all_cpp))
check("cpp: image origin policy exists and is enforced by the engine",
      "classify(" in strip_comments(read(os.path.join(UPDATE, "imageorigin.h")))
      and "ImageOrigin::allowsUpdate" in engine_cpp
      and "origin-foreign" in engine_cpp)
check("cpp: canUpdate depends on updateBlockReason",
      re.search(r"canUpdate\(\) const\s*\{\s*if \(!updateBlockReason\(\)\.isEmpty\(\)", engine_cpp) is not None)
check("cpp: system and app updates are separate backend lists",
      "systemUpdates" in read(os.path.join(UPDATE, "updateengine.h"))
      and "appUpdates" in read(os.path.join(UPDATE, "updateengine.h")))

# Lote 8: separated flows, protected rollback, preflight and staged-origin gate.
engine_h = read(os.path.join(UPDATE, "updateengine.h"))
check("cpp: engine exposes system-only and apps-only update entry points",
      "requestSystemUpdate" in engine_h and "requestAppUpdates" in engine_h)
check("cpp: engine exposes a protected rollback entry point",
      "requestRollback" in engine_h and "canRollback" in engine_h)
check("cpp: engine uses the three fixed Enthroned units",
      all(u in engine_cpp for u in ("enthroned-system-update.service",
                                    "enthroned-flatpak-update.service",
                                    "enthroned-rollback.service")))
check("cpp: mutating flows share one authorization gate",
      "mutatingFlowGate" in engine_cpp
      and engine_cpp.count("engine-update-started") >= 3)
check("cpp: preflight blocks on missing storage and concurrent runs",
      "QStorageInfo" in engine_cpp and "preflight-blocked" in engine_cpp
      and "concurrent-operation-detected" in engine_cpp)
check("cpp: staged deployment origin is verified against the channel",
      "staged-origin-blocked" in engine_cpp and "stagedImageRef" in engine_cpp)
check("cpp: channel-configured honesty flag exposed",
      "channelConfigured" in engine_h)
bootc_h = read(os.path.join(SRC, "bootcstatusprovider.h"))
check("cpp: bootc provider exposes the staged image reference",
      "stagedImageRef" in bootc_h)
flatpak_cpp = strip_comments(read(os.path.join(SRC, "flatpakupdatesprovider.cpp")))
check("cpp: flatpak updates cover user and system installations",
      "--user" in flatpak_cpp and "--system" in flatpak_cpp)
check("cpp: flatpak user update is fixed and non-interactive",
      '"--noninteractive"' in flatpak_cpp and "setArguments" in flatpak_cpp)
kcm_cpp = strip_comments(read(os.path.join(SRC, "kcmlauncher.cpp")))
check("cpp: KCM launch restricted to modules kcmshell6 listed", "m_available.contains(module)" in kcm_cpp)
device_cpp = strip_comments(read(os.path.join(SRC, "deviceinfoprovider.cpp")))
check("cpp: device info collected on a worker thread", "QThread::create" in device_cpp
      and "Qt::QueuedConnection" in device_cpp)
pers_cpp = strip_comments(read(os.path.join(SRC, "personalizationcontroller.cpp")))
check("cpp: personalization uses Plasma tools with an allowlist only",
      "plasma-apply-colorscheme" in pers_cpp and "plasma-apply-wallpaperimage" in pers_cpp
      and "findScheme" in pers_cpp and "findWallpaper" in pers_cpp
      and not re.search(r'"(sh|bash)"|-c"', pers_cpp))
channel_json = json.loads(read(os.path.join(SYSFILES, "share", "enthroned-os", "release-channel.json")))
check("data: release-channel declares expected_image_references",
      isinstance(channel_json.get("expected_image_references"), list))

# ---- 4. Packaging / data -----------------------------------------------------
cmake = read(os.path.join(SETTINGS, "CMakeLists.txt"))
check("cmake: references Kirigami/KI18n/KNotifications",
      all(x in cmake for x in ("KF6::Kirigami", "KF6::I18n", "KF6::Notifications")))
qml_files_in_cmake = re.findall(r"qml/[\w/]+\.qml", cmake)
on_disk = {os.path.relpath(p, SETTINGS).replace("\\", "/") for p in qml_files}
check("cmake: all QML files declared", on_disk <= set(qml_files_in_cmake),
      str(on_disk - set(qml_files_in_cmake)))
declared = {p for p in qml_files_in_cmake}
check("cmake: declared QML files exist", declared <= on_disk, str(declared - on_disk))
check("cmake: spec + 20 scenarios embedded as resources",
      "update-state-spec.json" in cmake and cmake.count("scenarios/") >= 20)

desktop_path = os.path.join(DATA, "org.enthroned.settings.desktop")
desktop = read(desktop_path)
check("desktop: Type present", "[Desktop Entry]" in desktop and "Type=Application" in desktop)
check("desktop: Exec matches binary", "Exec=enthroned-settings" in desktop)
check("desktop: Icon declared", "Icon=org.enthroned.settings" in desktop)
_sizes = (16, 22, 24, 32, 48, 64, 128, 256, 512)
_icons = [os.path.join(DATA, "icons", "hicolor", f"{n}x{n}", "apps", "org.enthroned.settings.png") for n in _sizes]
check("desktop: official icon set (hicolor PNG 16-512) exists", all(os.path.isfile(f) for f in _icons))
check("cmake: installs the hicolor icon directory", "install(DIRECTORY data/icons/hicolor" in cmake)
check("desktop: no leftover scalable placeholder icon",
      not os.path.exists(os.path.join(DATA, "icons", "org.enthroned.settings.svg")))
check("desktop: no dead shortcuts in system_files",
      not os.path.exists(os.path.join(SYSFILES, "share", "applications", "org.enthroned.settings.desktop")))

try:
    ET.parse(os.path.join(DATA, "org.enthroned.settings.appdata.xml"))
    check("appdata: xml parses", True)
except ET.ParseError as exc:
    check("appdata: xml parses", False, str(exc))

notifyrc = read(os.path.join(DATA, "enthronedsettings.notifyrc"))
check("notifyrc: 5 events declared",
      all(f"[Event/{e}]" in notifyrc for e in
          ("update-available", "download-finished", "update-staged",
           "restart-required", "update-failed")))
notify_cpp = read(os.path.join(UPDATE, "notificationpresenter.cpp"))
check("notifyrc: component name matches code", "enthronedsettings" in notify_cpp)

# ---- 5. Image integration (system_files) --------------------------------------
unit_path = os.path.join(SYSFILES, "lib", "systemd", "system", "enthroned-update-check.service")
check("unit: check service exists", os.path.isfile(unit_path))
unit = read(unit_path)
check("unit: runs the read-only uupd check", "ExecStart=/usr/bin/uupd update-check" in unit)
check("unit: not enabled (no [Install])", "[Install]" not in unit)
check("unit: condition guards uupd presence", "ConditionPathExists=/usr/bin/uupd" in unit)

# Lote 8: the three new fixed-command units.
def read_unit(name):
    return read(os.path.join(SYSFILES, "lib", "systemd", "system", name))

system_unit = read_unit("enthroned-system-update.service")
check("unit: system update runs the fixed helper",
      "ExecStart=/usr/libexec/enthroned-system-update" in system_unit)
check("unit: system update guards bootc presence",
      "ConditionPathExists=/usr/bin/bootc" in system_unit)
check("unit: system update not enabled (no [Install])", "[Install]" not in system_unit)
flatpak_unit = read_unit("enthroned-flatpak-update.service")
check("unit: flatpak update has a fixed non-interactive command",
      "ExecStart=/usr/bin/flatpak update --noninteractive --system" in flatpak_unit)
check("unit: flatpak update not enabled (no [Install])", "[Install]" not in flatpak_unit)
rollback_unit = read_unit("enthroned-rollback.service")
check("unit: rollback has a fixed bootc command", "ExecStart=/usr/bin/bootc rollback" in rollback_unit)
check("unit: rollback not enabled (no [Install])", "[Install]" not in rollback_unit)
timer_path = os.path.join(SYSFILES, "lib", "systemd", "system", "enthroned-system-update.timer")
check("timer: file exists but stays disabled", os.path.isfile(timer_path)
      and "[Install]" in read(timer_path))
build_sh = read(os.path.join(ROOT, "build_files", "build.sh"))
check("timer: build never enables it", "systemctl enable enthroned-system-update.timer" not in build_sh)
helper_path = os.path.join(ROOT, "system_files", "usr", "libexec", "enthroned-system-update")
check("helper: fixed bootc helper exists", os.path.isfile(helper_path))
if os.path.isfile(helper_path):
    helper = read(helper_path)
    check("helper: runs bootc upgrade with no arguments taken",
          "exec /usr/bin/bootc upgrade --progress-fd 9" in helper)
    check("helper: no network or arbitrary command execution",
          not any(x in helper for x in ("curl", "wget", "eval", "$(", "dnf")))

rules_path = os.path.join(SYSFILES, "share", "polkit-1", "rules.d", "10-org.enthroned.settings.rules")
check("polkit: rule exists", os.path.isfile(rules_path))
rules = read(rules_path)
# Lote 8: exactly the four Enthroned units are granted, nothing else.
check("polkit: grants exactly the four Enthroned update units",
      all(u in rules for u in ("enthroned-update-check.service",
                               "enthroned-system-update.service",
                               "enthroned-flatpak-update.service",
                               "enthroned-rollback.service"))
      and "uupd.service" not in rules
      and rules.count('"uupd') == 0)
check("polkit: restricts to active local wheel users",
      all(x in rules for x in ('subject.local', 'subject.active', 'isInGroup("wheel")')))

# Gate 12.2: Aurora's uupd.rules answers YES to anyone for uupd*.service. The
# Enthroned confinement rule must sort before it and only narrow that grant.
uupd_rules_name = "10-org.enthroned.uupd.rules"
uupd_rules_path = os.path.join(SYSFILES, "share", "polkit-1", "rules.d", uupd_rules_name)
check("polkit: uupd confinement rule exists", os.path.isfile(uupd_rules_path))
uupd_rules = read(uupd_rules_path)
uupd_code = "\n".join(l for l in uupd_rules.splitlines() if not l.lstrip().startswith("//"))
check("polkit: uupd rule sorts before the upstream uupd.rules", uupd_rules_name < "uupd.rules")
check("polkit: uupd rule is limited to the two uupd units and manage-units",
      'action.id != "org.freedesktop.systemd1.manage-units"' in uupd_code
      and uupd_code.count("uupd.service") == 1 and uupd_code.count("uupd-manual.service") == 1
      and uupd_code.count('"uupd') == 2)
check("polkit: uupd rule grants YES only to active local wheel, verb start",
      uupd_code.count("polkit.Result.YES") == 1
      and 'action.lookup("verb") == "start"' in uupd_code
      and all(x in uupd_code for x in ("subject.local", "subject.active", 'isInGroup("wheel")')))
check("polkit: uupd rule never grants NO and falls back to admin authentication",
      "Result.NO" not in uupd_code and "NOT_HANDLED" not in uupd_code
      and "polkit.Result.AUTH_ADMIN" in uupd_code and "AUTH_SELF" not in uupd_code)
check("polkit: uupd rule leaves run0 --empower users to empower.rules",
      'isInGroup("empower")' in uupd_code)

containerfile = read(os.path.join(ROOT, "Containerfile"))
check("containerfile: settings compiled and installed through shared builder",
      "FROM runtime AS apps-builder" in containerfile
      and "cmake -S /src/settings" in containerfile
      and "DESTDIR=/out cmake --install /build/settings" in containerfile
      and "COPY --from=apps-builder /out/ /" in containerfile)
check("containerfile: final stage intact", "bootc container lint" in containerfile)

justfile = read(os.path.join(ROOT, "Justfile"))
check("justfile: verify-settings recipe", "verify-settings" in justfile)

# ---- 6. Tests harness present --------------------------------------------------
tests_runner = os.path.join(SETTINGS, "tests", "run-tests.mjs")
check("tests: logic runner exists", os.path.isfile(tests_runner))
runner = read(tests_runner)
check("tests: runner reads shared spec", "update-state-spec.json" in runner)

# ---- Report --------------------------------------------------------------------
total = 0
print()
if failures:
    print(f"VALIDATION FAILED: {len(failures)} check(s) failed:")
    for name in failures:
        print(f"  - {name}")
    sys.exit(1)
print("All settings validation checks passed.")
PYEOF
