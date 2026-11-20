#!/usr/bin/env bash
# Lote 11A regression harness (system stability, security, recovery).
#
# Part A runs the REAL /usr/libexec/enthroned-firstboot-flatpaks helper against
# a stubbed `flatpak` in a temporary directory (no root, no real flatpak, no
# network, nothing outside $WORK is touched). Happy path AND negative paths:
#   success, repeat run, genuine failure, offline, interrupted/corrupt repo,
#   pre-installed app, partial failure, concurrent run, SIGTERM interruption.
# Part B checks the shipped sources statically (systemd units, build.sh,
# SELinux label, Discover/PackageKit policy). `systemd-analyze verify` runs
# when available.
#
# Run: bash scripts/test-system-stability.sh   (WSL/Linux; no root)
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC2015  # A && pass || fail is the harness idiom (as in the sibling harnesses)
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/system_files/usr/libexec/enthroned-firstboot-flatpaks"
UNIT_DIR="${ROOT}/system_files/usr/lib/systemd/system"
[[ -f "${SCRIPT}" ]] || { echo "firstboot helper not found"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected [$2], got [$3])"; fi; }
assert_has() { if grep -Fq -- "$2" <<<"$3"; then pass "$1"; else fail "$1 (missing [$2])"; fi; }
assert_lacks() { if grep -Fq -- "$2" <<<"$3"; then fail "$1 (found [$2])"; else pass "$1"; fi; }

# ---- Part A: runtime behaviour --------------------------------------------
STUBS="${WORK}/stubs"
mkdir -p "${STUBS}"
cat >"${STUBS}/flatpak" <<'STUB'
#!/usr/bin/env bash
# Stub: state in $STUB_STATE (installed/<app>, mode.<app>, calls.log, no-remote)
echo "$*" >>"${STUB_STATE}/calls.log"
case "$1" in
remotes)
	[[ -e "${STUB_STATE}/no-remote" ]] || echo "flathub"
	exit 0 ;;
info)
	[[ -e "${STUB_STATE}/installed/${@: -1}" ]]; exit $? ;;
install)
	app="${@: -1}"
	mode="ok"; [[ -f "${STUB_STATE}/mode.${app}" ]] && mode="$(<"${STUB_STATE}/mode.${app}")"
	case "${mode}" in
	ok) touch "${STUB_STATE}/installed/${app}"; echo "Installation complete."; exit 0 ;;
	offline) echo "error: Unable to load summary from remote flathub: While fetching https://dl.flathub.org/repo/summary: [6] Could not resolve hostname" >&2; exit 1 ;;
	connect) echo "error: Unable to load summary from remote flathub: While fetching https://dl.flathub.org/repo/summary.idx: [7] Could not connect to server" >&2; exit 1 ;;
	timeout) echo "error: While fetching https://dl.flathub.org/repo/summary.idx: [28] Timeout was reached" >&2; exit 1 ;;
	corrupt) echo "error: Couldn't find file object '967c0b4e'" >&2; exit 1 ;;
	other) echo "error: boom: unexpected failure" >&2; exit 1 ;;
	hang) touch "${STUB_STATE}/hang-started"; sleep 30; exit 0 ;;
	esac ;;
esac
# repair / uninstall / remote-* must never be called by the helper.
echo "UNEXPECTED flatpak $*" >>"${STUB_STATE}/calls.log"
exit 2
STUB
chmod +x "${STUBS}/flatpak"

# Fresh sandbox per case: patched copy of the helper pointing at $WORK paths.
new_case() { # name app...
	CASE="${WORK}/$1"; shift
	mkdir -p "${CASE}/state/installed" "${CASE}/var"
	: >"${CASE}/state/calls.log"
	printf '# test list\n' >"${CASE}/list.txt"
	for a in "$@"; do printf '%s\n' "$a" >>"${CASE}/list.txt"; done
	sed -e "s#^LIST_FILE=.*#LIST_FILE=\"${CASE}/list.txt\"#" \
	    -e "s#^MARKER_DIR=.*#MARKER_DIR=\"${CASE}/var\"#" \
	    -e "s#^LOCK_FILE=.*#LOCK_FILE=\"${CASE}/lock\"#" \
	    "${SCRIPT}" >"${CASE}/helper"
	grep -q "${CASE}/list.txt" "${CASE}/helper" || echo "WARN: path patch did not apply"
}
run_helper() { # sets RC and OUT
	OUT="$(STUB_STATE="${CASE}/state" PATH="${STUBS}:${PATH}" timeout 20 bash "${CASE}/helper" 2>&1)"
	RC=$?
}
marker() { cat "${CASE}/var/firstboot-flatpaks.done" 2>/dev/null; }
status() { cat "${CASE}/var/firstboot-flatpaks.status" 2>/dev/null; }
calls() { cat "${CASE}/state/calls.log"; }

echo "== A1 success"
new_case a1 com.example.One
run_helper
assert_eq "success: exit 0" 0 "${RC}"
assert_eq "success: marker lists app" "com.example.One" "$(marker)"
assert_has "success: status ok" "result=ok" "$(status)"

