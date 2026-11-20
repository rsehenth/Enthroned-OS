#!/usr/bin/env bash
set -euo pipefail

vendor_unit=$1
override_unit=$2

# Reconstruct the RPM fragment by removing our header and restoring one edge.
if ! grep -Fxq 'After=systemd-sysctl.service dbus.service polkit.service' "$override_unit" \
    || ! diff -u -- "$vendor_unit" <(
        sed -n -e '/^After=systemd-sysctl\.service dbus\.service polkit\.service$/s/ dbus/ network.target dbus/' \
            -e '/^\[Unit\]$/,$p' "$override_unit"
    ); then
    echo "TuneD unit drifted from the pinned baseline; re-review $override_unit (Gate 16)" >&2
    exit 1
fi
