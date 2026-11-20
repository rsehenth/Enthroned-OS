#!/bin/bash
# Gate 12.2: authorization tests for the uupd polkit confinement.
#
# MUST run as root inside a DISPOSABLE container on the pinned Aurora base (it adds
# users, installs dbus-daemon/nodejs and starts polkitd). It needs network for dnf:
#   podman run --rm --network=host -v "$PWD":/src:ro <aurora@sha256:...> \
#       bash /src/scripts/test-polkit-uupd.sh
# Part A asks a REAL polkitd (pkcheck) for subjects without a logind session.
# Part B evaluates the real rule files with scripts/polkit-rules-harness.js for
# subjects that need a session (local/active). Nothing is started or stopped:
# only authorization is asked, never a unit.
# WITHOUT_UUPD_RULE=1 omits the new rule, to reproduce the pre-fix behaviour.
#
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC2034
set -u

SRC="${SRC:-/src}"
RULES_SRC="${SRC}/system_files/usr/share/polkit-1/rules.d"
if [ "$(id -u)" -ne 0 ] || { [ ! -e /run/.containerenv ] && [ ! -e /.dockerenv ]; }; then
	echo "refusing to run: needs root inside a disposable container" >&2
	exit 2
fi

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "PASS  $1"; }
ko() { fail=$((fail + 1)); echo "FAIL  $1"; }

dnf5 -y install dbus-daemon nodejs >/tmp/dnf.log 2>&1 || { tail -5 /tmp/dnf.log; exit 2; }

# Same shipping step as the image: Enthroned rules next to the Aurora ones.
cp "${RULES_SRC}/10-org.enthroned.settings.rules" /usr/share/polkit-1/rules.d/
if [ "${WITHOUT_UUPD_RULE:-0}" != 1 ]; then
	cp "${RULES_SRC}/10-org.enthroned.uupd.rules" /usr/share/polkit-1/rules.d/
fi

echo "== Part A: real polkitd (subjects without a login session)"
groupadd -f empower
# the base can define groups in /usr/lib/group only; useradd -G reads /etc/group
grep -q '^empower:' /etc/group || getent group empower >>/etc/group
useradd -m bob 2>/dev/null
useradd -m -G wheel alice 2>/dev/null
useradd -m -G empower eve || echo "useradd eve failed" >&2
mkdir -p /var/lib/dbus /run/dbus
dbus-uuidgen --ensure
dbus-daemon --system --fork 2>/dev/null
/usr/lib/polkit-1/polkitd --no-debug >/tmp/polkitd.log 2>&1 &
sleep 3

# rc 0 = YES, rc 2 = authentication required, rc 1 = NO
ask() {
	local user="$1" verb="$2" unit="$3" pid rc
	setpriv --reuid="$(id -u "$user")" --regid="$(id -g "$user")" --init-groups sleep 60 &
	pid=$!
	sleep 0.2
	pkcheck -a org.freedesktop.systemd1.manage-units -p "$pid" \
		--detail unit "${unit}" --detail verb "${verb}" >/dev/null 2>&1
	rc=$?
	kill "$pid" 2>/dev/null
	wait "$pid" 2>/dev/null
	echo "$rc"
}
expect_rc() { # label user verb unit want
	local got
	got="$(ask "$2" "$3" "$4")"
	if [ "$got" = "$5" ]; then ok "$1 (rc=${got})"; else ko "$1 (rc=${got}, wanted $5)"; fi
}
for unit in uupd.service uupd-manual.service; do
	for verb in start stop restart kill; do
		expect_rc "no-group user without session: ${verb} ${unit} needs authentication" bob "$verb" "$unit" 2
		expect_rc "wheel user without a login session: ${verb} ${unit} needs authentication" alice "$verb" "$unit" 2
	done
	expect_rc "empower user keeps YES: stop ${unit}" eve stop "$unit" 0
done
expect_rc "baseline: unrelated unit needs authentication" bob start sshd.service 2
expect_rc "baseline: Enthroned unit not granted without a session" alice start enthroned-system-update.service 2

echo "== Part B: rule files evaluated with session attributes"
node "${SRC}/scripts/polkit-rules-harness.js" /etc/polkit-1/rules.d /usr/share/polkit-1/rules.d | tee /tmp/harness.out
hp="$(grep -c '^PASS' /tmp/harness.out)"
hf="$(grep -c -E '^(FAIL|LOAD-ERROR)' /tmp/harness.out)"
pass=$((pass + hp))
fail=$((fail + hf))

echo
echo "polkit uupd tests: ${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
