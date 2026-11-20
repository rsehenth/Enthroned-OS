#!/usr/bin/env bash
# Lote 9.2 regression harness for the shipped desktop helpers.
# Runs the REAL helper scripts with stubbed kreadconfig6/kwriteconfig6/
# xdg-user-dir/gio and a temporary HOME:
#   - H4-008: first-login migration seeds defaults once, only for ABSENT
#     keys; explicit empty values and later removals survive; heal still
#     swaps a stale Enthroned binding for the stock plugin.
#   - H4-009: a disabled XDG Desktop never gets files nor a $HOME/Desktop
#     fallback; missing configuration still falls back; user files win.
#   - H4-002 (helper side): malformed storage ids are rejected untouched.
#
# Run: bash scripts/test-desktop-helpers.sh   (WSL/Linux; no root, no Plasma)
# SPDX-License-Identifier: Apache-2.0
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBEXEC="${ROOT}/system_files/usr/libexec/enthroned-desktop-actions"
BIN="${ROOT}/system_files/usr/bin/enthroned-desktop-shortcut"
[[ -f "${LIBEXEC}" ]] || { echo "desktop-actions helper not found"; exit 1; }
[[ -f "${BIN}" ]] || { echo "desktop-shortcut helper not found"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
assert_eq() { # desc expected actual
	if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected [$2], got [$3])"; fi
}
assert_absent() {
	if [[ ! -e "$1" ]]; then pass "$2"; else fail "$2 (exists: $1)"; fi
}

# ---- stubs -----------------------------------------------------------------
STUBS="${WORK}/stubs"
mkdir -p "${STUBS}"

cat > "${STUBS}/kreadconfig6" <<'STUB'
#!/usr/bin/env bash
file=""; groups=(); key=""; default=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--file) file="$2"; shift 2 ;;
	--group) groups+=("$2"); shift 2 ;;
	--key) key="$2"; shift 2 ;;
	--default) default="$2"; shift 2 ;;
	*) shift ;;
	esac
done
prefix="${file}|"
if [[ ${#groups[@]} -gt 0 ]]; then
	oldIFS="${IFS}"; IFS="/"
	prefix+="${groups[*]}/"
	IFS="${oldIFS}"
fi
prefix+="${key}"
if [[ -f "${KCFG_STUB_STATE}" ]]; then
	line="$(grep -F -- "${prefix}=" "${KCFG_STUB_STATE}" | tail -n 1)"
	if [[ -n "${line}" ]]; then
		printf '%s' "${line#*=}"
		exit 0
	fi
fi
printf '%s' "${default}"
STUB

cat > "${STUBS}/kwriteconfig6" <<'STUB'
#!/usr/bin/env bash
file=""; groups=(); key=""; value=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--file) file="$2"; shift 2 ;;
	--group) groups+=("$2"); shift 2 ;;
	--key) key="$2"; shift 2 ;;
	*) value="$1"; shift ;;
	esac
