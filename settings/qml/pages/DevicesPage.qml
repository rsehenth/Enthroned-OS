/*
 * Enthroned Settings - Bluetooth and devices page (Lote 4).
 * Entry points to REAL native KDE device modules (kcmshell6). Availability is
 * detected at runtime; unavailable modules stay disabled with an honest note
 * (or are hidden when they only exist with optional packages).
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("Bluetooth & devices")

    readonly property var modules: [
        { title: i18n("Bluetooth"), subtitle: i18n("Pair and manage Bluetooth devices."),
          icon: "preferences-system-bluetooth", ids: ["kcm_bluetooth"] },
        { title: i18n("Mouse"), subtitle: i18n("Speed, buttons and scrolling."),
          icon: "input-mouse", ids: ["kcm_mouse"] },
        { title: i18n("Touchpad"), subtitle: i18n("Tapping, scrolling and gestures."),
          icon: "input-touchpad", ids: ["kcm_touchpad"] },
        { title: i18n("Keyboard"), subtitle: i18n("Layouts, key repeat and shortcuts."),
          icon: "input-keyboard", ids: ["kcm_keyboard"] },
        { title: i18n("Printers"), subtitle: i18n("Printers and print queues."),
          icon: "printer", ids: ["kcm_printer_manager", "printers"] },
        { title: i18n("Game controllers"), subtitle: i18n("Gamepads and joysticks."),
          icon: "input-gaming", ids: ["kcm_gamecontroller"] },
        { title: i18n("Drawing tablet"), subtitle: i18n("Graphics tablets."),
          icon: "input-tablet", ids: ["kcm_tablet", "kcm_wacomtablet"], optional: true },
        { title: i18n("Removable media"), subtitle: i18n("Automatic mounting of USB drives and disks."),
          icon: "drive-removable-media", ids: ["kcm_device_automounter"], optional: true },
        { title: i18n("KDE Connect"), subtitle: i18n("Integration with your phone."),
          icon: "kdeconnect", ids: ["kcm_kdeconnect"], optional: true }
    ]

    Component.onCompleted: kcm.refreshAvailable()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        ModuleList { modules: root.modules }

        EmptyState {
            Layout.fillWidth: true
            visible: !kcm.toolPresent
            icon: "input-keyboard"
            title: i18n("No module can be opened in this environment")
            note: i18n("This page only opens native KDE modules; nothing is simulated.")
        }
    }
}
