/*
 * Enthroned Settings - SettingRow (Lote 15).
 * One consistent row for a single preference: title and one-line explanation
 * on the left, the control(s) on the right; on a narrow window the controls
 * drop below the text. No card, no border: rows are separated by whitespace
 * and an optional hairline, so a page of ten settings stays calm.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

GridLayout {
    id: root

    property string title
    property string subtitle
    property bool separator: true
    // Controls declared inside a SettingRow land in the control area.
    default property alias controls: controlArea.data

    readonly property bool narrow: width < Kirigami.Units.gridUnit * 34

    Layout.fillWidth: true
    columns: narrow ? 1 : 2
    columnSpacing: Kirigami.Units.gridUnit
    rowSpacing: Kirigami.Units.smallSpacing

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: 0

        QQC2.Label {
            Layout.fillWidth: true
            text: root.title
            wrapMode: Text.WordWrap
            font.weight: Font.DemiBold
            Accessible.ignored: true
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: root.subtitle.length > 0
            text: root.subtitle
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
            Accessible.ignored: true
        }
    }

    Flow {
        id: controlArea
        Layout.alignment: root.narrow ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignTop)
        Layout.fillWidth: root.narrow
        Layout.maximumWidth: root.narrow ? -1 : Kirigami.Units.gridUnit * 22
        spacing: Kirigami.Units.smallSpacing
    }

    Kirigami.Separator {
        visible: root.separator
        Layout.fillWidth: true
        Layout.columnSpan: root.columns
        Layout.topMargin: Kirigami.Units.smallSpacing
        opacity: 0.6
    }
}
