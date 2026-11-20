#!/bin/bash
# Enthroned OS image build script, executed inside the bootc build container.
# Derived from Universal Blue image-template build_files/build.sh (Apache-2.0).

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# Normalize permissions on files copied from host/Windows volumes so systemd
# and KDE do not warn about executable unit files or world-writable configs.
find /etc/xdg /etc/plasmalogin.conf.d /etc/NetworkManager/conf.d /usr/lib/systemd/system/enthroned-* \
    /usr/lib/systemd/user/enthroned-* \
    /usr/share/color-schemes /usr/share/enthroned-os /usr/share/polkit-1/rules.d \
    /usr/share/applications/enthroned-os-about.desktop \
    /usr/share/plasma/look-and-feel/org.enthroned.* \
    /usr/share/plasma/plasmoids/org.enthroned.launcher \
    /usr/share/plasma/packages/org.kde.plasmasetup.* \
    /usr/share/plasma/plasma-welcome \
    /usr/share/icons/Enthroned /usr/share/icons/EnthronedDark \
    /usr/share/wallpapers/Enthroned /usr/share/wallpapers/EnthronedNocturne \
    /usr/share/wallpapers/EnthronedSoberania /usr/share/wallpapers/EnthronedAscensao \
    /usr/share/wallpapers/EnthronedVigilia \
    -type d -exec chmod 0755 {} +
