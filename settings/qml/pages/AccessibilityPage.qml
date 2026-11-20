/*
 * Enthroned Settings - Accessibility page (Lote 4).
 * Entry points to the native KDE accessibility modules and to the Orca screen
 * reader when it is installed. Nothing here changes settings by itself.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("Accessibility")

    readonly property var modules: [
        { title: i18n("Accessibility"), subtitle: i18n("Sound alerts, sticky keys, keyboard and screen reader."),
          icon: "preferences-desktop-accessibility", ids: ["kcm_access"] },
        { title: i18n("Fonts and text size"), subtitle: i18n("System font size and type."),
          icon: "preferences-desktop-font", ids: ["kcm_fonts"] },
        { title: i18n("Colors and contrast"), subtitle: i18n("Color scheme, including higher-contrast options."),
          icon: "preferences-desktop-color", ids: ["kcm_colors"] },
        { title: i18n("Mouse cursor"), subtitle: i18n("Cursor theme and size."),
          icon: "input-mouse", ids: ["kcm_cursortheme"] },
        { title: i18n("Magnifier and zoom"), subtitle: i18n("Screen magnification effects, in Desktop effects."),
          icon: "zoom-in", ids: ["kcm_kwin_effects"] }
    ]

    Component.onCompleted: kcm.refreshAvailable()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        ModuleList { modules: root.modules }

        Kirigami.AbstractCard {
            id: orcaCard
            Layout.fillWidth: true
            readonly property bool available: kcm.hasExecutable("orca")

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    source: "orca"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: i18n("Screen reader (Orca)")
                        font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: available
                            ? i18n("Starts the Orca screen reader.")
                            : i18n("Orca is not installed on this system.")
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
                QQC2.Button {
                    text: i18n("Open")
                    icon.name: "window-open"
                    enabled: orcaCard.available
                    onClicked: kcm.launchApp("orca")
                    Accessible.description: i18n("Starts the Orca screen reader")
                }
            }
        }
    }
}
