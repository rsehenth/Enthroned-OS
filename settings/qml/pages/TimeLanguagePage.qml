/*
 * Enthroned Settings - Time and language page (Lote 4).
 * Current time zone and locale read from the running system, plus the native
 * KDE modules that change them.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("Time & language")

    readonly property var modules: [
        { title: i18n("Date and time"), subtitle: i18n("Time zone and automatic clock adjustment."),
          icon: "preferences-system-time", ids: ["kcm_clock"] },
        { title: i18n("Language and region"), subtitle: i18n("System language and date, number and currency formats."),
          icon: "preferences-desktop-locale", ids: ["kcm_regionandlang"] },
        { title: i18n("Keyboard"), subtitle: i18n("Keyboard layouts and shortcuts."),
          icon: "input-keyboard", ids: ["kcm_keyboard"] }
    ]

    Component.onCompleted: kcm.refreshAvailable()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                InfoRow { label: i18n("Time zone"); value: deviceInfo.timeZone }
                InfoRow { label: i18n("Language and region (locale)"); value: deviceInfo.localeName }
            }
        }

        ModuleList { modules: root.modules }
    }
}
