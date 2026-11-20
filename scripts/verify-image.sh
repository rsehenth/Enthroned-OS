#!/usr/bin/env bash
# Enthroned OS image verification.
# Inspects metadata of an already built OCI image and runs the identity helper
# inside it. Nothing is installed and no host system is modified.
# Usage: verify-image.sh [image-ref]   (default: localhost/enthroned-os:f1-dev)

set -euo pipefail

IMAGE_REF="${1:-localhost/enthroned-os:f1-dev}"
if [ $# -gt 1 ]; then
    echo "usage: verify-image.sh [image-ref]" >&2
    exit 2
fi

if ! command -v podman >/dev/null 2>&1; then
    echo "BLOCKED podman not available - cannot verify ${IMAGE_REF}" >&2
    exit 2
fi

if ! podman image exists "${IMAGE_REF}"; then
    echo "BLOCKED image ${IMAGE_REF} is not present locally. Build it first with: just build" >&2
    exit 2
fi

FAIL=0
pass() { printf 'PASS    %s\n' "$*"; }
fail() { printf 'FAIL    %s\n' "$*"; FAIL=1; }
warn() { printf 'WARN    %s\n' "$*"; }

# ---- Labels ---------------------------------------------------------------
LABELS="$(podman image inspect "${IMAGE_REF}" | jq -r '.[0].Labels // .[0].Config.Labels // empty' 2>/dev/null || echo '')"
if [ -z "${LABELS}" ]; then
    warn "labels: could not read image labels (jq missing or label absent)"
else
    BOOTC="$(printf '%s' "${LABELS}" | jq -r '."containers.bootc" // empty')"
    TITLE="$(printf '%s' "${LABELS}" | jq -r '."org.opencontainers.image.title" // empty')"
    [ "${BOOTC}" = "1" ] && pass "bootc: containers.bootc=1" || fail "bootc: containers.bootc label missing (got '${BOOTC:-none}')"
    [ "${TITLE}" = "enthroned-os" ] && pass "labels: org.opencontainers.image.title=enthroned-os" || warn "labels: title='${TITLE:-none}' (expected enthroned-os)"
fi

# ---- Enthroned OS presentation in os-release -------------------------------
OS_RELEASE="$(podman run --rm --network=none --entrypoint /bin/sh "${IMAGE_REF}" -c '. /etc/os-release && printf "%s|%s|%s" "${NAME:-}" "${VERSION_ID:-}" "${DEFAULT_HOSTNAME:-}"' || true)"
if printf '%s' "${OS_RELEASE}" | grep -q '^Enthroned OS|.*|enthroned$'; then
    pass "os-release: ${OS_RELEASE}"
else
    fail "os-release: unexpected '${OS_RELEASE}' (expected NAME=Enthroned OS and DEFAULT_HOSTNAME=enthroned)"
fi

# ---- Initramfs and previously identified upstream remnants ----------------
if podman run --rm --network=none --read-only --entrypoint /bin/bash "${IMAGE_REF}" -c '
    set -euo pipefail
    mapfile -t kernels < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf "%f\n")
    test "${#kernels[@]}" -eq 1
    initrd="/usr/lib/modules/${kernels[0]}/initramfs.img"
    release=$(lsinitrd -f usr/lib/initrd-release "$initrd")
    grep -Fxq '\''NAME="Enthroned OS"'\'' <<< "$release"
    grep -Fxq '\''DEFAULT_HOSTNAME="enthroned"'\'' <<< "$release"
    lsinitrd "$initrd" | grep -E "(etc/initrd-release|etc/os-release|usr/lib/os-release).* -> "
    for wallpaper in xe_clouds xe_foothills xe_space_needle xe_sunset; do
        test ! -L "/usr/share/wallpapers/$wallpaper" || test -e "/usr/share/wallpapers/$wallpaper"
    done
    defaults=/usr/share/kde-settings/kde-profile/default/xdg
    ! grep -E "dev\.getaurora|wallpapers/Aurora|^Name=Aurora|^Website=https://getaurora.dev" \
        "$defaults/kdeglobals" "$defaults/ksplashrc" "$defaults/kscreenlockerrc" \
        "$defaults/kcm-about-distrorc" "$defaults/kicker-extra-favoritesrc"
    '; then
    pass "initramfs identity and targeted KDE defaults/wallpaper aliases"
else
    fail "initramfs identity or targeted KDE defaults/wallpaper aliases"
fi

# ---- Look-and-feel discovery via enthroned-profile -------------------------
PROFILES_OUT="$(podman run --rm --network=none --entrypoint /usr/bin/enthroned-profile "${IMAGE_REF}" list || true)"
if printf '%s' "${PROFILES_OUT}" | grep -q 'org\.enthroned\.classic' && printf '%s' "${PROFILES_OUT}" | grep -q 'org\.enthroned\.modern'; then
    pass "enthroned-profile: discovers org.enthroned.classic and org.enthroned.modern"
else
    fail "enthroned-profile: missing Classic/Modern in list output: ${PROFILES_OUT}"
fi

# ---- Identity inside the image --------------------------------------------
IDENTITY_CHANNEL="$(podman run --rm --network=none --entrypoint /usr/bin/enthroned-identity "${IMAGE_REF}" --field channel || true)"
if [ "${IDENTITY_CHANNEL}" = "f1-dev" ]; then
    pass "identity: channel=f1-dev"
else
    fail "identity: channel='${IDENTITY_CHANNEL:-<empty>}' (expected f1-dev)"
