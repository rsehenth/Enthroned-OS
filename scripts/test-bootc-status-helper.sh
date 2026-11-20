#!/bin/bash
# Gate 12.1: adversarial regression tests for the privileged, read-only
# /usr/libexec/enthroned-bootc-status helper.
#
# MUST run as root inside a DISPOSABLE container (it replaces /usr/bin/bootc with
# a fake that only answers `status --format=json` and rewrites /run/enthroned):
#   podman run --rm --network=none -v "$PWD":/src:ro <aurora@sha256:...> \
#       bash /src/scripts/test-bootc-status-helper.sh
# It refuses to run outside a container. Never calls a mutating bootc verb.
#
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC2034,SC2016  # check() evaluates quoted assertions; rc/t* are read inside them
set -u

HELPER="${HELPER:-/src/system_files/usr/libexec/enthroned-bootc-status}"
OUT_DIR=/run/enthroned
OUT_FILE="${OUT_DIR}/bootc-status.json"
LOCK_FILE="${OUT_DIR}/.bootc-status.lock"
CALLS=/tmp/fake-bootc-calls.log

if [ "$(id -u)" -ne 0 ] || { [ ! -e /run/.containerenv ] && [ ! -e /.dockerenv ]; }; then
	echo "refusing to run: needs root inside a disposable container" >&2
	exit 2
fi

pass=0
fail=0
: >/tmp/fake-bootc-all.log
ok() { pass=$((pass + 1)); echo "PASS  $1"; }
ko() { fail=$((fail + 1)); echo "FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

# Fake bootc: records the call, accepts ONLY `status --format=json`.
cat >/usr/bin/bootc <<'EOF'
#!/bin/bash
echo "$*" >>/tmp/fake-bootc-calls.log
echo "$*" >>/tmp/fake-bootc-all.log
[ "$1" = status ] && [ "${2:-}" = --format=json ] && [ $# -eq 2 ] || exit 64
[ -n "${FAKE_SLEEP:-}" ] && sleep "${FAKE_SLEEP}"
case "${FAKE_MODE:-ok}" in
ok) echo '{"status":{"booted":{"image":{"image":{"image":"ghcr.io/example/enthroned:f1-dev"},"version":"1.0"}},"staged":null}}' ;;
staged) echo '{"status":{"booted":{"image":{"image":{"image":"ghcr.io/example/enthroned:f1-dev"},"version":"1.0"}},"staged":{"image":{"image":{"image":"ghcr.io/example/enthroned:f1-dev"},"version":"2.0"}}}}' ;;
fail) echo boom >&2; exit 1 ;;
empty) ;;
nobooted) echo '{"status":{"booted":null}}' ;;
huge) head -c 1100000 /dev/zero | tr '\0' 'a' ;;
esac
EOF
chmod 0755 /usr/bin/bootc

reset() {
	rm -rf "${OUT_DIR}"
	: >"${CALLS}"
	unset FAKE_SLEEP FAKE_MODE
}
mono_usec() { python3 -I -c 'import time; print(time.monotonic_ns() // 1000)'; }
capture_of() { jq -r '.enthronedCaptureUsec' "${OUT_FILE}" 2>/dev/null; }
run_helper() { bash "${HELPER}" 2>/tmp/helper.err; }

echo "== T1 baseline publication"
reset
t0="$(mono_usec)"
run_helper; rc=$?
t1="$(mono_usec)"
cap="$(capture_of)"
check "T1a exits 0" '[ "$rc" -eq 0 ]'
check "T1b file is root:root 0644 regular" '[ "$(stat -c "%U:%G:%a" "${OUT_FILE}")" = root:root:644 ] && [ -f "${OUT_FILE}" ] && [ ! -L "${OUT_FILE}" ]'
check "T1c capture is a decimal string within [t0,t1] on the systemd clock" '[[ "$cap" =~ ^[0-9]+$ ]] && [ "$cap" -ge "$t0" ] && [ "$cap" -le "$t1" ]'
check "T1d capture serialised as JSON string (reader uses toString)" '[ "$(jq -r ".enthronedCaptureUsec|type" "${OUT_FILE}")" = string ]'
check "T1e exactly one bootc call, read-only" '[ "$(wc -l <"${CALLS}")" -eq 1 ] && [ "$(cat "${CALLS}")" = "status --format=json" ]'
check "T1f no temp file left" '! ls -A "${OUT_DIR}" | grep -q "tmp"'

echo "== T2 unsafe managed directory is rejected, nothing published"
reset; mkdir -m 0775 "${OUT_DIR}"; run_helper; rc=$?
check "T2a group-writable dir -> exit 1, no cache" '[ "$rc" -eq 1 ] && [ ! -e "${OUT_FILE}" ]'
reset; mkdir -m 0755 "${OUT_DIR}"; chown 65534:65534 "${OUT_DIR}"; run_helper; rc=$?
check "T2b non-root-owned dir -> exit 1, no cache" '[ "$rc" -eq 1 ] && [ ! -e "${OUT_FILE}" ]'
reset; mkdir /tmp/elsewhere-$$; ln -s /tmp/elsewhere-$$ "${OUT_DIR}"; run_helper; rc=$?
check "T2c symlinked dir -> exit 1, target untouched" '[ "$rc" -eq 1 ] && [ -z "$(ls -A /tmp/elsewhere-$$)" ]'
rm -f "${OUT_DIR}"; rmdir /tmp/elsewhere-$$ 2>/dev/null

