#!/usr/bin/env bash
# Enthroned OS source verification (run from the repository root or any cwd).
# Checks: Aurora base image, identity metadata, absence of secrets,
# .gitignore coverage and CI publish policy. Read-only; fails on real divergence.

set -euo pipefail

cd "$(dirname "$0")/.."

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() { printf 'PASS    %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
warn() { printf 'WARN    %s\n' "$*"; WARN_COUNT=$((WARN_COUNT + 1)); }
fail() { printf 'FAIL    %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

HAVE_JQ=false
if command -v jq >/dev/null 2>&1; then
    HAVE_JQ=true
fi

# ---- 1. Base image -------------------------------------------------------
if grep -q '^FROM ghcr\.io/ublue-os/aurora:stable' Containerfile; then
    pass "base image: ghcr.io/ublue-os/aurora:stable"
else
    fail "base image: expected 'FROM ghcr.io/ublue-os/aurora:stable' in Containerfile"
fi
if grep -qE '^FROM ghcr\.io/ublue-os/(bazzite|bluefin)' Containerfile; then
    fail "base image: Bazzite/Bluefin reference active in Containerfile (wrong upstream)"
else
    pass "base image: no Bazzite/Bluefin reference active"
fi

# ---- 2. Identity metadata ------------------------------------------------
IDENTITY="system_files/usr/share/enthroned-os/identity.json"
CHANNEL="system_files/usr/share/enthroned-os/release-channel.json"
for f in "${IDENTITY}" "${CHANNEL}"; do
    if [ ! -r "$f" ]; then
        fail "identity file missing: $f"
    fi
done
if [ -r "${IDENTITY}" ]; then
    if ${HAVE_JQ}; then
        if jq -e . "${IDENTITY}" >/dev/null 2>&1; then
            pass "identity.json: valid JSON"
        else
            fail "identity.json: invalid JSON"
        fi
        PRODUCT="$(jq -r '.product_name // empty' "${IDENTITY}")"
        CHAN="$(jq -r '.channel // empty' "${IDENTITY}")"
        BASE="$(jq -r '.base // empty' "${IDENTITY}")"
    else
        warn "jq missing: JSON validity check weakened to string match"
        PRODUCT="$(sed -n 's/.*"product_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${IDENTITY}")"
        CHAN="$(sed -n 's/.*"channel"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${IDENTITY}")"
        BASE="$(sed -n 's/.*"base"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${IDENTITY}")"
    fi
    [ "${PRODUCT}" = "Enthroned OS" ] && pass "identity: product_name=Enthroned OS" || fail "identity: unexpected product_name '${PRODUCT}'"
    [ "${CHAN}" = "f1-dev" ] && pass "identity: channel=f1-dev" || fail "identity: unexpected channel '${CHAN}'"
    [ "${BASE}" = "aurora" ] && pass "identity: base=aurora" || fail "identity: unexpected base '${BASE}'"
fi
if [ -r "${CHANNEL}" ]; then
    if ${HAVE_JQ}; then
        PROD_READY="$(jq -r '.production_ready' "${CHANNEL}")"
    else
        PROD_READY="$(grep -o '"production_ready"[[:space:]]*:[[:space:]]*[^,}]*' "${CHANNEL}" | head -n 1 | sed 's/^.*:[[:space:]]*//')"
    fi
    [ "${PROD_READY}" = "false" ] && pass "release channel: production_ready=false" || fail "release channel: production_ready='${PROD_READY}' (expected false in F1)"
fi

# ---- 3. Secrets ----------------------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    VIOLATIONS=""
    while IFS= read -r f; do
        case "$f" in
            cosign.key | *.pem | .env | .env.*)
                VIOLATIONS+="${f}"$'\n'
                ;;
            *.key)
                [ "$f" = "cosign.pub" ] || VIOLATIONS+="${f}"$'\n'
                ;;
        esac
    done < <(git ls-files --cached --others --exclude-standard)
    if [ -n "${VIOLATIONS}" ]; then
        fail "secret-like files present in the work tree:"
        printf '%s' "${VIOLATIONS}" | sed 's/^/        /'
    else
        pass "secrets: no key/env files present in work tree"
    fi
else
    warn "git: not a work tree - skipping work-tree secret path check"
fi
if grep -RIlE 'BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY' --exclude-dir=.git . >/dev/null 2>&1; then
    fail "secrets: private key material found in files:"
    grep -RIlE 'BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY' --exclude-dir=.git . | sed 's/^/        /'
else
    pass "secrets: no private key material in repository files"
fi

# ---- 4. .gitignore coverage ----------------------------------------------
if grep -q '^cosign\.key$' .gitignore && grep -q '^\.env' .gitignore; then
    pass "gitignore: cosign.key and .env* ignored"
else
    fail "gitignore: missing cosign.key/.env ignore patterns"
fi

# ---- 5. CI publish policy -------------------------------------------------
if grep -rq 'cron:' .github/workflows/ 2>/dev/null; then
    fail "workflows: scheduled (cron) trigger found - F1 policy forbids automatic builds"
else
    pass "workflows: no cron triggers"
fi
if grep -rqE 'docker/login-action|podman push|skopeo copy' .github/workflows/ 2>/dev/null; then
    fail "workflows: publish machinery found (login/push) - F1 policy forbids registry publishing"
else
    pass "workflows: no registry login/push steps"
fi
if [ -f .github/workflows/build-disk.yml ]; then
    if grep -qE '^[[:space:]]*(pull_request|push|schedule):' .github/workflows/build-disk.yml; then
        fail "workflows: build-disk.yml has automatic triggers (must be workflow_dispatch only)"
    else
        pass "workflows: build-disk.yml is dispatch-only"
    fi
else
    warn "workflows: build-disk.yml not found"
fi

# ---- 6. Placeholders and channel -----------------------------------------
if grep -q 'SET_ME_BEFORE_PUBLISH' disk_config/iso.toml; then
    warn "iso.toml: installer target uses the namespace placeholder (expected until ADR-0002 config)"
else
    pass "iso.toml: installer target namespace configured"
fi
REPO_VALUE="$(grep '^REPO_ORGANIZATION=' image-template.env | head -n 1 | cut -d= -f2- | tr -d '"')"
if [ "${REPO_VALUE}" = "SET_ME_BEFORE_PUBLISH" ]; then
    pass "env: REPO_ORGANIZATION is the placeholder (accidental publishing blocked)"
else
    warn "env: REPO_ORGANIZATION set to '${REPO_VALUE}' - confirm this is intentional before any publish"
fi
if grep -q '^DEFAULT_TAG="f1-dev"' image-template.env; then
    pass "env: DEFAULT_TAG=f1-dev (development channel)"
else
    warn "env: DEFAULT_TAG is not f1-dev - verify the channel change is intentional"
fi

printf '\nSummary: %d pass, %d warn, %d fail\n' \
    "${PASS_COUNT}" "${WARN_COUNT}" "${FAIL_COUNT}"

if [ "${FAIL_COUNT}" -gt 0 ]; then
    exit 1
fi
exit 0
