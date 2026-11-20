#!/bin/bash
# Enthroned OS - bootc capability inspection (Lote 8).
#
# Read-only audit of the REAL bootc available on this machine (the image VM
# or any host with bootc installed). Confirms which arguments and flows the
# installed version supports BEFORE the Update Center relies on them:
#   - bootc status --format=json (deployments, staged, rollback);
#   - bootc upgrade --check (read-only check used by the check unit);
#   - bootc upgrade (download + stage, what enthroned-system-update runs);
#   - bootc upgrade --progress-fd (progress JSON consumed by the journal);
#   - bootc rollback (previous deployment switch).
# Nothing here stages, deploys, reboots or mutates the system.
#
# Usage: bash scripts/bootc-capabilities.sh          (host with bootc)
#        bash scripts/bootc-capabilities.sh <qemu>   (NOT supported yet:
#         run inside the booted VM instead; see docs/operations/VM-FIRST-BOOT.md)
# SPDX-License-Identifier: Apache-2.0
set -uo pipefail

pass() { printf 'PASS: %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; }
[ $# -eq 0 ] || { warn "this script inspects the LOCAL bootc only; run it inside the booted system"; exit 2; }

if ! command -v bootc >/dev/null 2>&1 && [ ! -x /usr/bin/bootc ]; then
    fail "bootc not found on this system (run inside the Enthroned OS VM)"
    exit 1
fi
BOOTC="$(command -v bootc || printf /usr/bin/bootc)"

printf 'bootc binary: %s\n' "$BOOTC"
"$BOOTC" --version && pass "bootc --version" || warn "bootc --version failed"

# 1. status --format=json (used by BootcStatusProvider)
if "$BOOTC" status --format=json >/dev/null 2>&1; then
    pass "bootc status --format=json"
    "$BOOTC" status --format=json | jq -r '
        .status | "booted: \(.booted.image.image.image // "?")",
                 "staged: \(if .staged == {} then "none" else (.staged.image.image.image // "present") end)",
                 "rollback: \(if .rollback == {} then "none" else (.rollback.image.image.image // "present") end)"' \
        2>/dev/null || true
else
    fail "bootc status --format=json (required by the Update Center)"
fi

# 2. upgrade --check (read-only; used by uupd update-check / check unit)
if "$BOOTC" upgrade --check >/dev/null 2>&1; then
    pass "bootc upgrade --check (read-only check)"
else
    rc=$?
    if [ "$rc" = 77 ]; then
        pass "bootc upgrade --check (exit 77: no update, read-only confirmed)"
    else
        warn "bootc upgrade --check returned $rc (inspect manually)"
    fi
fi

# 3. argument support of the installed version (help text only)
for arg in "--progress-fd" "--apply"; do
    if "$BOOTC" upgrade --help 2>&1 | grep -q -- "$arg"; then
        pass "bootc upgrade supports $arg"
    else
        warn "bootc upgrade does NOT document $arg (progress falls back to indeterminate)"
    fi
done
if "$BOOTC" rollback --help >/dev/null 2>&1; then
    pass "bootc rollback (previous deployment switch)"
else
    fail "bootc rollback unavailable; recovery stays detection-only"
fi

printf '\nRemember: record the results of this audit in\n'
printf 'docs/validation/LOTE-8-STATIC-VALIDATION.md during VM homologation.\n'