find /etc/xdg /etc/plasmalogin.conf.d /etc/NetworkManager/conf.d /usr/lib/systemd/system/enthroned-* \
    /usr/lib/systemd/user/enthroned-* \
    /usr/share/color-schemes /usr/share/enthroned-os /usr/share/polkit-1/rules.d \
    /usr/share/applications/enthroned-os-about.desktop \
    /usr/share/plasma/look-and-feel/org.enthroned.* \
    /usr/share/plasma/plasmoids/org.enthroned.launcher \
    /usr/share/plasma/packages/org.kde.plasmasetup.* \
    /usr/share/plasma/plasma-welcome \
    /usr/share/icons/Enthroned /usr/share/icons/EnthronedDark \
    /usr/share/wallpapers/Enthroned /usr/share/wallpapers/EnthronedNocturne \
    /usr/share/wallpapers/EnthronedSoberania /usr/share/wallpapers/EnthronedAscensao \
    /usr/share/wallpapers/EnthronedVigilia \
    /usr/share/icons/hicolor/*/apps/org.enthroned.* \
    -type f -exec chmod 0644 {} +

chmod 0755 /usr/bin/enthroned-identity
chmod 0755 /usr/bin/enthroned-profile
chmod 0755 /usr/bin/enthroned-desktop-shortcut
chmod 0755 /usr/bin/enthroned-diagnostics
chmod 0755 /usr/libexec/enthroned-firstboot-flatpaks
chmod 0755 /usr/libexec/enthroned-files-setup
chmod 0755 /usr/libexec/enthroned-desktop-actions
# Lote 8: fixed bootc update helper (takes no arguments; see the unit file).
chmod 0755 /usr/libexec/enthroned-system-update
# Lote 10 (P1-2): read-only bootc status cache writer for the Update Center.
chmod 0755 /usr/libexec/enthroned-bootc-status

### F4: applications policy (ADR-0006)
# KDE Discover is the Enthroned app store. Installing explicitly guarantees
# policy presence regardless of upstream base changes.
# Lote 6: gettext provides msgfmt for the Enthroned translation catalogs and
# a pt langpack keeps a pt_BR session locale fully functional. qt6/kf6/gettext
# are preinstalled in the Aurora KDE base and dnf5 fails on already-installed
# names, so only what is genuinely missing is requested here. Fedora ships the
# Portuguese locale as glibc-langpack-pt (no per-country pt_BR package).
#
# Lote 11A (H5 P2-2): Aurora does not ship Discover, so this install pulled
# plasma-discover-packagekit and plasma-discover-offline-updates as WEAK
# dependencies (H5 build.log). On an image-based system those enable the RPM
# update path and Discover's "update problem" dialog, while OS updates belong
# to bootc and the Enthroned Update Center. Fedora Kinoite itself excludes
# both subpackages. Exclude them here, at the proven origin; Flatpak search,
# catalog and installs (plasma-discover-flatpak) are untouched. Gate 11C
# (dnf5 5.4.8 on the approved Aurora base): the PackageKit daemon and
# appstream-data were only pulled in by plasma-discover-packagekit, so they
# no longer install; nothing else requires them and they are not masked.
dnf5 -y install --exclude=plasma-discover-packagekit \
    --exclude=plasma-discover-offline-updates \
    plasma-discover plasma-discover-flatpak glibc-langpack-pt
# Fail the build loudly if the RPM backends ever return (e.g. base change).
if rpm -q plasma-discover-packagekit >/dev/null 2>&1 \
    || rpm -q plasma-discover-offline-updates >/dev/null 2>&1; then
    echo "build.sh: Discover RPM/PackageKit backend present on an atomic image" >&2
    exit 1
fi
rpm -q plasma-discover-flatpak >/dev/null

### Gate 12.3: the development image ships with OS updates closed.
bash /ctx/close-os-updates.sh

### F4: first-boot Flatpak provisioning (Brave browser, ADR-0006)
systemctl enable enthroned-firstboot-flatpaks.timer

### Lote 10 (P1-2): per-boot bootc status cache for the Update Center
# Root-owned read-only helper; publishes /run/enthroned/bootc-status.json so
# the unprivileged Settings app can show the real version/origin (H4 P1-2).
# Lote 10.2 (Gate 10.1): the unit is wanted by graphical.target (not
# multi-user.target) and orders itself After=graphical.target in the unit
# file; systemd then suppresses the implicit "target After= wanted unit"
# ordering, so the oneshot never holds back the graphical target while still
# running once per boot. add-wants (not `systemctl enable`): shipped system
# services carry no [Install] section by convention, keeping boot-chain
# wiring here.
systemctl add-wants graphical.target enthroned-bootc-status.service

### Lote 10.2 (Gate 10.1): move the Fedora Atomic desktops workarounds
# (AppStream cache refresh, man-db update) out of the boot critical path.
# The base enables both into multi-user.target.wants, so multi-user.target -
# and with it graphical.target - waits for each oneshot to finish (H4:
# ~55-70 s AppStream refresh + ~38 s man-db on the critical/blame path).
# Re-point the enablement to graphical.target: combined with the
# After=graphical.target drop-ins shipped in system_files, systemd suppresses
# the implicit ordering and the target no longer waits, while both routines
# still run once per desktop boot with the same commands, conditions and
# caches (Discover included). Old links are removed BEFORE the new ordering
# is created: keeping a multi-user link alongside the new After= would form
# the cycle service -> multi-user.target -> graphical.target -> service.
# A boot stopped at multi-user.target intentionally skips both routines, and
# the real boot-time effect is only measurable in a VM (H5 validation).
for unit in fedora-atomic-desktop-appstream-cache-refresh.service \
            fedora-atomic-desktop-mandb-update.service; do
    if [ -f "/usr/lib/systemd/system/${unit}" ]; then
        rm -f "/etc/systemd/system/multi-user.target.wants/${unit}"
        systemctl add-wants graphical.target "${unit}"
    else
        echo "build.sh: WARNING: ${unit} not found in the base; boot-order change skipped" >&2
    fi
done
# Ship the shipped drop-ins with sane permissions (cp from the build context
# may carry host permissions).
find /usr/lib/systemd/system -name 'enthroned-boot-order.conf' -exec chmod 0644 {} +
chmod 0755 /usr/lib/systemd/system/input-remapper.service.d
chmod 0644 /usr/lib/systemd/system/input-remapper.service.d/*.conf

### Gate 16: boot critical path (H6 boot 2: graphical.target @72,413s)
# 1. tuned.service override (system_files/etc/systemd/system/tuned.service):
#    removing After=network.target lets TuneD and NetworkManager start in parallel.
#    Reject any other difference from the Aurora RPM unit.
bash /ctx/verify-tuned-unit.sh /usr/lib/systemd/system/tuned.service /etc/systemd/system/tuned.service
chmod 0755 /etc/systemd/system
chmod 0644 /etc/systemd/system/tuned.service
# 2. input-remapper.service drop-in (01-enthroned-default-deps.conf):
#    DefaultDependencies=no removes the implicit "graphical.target After=
#    wanted unit" edge (systemctl show in the pinned base confirmed the
#    target waited for the daemon; H6: +30,560s, last before the target).
#    The drop-in restores the service's default startup and shutdown edges.
#    The Gate 12.7 90s timeout remains in force for the daemon itself.
# Gate 12.1: the republish drop-ins live in directories the enthroned-* globs
# above do not reach; a Windows/WSL build context would otherwise ship them
# 0777. Same fail-closed behaviour as the wants loop (a missing one aborts).
find /usr/lib/systemd/system/uupd.service.d /usr/lib/systemd/system/uupd-manual.service.d \
    -type d -exec chmod 0755 {} +
find /usr/lib/systemd/system/uupd.service.d /usr/lib/systemd/system/uupd-manual.service.d \
    -type f -exec chmod 0644 {} +

### Lote 7.1: desktop context menu defaults
# The user unit rewrites (idempotently) the per-user Plasma binding so the
# desktop right button uses the Enthroned context menu plugin and the
# separator gaps are closed, before plasmashell reads its configuration.
systemctl --global enable enthroned-desktop-actions.service

### Enthroned OS first-boot & visual identity integration
# 1. Update user-facing os-release presentation fields while keeping technical
#    provenance/update fields (ID, ID_LIKE, VERSION_ID, OSTREE_VERSION, CPE_NAME).
python3 - <<'PY'
path = "/usr/lib/os-release"
with open(path, "r", encoding="utf-8") as fh:
    lines = fh.read().splitlines()

updates = {
    "NAME": '"Enthroned OS"',
    "DEFAULT_HOSTNAME": '"enthroned"',
    "LOGO": "org.enthroned.enthroned-os",
    "HOME_URL": '"https://enthroned.local/"',
    "DOCUMENTATION_URL": '"https://enthroned.local/docs"',
    "SUPPORT_URL": '"https://enthroned.local/support"',
    "BUG_REPORT_URL": '"https://enthroned.local/issues"',
}
ver = ""
variant = "Desktop"
for line in lines:
    if line.startswith("VERSION_ID="):
        ver = line.split("=", 1)[1].strip('"')
    elif line.startswith("VARIANT="):
        variant = line.split("=", 1)[1].strip('"')
updates["PRETTY_NAME"] = f'"Enthroned OS {ver} ({variant})"' if ver else '"Enthroned OS"'

seen = set()
out = []
for line in lines:
    key = line.split("=", 1)[0] if "=" in line else ""
    if key in updates:
        out.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        out.append(line)
for key, val in updates.items():
    if key not in seen:
        out.append(f"{key}={val}")

with open(path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
PY

# 2. Replace upstream Aurora wallpapers, splash/look-and-feel, docs, and menu entries.
rm -rf /usr/share/plasma/look-and-feel/dev.getaurora.*
rm -f /usr/share/applications/dev.getaurora.*.desktop \
      /usr/share/kglobalaccel/dev.getaurora.offline-docs.desktop
rm -rf /usr/share/doc/aurora

# Keep plasma-welcome libraries intact for KDE dependencies, but hide its desktop
# entry from the launcher so Enthroned Welcome is the single welcome app.
if [ -f /usr/share/applications/org.kde.plasma-welcome.desktop ]; then
    sed -i '/^Hidden=/d;/^NoDisplay=/d' /usr/share/applications/org.kde.plasma-welcome.desktop
    printf '\nHidden=true\nNoDisplay=true\n' >> /usr/share/applications/org.kde.plasma-welcome.desktop
fi
if [ -f /usr/share/applications/kcm_ublue.desktop ]; then
    # Lote 6: the image-level preferences KCM must not appear in the main
    # System Settings experience. NoDisplay/Hidden keep the entry out of
    # launchers and the settings sidebar while `kcmshell6 kcm_ublue` still
    # works; Enthroned Settings (Apps page, advanced area) offers an honest
    # entry point. Créditos e proveniência do módulo permanecem intactos.
    if ! grep -q '^NoDisplay=' /usr/share/applications/kcm_ublue.desktop; then
        printf '\nNoDisplay=true\nHidden=true\n' >> /usr/share/applications/kcm_ublue.desktop
    fi
    # Correção homologação 3: belt-and-braces — if the entry ever surfaces
    # despite NoDisplay/Hidden (e.g. a module list that ignores NoDisplay),
    # it must not present upstream branding to the user. No-op when the
    # upstream display name is not "Aurora…".
    sed -i 's|^Name=Aurora.*$|Name=Enthroned OS|; s|^Name\[pt_BR\]=Aurora.*$|Name\[pt_BR\]=Enthroned OS|' \
        /usr/share/applications/kcm_ublue.desktop
fi

# Present Dolphin to the user as "Files" / "Arquivos" (Lote 6) while keeping
# the binary, storage id (org.kde.dolphin.desktop) and MIME associations
# untouched. Only the display name of the launcher entry changes; GenericName
# and every action remain the upstream ones.
if [ -f /usr/share/applications/org.kde.dolphin.desktop ]; then
    sed -i 's|^Name=Dolphin$|Name=Files|; s|^Name\[pt_BR\]=.*$|Name[pt_BR]=Arquivos|' \
        /usr/share/applications/org.kde.dolphin.desktop
fi

# Generate Enthroned JXL backgrounds and replace Aurora's hardcoded plasma-setup
# landing image (/usr/share/wallpapers/Aurora/contents/images/3840x2160.jxl)
# without metadata.json so it never shows as an "Aurora" wallpaper choice.
mkdir -p /usr/share/backgrounds/enthroned /usr/share/wallpapers/Aurora/contents/images
# Lote 13: the official default wallpaper (Enthroned - Vigilia, wall3.png,
# 1672x941) is the only landing/fallback art. It is scaled with Lanczos at
# build time into derived files; the packaged original is never modified.
vigilia_src=/usr/share/wallpapers/EnthronedVigilia/contents/images/1672x941.png
magick "$vigilia_src" -filter Lanczos -resize 3840x2160^ -gravity center -extent 3840x2160 \
    /usr/share/backgrounds/enthroned/enthroned-light.jxl
cp -f /usr/share/backgrounds/enthroned/enthroned-light.jxl /usr/share/backgrounds/enthroned/enthroned-dark.jxl

rm -rf /usr/share/backgrounds/aurora \
       /usr/share/wallpapers/aurora-* \
       /usr/share/wallpapers/greg-rakozy-aurora \
       /usr/share/wallpapers/jonatan-pie-aurora \
       /usr/share/wallpapers/Aurora
# These upstream aliases now point into the removed Aurora backgrounds.
for wallpaper in xe_clouds xe_foothills xe_space_needle xe_sunset; do
    alias_path="/usr/share/wallpapers/$wallpaper"
    if [ -L "$alias_path" ] && [ ! -e "$alias_path" ]; then
        rm -- "$alias_path"
    fi
done
mkdir -p /usr/share/wallpapers/Aurora/contents/images
cp -f /usr/share/backgrounds/enthroned/enthroned-light.jxl \
    /usr/share/wallpapers/Aurora/contents/images/3840x2160.jxl
chmod 0755 /usr/share/wallpapers/Aurora /usr/share/wallpapers/Aurora/contents \
    /usr/share/wallpapers/Aurora/contents/images
chmod 0644 /usr/share/wallpapers/Aurora/contents/images/3840x2160.jxl

ln -snf enthroned/enthroned-light.jxl /usr/share/backgrounds/default.jxl
ln -snf enthroned/enthroned-dark.jxl /usr/share/backgrounds/default-dark.jxl
rm -f /usr/share/backgrounds/default.xml
cat <<'EOF' > /usr/share/backgrounds/default.xml
<background>
  <static>
    <duration>86400.0</duration>
    <file>/usr/share/backgrounds/default.jxl</file>
  </static>
</background>
EOF
chmod 0644 /usr/share/backgrounds/default.xml

# Point Plasma Login Manager distro defaults to Enthroned wallpaper too.
if [ -f /usr/lib/plasmalogin/defaults.conf ]; then
    sed -i 's|file:///usr/share/wallpapers/Aurora/|file:///usr/share/wallpapers/EnthronedVigilia/|g' \
        /usr/lib/plasmalogin/defaults.conf
fi

# Keep the lower-priority KDE profile consistent with /etc/xdg, retaining KDE's
# other settings and allowing /etc/xdg and per-user configuration to take precedence.
kde_defaults=/usr/share/kde-settings/kde-profile/default/xdg
sed -i 's/dev\.getaurora\.aurora\.desktop/org.enthroned.classic/g;s/^ColorScheme=BreezeDark$/ColorScheme=EnthronedLight/' \
    "$kde_defaults/kdeglobals" "$kde_defaults/ksplashrc"
sed -i 's|file:///usr/share/wallpapers/Aurora/|file:///usr/share/wallpapers/EnthronedVigilia/|g' \
    "$kde_defaults/kscreenlockerrc"
sed -i 's/^Name=Aurora$/Name=Enthroned OS/;s|^Website=https://getaurora.dev$|Website=|' \
    "$kde_defaults/kcm-about-distrorc"
sed -i 's/dev\.getaurora\.aurora-docs\.desktop;//g' "$kde_defaults/kicker-extra-favoritesrc"

# 2.5 Enthroned translation catalogs (Lote 6).
# The .po sources under /ctx/l10n (from build_files/l10n in the build context)
# are compiled to GNU gettext .mo catalogs for pt_BR. Enthroned applications use the ki18n
# domain matching their translation domain ( enthroned-welcome,
# enthroned-settings, org.enthroned.launcher ). The plasma-setup catalog is
# special: it is MERGED with the upstream pt_BR catalog (when the base image
# ships one) so the wizard keeps its own translations while the Enthroned
# entries override only the strings we must brand (greeting, start button and
# the first-boot completion page). The upstream English source text of the
# Plasma Setup landing page is compiled into the plasma-setup binary, so a
# translation catalog is the supported customization mechanism; there is no
# en_US catalog because ki18n treats en_US as the source language itself.
python3 - <<'PY'
import os
import struct

EOT = "\x04"


def parse_po(path):
    """Minimal parser for the controlled .po files shipped in /l10n."""
    entries = {}
    entry = {}
    pending = None

    def unquote(raw):
        body = raw[1:-1]
        return (body.replace('\\"', '"').replace("\\n", "\n")
                    .replace("\\t", "\t").replace("\\\\", "\\"))

    def commit():
        if entry.get("id") and entry.get("str"):
            key = (entry["ctxt"] + EOT + entry["id"]) if entry.get("ctxt") else entry["id"]
            entries[key] = entry["str"]

    with open(path, "r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("msgctxt "):
                commit()
                entry = {}
                pending = "ctxt"
                entry["ctxt"] = unquote(line[8:])
            elif line.startswith("msgid "):
                if pending == "str":
                    commit()
                    entry = {}
                pending = "id"
                entry["id"] = unquote(line[6:])
            elif line.startswith("msgstr "):
                pending = "str"
                entry["str"] = unquote(line[7:])
            elif line.startswith('"'):
                entry[pending] = entry.get(pending, "") + unquote(line)
    commit()
    return entries


def read_mo(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, n, o_off, t_off = struct.unpack("<5I", data[:20])
    if magic != 0x950412DE:
        raise ValueError("not a .mo file")
    entries = {}
    for i in range(n):
        olen, ooff = struct.unpack("<2I", data[o_off + 8 * i:o_off + 8 * i + 8])
        tlen, toff = struct.unpack("<2I", data[t_off + 8 * i:t_off + 8 * i + 8])
        orig = data[ooff:ooff + olen].decode("utf-8")
        trans = data[toff:toff + tlen].decode("utf-8")
        if orig and not orig.startswith("Project-Id-Version"):
            entries[orig] = trans
    return entries


def write_mo(path, entries):
    keys = sorted(k.encode("utf-8") for k in entries)
    vals = [entries[k.decode("utf-8")].encode("utf-8") for k in keys]
    n = len(keys)
    o_off = 28
    t_off = o_off + 8 * n
    data_off = t_off + 8 * n
    out = bytearray()
    out += struct.pack("<7I", 0x950412DE, 0, n, o_off, t_off, 0, data_off)
    koffsets = []
    cur = data_off
    for k in keys:
        koffsets.append((len(k), cur))
        cur += len(k) + 1
    voffsets = []
    for v in vals:
        voffsets.append((len(v), cur))
        cur += len(v) + 1
    # Canonical .mo layout: header, orig table, trans table, then strings.
    for length, off in koffsets:
        out += struct.pack("<2I", length, off)
    for length, off in voffsets:
        out += struct.pack("<2I", length, off)
    for k in keys:
        out += k + b"\x00"
    for v in vals:
        out += v + b"\x00"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(bytes(out))


def compile_po(po_path, mo_path):
    write_mo(mo_path, parse_po(po_path))
    print(f"enthroned l10n: {po_path} -> {mo_path} ({len(parse_po(po_path))} strings)")


l10n_dir = "/ctx/l10n/pt_BR"
locale_dir = "/usr/share/locale/pt_BR/LC_MESSAGES"
if not os.path.isdir(l10n_dir):
    raise SystemExit("enthroned l10n: missing /ctx/l10n/pt_BR build context")

for po in sorted(os.listdir(l10n_dir)):
    if not po.endswith(".po"):
        continue
    domain = po[:-3]
    mo = os.path.join(locale_dir, domain + ".mo")
    if domain == "org.kde.plasmasetup":
        # Merge with the upstream catalog when the base image ships one, so
        # only our branded strings are overridden.
        existing = read_mo(mo) if os.path.isfile(mo) else {}
        existing.update(parse_po(os.path.join(l10n_dir, po)))
        write_mo(mo, existing)
        print(f"enthroned l10n: merged {po} into {mo} ({len(existing)} strings)")
    else:
        compile_po(os.path.join(l10n_dir, po), mo)
PY

# 2.6 Plasma Setup landing background (Lote 6).
# The compiled plasma-setup landing looks the image up under
# /usr/share/wallpapers/Next/contents/images{,_dark}/ (5120x2880 landscape,
# 1440x2960 portrait). Replace the upstream Plasma art with the Enthroned
# wallpaper (Lote 13: Enthroned - Vigilia) so the first-boot wizard opens with
# the product's own identity.
next_dir=/usr/share/wallpapers/Next/contents/images
next_dark_dir=/usr/share/wallpapers/Next/contents/images_dark
mkdir -p "$next_dir" "$next_dark_dir"
magick "$vigilia_src" -filter Lanczos -resize 5120x2880^ -gravity center -extent 5120x2880 \
    "$next_dir/5120x2880.png"
magick "$vigilia_src" -filter Lanczos -resize 1440x2960^ -gravity center -extent 1440x2960 \
    "$next_dir/1440x2960.png"
cp -f "$next_dir/5120x2880.png" "$next_dark_dir/5120x2880.png"
cp -f "$next_dir/1440x2960.png" "$next_dark_dir/1440x2960.png"
chmod 0755 /usr/share/wallpapers/Next /usr/share/wallpapers/Next/contents \
    "$next_dir" "$next_dark_dir"
chmod 0644 "$next_dir"/*.png "$next_dark_dir"/*.png

# 3. Replace distributor/system logos used in About, login, and fallback start icons.
# Lote 13: the logos are the owner's original artwork (assets/), shipped as
# pre-derived hicolor PNGs by scripts/gen-brand-assets.py - nothing is redrawn
# here. The old placeholder crown artwork is no longer shipped.
icon_root=/usr/share/icons/hicolor
install -Dm0644 "$icon_root/256x256/apps/org.enthroned.enthroned-os.png" /usr/share/pixmaps/enthroned-logo.png
cp -f /usr/share/pixmaps/enthroned-logo.png /usr/share/pixmaps/system-logo.png
cp -f /usr/share/pixmaps/enthroned-logo.png /usr/share/pixmaps/system-logo-white.png
rm -f /usr/share/pixmaps/aurora-banner.svg
for size in 16 22 24 32 48 64 128 256 512; do
    mkdir -p "$icon_root/${size}x${size}/places"
    cp -f "$icon_root/${size}x${size}/apps/org.enthroned.enthroned-os.png" \
        "$icon_root/${size}x${size}/places/distributor-logo.png"
    cp -f "$icon_root/${size}x${size}/apps/org.enthroned.launcher-classic.png" \
        "$icon_root/${size}x${size}/places/start-here.png"
done
rm -f /usr/share/icons/hicolor/scalable/distributor-logo.svg \
        /usr/share/icons/hicolor/scalable/places/distributor-logo.svg \
        /usr/share/icons/hicolor/scalable/places/start-here.svg
# No symbolic/white distributor logo is shipped: KDE falls back to distributor-logo.
rm -f /usr/share/icons/hicolor/scalable/places/distributor-logo-symbolic.svg \
      /usr/share/icons/hicolor/scalable/places/distributor-logo-white.svg
rm -f /usr/share/icons/hicolor/scalable/places/auroralogo-*.svg \
        /usr/share/icons/hicolor/scalable/apps/aurora-*.svg
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true

# 4. Replace terminal MOTD / ASCII branding and disable Aurora notifier timer.
if [ -d /usr/share/ublue-os/motd ]; then
    cat <<'EOF' > /usr/share/ublue-os/motd/template.md
# Welcome to Enthroned OS

`${MOTD_IMAGE_NAME}:${MOTD_IMAGE_TAG}`

| Command | Description |
| ------- | ----------- |
| `enthroned-identity` | Show Enthroned OS image identity |
| `enthroned-profile status` | Show active appearance profile |
| `ujust --choose` | Show available system tasks |
| `brew help` | Manage command line packages |

${MOTD_TIP}
EOF
    cat <<'EOF' > /usr/share/ublue-os/motd/tips/10-tips.md
Use `enthroned-profile apply classic` or `enthroned-profile apply modern` to switch desktop profiles.
Update break something? You can roll back with `bootc rollback`.
Use `Ctrl`-`Alt`-`T` to quickly open a terminal.
EOF
fi
if [ -f /usr/share/ublue-os/aurora-ascii-logo.txt ]; then
    cat <<'EOF' > /usr/share/ublue-os/aurora-ascii-logo.txt
   ______      __  __                             __   ____  _____
  / ____/___  / /_/ /_  _________  ____  ___  ___/ /  / __ \/ ___/
 / __/ / __ \/ __/ __ \/ ___/ __ \/ __ \/ _ \/ __  /  / / / /\__ \ 
/ /___/ / / / /_/ / / / /  / /_/ / / / /  __/ /_/ /  / /_/ /___/ / 
/_____/_/ /_/\__/_/ /_/_/   \____/_/ /_/\___/\__,_/   \____//____/  
EOF
fi
systemctl disable aurora-iwd-deprecation-notifier.timer 2>/dev/null || true

# bootc consumes this image's kernel/initramfs pair, never the build host kernel.
# A split-kernel bootc image must contain exactly one kernel; fail on ambiguity.
mapfile -t kernels < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
if [ "${#kernels[@]}" -ne 1 ]; then
    printf 'Expected one bootc kernel, found %s: %s\n' "${#kernels[@]}" "${kernels[*]}" >&2
    exit 1
fi
KVER="${kernels[0]}"
test -f "/usr/lib/modules/$KVER/vmlinuz"
DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "$KVER" --reproducible --force \
    "/usr/lib/modules/$KVER/initramfs.img"
initrd_release="$(lsinitrd -f usr/lib/initrd-release "/usr/lib/modules/$KVER/initramfs.img")"
grep -Fxq 'NAME="Enthroned OS"' <<< "$initrd_release"
grep -Fxq 'DEFAULT_HOSTNAME="enthroned"' <<< "$initrd_release"
printf 'Verified initrd-release identity for kernel %s\n' "$KVER"
