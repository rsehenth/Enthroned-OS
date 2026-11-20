#!/usr/bin/env bash
# Enthroned OS - Lote 11A evidence collector, to run INSIDE the VM (read-only).
#
# Collects exactly the evidence the H5 left missing for the items that could not
# be closed from source: tuned ordering/duration, /var read-only after an
# unclean shutdown, Discover/PackageKit, the SELinux test label and the
# first-boot Flatpak status. It changes nothing (no services, no mounts, no
# flatpak/bootc operations). Needs sudo only to read the system journal.
#
# Usage: bash stability-audit-vm.sh [output-file]   (default ~/stability-audit-11a.txt)
# Review the file before sharing (hostnames, process lists).
# SPDX-License-Identifier: Apache-2.0
set -uo pipefail
OUT="${1:-${HOME}/stability-audit-11a.txt}"
J=(journalctl --no-pager)
[ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && J=(sudo journalctl --no-pager)

sec() { printf '\n##### %s\n' "$*"; }
{
	printf '=== Enthroned OS stability audit (Lote 11A) %s ===\n' "$(date -Is)"
	printf 'virt=%s kernel=%s\n' "$(systemd-detect-virt 2>/dev/null)" "$(uname -r)"

	sec "tuned: unit ordering as systemd resolved it (After/Before/Requires/Wants)"
	systemctl show tuned.service tuned-ppd.service -p After -p Before -p Requires -p Wants -p ActiveEnterTimestamp -p ExecMainStartTimestamp 2>&1
	sec "tuned: effective unit + drop-ins"
	systemctl cat tuned.service 2>&1
	sec "tuned: critical chain and blame (this boot)"
	systemd-analyze critical-chain tuned.service 2>&1
	systemd-analyze blame 2>&1 | head -15
	sec "tuned: active profile and daemon log"
	tuned-adm active 2>&1
	"${J[@]}" -b -u tuned.service -u tuned-ppd.service 2>&1 | tail -40

	sec "/var: mount options now (look for 'ro')"
	findmnt -no TARGET,SOURCE,FSTYPE,OPTIONS /var /sysroot / 2>&1
	sec "/var: remount / readonly traces in the previous and current boots"
	for b in -1 0; do
		printf -- '--- boot %s\n' "${b}"
		"${J[@]}" -b "${b}" -k 2>&1 | grep -iE 'btrfs|remount|read-only|readonly|EXT4-fs|errors=' | tail -25
		"${J[@]}" -b "${b}" 2>&1 | grep -iE 'ostree-remount|sysroot|finalize-staged|systemd-remount-fs|var\.mount|Remounting' | tail -25
	done
	sec "/var: ostree/bootc remount units"
	systemctl status ostree-remount.service ostree-finalize-staged.service 2>&1 | head -40
	sec "/var: previous boot ended cleanly? (last lines of boot -1)"
	"${J[@]}" -b -1 -n 15 2>&1

	sec "Discover/PackageKit: installed RPM backends (expected: only plasma-discover-flatpak)"
	rpm -qa 'plasma-discover*' 'PackageKit*' 2>&1 | sort
	systemctl is-enabled packagekit.service packagekit-offline-update.service 2>&1
	sec "Discover/PackageKit: recent journal"
	"${J[@]}" -b --since=-1h 2>&1 | grep -iE 'packagekit|plasma-discover|discover' | tail -40
	sec "Discover: legacy offline-update config"
	ls -l /etc/xdg/discoverrc /var/lib/PackageKit/offline-update-action 2>&1

	sec "SELinux: test label occurrences (shipped config and policy store)"
	getenforce 2>&1
	sudo grep -rIl invalid_bootcinstall_testlabel_t /etc /usr/etc /usr/lib/systemd 2>/dev/null || echo "none in config"
	sudo ausearch -m avc -ts boot 2>/dev/null | grep -c invalid_bootcinstall_testlabel_t || true
	"${J[@]}" -b 2>&1 | grep -c invalid_bootcinstall_testlabel_t || true

	sec "firstboot flatpaks: status, marker, unit result"
	cat /var/lib/enthroned-os/firstboot-flatpaks.status /var/lib/enthroned-os/firstboot-flatpaks.done 2>&1
	systemctl show enthroned-firstboot-flatpaks.service -p Result -p ExecMainStatus -p ActiveState 2>&1
	"${J[@]}" -b -u enthroned-firstboot-flatpaks.service 2>&1 | tail -30
	flatpak list --system --app --columns=application,origin 2>&1
} >"${OUT}" 2>&1
printf 'Wrote %s\n' "${OUT}"
