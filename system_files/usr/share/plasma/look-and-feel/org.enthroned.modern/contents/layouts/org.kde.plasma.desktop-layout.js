/*
 * Enthroned Modern default layout (KDE Plasma 6.x desktop scripting API).
 * Structure mirrors the official
 * layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js and
 * lookandfeel/org.kde.breeze/contents/layouts/org.kde.plasma.desktop-layout.js
 * (plasma-desktop / plasma-workspace, Plasma 6.6):
 * a bottom floating panel whose start-menu/taskbar cluster is centered
 * (Windows 11-inspired) with tray and clock kept on the right edge.
 *
 * Start menu: the Enthroned Launcher plasmoid (own menu on the native kicker
 * models). If the plasmoid cannot be instantiated the layout falls back to
 * the stock org.kde.plasma.kickoff widget with the Enthroned icon.
 *
 * Other widgets are stock Plasma applets: org.kde.plasma.icontasks
 * (icons-only task manager), org.kde.plasma.panelspacer,
 * org.kde.plasma.systemtray and org.kde.plasma.digitalclock.
 * The desktop keeps the Plasma 6 default Folder View (desktop icons) and
 * gains a stock Trash widget (org.kde.plasma.trash), Windows 11 style.
 *
 * Panel properties (floating, hiding) are part of the desktop scripting API
 * verified in plasma-workspace shell/scripting/panel.cpp (Plasma 6.6).
 * Containment addWidget is verified in shell/scripting/containment.cpp.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

var panel = new Panel
panel.location = "bottom"
// F4+: 48px (was 44) gives the floating dock more presence and breathing room
// around the centered cluster; still >= 44px for comfortable targets.
panel.height = 48
panel.floating = true
panel.hiding = "none"

// Left spacer + centered cluster + right spacer: the menu and taskbar sit in
// the middle of the panel while tray/clock stay at the right edge.
panel.addWidget("org.kde.plasma.panelspacer")

// Start menu: Enthroned Launcher with the Meta key global shortcut; stock
// kickoff only as a safe fallback if the custom applet fails to load.
var menu = null
try {
    menu = panel.addWidget("org.enthroned.launcher")
    if (menu && !(menu instanceof Error)) {
        // Lote 13: Modern start button = the Enthroned throne symbol
        // (installed theme icon, no absolute paths). Written on every layout
        // reset, so switching Classic <-> Modern swaps the icon with the panel.
        menu.currentConfigGroup = ["General"]
        menu.writeConfig("icon", "org.enthroned.launcher-modern")
        menu.currentConfigGroup = ["Shortcuts"]
        menu.writeConfig("global", "Meta")
    } else {
        menu = null
    }
} catch (e) {
    menu = null
}
if (menu === null) {
    var kickoff = panel.addWidget("org.kde.plasma.kickoff")
    kickoff.currentConfigGroup = ["General"]
    kickoff.writeConfig("icon", "org.enthroned.launcher-modern")
    kickoff.writeConfig("favorites", "preferred://browser,org.kde.dolphin.desktop,preferred://terminal,org.enthroned.settings.desktop,org.kde.discover.desktop")
    kickoff.currentConfigGroup = ["Shortcuts"]
    kickoff.writeConfig("global", "Meta")
}

// Taskbar: pinned file manager and browser, running windows grouped.
var tasks = panel.addWidget("org.kde.plasma.icontasks")
tasks.currentConfigGroup = ["General"]
tasks.writeConfig("launchers", "preferred://browser,preferred://filemanager")

panel.addWidget("org.kde.plasma.panelspacer")

panel.addWidget("org.kde.plasma.systemtray")
var clock = panel.addWidget("org.kde.plasma.digitalclock")
// Lote 14: digitalclock reads showDate from the "Appearance" group (the same
// group its own update scripts use); the old "General" write was ignored and
// the stock date showed up. Only this one key is set, so the regional
// date/time format and any personal clock settings stay untouched.
clock.currentConfigGroup = ["Appearance"]
clock.writeConfig("showDate", false)

// Desktop wallpaper comes from the look-and-feel defaults ([Wallpaper]
// Image=EnthronedVigilia); ensure the image wallpaper plugin is active on
// every screen and add the stock Trash widget (user-removable).
//
// Lote 6: desktop icon behavior made explicit (native Folder View keys):
// sortMode 0 = unsorted, which enables the Positioner and keeps FREE, user
// chosen icon positions; locked = false so selecting with a left click,
// dragging icons and double-clicking to open work without entering any edit
// mode. Positions persist in the containment configuration.
var desktopsArray = desktopsForActivity(currentActivity())
for (var j = 0; j < desktopsArray.length; j++) {
    var desktop = desktopsArray[j]
    desktop.wallpaperPlugin = "org.kde.image"
    desktop.currentConfigGroup = ["General"]
    desktop.writeConfig("locked", false)
    desktop.writeConfig("sortMode", 0)
    desktop.writeConfig("alignment", 0)
    // Stock Trash widget that cannot be removed or reconfigured: the
    // scripting Widget.locked property maps to the official applet
    // immutability (UserImmutable), which hides the "Remove" and
    // "Configure" entries in the widget's context menu while the widget
    // itself (Empty Trash, Open) keeps working.
    var trash = desktop.addWidget("org.kde.plasma.trash")
    if (trash && !(trash instanceof Error)) {
        trash.locked = true
    }
}
