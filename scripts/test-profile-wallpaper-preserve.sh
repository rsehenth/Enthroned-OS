#!/usr/bin/env bash
# Lote 13: enthroned-profile must keep the user's wallpaper(s) across a
# Classic <-> Modern switch (plasma-apply-lookandfeel --resetLayout recreates the
# desktops). Runs the real script against mock KDE tools; real Plasma NOT RUN.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${ROOT}/system_files/usr/bin/enthroned-profile"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
BIN="${WORK}/bin"
mkdir -p "${BIN}" "${WORK}/home"

# --- mock KDE tools -------------------------------------------------------
cat >"${BIN}/kreadconfig6" <<'MOCK'
#!/usr/bin/env bash
cat "${MOCK_DIR}/active" 2>/dev/null || true
MOCK
cat >"${BIN}/kpackagetool6" <<'MOCK'
#!/usr/bin/env bash
printf 'Listing service types: Plasma/LookAndFeel\norg.enthroned.classic\norg.enthroned.modern\n'
MOCK
cat >"${BIN}/plasma-apply-lookandfeel" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >>"${MOCK_DIR}/apply.log"
printf '%s' "${@: -1}" >"${MOCK_DIR}/active"
MOCK
# qdbus6: NameHasOwner answers MOCK_OWNER (default true); snapshot scripts
# (readConfig) get the canned answer; restore scripts (writeConfig) are logged
# and answer MOCK_WRITTEN (number of desktops written, default 1). MOCK_HANG
# makes evaluateScript hang, as a stuck plasmashell would.
cat >"${BIN}/qdbus6" <<'MOCK'
#!/usr/bin/env bash
if [[ "$3" == *NameHasOwner ]]; then
  printf '%s
' "${MOCK_OWNER:-true}"
  exit 0
fi
echo "evaluateScript" >>"${MOCK_DIR}/calls.log"
[ -z "${MOCK_HANG:-}" ] || sleep 20
script="$4"
if [[ "${script}" == *'readConfig("iconSize"'* ]]; then
  printf '%b' "${MOCK_ICONSNAP:-}"
elif [[ "${script}" == *readConfig* ]]; then
  printf '%b' "${MOCK_SNAPSHOT}"
else
  printf '%s
' "${script}" >>"${MOCK_DIR}/restore.log"
  printf '%s