echo "== A2 repeat run is idempotent"
OLD_CALLS="$(calls)"
run_helper
assert_eq "repeat: exit 0" 0 "${RC}"
assert_eq "repeat: marker not duplicated" "com.example.One" "$(marker)"
assert_eq "repeat: no new flatpak install" "$(grep -c '^install' <<<"${OLD_CALLS}")" "$(calls | grep -c '^install')"

echo "== A3 genuine failure propagates and keeps the original error"
new_case a3 com.example.One
echo other >"${CASE}/state/mode.com.example.One"
run_helper
assert_eq "failure: exit 1" 1 "${RC}"
assert_has "failure: original flatpak error logged" "boom: unexpected failure" "${OUT}"
assert_eq "failure: marker empty" "" "$(marker)"
assert_has "failure: status failed" "result=failed" "$(status)"
echo ok >"${CASE}/state/mode.com.example.One"
run_helper
assert_eq "failure then retry: exit 0" 0 "${RC}"
assert_eq "failure then retry: marker lists app" "com.example.One" "$(marker)"

echo "== A4 offline is a deferral (75), not success and not silent"
new_case a4 com.example.One
echo offline >"${CASE}/state/mode.com.example.One"
run_helper
assert_eq "offline: exit 75" 75 "${RC}"
assert_has "offline: original error logged" "Could not resolve hostname" "${OUT}"
assert_has "offline: status offline" "result=offline" "$(status)"
assert_eq "offline: marker empty" "" "$(marker)"

echo "== A5 interrupted download / inconsistent repo: fail, advise, never repair"
new_case a5 com.example.One
echo corrupt >"${CASE}/state/mode.com.example.One"
run_helper
assert_eq "corrupt: exit 77" 77 "${RC}"
assert_has "corrupt: original error logged" "Couldn't find file object" "${OUT}"
assert_has "corrupt: advises manual repair" "flatpak repair --system" "${OUT}"
assert_has "corrupt: status corrupt" "result=corrupt" "$(status)"
assert_lacks "corrupt: helper never ran repair/uninstall/remote changes" "UNEXPECTED" "$(calls)"
assert_lacks "corrupt: no repair call" "repair" "$(calls)"

echo "== A5b real libcurl wording (Aurora fc45 libcurl 8.21) is a deferral too; recovery after 77 is by the timer"
for m in connect timeout; do
	new_case "a5b-$m" com.example.One
	echo "$m" >"${CASE}/state/mode.com.example.One"
	run_helper
	assert_eq "$m: exit 75" 75 "${RC}"
	assert_has "$m: status offline" "result=offline" "$(status)"
