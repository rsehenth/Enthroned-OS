#!/usr/bin/env bash
# Gate 16. Run inside a disposable, offline container of the pinned Aurora
# base (ghcr.io/ublue-os/aurora@sha256:9599680497ef22def5e9f05735faaf70ea2b4550ae8391f7ab71c6273432ae92)
# with the repository mounted read-only at /src (the container itself must be
# writable: the test installs the artifacts and wants-links), e.g.:
#   podman run --rm --pull=never --network=none \
#       --tmpfs /run --tmpfs /tmp --tmpfs /var \
#       -v "$PWD":/src:ro <pinned-aurora> /sbin/init &
#   podman exec <ctr> bash /src/scripts/test-gate16-boot-order.sh
set -euo pipefail

if [[ $EUID != 0 || ! -f /run/.containerenv ]]; then
    echo "This test requires root inside a disposable Podman container." >&2
    exit 2
fi
if [[ ! -d /src/system_files ]]; then
    echo "Mount the repository read-only at /src." >&2
    exit 2
fi

fails=0
passes=0
pass() { printf 'PASS  %s\n' "$*"; passes=$((passes + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
check() { # check <description> <command...>
    local desc=$1; shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}
contains() { # contains <list> <needle>...
    local list=$1 needle
    shift
    for needle in "$@"; do
        grep -Fxq -- "$needle" <<<"${list// /$'\n'}" || return 1
    done
}
lacks() {
    ! contains "$@"
}

trap 'echo "FAIL  line $LINENO: $BASH_COMMAND" >&2; exit 1' ERR

echo "== preflight =="
bash -n /src/build_files/build.sh
pass "build_files/build.sh passes bash -n"

echo "== install artifacts exactly as build.sh would =="
install -D -m 0644 /src/system_files/etc/systemd/system/tuned.service \
    /etc/systemd/system/tuned.service
install -D -m 0644 /src/system_files/usr/lib/systemd/system/input-remapper.service.d/00-enthroned-start-timeout.conf \
    /usr/lib/systemd/system/input-remapper.service.d/00-enthroned-start-timeout.conf
install -D -m 0644 /src/system_files/usr/lib/systemd/system/input-remapper.service.d/01-enthroned-default-deps.conf \
    /usr/lib/systemd/system/input-remapper.service.d/01-enthroned-default-deps.conf
install -m 0644 /src/system_files/usr/lib/systemd/system/enthroned-bootc-status.service \
    /usr/lib/systemd/system/enthroned-bootc-status.service
install -m 0755 /src/system_files/usr/libexec/enthroned-bootc-status /usr/libexec/
systemctl add-wants graphical.target enthroned-bootc-status.service
systemctl daemon-reload

echo "== build guard against vendor unit drift =="
tuned_vendor=/usr/lib/systemd/system/tuned.service
tuned_override=/etc/systemd/system/tuned.service
bash /src/build_files/verify-tuned-unit.sh "$tuned_vendor" "$tuned_override"
pass "build guard accepts the pinned unit with only the network.target edge removed"

drifted_unit=$(mktemp)
trap 'rm -f -- "$drifted_unit"' EXIT
sed '/^\[Service\]$/a ProtectSystem=full' "$tuned_vendor" > "$drifted_unit"
if bash /src/build_files/verify-tuned-unit.sh "$drifted_unit" "$tuned_override" >/dev/null 2>&1; then
    fail "build guard accepted an upstream service change outside After="
else
    pass "build guard rejects an upstream service change outside After="
fi
check "override ships no network.target outside comments" \
    bash -c "! grep -q '^[[:space:]]*[^#].*network.target' /etc/systemd/system/tuned.service"

echo "== systemd level =="
systemd-analyze --man=no --recursive-errors=no verify \
    tuned.service tuned-ppd.service input-remapper.service \
    enthroned-bootc-status.service
pass "systemd-analyze verify: tuned, tuned-ppd, input-remapper, bootc-status"

tuned_after=$(systemctl show tuned.service -p After --value)
tuned_before=$(systemctl show tuned.service -p Before --value)
tuned_req=$(systemctl show tuned.service -p Requires --value)
check "tuned After=: sysctl/dbus/polkit kept" contains \
    "$tuned_after" systemd-sysctl.service dbus-broker.service polkit.service
check "tuned After=: network.target gone" lacks "$tuned_after" network.target
check "tuned Before=: tuned-ppd and multi-user waits preserved" contains \
    "$tuned_before" tuned-ppd.service multi-user.target
check "tuned Requires=dbus preserved" contains "$tuned_req" dbus-broker.service dbus.socket
[[ $(systemctl show tuned.service -p FragmentPath --value) == /etc/systemd/system/tuned.service ]]
pass "tuned loads the /etc override fragment"
[[ $(systemctl show tuned.service -p Type --value) == dbus && \
    $(systemctl show tuned.service -p BusName --value) == com.redhat.tuned ]]
pass "tuned Type=dbus + BusName unchanged"

ppd_after=$(systemctl show tuned-ppd.service -p After --value)
ppd_before=$(systemctl show tuned-ppd.service -p Before --value)
ppd_req=$(systemctl show tuned-ppd.service -p Requires --value)
check "tuned-ppd still After=tuned.service" contains "$ppd_after" tuned.service
check "tuned-ppd still Requires=tuned.service" contains "$ppd_req" tuned.service
check "tuned-ppd Before= (graphical/multi-user/display-manager) unchanged" contains \
    "$ppd_before" graphical.target multi-user.target display-manager.target

multi_after=$(systemctl show multi-user.target -p After --value)
check "multi-user.target still waits for tuned and tuned-ppd" contains \
    "$multi_after" tuned.service tuned-ppd.service

remapper_dd=$(systemctl show input-remapper.service -p DefaultDependencies --value)
remapper_to=$(systemctl show input-remapper.service -p TimeoutStartUSec --value)
remapper_after=$(systemctl show input-remapper.service -p After --value)
remapper_req=$(systemctl show input-remapper.service -p Requires --value)
remapper_before=$(systemctl show input-remapper.service -p Before --value)
remapper_conflicts=$(systemctl show input-remapper.service -p Conflicts --value)
remapper_bus=$(systemctl show input-remapper.service -p BusName --value)
[[ $remapper_dd == no ]]
pass "input-remapper DefaultDependencies=no (implicit target edge removed)"
[[ $remapper_to == '1min 30s' ]]
pass "input-remapper Gate 12.7 timeout of 90 s preserved"
check "input-remapper retains startup ordering on dbus, sysinit and basic" contains \
    "$remapper_after" dbus-broker.service dbus.socket sysinit.target basic.target
check "input-remapper still requires dbus and sysinit" contains \
    "$remapper_req" dbus-broker.service dbus.socket sysinit.target
check "input-remapper still stops before shutdown.target" contains "$remapper_before" shutdown.target
check "shutdown.target still queues a stop for input-remapper" contains "$remapper_conflicts" shutdown.target
[[ $remapper_bus == inputremapper.Control && \
    $(systemctl show input-remapper.service -p Type --value) == dbus && \
    $(systemctl show input-remapper.service -p ExecStart --value) == *'/usr/bin/input-remapper-service'* ]]
pass "input-remapper Type=dbus, BusName and ExecStart untouched"

g_after=$(systemctl show graphical.target -p After --value)
g_wants=$(systemctl show graphical.target -p Wants --value)
check "graphical.target no longer waits for input-remapper" lacks "$g_after" input-remapper.service
check "graphical.target still pulls input-remapper into the boot transaction" contains \
    "$g_wants" input-remapper.service
check "Lote 10.2 preserved: graphical.target does not wait for bootc-status" lacks \
    "$g_after" enthroned-bootc-status.service

if [[ -f /usr/lib/systemd/system/fedora-atomic-desktop-appstream-cache-refresh.service ]]; then
    install -D -m 0644 /src/system_files/usr/lib/systemd/system/fedora-atomic-desktop-appstream-cache-refresh.service.d/enthroned-boot-order.conf \
        /usr/lib/systemd/system/fedora-atomic-desktop-appstream-cache-refresh.service.d/enthroned-boot-order.conf
    systemctl add-wants graphical.target fedora-atomic-desktop-appstream-cache-refresh.service
    systemctl daemon-reload
    g_after=$(systemctl show graphical.target -p After --value)
    check "Lote 10.2 preserved: AppStream refresh stays off the graphical wait" lacks \
        "$g_after" fedora-atomic-desktop-appstream-cache-refresh.service
fi

echo
echo "== summary: $passes passed, $fails failed =="
exit "$fails"
