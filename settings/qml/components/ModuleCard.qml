/*
 * Enthroned Settings - card that opens a REAL native KDE module (kcmshell6).
 * `modules` lists candidate module ids (first one reported by kcmshell6 wins,
 * since ids differ across Plasma versions). Reading kcm.available makes the
 * state update when the asynchronous module listing finishes. Unavailable
 * modules stay disabled with an honest note, or disappear (hideIfUnavailable).
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.AbstractCard {
    id: root

    property string title
    property string subtitle
    property string iconName: "preferences-system"
    property var modules: []
    property bool hideIfUnavailable: false

    readonly property string resolvedModule: {
        const listed = kcm.available;
        for (let i = 0; i < modules.length; i++) {
            if (listed.indexOf(modules[i]) !== -1) {
                return modules[i];
            }
        }
        return "";
    }
    readonly property bool moduleAvailable: kcm.toolPresent && resolvedModule.length > 0

    Layout.fillWidth: true
    visible: moduleAvailable || !hideIfUnavailable
    // Gate 13.1: no blanket opacity (it lowered text contrast); the disabled
    // button and the "unavailable" note already carry the state.

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Icon {
            source: root.iconName
            implicitWidth: Kirigami.Units.iconSizes.medium
            implicitHeight: Kirigami.Units.iconSizes.medium
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                text: root.title
                font.bold: true
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.moduleAvailable
                    ? root.subtitle
                    : i18n("Module unavailable on this system.")
                color: Kirigami.Theme.disabledTextColor
            }
        }
        QQC2.Button {
            text: i18n("Open")
            icon.name: "window-open"
            enabled: root.moduleAvailable
            onClicked: kcm.launch(root.resolvedModule)
            Accessible.name: i18n("Open %1", root.title)
            Accessible.description: i18n("Opens the native KDE System Settings module")
        }
    }
}
