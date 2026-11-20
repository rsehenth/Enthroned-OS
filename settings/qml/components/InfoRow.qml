/*
 * Enthroned Settings - shared InfoRow component.
 * Label/value row used by the information pages. Values show "Indisponível"
 * (passed by callers) when a real source is missing.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property string label
    property string value
    property string detail: ""

    spacing: Kirigami.Units.largeSpacing

    QQC2.Label {
        text: root.label
        color: Kirigami.Theme.disabledTextColor
        wrapMode: Text.WordWrap
        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        Layout.maximumWidth: Kirigami.Units.gridUnit * 10
        Layout.alignment: Qt.AlignTop
    }
    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.fillWidth: true
        QQC2.Label {
            text: root.value.length > 0 ? root.value : i18n("Unavailable")
            color: root.value.length > 0 ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        QQC2.Label {
            visible: root.detail.length > 0
            text: root.detail
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
