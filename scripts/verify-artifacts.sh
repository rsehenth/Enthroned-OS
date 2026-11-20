#!/usr/bin/env bash
# Enthroned OS artifact verification.
# For each artifact: existence, byte size, SHA-256 and detected real format
# (qcow2 magic or ISO 9660 "CD001" descriptor). No results are simulated.
# Usage: verify-artifacts.sh <file> [file...]

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: verify-artifacts.sh <file> [file...]" >&2
    exit 2
fi

FAIL=0
pass() { printf 'PASS    %s\n' "$*"; }
warn() { printf 'WARN    %s\n' "$*"; }
fail() { printf 'FAIL    %s\n' "$*"; FAIL=1; }

for file in "$@"; do
    echo "== ${file}"
    if [ ! -f "${file}" ]; then
        fail "not found: ${file}"
        continue
    fi

    SIZE_BYTES="$(stat -c %s "${file}" 2>/dev/null || wc -c < "${file}")"
    SHA="$(sha256sum "${file}" | awk '{print $1}')"
    pass "size: ${SIZE_BYTES} bytes"
    pass "sha256: ${SHA}"

    FORMAT="unknown"
    MAGIC="$(dd if="${file}" bs=1 skip=0 count=4 2>/dev/null | od -An -c | tr -d ' \n')"
    case "${MAGIC}" in
        QFI373*)
            FORMAT="qcow2"
            if command -v qemu-img >/dev/null 2>&1; then
                qemu-img info "${file}" | sed 's/^/        /'
            else
                warn "qemu-img not installed - skipping deep qcow2 inspection"
            fi
            ;;
        *)
            ISO_MAGIC="$(dd if="${file}" bs=1 skip=32769 count=5 2>/dev/null | od -An -c | tr -d ' \n')"
            if [ "${ISO_MAGIC}" = "CD001" ]; then
                FORMAT="iso9660"
            elif [ "$(dd if="${file}" bs=1 skip=64 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f10dabe" ]; then
                FORMAT="vdi"
                if command -v qemu-img >/dev/null 2>&1; then
                    qemu-img info "${file}" | sed 's/^/        /'
                fi
            fi
            ;;
    esac

    if [ "${FORMAT}" = "unknown" ]; then
        fail "format: unrecognized (not qcow2, not ISO 9660, not VDI)"
    else
        pass "format: ${FORMAT}"
    fi

    case "$(basename "${file}")" in
        EnthronedOS-*)
            pass "naming: matches EnthronedOS-* convention"
            ;;
        *)
            warn "naming: does not match the EnthronedOS-F1-dev-<id> convention"
            ;;
    esac
    echo
done

if [ "${FAIL}" -eq 0 ]; then
    echo "Artifact verification: PASS"
else
    echo "Artifact verification: FAIL"
fi
exit "${FAIL}"
