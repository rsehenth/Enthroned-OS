#!/usr/bin/env bash
# Apply the closed-channel policy to the image filesystem without contacting PID 1.
set -euo pipefail

timers=(uupd.timer enthroned-system-update.timer
    bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer)

chmod 0644 /usr/lib/systemd/system-preset/20-enthroned-os-updates.preset
# Remove inherited enablement links before masking so boot does not queue them.
systemctl --root=/ disable "${timers[@]}"
# A mask also blocks activation by a dependency or an authorized StartUnit.
systemctl --root=/ mask "${timers[@]}" uupd.service uupd-manual.service \
    enthroned-system-update.service bootc-fetch-apply-updates.service \
    rpm-ostreed-automatic.service