fi

PROD_READY="$(podman run --rm --network=none --entrypoint /bin/sh "${IMAGE_REF}" -c "grep -o '\"production_ready\"[^,}]*' /usr/share/enthroned-os/release-channel.json" || true)"
if printf '%s' "${PROD_READY}" | grep -q 'false'; then
    pass "identity: release channel marked production_ready=false"
else
    fail "identity: production_ready flag not false (got '${PROD_READY:-<none>}')"
fi

echo
echo "Identity summary from inside the image:"
podman run --rm --network=none --entrypoint /usr/bin/enthroned-identity "${IMAGE_REF}" --summary

# Check only the built image. No network, update/install operation or host GUI.
if podman run --rm --network=none --read-only --tmpfs /tmp \
    --entrypoint /bin/bash "${IMAGE_REF}" -c '
    set -eu
    export HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/runtime
    export XDG_CONFIG_HOME=/tmp/config XDG_STATE_HOME=/tmp/state XDG_CACHE_HOME=/tmp/cache
    export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=Basic
    export QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_TO_CONSOLE=1
    export QT_LOGGING_RULES="*.warning=true;*.critical=true"
    export ENTHRONED_SETTINGS_ALLOW_MUTATION=0 ENTHRONED_WELCOME_ALLOW_INSTALL=0
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    chmod 0700 "$XDG_RUNTIME_DIR"
    for app in enthroned-settings enthroned-welcome; do
        test -x "/usr/bin/$app"
        if ldd "/usr/bin/$app" | grep -q "not found"; then
            echo "Missing runtime library for $app" >&2
            exit 1
        fi
        rc=0
        timeout --kill-after=2 5 "$app" --demo >"/tmp/$app.log" 2>&1 || rc=$?
        cat "/tmp/$app.log"
        test "$rc" -eq 124
        if grep -Eq "failed to load component|is not a type|is not installed|ReferenceError|TypeError|Cannot assign" "/tmp/$app.log"; then
            exit 1
        fi
    done
    test -x /usr/bin/plasma-discover
    test -x /usr/bin/dolphin
    test -f /etc/xdg/autostart/org.enthroned.welcome.autostart.desktop
    test -f /usr/share/applications/org.enthroned.settings.desktop
    test -f /usr/share/applications/org.enthroned.welcome.desktop
    '; then
    pass "MVP image packaging and headless demo QML startup (desktop session NOT tested)"
else
    fail "MVP image packaging or headless QML startup"
fi

# ---- Lote 11A: Discover/PackageKit policy and SELinux test label ------------
# Discover keeps the Flatpak backend only (OS updates are bootc/Update Center);
# the bootc probe label must never be written into shipped policy/config.
if podman run --rm --network=none --read-only --entrypoint /bin/bash "${IMAGE_REF}" -c '
    set -eu
    rpm -q plasma-discover-flatpak >/dev/null
    ! rpm -q plasma-discover-packagekit >/dev/null 2>&1
    ! rpm -q plasma-discover-offline-updates >/dev/null 2>&1
    ! grep -rIl invalid_bootcinstall_testlabel_t /etc /usr/etc /usr/lib/systemd /usr/share/selinux 2>/dev/null | grep -q .
    '; then
    pass "Discover has no RPM backend; no SELinux test label in shipped config (policy store itself not scanned)"
else
    fail "Discover RPM backend present or SELinux test label found in shipped config"
fi
# ---- Lote 13: official wallpapers, brand icons and defaults ---------------
# Static file checks inside the built image (no GUI, no network).
if podman run --rm --network=none --read-only --entrypoint /bin/bash "${IMAGE_REF}" -c '
    set -euo pipefail
    for pkg in EnthronedSoberania EnthronedAscensao EnthronedVigilia; do
        test -f "/usr/share/wallpapers/$pkg/metadata.json"
        test -f "/usr/share/wallpapers/$pkg/contents/screenshot.png"
        test -f "/usr/share/wallpapers/$pkg/contents/images/1672x941.png"
    done
    grep -q "Vig" /usr/share/wallpapers/EnthronedVigilia/metadata.json
    for laf in classic modern; do
        grep -Fxq "Image=EnthronedVigilia" "/usr/share/plasma/look-and-feel/org.enthroned.$laf/contents/defaults"
        grep -q "org.enthroned.launcher-$laf" "/usr/share/plasma/look-and-feel/org.enthroned.$laf/contents/layouts/org.kde.plasma.desktop-layout.js"
    done
    for size in 16 32 48 256; do
        test -f "/usr/share/icons/hicolor/${size}x${size}/apps/org.enthroned.launcher-classic.png"
        test -f "/usr/share/icons/hicolor/${size}x${size}/apps/org.enthroned.launcher-modern.png"
    done
    test -f /usr/share/enthroned-os/branding/enthroned-wordmark.png
    grep -q "wallpapers/EnthronedVigilia/" /etc/xdg/kscreenlockerrc
    grep -q "wallpapers/EnthronedVigilia/" /etc/plasmalogin.conf.d/10-enthroned.conf
    '; then
    pass "Lote 13: official wallpapers (Vigilia default), per-profile start icons and wordmark are installed"
else
    fail "Lote 13: wallpaper packages, start icons, wordmark or Vigilia defaults missing"
fi

echo
if [ "${FAIL}" -eq 0 ]; then
    echo "Image verification: PASS"
else
    echo "Image verification: FAIL"
fi
exit "${FAIL}"
