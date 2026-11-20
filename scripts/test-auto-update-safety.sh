#!/usr/bin/env bash
# Gate 12.3. Run in the disposable, offline Aurora container described in the report.
set -euo pipefail

if [[ $EUID != 0 || ! -f /run/.containerenv ]]; then
    echo "This test requires root inside a disposable Podman container." >&2
    exit 2
fi

units=/etc/systemd/system
if [[ ${1:-} == --init && $$ == 1 ]]; then
    printf '[Unit]\nDescription=Gate 12.3 isolated test boot\nDefaultDependencies=no\n' \
        >"$units/gate-12-3.target"
    exec /usr/lib/systemd/systemd --unit=gate-12-3.target
fi
systemctl is-active --quiet gate-12-3.target

trap 'echo "FAIL  line $LINENO: $BASH_COMMAND" >&2' ERR
src=/src/system_files/usr/lib/systemd
vendor=/usr/lib/systemd/system
channel=/usr/share/enthroned-os/release-channel.json
policy=/src/build_files/close-os-updates.sh
timers=(uupd.timer enthroned-system-update.timer
    bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer)
services=(uupd.service uupd-manual.service enthroned-system-update.service
    bootc-fetch-apply-updates.service rpm-ostreed-automatic.service)
read_only=(enthroned-bootc-status.service enthroned-update-check.service)
flatpak=(enthroned-flatpak-update.service enthroned-firstboot-flatpaks.service)
tested_services=("${services[@]}" "${read_only[@]}" "${flatpak[@]}")
offline_state() { systemctl --root=/ is-enabled "$1" || :; }
pass() { printf 'PASS  %s\n' "$*"; }

install -m 0644 "$src"/system/enthroned-*.{service,timer} "$vendor/"
for unit in uupd.service uupd-manual.service; do
    install -D -m 0644 "$src/system/$unit.d/enthroned-bootc-status.conf" \
        "$vendor/$unit.d/enthroned-bootc-status.conf"
done
install -m 0755 /src/system_files/usr/libexec/enthroned-{system-update,bootc-status,firstboot-flatpaks} \
    /usr/libexec/
systemd-analyze --man=no --recursive-errors=no verify \
    "${timers[@]}" "${tested_services[@]}" enthroned-firstboot-flatpaks.timer
pass "original unit definitions and Gate 12.1 drop-ins pass systemd-analyze verify"

# Every command below that can reach ExecStart uses a harmless file marker.
install -d /run/gate-12-3
for unit in "${tested_services[@]}"; do
    install -d "$units/$unit.d"
    cat >"$units/$unit.d/99-gate-test.conf" <<EOF
[Unit]
DefaultDependencies=no
ConditionPathExists=
[Service]
SELinuxContext=
ExecStart=
ExecStart=/usr/bin/touch /run/gate-12-3/$unit
ExecStartPost=
EOF
done
for unit in uupd.timer enthroned-system-update.timer; do
    install -d "$units/$unit.d"
    printf '[Timer]\nOnCalendar=\nOnActiveSec=100ms\nAccuracySec=1ms\nRandomizedDelaySec=0\nPersistent=false\n' \
        >"$units/$unit.d/99-gate-test.conf"
done
systemctl daemon-reload
for unit in "${tested_services[@]}"; do
    [[ $(systemctl show "$unit" -p ExecStart --value) == *"argv[]=/usr/bin/touch /run/gate-12-3/$unit ;"* ]]
done

[[ $(offline_state uupd.timer) == enabled ]]
test -L "$units/timers.target.wants/uupd.timer"
[[ ! -e $channel ]]
systemctl start uupd.timer
timeout 5 bash -c 'until [[ -e /run/gate-12-3/uupd.service ]]; do sleep .1; done'
[[ $(stat -c %u /run/gate-12-3/uupd.service) == 0 ]]
systemctl stop uupd.timer
rm /run/gate-12-3/uupd.service
pass "the enabled Aurora timer fires its root service with no channel file"

