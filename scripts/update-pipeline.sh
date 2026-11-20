#!/bin/bash
# Enthroned OS - update pipeline (Lote 8).
#
# Automates the Enthroned image update chain over an updated Aurora base:
#   1. check-base : detect a new ghcr.io/ublue-os/aurora:stable digest
#   2. build      : rebuild the Enthroned image over that base
#                   (build_files/build.sh customizations + compiled apps +
#                   'bootc container lint' as the last RUN of the Containerfile)
#   3. verify     : source policy, static validators and the built image checks
#   4. version    : tag the image with a versioned tag (<channel>.<date>.<sha>)
#   5. notes      : write output/release-notes.json (version, digests, changelog)
#   6. publish    : GATED. Push + cosign sign, ONLY with a configured registry,
#                   a real namespace, an explicit confirmation variable and a
#                   cosign key provided by the environment (ADR-0002).
#
# The pipeline never runs by itself in CI (no cron, no push triggers, no
# credentials in the repository). Nothing is pushed without phase "publish"
# and every publish gate below. Read-only unless build/version/notes run.
#
# Requirements: podman, skopeo (check-base), just, jq; cosign only to publish.
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
[ -f "$ROOT/image-template.env" ] && set -a && . "$ROOT/image-template.env" && set +a

BASE_IMAGE="${ENTHRONED_BASE_IMAGE:-ghcr.io/ublue-os/aurora:stable}"
IMAGE_NAME="${IMAGE_NAME:-enthroned-os}"
DEFAULT_TAG="${DEFAULT_TAG:-f1-dev}"
PUBLISH_PLACEHOLDER="SET_ME_BEFORE_PUBLISH"
CHANNEL_FILE="$ROOT/system_files/usr/share/enthroned-os/release-channel.json"
OUT_DIR="$ROOT/output"
LAST_RELEASE="$OUT_DIR/last-release.json"
CHANGELOG="$ROOT/docs/updates/CHANGELOG.md"

log()  { printf '[pipeline] %s\n' "$*"; }
warn() { printf '[pipeline] WARN: %s\n' "$*" >&2; }
die()  { printf '[pipeline] BLOCKED: %s\n' "$*" >&2; exit 2; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

registry_namespace() {
    # The namespace comes from the environment file only; it is never invented.
    if [ -z "${REPO_ORGANIZATION:-}" ] || [ "$REPO_ORGANIZATION" = "$PUBLISH_PLACEHOLDER" ]; then
        printf ''
    else
        printf '%s' "$REPO_ORGANIZATION"
    fi
}

publish_registry() {
    jq -r '(.publish_registry // "")' "$CHANNEL_FILE" 2>/dev/null || printf ''
}

source_sha() {
    if git -C "$ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
        git -C "$ROOT" rev-parse --short HEAD
    else
        printf 'nosha'
    fi
}

phase_check_base() {
    need skopeo
    mkdir -p "$OUT_DIR"
    local digest
    digest="$(skopeo inspect "docker://$BASE_IMAGE" --format '{{.Digest}}')"
    log "base $BASE_IMAGE resolves to $digest"
    printf '{"base_image": "%s", "base_digest": "%s", "checked_at": "%s"}\n' \
        "$BASE_IMAGE" "$digest" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > "$OUT_DIR/aurora-base.json"
    if [ -f "$LAST_RELEASE" ] && jq -e . "$LAST_RELEASE" >/dev/null 2>&1; then
        local last
        last="$(jq -r '.base_digest // ""' "$LAST_RELEASE")"
        if [ -n "$last" ] && [ "$last" != "$digest" ]; then
            log "NEW BASE AVAILABLE: previous $last -> current $digest (rebuild required)"
        else
            log "base unchanged since the last recorded release ($digest)"
        fi
    else
        warn "no $LAST_RELEASE recorded yet; rebuild decision needs a baseline"
    fi
}

phase_build() {
    need podman
    need just
    log "building $IMAGE_NAME:$DEFAULT_TAG over the current $BASE_IMAGE"
    log "the Containerfile runs build_files/build.sh, compiles the apps and ends with 'bootc container lint'"
    just build
}

phase_verify() {
    log "static policy + validators"
    bash "$SCRIPT_DIR/verify-source.sh"
    bash "$SCRIPT_DIR/validate-desktop.sh"
    bash "$SCRIPT_DIR/validate-settings.sh"
    bash "$SCRIPT_DIR/validate-welcome.sh"
    if command -v podman >/dev/null 2>&1 && podman image exists "localhost/$IMAGE_NAME:$DEFAULT_TAG" 2>/dev/null; then
        log "verifying the built image"
        just verify-image
    else
        warn "image localhost/$IMAGE_NAME:$DEFAULT_TAG not present locally; image checks skipped (NOT RUN)"
    fi
}

phase_version() {
    need podman
    local tag sha
    sha="$(source_sha)"
    tag="$DEFAULT_TAG.$(date +%Y%m%d).$sha"
    podman tag "localhost/$IMAGE_NAME:$DEFAULT_TAG" "localhost/$IMAGE_NAME:$tag"
    log "versioned tag: localhost/$IMAGE_NAME:$tag"
    printf '%s' "$tag" > "$OUT_DIR/version-tag.txt"
}

phase_notes() {
    need jq
    mkdir -p "$OUT_DIR"
    local tag sha base_digest image_digest
    tag="$(cat "$OUT_DIR/version-tag.txt" 2>/dev/null || printf '%s' "$DEFAULT_TAG.$(date +%Y%m%d).$(source_sha)")"
    sha="$(source_sha)"
    base_digest="$(jq -r '.base_digest // ""' "$OUT_DIR/aurora-base.json" 2>/dev/null || printf '')"
    image_digest="$(podman image inspect "localhost/$IMAGE_NAME:$tag" --format '{{.Digest}}' 2>/dev/null || printf '')"
    jq -n \
        --arg image "$IMAGE_NAME" --arg tag "$tag" --arg sha "$sha" \
        --arg base "$BASE_IMAGE" --arg baseDigest "$base_digest" \
        --arg digest "$image_digest" --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg changelog "$(sed -n '/^## /,$p' "$CHANGELOG" 2>/dev/null | head -c 4000)" \
        '{image: $image, tag: $tag, source_sha: $sha, base_image: $base,
          base_digest: $baseDigest, image_digest: $digest,
          generated_at: $generated, changelog: $changelog,
          signed: false, published: false}' \
        > "$OUT_DIR/release-notes.json"
    log "release notes: $OUT_DIR/release-notes.json (unsigned, unpublished)"
}

