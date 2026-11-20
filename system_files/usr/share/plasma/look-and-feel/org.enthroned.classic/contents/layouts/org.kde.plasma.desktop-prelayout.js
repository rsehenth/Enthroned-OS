// Restore the desktop defaults before Plasma creates containments for a reset layout.
// SPDX-License-Identifier: Apache-2.0
var contextMenuModule = "/qt6/plugins/plasma/containmentactions/org.enthroned.contextmenu.so"
if (fileExists("/usr/lib64" + contextMenuModule) || fileExists("/usr/lib" + contextMenuModule)) {
    var actions = new ConfigFile("plasma-org.kde.plasma.desktop-appletsrc", "ActionPlugins")
    if (actions.groupList.indexOf("0") === -1) {
        var desktopActions = new ConfigFile(actions, "0")
        desktopActions.writeEntry("RightButton;NoModifier", "org.enthroned.contextmenu")
        desktopActions.writeEntry("MiddleButton;NoModifier", "org.kde.paste")
    }
}