done
new_case a5c com.example.One
echo corrupt >"${CASE}/state/mode.com.example.One"
run_helper
assert_eq "corrupt first: exit 77" 77 "${RC}"
echo ok >"${CASE}/state/mode.com.example.One"   # operator ran flatpak repair
run_helper
assert_eq "77 then repaired: next timer run exits 0" 0 "${RC}"
assert_has "77 then repaired: status ok" "result=ok" "$(status)"
assert_eq "no stray status temp files" 0 "$(compgen -G "${CASE}/var/*.status.*" | wc -l)"
new_case a5d com.example.Bad com.example.Corrupt
echo other >"${CASE}/state/mode.com.example.Bad"; echo corrupt >"${CASE}/state/mode.com.example.Corrupt"
run_helper
assert_eq "corrupt + other failure: 77 wins, both errors still logged" 77 "${RC}"
assert_has "mixed: other failure logged" "could not install com.example.Bad" "${OUT}"

echo "== A6 pre-installed apps are preserved"
new_case a6 com.example.One
touch "${CASE}/state/installed/com.example.One"
run_helper
assert_eq "preinstalled: exit 0" 0 "${RC}"
assert_lacks "preinstalled: no install/uninstall" "install" "$(calls | grep -v '^info')"
assert_eq "preinstalled: recorded in marker" "com.example.One" "$(marker)"

echo "== A7 partial failure does not block or undo the others"
new_case a7 com.example.Bad com.example.Good
echo other >"${CASE}/state/mode.com.example.Bad"
run_helper
assert_eq "partial: exit 1" 1 "${RC}"
[[ -e "${CASE}/state/installed/com.example.Good" ]] && pass "partial: second app still installed" || fail "partial: second app still installed"
assert_eq "partial: marker only has the good app" "com.example.Good" "$(marker)"

echo "== A8 missing flathub remote defers without touching remotes"
new_case a8 com.example.One
touch "${CASE}/state/no-remote"
run_helper
assert_eq "no remote: exit 75" 75 "${RC}"
assert_lacks "no remote: no remote add" "remote-add" "$(calls)"
assert_lacks "no remote: no install attempt" "install" "$(calls)"

echo "== A9 concurrent run is refused"
new_case a9 com.example.One
exec 8>"${CASE}/lock"
flock -n 8
run_helper
exec 8>&-
assert_eq "concurrent: exit 75" 75 "${RC}"
assert_lacks "concurrent: no install attempt" "install" "$(calls)"

echo "== A10 SIGTERM mid-install: no marker, lock released, retry works"
new_case a10 com.example.One
echo hang >"${CASE}/state/mode.com.example.One"
( STUB_STATE="${CASE}/state" PATH="${STUBS}:${PATH}" bash "${CASE}/helper" >"${CASE}/out.txt" 2>&1; echo $? >"${CASE}/rc.txt" ) &
for _ in $(seq 1 50); do [[ -e "${CASE}/state/hang-started" ]] && break; sleep 0.1; done
pkill -TERM -f "bash ${CASE}/helper"
for _ in $(seq 1 50); do [[ -s "${CASE}/rc.txt" ]] && break; sleep 0.1; done
assert_eq "interrupt: exit 143" 143 "$(cat "${CASE}/rc.txt" 2>/dev/null)"
assert_has "interrupt: logged" "interrupted" "$(cat "${CASE}/out.txt")"
assert_eq "interrupt: marker empty" "" "$(marker)"
pkill -f "sleep 30" 2>/dev/null || true
echo ok >"${CASE}/state/mode.com.example.One"
run_helper
assert_eq "interrupt then retry: exit 0" 0 "${RC}"
assert_eq "interrupt then retry: marker lists app" "com.example.One" "$(marker)"
pkill -f "sleep 30" 2>/dev/null || true

# ---- Part B: shipped sources ----------------------------------------------
echo "== B1 firstboot unit"
UNIT="$(cat "${UNIT_DIR}/enthroned-firstboot-flatpaks.service")"
assert_has "unit: only the documented deferral code is a success" "SuccessExitStatus=75" "${UNIT}"
assert_lacks "unit: 77 (corrupt repo) is not a success" "77" "$(grep '^SuccessExitStatus' <<<"${UNIT}")"
assert_lacks "unit: no automatic flatpak repair" "flatpak repair" "$(grep -E '^Exec' <<<"${UNIT}")"

TIMER="$(cat "${UNIT_DIR}/enthroned-firstboot-flatpaks.timer")"
assert_has "timer: keeps retrying after a failed run (OnUnitActiveSec)" "OnUnitActiveSec=" "${TIMER}"
assert_lacks "unit: no Restart= loop hiding the failure" "Restart=" "${UNIT}"

echo "== B2 Discover on an atomic system"
BUILD="$(cat "${ROOT}/build_files/build.sh")"
assert_has "build: PackageKit Discover backend excluded" "--exclude=plasma-discover-packagekit" "${BUILD}"
assert_has "build: offline-updates excluded" "--exclude=plasma-discover-offline-updates" "${BUILD}"
assert_has "build: flatpak backend still installed" "plasma-discover-flatpak" "${BUILD}"
assert_has "build: fails if the RPM backends come back" "rpm -q plasma-discover-packagekit" "${BUILD}"
assert_lacks "build: PackageKit daemon not masked/removed blindly" "mask packagekit" "${BUILD}"
assert_lacks "build: PackageKit daemon not removed" "remove PackageKit" "${BUILD}"

echo "== B3 SELinux test label must never be shipped"
if grep -rIl --exclude-dir=docs --exclude-dir=.git --exclude=test-system-stability.sh \
	'invalid_bootcinstall_testlabel_t' "${ROOT}/system_files" "${ROOT}/build_files" "${ROOT}/Containerfile" 2>/dev/null | grep -q .; then
	fail "selinux: test label present in shipped sources"
else
	pass "selinux: test label absent from system_files/build_files/Containerfile"
fi
assert_lacks "selinux: build never disables enforcing" "setenforce" "${BUILD}"
assert_lacks "selinux: build never edits SELINUX=" "SELINUX=" "${BUILD}"
assert_has "image check scans the produced policy for the test label" "invalid_bootcinstall_testlabel_t" "$(cat "${ROOT}/scripts/verify-image.sh")"

echo "== B4 production channel stays closed"
CHANNEL="$(cat "${ROOT}/system_files/usr/share/enthroned-os/release-channel.json")"
assert_has "channel: f1-dev" "f1-dev" "${CHANNEL}"

echo "== B5 systemd-analyze verify (when available)"
if command -v systemd-analyze >/dev/null 2>&1; then
	VOUT="$(systemd-analyze verify --man=no "${UNIT_DIR}/enthroned-firstboot-flatpaks.service" "${UNIT_DIR}/enthroned-firstboot-flatpaks.timer" 2>&1 | grep -iE 'enthroned-firstboot' | grep -viE "marked executable|marked world-writable|not found|No such file|Failed to (load|open)|ExecStart=.*(executable|not executable)|File .* is not (executable|a regular)" || true)"
	if [[ -z "${VOUT}" ]]; then pass "systemd-analyze: no unit syntax findings"; else fail "systemd-analyze: ${VOUT}"; fi
else
	echo "SKIP: systemd-analyze not available"
fi

echo
if (( failures == 0 )); then echo "ALL PASS"; else echo "${failures} FAILURE(S)"; fi
exit $(( failures > 0 ))