phase_publish() {
    # ---- gates (all of them, in order) ------------------------------------
    local namespace registry
    namespace="$(registry_namespace)"
    [ -n "$namespace" ] || die "REPO_ORGANIZATION is '$PUBLISH_PLACEHOLDER'; configure a real registry namespace first (ADR-0002)"
    registry="$(publish_registry)"
    [ -n "$registry" ] && [ "$registry" != "null" ] \
        || die "release-channel.json has no publish_registry; configure the official registry first"
    [ "${ENTHRONED_PUBLISH_CONFIRM:-}" = "1" ] \
        || die "set ENTHRONED_PUBLISH_CONFIRM=1 to confirm a real publication (human approval, ADR-0002)"
    need cosign
    [ -n "${ENTHRONED_COSIGN_KEY:-}" ] || die "set ENTHRONED_COSIGN_KEY to the cosign private key file (never committed to the repository)"
    [ -f "${ENTHRONED_COSIGN_KEY:-}" ] || die "ENTHRONED_COSIGN_KEY does not point to a readable key file"
    # ---- plan --------------------------------------------------------------
    local tag sha
    tag="$(cat "$OUT_DIR/version-tag.txt" 2>/dev/null || printf '%s' "$DEFAULT_TAG.$(date +%Y%m%d).$(source_sha)")"
    sha="$(source_sha)"
    log "PUBLISH PLAN (human-approved via ENTHRONED_PUBLISH_CONFIRM=1):"
    log "  push localhost/$IMAGE_NAME:$tag      -> $registry/$namespace/$IMAGE_NAME:$tag"
    log "  push localhost/$IMAGE_NAME:$DEFAULT_TAG -> $registry/$namespace/$IMAGE_NAME:$DEFAULT_TAG"
    log "  sign BOTH digests with cosign (key from ENTHRONED_COSIGN_KEY)"
    podman push "localhost/$IMAGE_NAME:$tag" "$registry/$namespace/$IMAGE_NAME:$tag"
    podman push "localhost/$IMAGE_NAME:$DEFAULT_TAG" "$registry/$namespace/$IMAGE_NAME:$DEFAULT_TAG"
    local remote_digest
    remote_digest="$(podman image inspect "$registry/$namespace/$IMAGE_NAME:$tag" --format '{{.Digest}}')"
    COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" cosign sign --key "$ENTHRONED_COSIGN_KEY" \
        "$registry/$namespace/$IMAGE_NAME@$remote_digest"
    log "published and signed: $registry/$namespace/$IMAGE_NAME@$remote_digest"
    if [ -f "$OUT_DIR/release-notes.json" ]; then
        jq '.signed = true | .published = true | .remote_digest = $d' \
            --arg d "$remote_digest" "$OUT_DIR/release-notes.json" \
            > "$OUT_DIR/release-notes.json.tmp" \
            && mv "$OUT_DIR/release-notes.json.tmp" "$OUT_DIR/release-notes.json"
    fi
    log "next step: update release-channel.json expected_image_references with the published repository"
}

usage() {
    cat <<'USAGE'
Usage: update-pipeline.sh [phase...]

Phases:
  check-base   detect a new Aurora base digest (read-only + output/aurora-base.json)
  build        rebuild the Enthroned image (just build; includes bootc container lint)
  verify       run all static validators and, if the image exists, just verify-image
  version      tag the built image with <channel>.<date>.<sha>
  notes        write output/release-notes.json
  publish      GATED push + cosign sign (needs namespace, registry, confirmation, key)
  all          check-base, build, verify, version, notes (never publish)

Examples:
  bash scripts/update-pipeline.sh all
  bash scripts/update-pipeline.sh check-base
USAGE
}

case "${1:-}" in
    check-base) phase_check_base ;;
    build)      phase_build ;;
    verify)     phase_verify ;;
    version)    phase_version ;;
    notes)      phase_notes ;;
    publish)    phase_publish ;;
    all)
        phase_check_base
        phase_build
        phase_verify
        phase_version
        phase_notes
        ;;
    *) usage; [ "${1:-}" = "" ] || exit 2 ;;
esac
