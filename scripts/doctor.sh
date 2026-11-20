#!/usr/bin/env bash
# Enthroned OS doctor - read-only environment checks.
# Verifies build/test tooling availability and reports PASS/WARN/BLOCKED.
# Makes no changes to the system. See docs/operations/BUILD.md for remediation.

set -uo pipefail

PASS_COUNT=0
WARN_COUNT=0
BLOCKED_COUNT=0

pass()    { printf 'PASS    %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
warn()    { printf 'WARN    %s\n' "$*"; WARN_COUNT=$((WARN_COUNT + 1)); }
blocked() { printf 'BLOCKED %s\n' "$*"; BLOCKED_COUNT=$((BLOCKED_COUNT + 1)); }

have() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"
case "$OS" in
    Linux)
        pass "host OS: Linux ($(uname -r))"
        if grep -qi microsoft /proc/version 2>/dev/null; then
            warn "WSL2 detected: builds work here; VM smoke tests need nested virtualization"
        fi
        ;;
    *)
        blocked "host OS: ${OS} - image builds need Linux (WSL2/CI); see docs/operations/BUILD.md"
        ;;
esac

for tool in git just podman jq shellcheck; do
    if have "$tool"; then
        pass "tool: ${tool} ($("$tool" --version 2>/dev/null | head -n 1))"
    else
        case "$tool" in
            podman)
                blocked "tool: podman missing - OCI build impossible here (docs/operations/BUILD.md)"
                ;;
            just)
                blocked "tool: just missing - build recipes unavailable (docs/operations/BUILD.md)"
                ;;
            *)
                warn "tool: ${tool} missing - some checks will be skipped"
                ;;
        esac
    fi
done

if have podman && have jq; then
    if podman info >/dev/null 2>&1; then
        pass "podman: storage ready"
    else
        blocked "podman: storage not usable (run 'podman info' for details)"
    fi
fi

if have skopeo; then
    pass "tool: skopeo ($(skopeo --version 2>/dev/null | head -n 1))"
else
    warn "tool: skopeo missing - optional (registry image inspection)"
fi

if have cosign; then
    pass "tool: cosign ($(cosign version 2>/dev/null | head -n 1))"
else
    warn "tool: cosign missing - required later for image signing (ADR-0002)"
fi

if have qemu-img; then
    pass "tool: qemu-img available"
else
    warn "tool: qemu-img missing - optional (disk artifact verification)"
fi

if [ -e /dev/kvm ]; then
    pass "kvm: /dev/kvm present (hardware VM acceleration)"
elif [ "$OS" = "Linux" ]; then
    warn "kvm: /dev/kvm absent - VM smoke tests will be slow or unavailable"
fi

if [ -d .git ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    pass "git: repository detected (branch: $(git branch --show-current 2>/dev/null || echo 'none'))"
else
    warn "git: no usable repository - version labels will be skipped in builds"
fi

FREE_KB="$(df -Pk . 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${FREE_KB}" ]; then
    FREE_GB=$((FREE_KB / 1024 / 1024))
    if [ "${FREE_GB}" -ge 30 ]; then
        pass "disk: ~${FREE_GB} GB free in the workspace filesystem (a full build wants roughly 30 GB)"
    else
        blocked "disk: ~${FREE_GB} GB free - a full build wants roughly 30 GB"
    fi
fi

printf '\nSummary: %d pass, %d warn, %d blocked\n' \
    "${PASS_COUNT}" "${WARN_COUNT}" "${BLOCKED_COUNT}"

if [ "${BLOCKED_COUNT}" -gt 0 ]; then
    exit 1
fi
exit 0