echo "== T3 planted symlink/FIFO at the destination is replaced, never followed"
reset; mkdir -m 0755 "${OUT_DIR}"; echo victim >/tmp/victim-$$; ln -s /tmp/victim-$$ "${OUT_FILE}"
run_helper; rc=$?
check "T3a symlink replaced by a regular file; victim unchanged" '[ "$rc" -eq 0 ] && [ ! -L "${OUT_FILE}" ] && [ "$(cat /tmp/victim-$$)" = victim ]'
reset; mkdir -m 0755 "${OUT_DIR}"; mkfifo "${OUT_FILE}"
timeout 20 bash "${HELPER}" 2>/dev/null; rc=$?
check "T3b FIFO at destination replaced atomically (no hang)" '[ "$rc" -eq 0 ] && [ -f "${OUT_FILE}" ] && [ ! -p "${OUT_FILE}" ]'
rm -f /tmp/victim-$$

echo "== T4 failures discard the previous capture (never present it as fresh)"
for mode in fail empty nobooted huge; do
	reset; run_helper; export FAKE_MODE=$mode
	run_helper; rc=$?
	check "T4 mode=${mode}: exit 1 and previous cache removed" '[ "$rc" -eq 1 ] && [ ! -e "${OUT_FILE}" ]'
	unset FAKE_MODE
done

echo "== T5 ordering: a later capture can never be overwritten by an older one"
reset
export FAKE_SLEEP=0.4
bash "${HELPER}" 2>/dev/null & p1=$!
sleep 0.1
t_second="$(mono_usec)"
bash "${HELPER}" 2>/dev/null & p2=$!
wait "$p1"; rc1=$?; wait "$p2"; rc2=$?
unset FAKE_SLEEP
check "T5a overlapping writers both succeed within the 2 s lock budget" '[ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]'
check "T5b published file carries the LAST writer's capture (> first query start)" \
	'[ "$(capture_of)" -gt "$t_second" ] && [ "$(wc -l <"${CALLS}")" -eq 2 ]'

echo "== T6 an unprivileged local user must not be able to block publication"
reset; run_helper
check "T6a lock file is not readable by other users (0600 root)" \
	'[ "$(stat -c "%a:%U" "${LOCK_FILE}")" = 600:root ]'
setpriv --reuid=65534 --regid=65534 --clear-groups flock -x -w 20 "${LOCK_FILE}" sleep 6 2>/dev/null &
sleep 0.5
run_helper; rc=$?
check "T6b helper still publishes while an unprivileged flock attempt is running" '[ "$rc" -eq 0 ]'
wait

echo "== T7 failure paths after publication never leave a stale capture"
reset; run_helper
c0="$(capture_of)"
flock -x "${LOCK_FILE}" sleep 6 &
sleep 0.5
run_helper; rc=$?
check "T7a lock timeout: exit 1 AND the older capture is discarded" '[ "$rc" -eq 1 ] && [ ! -e "${OUT_FILE}" ]'
wait
reset; run_helper
export FAKE_SLEEP=20
timeout 3 bash "${HELPER}" 2>/dev/null; rc=$?
unset FAKE_SLEEP
check "T7b helper killed by timeout(1) (SIGTERM): older capture is discarded" '[ "$rc" -ne 0 ] && [ ! -e "${OUT_FILE}" ]'
check "T7c every bootc call in this whole run was read-only" '[ -s /tmp/fake-bootc-all.log ] && [ -z "$(grep -v "^status --format=json$" /tmp/fake-bootc-all.log)" ]'

echo "== T8 every unit that can stage a deployment republishes the cache (static)"
SRC="${HELPER%/system_files/*}"
UNITS="${SRC}/system_files/usr/lib/systemd/system"
POST='ExecStartPost=-/usr/bin/timeout 30s /usr/libexec/enthroned-bootc-status'
dropin_body() { grep -vE '^[[:space:]]*(#|$)' "$1" | tr '\n' '|'; }
for dropin in uupd.service.d uupd-manual.service.d; do
	check "T8 ${dropin}: only [Service] + the fixed read-only ExecStartPost" \
		'[ "$(dropin_body "${UNITS}/${dropin}/enthroned-bootc-status.conf")" = "[Service]|${POST}|" ]'
done
check "T8 enthroned-system-update.service republishes after ExecStart" \
	'[ "$(grep -c "^${POST}\$" "${UNITS}/enthroned-system-update.service")" -eq 1 ]'
uncovered=""
for u in $(grep -lE '^ExecStart=.*(bootc (upgrade|switch)|uupd)' /usr/lib/systemd/system/*.service | xargs -n1 basename); do
	[ "$u" = bootc-fetch-apply-updates.service ] && continue # timer not enabled in the base; applies and reboots
	[ -f "${UNITS}/${u}.d/enthroned-bootc-status.conf" ] || uncovered="${uncovered} ${u}"
done
check "T8 no base unit that stages a deployment lacks the republish drop-in:${uncovered:- none}" '[ -z "${uncovered}" ]'

echo "== T9 build.sh normalises the drop-in permissions of a 0777 build context"
cp -a "${SRC}/system_files/." /
chmod -R 777 /usr/lib/systemd/system/uupd.service.d /usr/lib/systemd/system/uupd-manual.service.d
awk '/^find /{p=1} p{print} p&&!/\\$/{p=0}' "${SRC}/build_files/build.sh" >/tmp/build-finds.sh
sh /tmp/build-finds.sh 2>/dev/null
for d in uupd.service.d uupd-manual.service.d; do
	check "T9 ${d}: dir 0755 and drop-in 0644 after build.sh" \
		'[ "$(stat -c %a "/usr/lib/systemd/system/${d}")" = 755 ] && [ "$(stat -c %a "/usr/lib/systemd/system/${d}/enthroned-bootc-status.conf")" = 644 ]'
done

echo
echo "bootc-status helper tests: ${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