# Verify preset precedence independently of the stronger service masks.
install -m 0644 "$src/system-preset/20-enthroned-os-updates.preset" /usr/lib/systemd/system-preset/
systemctl --root=/ preset uupd.timer
[[ $(offline_state uupd.timer) == disabled ]]
systemctl --root=/ enable "${timers[@]}"
bash "$policy"
systemctl daemon-reload
for unit in "${timers[@]}"; do
    [[ ! -L $units/timers.target.wants/$unit ]]
done
pass "Enthroned preset beats Aurora and the build removes inherited wants links"

install -d /etc/systemd/system-preset "$units/gate-12-3-dependency.target.wants"
printf 'enable uupd.timer\n' >/etc/systemd/system-preset/00-test-enable.preset
if diagnostic=$(systemctl --root=/ preset uupd.timer 2>&1); then
    echo "Preset unexpectedly enabled a masked timer" >&2
    exit 1
fi
[[ $diagnostic == *"uupd.timer is masked"* ]]
[[ ! -L $units/timers.target.wants/uupd.timer ]]
pass "even an earlier enabling preset cannot restore the masked timer"

for unit in "${timers[@]}" "${services[@]}"; do
    [[ $(systemctl show "$unit" -p LoadState --value) == masked ]]
    if diagnostic=$(systemctl start "$unit" 2>&1); then
        echo "Unexpected start: $unit" >&2
        exit 1
    fi
    [[ $diagnostic == *"Unit $unit is masked."* ]]
    [[ ! -e /run/gate-12-3/$unit ]]
done
pass "all nine unit starts fail visibly even for root with the channel file absent"

printf '[Unit]\nDescription=Gate 12.3 dependency test\nDefaultDependencies=no\n' \
    >"$units/gate-12-3-dependency.target"
ln -s "$vendor/uupd.timer" "$units/gate-12-3-dependency.target.wants/uupd.timer"
printf '[Unit]\nDescription=Gate 12.3 direct dependency test\nDefaultDependencies=no\nRequires=uupd.service\n' \
    >"$units/gate-12-3-requires.target"
systemctl daemon-reload
systemctl start gate-12-3-dependency.target
[[ $(systemctl show gate-12-3-dependency.target -p Wants --value) == *uupd.timer* ]]
[[ $(systemctl show uupd.timer -p ActiveState --value) == inactive ]]
if systemctl start gate-12-3-requires.target; then
    echo "Required dependency unexpectedly started" >&2
    exit 1
fi
[[ ! -e /run/gate-12-3/uupd.service ]]
pass "restored Wants link and direct Requires dependency cannot start the updater"

install -D -m 0644 /src/system_files/usr/share/enthroned-os/release-channel.json "$channel"
for metadata in '{"production_ready":true}' \
    '{"production_ready":true,"channel":"stable","expected_image_references":["registry.example.invalid/enthroned/os"]}'; do
    [[ $(systemctl show enthroned-system-update.service -p LoadState --value) == masked ]]
    printf '%s\n' "$metadata" >"$channel"
done
[[ $(systemctl show enthroned-system-update.service -p LoadState --value) == masked ]]
pass "development, readiness flag alone and simulated official metadata retain the mask"

systemctl start "${read_only[@]}" "${flatpak[@]}"
for unit in "${read_only[@]}" "${flatpak[@]}"; do
    [[ -f /run/gate-12-3/$unit ]]
done
systemctl --root=/ enable enthroned-firstboot-flatpaks.timer
[[ $(offline_state enthroned-firstboot-flatpaks.timer) == enabled ]]
pass "both read-only and both independent Flatpak services can start with the channel closed"

# Simulate a separately approved future policy change. Only the inert Enthroned pair is released.
systemctl --root=/ unmask enthroned-system-update.{timer,service}
systemctl daemon-reload
systemctl start enthroned-system-update.timer
timeout 5 bash -c 'until [[ -e /run/gate-12-3/enthroned-system-update.service ]]; do sleep .1; done'
[[ $(systemctl show uupd.service -p LoadState --value) == masked ]]
pass "a simulated selective release can stage through the Enthroned timer without releasing uupd"