' "${MOCK_WRITTEN:-1}"
fi
MOCK
chmod +x "${BIN}"/*

run() { # snapshot-text profile
  rm -f "${WORK}/apply.log" "${WORK}/restore.log" "${WORK}/calls.log"
  ENTHRONED_PLASMA_TIMEOUT=1 ENTHRONED_PLASMA_RETRY_DELAY=0 MOCK_DIR="${WORK}" MOCK_SNAPSHOT="$1" HOME="${WORK}/home" XDG_STATE_HOME="${WORK}/state" PATH="${BIN}:${PATH}" \
    bash "${TOOL}" apply "$2" >/dev/null
}

fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

# 1. two monitors, the user picked Ascensao on screen 0 and an external image on 1
run '0|file:///usr/share/wallpapers/EnthronedAscensao/\n1|file:///home/u/Pictures/mine.png\n' modern
check "layout reset still runs" "grep -q -- '--resetLayout -a org.enthroned.modern' '${WORK}/apply.log'"
check "restores screen 0 wallpaper" "grep -q '\"0\": \"file:///usr/share/wallpapers/EnthronedAscensao/\"' '${WORK}/restore.log'"
check "restores screen 1 (external image)" "grep -q '\"1\": \"file:///home/u/Pictures/mine.png\"' '${WORK}/restore.log'"

# 2. nothing configured by the user: the profile default applies, no write
run '' classic
check "no restore when the user never chose a wallpaper" "[ ! -s '${WORK}/restore.log' ]"

# 3. hostile / malformed snapshot entries are skipped
run '0|file:///x/a"b.png\nx|file:///ok.png\n2|http://evil/x.png\n3|file:///x/back\slash.png\n' classic
check "quote/backslash/non-file/non-numeric entries dropped" "[ ! -s '${WORK}/restore.log' ]"

# 3b. both scripts sent to plasmashell are valid JS (a QJSEngine syntax error,
# e.g. a raw newline inside a string literal, would silently drop every wallpaper)
run '0|file:///x.png
' classic
check "snapshot script parses as JavaScript" "node -e '
const src = require(\"fs\").readFileSync(process.argv[1], \"utf8\");
const m = src.match(/wallpaper_snapshot\(\) \{\n\tplasma_script \x27([\s\S]*?)\x27 \|\| true/);
if (!m) process.exit(2);
new Function(\"desktops\", \"print\", m[1]);
' '${TOOL}'"
run '0|file:///x.png
' modern
check "restore script parses as JavaScript" "node -e '
new Function(\"desktops\", \"print\", require(\"fs\").readFileSync(process.argv[1], \"utf8\"));
' '${WORK}/restore.log'"

# 3c. plasmashell not running: no evaluateScript call (no D-Bus activation), switch still works
MOCK_OWNER=false run '0|file:///x.png
' modern
check "plasmashell absent: layout switch runs, evaluateScript never called"   "grep -q -- '--resetLayout' '${WORK}/apply.log' && [ ! -e '${WORK}/calls.log' ]"

# 3d. plasmashell hangs: the switch returns (bounded by timeout) and still applies the profile
start=$SECONDS
MOCK_HANG=1 run '0|file:///x.png
' modern
check "hung plasmashell: bounded wait, profile still applied"   "grep -q -- '--resetLayout' '${WORK}/apply.log' && [ $((SECONDS - start)) -lt 15 ]"

# 3e. desktops not there yet (write count 0): retried, never an error
MOCK_WRITTEN=0 run '0|file:///x.png
' modern
check "empty write retried at most 3 times" "[ \"\$(wc -l <'${WORK}/restore.log')\" -ge 1 ] && [ \"\$(grep -c evaluateScript '${WORK}/calls.log')\" -le 5 ]"

# 3f. Lote 15: the desktop icon size survives the switch too (written back per
# screen; only digits 0-6 for numeric screens; hostile entries dropped)
MOCK_ICONSNAP='0|2
1|4
' run '' modern
check "restores desktop icon size per screen" "grep -q '\"0\": 2' '${WORK}/restore.log' && grep -q '\"1\": 4' '${WORK}/restore.log' && grep -q 'writeConfig(\"iconSize\"' '${WORK}/restore.log'"
MOCK_ICONSNAP='0|9
x|2
1|abc
2|3;evil
' run '' classic
check "icon size: out-of-range/malformed entries dropped" "[ ! -s '${WORK}/restore.log' ]"
MOCK_ICONSNAP='' run '' classic
check "icon size untouched when the user never changed it" "[ ! -s '${WORK}/restore.log' ]"
check "icon size scripts parse as JavaScript" "node -e '
const src = require(\"fs\").readFileSync(process.argv[1], \"utf8\");
const m = src.match(/iconsize_snapshot\(\) \{\n\tplasma_script \x27([\s\S]*?)\x27 \|\| true/);
if (!m) process.exit(2);
new Function(\"desktops\", \"print\", m[1]);
' '${TOOL}'"
MOCK_ICONSNAP='0|2
' run '' modern
check "restore icon-size script parses as JavaScript" "node -e '
new Function(\"desktops\", \"print\", require(\"fs\").readFileSync(process.argv[1], \"utf8\"));
' '${WORK}/restore.log'"

# 4. no qdbus at all: the switch still works, profile default applies
rm -f "${BIN}/qdbus6"
run '0|file:///x.png\n' modern
check "works without a D-Bus client" "grep -q -- '--resetLayout' '${WORK}/apply.log' && [ ! -e '${WORK}/restore.log' ]"

exit "${fail}"
