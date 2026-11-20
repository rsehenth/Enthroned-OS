/*
 * Enthroned Settings - shared EmptyState component.
 * Used for empty lists and unavailable sources; never fakes content.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string icon: "emblem-question"
    property string title
    property string note: ""

    spacing: Kirigami.Units.smallSpacing

    Kirigami.Icon {
        source: root.icon
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: Kirigami.Units.iconSizes.large
        implicitHeight: Kirigami.Units.iconSizes.large
        opacity: 0.6
    }
    QQC2.Label {
        text: root.title
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.textColor
        font.bold: true
    }
    QQC2.Label {
        visible: root.note.length > 0
        text: root.note
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.disabledTextColor
    }
}
