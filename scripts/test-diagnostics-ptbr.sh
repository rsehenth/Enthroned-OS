#!/usr/bin/env bash
# Lote 10 regression harness for enthroned-diagnostics under pt_BR (P1-3).
#
# bash >= 5.3 (Fedora 45 / Aurora) formats EPOCHREALTIME with the locale
# decimal separator, so `run` used to abort with "value too great for base"
# (comma decimal) exactly as observed in H4 (kde-tests/t57). The harness runs
# the REAL script with fake app binaries and asserts:
#   - run settings works under pt_BR.UTF-8 and C.UTF-8 (no arithmetic errors,
#     integer millisecond stamps, exit line present);
#   - zero-duration, killed app, timed-out app (RUN_TIMEOUT shortened on a
#     temporary copy) and failing-app scenarios all produce a valid log;
#   - collect still completes under pt_BR.UTF-8.
#
# Run: bash scripts/test-diagnostics-ptbr.sh   (Linux with the pt_BR.UTF-8
# locale, e.g. the Aurora apps-builder container; no root, no network)
# SPDX-License-Identifier: Apache-2.0
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIAG="${ROOT}/system_files/usr/bin/enthroned-diagnostics"
[[ -f "${DIAG}" ]] || { echo "FAIL: enthroned-diagnostics not found"; exit 1; }

if ! locale -a 2>/dev/null | grep -qi '^pt_BR\.'; then
	echo "FAIL: pt_BR.UTF-8 locale unavailable; run inside the Aurora container"
	echo "      (podman run --rm --network=host ghcr.io/ublue-os/aurora:stable bash scripts/test-diagnostics-ptbr.sh)"
	exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# Fake app driven by ENTHRONED_FAKE_MODE; stdout/stderr must survive scrubbing.
FAKES="${WORK}/bin"
mkdir -p "${FAKES}" "${WORK}/state"
cat > "${FAKES}/enthroned-settings" <<'FAKE'
#!/usr/bin/env bash
case "${ENTHRONED_FAKE_MODE:-normal}" in
	normal) echo "linha um"; echo "linha dois" >&2; echo "linha tres"; exit 0 ;;
	silent) exit 0 ;;
	failing) echo "boom simulado" >&2; exit 3 ;;
	hanging) echo "vou dormir"; exec sleep 30 ;;
esac
FAKE
chmod +x "${FAKES}/enthroned-settings"

# Asserts a run log: no locale-arithmetic errors, only integer ms stamps.
check_log() {
	local log="$1" label="$2" err=0
	if grep -qE 'too great for base|valor muito grande|erro de sintaxe|syntax error' "${log}" "${DIAG_LOG}" 2>/dev/null; then
		fail "${label}: locale arithmetic error reached the output"
		err=1
	fi
	if grep -qvE '^\[\+[[:space:]]*[0-9]+ ms\] ' <(grep -E '^\[\+' "${log}"); then
		fail "${label}: non-integer millisecond stamp"
		err=1
	fi
	if ! grep -qE '^\[exit after [0-9]+ ms\]$' "${log}"; then
		fail "${label}: exit line missing or non-integer"
		err=1
	fi
	return "${err}"
}

run_case() { # label mode locale env_extra... -> sets LOG, DIAG_LOG
	local label="$1" mode="$2" locale="$3"
	LOG="${WORK}/out-${label}.log"
	DIAG_LOG="${WORK}/diag-${label}.log"
	ENTHRONED_FAKE_MODE="${mode}" PATH="${FAKES}:${PATH}" \
		LC_NUMERIC="${locale}" LANG="${locale}" \
		XDG_STATE_HOME="${WORK}/state" \
		bash "${DIAG}" run settings >"${LOG}" 2>"${DIAG_LOG}"
}

# 1. Normal run under pt_BR.UTF-8 (the H4 failure) and C.UTF-8.
for locale in pt_BR.UTF-8 C.UTF-8; do
	run_case "normal-${locale}" normal "${locale}"
	if [[ $? -eq 0 ]] && check_log "${WORK}/state/enthroned-os/diagnostics"/*/"run-settings.log" "run settings (${locale})"; then
		pass "run settings under ${locale}: log valid"
	fi
	if grep -q "linha tres" "${WORK}/state/enthroned-os/diagnostics"/*/"run-settings.log"; then
		pass "run settings under ${locale}: app output captured"
	else
		fail "run settings under ${locale}: app output missing"
	fi
	rm -rf "${WORK}/state/enthroned-os"