done
prefix="${file}|"
if [[ ${#groups[@]} -gt 0 ]]; then
	oldIFS="${IFS}"; IFS="/"
	prefix+="${groups[*]}/"
	IFS="${oldIFS}"
fi
prefix+="${key}"
touch "${KCFG_STUB_STATE}"
tmp="${KCFG_STUB_STATE}.tmp"
grep -Fv -- "${prefix}=" "${KCFG_STUB_STATE}" > "${tmp}" || true
printf '%s=%s\n' "${prefix}" "${value}" >> "${tmp}"
mv "${tmp}" "${KCFG_STUB_STATE}"
STUB

cat > "${STUBS}/xdg-user-dir" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${XDG_USER_DIR_STUB_VALUE}"
STUB

cat > "${STUBS}/gio" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

chmod 0755 "${STUBS}"/*

STATE="${WORK}/kcfg.state"
: > "${STATE}"
export KCFG_STUB_STATE="${STATE}"
PATH="${STUBS}:${PATH}"
export PATH

FILE=plasma-org.kde.plasma.desktop-appletsrc
RB="${FILE}|ActionPlugins/0/RightButton;NoModifier"
MB="${FILE}|ActionPlugins/0/MiddleButton;NoModifier"
SEP1="${FILE}|ActionPlugins/0/RightButton;NoModifier/_sep1"
kcfg_get() { # <prefix>
	if [[ -f "${STATE}" ]]; then
		local line
		line="$(grep -F -- "$1=" "${STATE}" | tail -n 1)"
		[[ -n "${line}" ]] && printf '%s' "${line#*=}" && return 0
	fi
	return 1
}

# ---- H4-008: desktop-actions -----------------------------------------------
# NOTE: plugin_installed() checks real system dirs, so on this host the
# Enthroned plugin counts as ABSENT (tests cover the absent-plugin paths and
# the heal; seeding with the plugin present needs the image).

H1="${WORK}/home1"
mkdir -p "${H1}/.config"
(
	export HOME="${H1}" XDG_CONFIG_HOME="${H1}/.config"
	"${LIBEXEC}" >/dev/null 2>&1
)
assert_eq "8.1 migration seeds the middle-click default" "org.kde.paste" "$(kcfg_get "${MB}")"
assert_eq "8.1 migration closes the gap separators" "false" "$(kcfg_get "${SEP1}")"
if kcfg_get "${RB}" >/dev/null 2>&1; then
	fail "8.1 right button not seeded while the plugin is absent"
else
	pass "8.1 right button not seeded while the plugin is absent"
fi
[[ -f "${H1}/.config/enthroned/desktop-actions.done" ]] && pass "8.1 migration marker written" \
	|| fail "8.1 migration marker written"

# User REMOVES the middle-click binding and a separator after the migration
# (explicit empty value): the next logins must keep the removal (the audited
# bug re-wrote org.kde.paste on every login).
grep -Fv -- "${MB}=" "${STATE}" > "${STATE}.t" && mv "${STATE}.t" "${STATE}"
printf '%s=\n' "${MB}" >> "${STATE}"
grep -Fv -- "${SEP1}=" "${STATE}" > "${STATE}.t" && mv "${STATE}.t" "${STATE}"
printf '%s=\n' "${SEP1}" >> "${STATE}"
(
	export HOME="${H1}" XDG_CONFIG_HOME="${H1}/.config"
	"${LIBEXEC}" >/dev/null 2>&1
	"${LIBEXEC}" >/dev/null 2>&1
)
assert_eq "8.2 explicitly emptied middle-click stays empty" "" "$(kcfg_get "${MB}")"
assert_eq "8.2 removed separator stays removed" "" "$(kcfg_get "${SEP1}")"

# A binding deleted entirely is NOT re-seeded after the migration.
grep -Fv -- "${MB}=" "${STATE}" > "${STATE}.t" && mv "${STATE}.t" "${STATE}"
(
	export HOME="${H1}" XDG_CONFIG_HOME="${H1}/.config"
	"${LIBEXEC}" >/dev/null 2>&1
)
if kcfg_get "${MB}" >/dev/null 2>&1; then
	fail "8.6 deleted binding is not re-seeded after migration"
else
	pass "8.6 deleted binding is not re-seeded after migration"
fi

# First login of a user who ALREADY configured an explicit empty value.
H2="${WORK}/home2"
mkdir -p "${H2}/.config"
printf '%s=\n' "${MB}" >> "${STATE}"
(
	export HOME="${H2}" XDG_CONFIG_HOME="${H2}/.config"
	"${LIBEXEC}" >/dev/null 2>&1
)
assert_eq "8.5 pre-existing empty value is respected on first login" "" "$(kcfg_get "${MB}")"

# Heal: stale Enthroned binding without the plugin binary goes back to stock;
# a custom binding is never touched.
printf '%s=%s\n' "${RB}" "org.enthroned.contextmenu" >> "${STATE}"
(
	export HOME="${H1}" XDG_CONFIG_HOME="${H1}/.config"
	"${LIBEXEC}" >/dev/null 2>&1
)
assert_eq "8.4 stale Enthroned binding heals to the stock menu" "org.kde.contextmenu" "$(kcfg_get "${RB}")"
printf '%s=%s\n' "${RB}" "custom.menu" >> "${STATE}"
(
	export HOME="${H1}" XDG_CONFIG_HOME="${H1}/.config"
	"${LIBEXEC}" >/dev/null 2>&1
)
assert_eq "8.3 custom binding is never rewritten" "custom.menu" "$(kcfg_get "${RB}")"

# ---- R93-03: migration marker only after CONFIRMED writes -------------------
# A failing kwriteconfig6 must NOT create the migration marker: the next login
# has to retry the missing keys. Login is still never blocked (exit 0), the
# existing configuration is preserved and an explicitly empty value is never
# reintroduced by the retry.

FAILW="${WORK}/failwrite"
mkdir -p "${FAILW}"
printf '#!/usr/bin/env bash\nexit 1\n' > "${FAILW}/kwriteconfig6"
chmod 0755 "${FAILW}/kwriteconfig6"

H4="${WORK}/home4"
mkdir -p "${H4}/.config"
# Fresh first-login state: the earlier cases left explicit empty/removal
# choices in the shared stub state; the R93-03 cases need absent keys so the
# required writes are actually attempted.
: > "${STATE}"
rc=0
(
	export HOME="${H4}" XDG_CONFIG_HOME="${H4}/.config"
	PATH="${FAILW}:${STUBS}:${PATH}"
	"${LIBEXEC}" >/dev/null 2>&1
) || rc=$?
assert_eq "10.1 all writes failing still exits 0 (login never blocked)" "0" "${rc}"
assert_absent "${H4}/.config/enthroned/desktop-actions.done" \
	"10.1 marker NOT created when the required writes fail"
assert_absent "${H4}/.config/enthroned" \
	"10.1 no migration state directory is left behind on failure"
if kcfg_get "${MB}" >/dev/null 2>&1; then
	fail "10.1 failed migration writes nothing"
else
	pass "10.1 failed migration writes nothing"
fi

# The next login retries the migration with a working kwriteconfig6 and
# completes it exactly once.
(
	export HOME="${H4}" XDG_CONFIG_HOME="${H4}/.config"
	"${LIBEXEC}" >/dev/null 2>&1
)
assert_eq "10.2 retry after failed writes seeds the middle-click default" \
	"org.kde.paste" "$(kcfg_get "${MB}")"
assert_eq "10.2 retry after failed writes closes the separators" "false" "$(kcfg_get "${SEP1}")"
[[ -f "${H4}/.config/enthroned/desktop-actions.done" ]] \
	&& pass "10.2 retry creates the marker after confirmed writes" \
	|| fail "10.2 retry creates the marker after confirmed writes"

# An explicitly empty user choice is preserved even when the first (failed)
# migration ran before it - the retry must never reintroduce the default.
H5="${WORK}/home5"
mkdir -p "${H5}/.config"
: > "${STATE}"
printf '%s=\n' "${MB}" >> "${STATE}"
rc=0
(
	export HOME="${H5}" XDG_CONFIG_HOME="${H5}/.config"
	PATH="${FAILW}:${STUBS}:${PATH}"
	"${LIBEXEC}" >/dev/null 2>&1
) || rc=$?
assert_eq "10.3 failed migration over an explicit empty still exits 0" "0" "${rc}"
(
	export HOME="${H5}" XDG_CONFIG_HOME="${H5}/.config"
	"${LIBEXEC}" >/dev/null 2>&1
)
assert_eq "10.3 explicit empty value is not reintroduced by the retry" "" "$(kcfg_get "${MB}")"
[[ -f "${H5}/.config/enthroned/desktop-actions.done" ]] \
	&& pass "10.3 retry with an explicit empty still completes the migration" \
	|| fail "10.3 retry with an explicit empty still completes the migration"

# ---- H4-009 + H4-002: desktop-shortcut -------------------------------------
mk_app() { # home
	mkdir -p "$1/.config" "$1/.local/share/applications"
	printf 'Type=Application\nName=Test App\nExec=true %%U\n' \
		> "$1/.local/share/applications/testapp.desktop"
}

H3="${WORK}/home3"
mk_app "${H3}"

# 9.1 Desktop disabled (configured as $HOME): exit 0, nothing written.
XDG_USER_DIR_STUB_VALUE="${H3}" HOME="${H3}" XDG_CONFIG_HOME="${H3}/.config" \
	"${BIN}" testapp.desktop >/dev/null 2>&1
code=$?
assert_eq "9.1 disabled Desktop exits 0" "0" "${code}"
assert_absent "${H3}/Desktop" "9.1 disabled Desktop creates no \$HOME/Desktop"

# 9.2 xdg-user-dir unavailable but user-dirs.dirs disables the Desktop.
printf 'XDG_DESKTOP_DIR="$HOME"\n' > "${H3}/.config/user-dirs.dirs"
XDG_USER_DIR_STUB_VALUE="" HOME="${H3}" XDG_CONFIG_HOME="${H3}/.config" \
	"${BIN}" testapp.desktop >/dev/null 2>&1
code=$?
assert_eq "9.2 disabled-by-config Desktop exits 0" "0" "${code}"
assert_absent "${H3}/Desktop" "9.2 disabled-by-config Desktop creates no fallback"

# 9.3 No user-dirs configuration at all: the legacy fallback still works.
rm -f "${H3}/.config/user-dirs.dirs"
XDG_USER_DIR_STUB_VALUE="" HOME="${H3}" XDG_CONFIG_HOME="${H3}/.config" \
	"${BIN}" testapp.desktop >/dev/null 2>&1
code=$?
assert_eq "9.3 missing configuration falls back to \$HOME/Desktop" "0" "${code}"
[[ -f "${H3}/Desktop/testapp.desktop" ]] && pass "9.3 shortcut created in the fallback dir" \
	|| fail "9.3 shortcut created in the fallback dir"

# 9.4 Localized Desktop dir from the real configuration.
printf 'XDG_DESKTOP_DIR="$HOME/Area de Trabalho"\n' > "${H3}/.config/user-dirs.dirs"
rm -f "${H3}/Desktop/testapp.desktop"
XDG_USER_DIR_STUB_VALUE="${H3}/Area de Trabalho" HOME="${H3}" XDG_CONFIG_HOME="${H3}/.config" \
	"${BIN}" testapp.desktop >/dev/null 2>&1
[[ -f "${H3}/Area de Trabalho/testapp.desktop" ]] && pass "9.4 localized Desktop dir is used" \
	|| fail "9.4 localized Desktop dir is used"

# 9.5 The user's own file is never overwritten.
printf 'USER FILE\n' > "${H3}/Area de Trabalho/testapp.desktop"
XDG_USER_DIR_STUB_VALUE="${H3}/Area de Trabalho" HOME="${H3}" XDG_CONFIG_HOME="${H3}/.config" \
	"${BIN}" testapp.desktop >/dev/null 2>&1
code=$?
assert_eq "9.5 existing personal file exits 0 untouched" "0" "${code}"
assert_eq "9.5 existing personal file content preserved" "USER FILE" "$(cat "${H3}/Area de Trabalho/testapp.desktop")"

# 9.6 Hidden entries are refused.
printf 'Type=Application\nName=Hidden\nExec=true\nNoDisplay=true\n' \
	> "${H3}/.local/share/applications/hidden.desktop"
XDG_USER_DIR_STUB_VALUE="${H3}/Area de Trabalho" HOME="${H3}" XDG_CONFIG_HOME="${H3}/.config" \
	"${BIN}" hidden.desktop >/dev/null 2>&1
assert_eq "9.6 hidden entry is refused" "1" "$?"

# 9.7 H4-002 (helper side): malformed ids are rejected before any lookup.
# The command-substitution id is passed as a LITERAL string (like it would
# arrive after shell interpolation) and must be rejected without executing.
shell_id='$('"${WORK}"'/shell-boundary).desktop'
for bad in "a b.desktop" "a;b.desktop" "a'b.desktop" "../evil.desktop" "a..b.desktop" \
	".hidden.desktop" "app" "${shell_id}"; do
	XDG_USER_DIR_STUB_VALUE="${H3}/Area de Trabalho" HOME="${H3}" XDG_CONFIG_HOME="${H3}/.config" \
		"${BIN}" "${bad}" >/dev/null 2>&1
	assert_eq "9.7 rejects malformed id: ${bad}" "1" "$?"
done
assert_absent "${WORK}/shell-boundary" "9.7 no shell side effect from a malformed id"

# 9.8 --if-enabled: default preference (true) proceeds; disabled preference
# (checked through the stubbed kreadconfig6) exits 0 without writing.
printf 'enthroned-os/preferences.conf|General/CreateDesktopShortcuts=false\n' >> "${STATE}"
XDG_USER_DIR_STUB_VALUE="${H3}/Area de Trabalho" HOME="${H3}" XDG_CONFIG_HOME="${H3}/.config" \
	"${BIN}" --if-enabled testapp.desktop >/dev/null 2>&1
assert_eq "9.8 --if-enabled respects the disabled preference" "0" "$?"

if [[ ${failures} -gt 0 ]]; then
	echo "FAILED: ${failures} case(s)"
	exit 1
fi
echo "ALL CHECKS PASSED"
