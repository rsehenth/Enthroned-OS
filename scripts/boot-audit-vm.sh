#!/usr/bin/env bash
# Enthroned OS - Lote 9 boot audit, to run INSIDE the VM (read-only).
#
# Purpose: single-script evidence collection for the slow-boot audit. It never
# changes services, configuration or files outside its output file. Run it as
# your normal user (enthroned); it uses sudo only to read the system journal
# (kernel + global errors) and will ask for your password once.
#
# Usage (in the VM, any session):
#   bash boot-audit-vm.sh            # output: ~/boot-audit-lote9.txt
#   bash boot-audit-vm.sh /tmp/x.txt # custom output path
#
# Run it twice for comparison: once right after the OOBE first boot and once
# after a normal reboot (2nd boot), then keep both files as evidence.
# The file may contain hostnames/process lists - review before sharing.

set -uo pipefail

OUT="${1:-${HOME}/boot-audit-lote9.txt}"

if [ "$(id -u)" -eq 0 ]; then
	J=(journalctl)
elif command -v sudo >/dev/null 2>&1; then
	J=(sudo journalctl)
else
	J=(journalctl)
	printf 'NOTE: sudo not found; system/kernel journal sections will show only your user journal.\n'
fi

# Keep going on individual command failures (read-only collection, not tests).
{
	printf '=== Enthroned OS boot audit (Lote 9) ===\n'
	printf 'date: %s\n' "$(date -Is 2>/dev/null || date)"
	printf 'boot id: %s\n' "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
	printf 'uptime: %s\n' "$(uptime 2>/dev/null)"
	printf 'virt: %s\n' "$(systemd-detect-virt 2>/dev/null || echo unknown)"
	printf 'kernel: %s\n' "$(uname -r)"
	if pgrep -a plasma-setup >/dev/null 2>&1; then
		printf 'stage: FIRST BOOT (plasma-setup OOBE running)\n'
	else
		printf 'stage: regular session (plasma-setup not running)\n'
	fi

	printf '\n--- [1] systemd-analyze (kernel + userspace + graphical) ---\n'
	systemd-analyze --no-pager 2>&1

	printf '\n--- [2] systemd-analyze blame (top 30) ---\n'
	systemd-analyze --no-pager blame 2>/dev/null | head -n 30

	printf '\n--- [2b] boot-gating candidates in blame ---\n'
	systemd-analyze --no-pager blame 2>/dev/null \
		| grep -iE 'ldconfig|wait-online|plymouth|NetworkManager|fsck|flatpak|enthroned|uupd' \
		|| echo 'none of the known candidates appear in blame'

	printf '\n--- [3] critical-chain (default) ---\n'
	systemd-analyze --no-pager critical-chain 2>&1

	printf '\n--- [4] critical-chain graphical.target ---\n'
	systemd-analyze --no-pager critical-chain graphical.target 2>&1

	printf '\n--- [5] display-manager ---\n'
	systemctl --no-pager status display-manager.service 2>&1 | head -n 15

	printf '\n--- [6] failed units (system) ---\n'
	systemctl --no-pager --failed 2>&1

	printf '\n--- [7] failed units (user) ---\n'
	systemctl --user --no-pager --failed 2>&1

	printf '\n--- [8] journal errors of this boot (system) ---\n'
	"${J[@]}" -b --no-pager -q -p err 2>&1 | tail -n 200

	printf '\n--- [9] journal warnings of this boot (system) ---\n'
	"${J[@]}" -b --no-pager -q -p warning 2>&1 | tail -n 200

	printf '\n--- [10] kernel messages of this boot ---\n'
	"${J[@]}" -b --no-pager -q -k 2>&1 | tail -n 200

	printf '\n--- [11] user journal errors of this boot ---\n'
	journalctl --user -b --no-pager -q -p err 2>&1 | tail -n 200

	printf '\n--- [12] Enthroned units (timers + status) ---\n'
	systemctl --no-pager list-timers --all 2>&1 | grep -iE 'NEXT|enthroned|uupd' || true
	systemctl --no-pager status enthroned-firstboot-flatpaks.service \
		enthroned-firstboot-flatpaks.timer enthroned-update-check.service 2>&1 | head -n 60
	systemctl --user --no-pager status enthroned-desktop-actions.service 2>&1 | head -n 15

	printf '\n--- [13] graphical renderer (software rendering proof) ---\n'
	qdbus=()
	if command -v qdbus6 >/dev/null 2>&1; then
		qdbus=(qdbus6)
	elif command -v qdbus-qt6 >/dev/null 2>&1; then
		qdbus=(qdbus-qt6)
	fi
	if [ "${#qdbus[@]}" -gt 0 ]; then
		"${qdbus[@]}" org.kde.KWin /KWin org.kde.KWin.supportInformation 2>/dev/null \
			| grep -iE 'compositing|opengl|renderer|driver|vendor|llvmpipe|software|platform' | head -n 40
	else
		echo 'qdbus not available in PATH'
	fi
} >"$OUT" 2>&1

printf 'Boot audit saved in: %s\n' "$OUT"
printf 'Run it again after a normal reboot (2nd boot) and keep both files.\n'
printf 'Review the file before sharing it.\n'