done

# 2. Zero-duration app: no output, instant exit, stamps stay integers.
run_case "zero" silent pt_BR.UTF-8
if check_log "${WORK}/state/enthroned-os/diagnostics"/*/"run-settings.log" "zero duration"; then
	pass "zero duration: log valid"
fi

# 3. Failing app (exit 3): log keeps stderr content and the exit line.
run_case "failing" failing pt_BR.UTF-8
if check_log "${WORK}/state/enthroned-os/diagnostics"/*/"run-settings.log" "failing app"; then
	pass "failing app: log valid"
fi
if grep -q "boom simulado" "${WORK}/state/enthroned-os/diagnostics"/*/"run-settings.log"; then
	pass "failing app: stderr captured"
else
	fail "failing app: stderr missing"
fi

# 4. Killed app: the sampler loop must end with a valid exit line.
LOG="${WORK}/out-killed.log"
DIAG_LOG="${WORK}/diag-killed.log"
( ENTHRONED_FAKE_MODE="hanging" PATH="${FAKES}:${PATH}" \
	LC_NUMERIC="pt_BR.UTF-8" LANG="pt_BR.UTF-8" \
	XDG_STATE_HOME="${WORK}/state" \
	bash "${DIAG}" run settings >"${LOG}" 2>"${DIAG_LOG}" ) &
killer_pid=$!
sleep 1
pkill -f "${FAKES}/enthroned-settings" 2>/dev/null
wait "${killer_pid}"
if check_log "${WORK}/state/enthroned-os/diagnostics"/*/"run-settings.log" "killed app"; then
	pass "killed app: log valid"
fi

# 5. Timeout: same code path, driven by RUN_TIMEOUT on a temporary copy.
rm -rf "${WORK}/state/enthroned-os"
sed 's/^RUN_TIMEOUT=900/RUN_TIMEOUT=2/' "${DIAG}" > "${WORK}/diag-short"
ENTHRONED_FAKE_MODE="hanging" PATH="${FAKES}:${PATH}" \
	LC_NUMERIC="pt_BR.UTF-8" LANG="pt_BR.UTF-8" \
	XDG_STATE_HOME="${WORK}/state" \
	bash "${WORK}/diag-short" run settings >"${WORK}/out-timeout.log" 2>"${WORK}/diag-timeout.log"
if grep -qE '^\[exit after [0-9]+ ms\]$' "${WORK}/state/enthroned-os/diagnostics"/*/"run-settings.log" \
	&& ! grep -qE 'too great for base|valor muito grande' "${WORK}/state/enthroned-os/diagnostics"/*/"run-settings.log" "${WORK}/diag-timeout.log"; then
	pass "timed-out app: log valid (RUN_TIMEOUT=2 on a temp copy)"
else
	fail "timed-out app: log invalid"
fi

# 6. collect keeps working under pt_BR.UTF-8.
rm -rf "${WORK}/state/enthroned-os"
collect_ok=0
if LC_NUMERIC="pt_BR.UTF-8" LANG="pt_BR.UTF-8" XDG_STATE_HOME="${WORK}/state" \
	bash "${DIAG}" collect >"${WORK}/out-collect.log" 2>&1; then
	system_files="$(ls "${WORK}"/state/enthroned-os/diagnostics/*/system.txt 2>/dev/null | head -1)"
	boot_files="$(ls "${WORK}"/state/enthroned-os/diagnostics/*/boot.txt 2>/dev/null | head -1)"
	if [[ -n "${system_files}" && -n "${boot_files}" ]] \
		&& ! grep -qE 'too great for base|valor muito grande' "${WORK}/out-collect.log"; then
		collect_ok=1
	fi
fi
if [[ ${collect_ok} -eq 1 ]]; then
	pass "collect under pt_BR.UTF-8: completed with system/boot files"
else
	fail "collect under pt_BR.UTF-8"
fi

echo "----------------------------------------"
if [[ ${failures} -eq 0 ]]; then
	echo "ALL PASS"
	exit 0
fi
echo "FAILURES: ${failures}"
exit 1
