/*
 * Enthroned Launcher — quick link row for the places column (folders and
 * tools). Presentation only: the caller decides what a click does.
 * With labelVisible=false (narrow popup) it collapses to an icon button and
 * the label moves into a tooltip.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

T.ItemDelegate {
    id: root

    property string iconName: ""
    property string label: ""
    property string caption: ""
    property bool labelVisible: true

    Layout.fillWidth: true

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitContentHeight + topPadding + bottomPadding, Kirigami.Units.gridUnit * 2)
    leftPadding: Kirigami.Units.smallSpacing * 2
    rightPadding: Kirigami.Units.smallSpacing * 2
    topPadding: Kirigami.Units.smallSpacing
    bottomPadding: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing * 2

    hoverEnabled: true
    text: label

    background: ItemBackground {
        hovered: root.hovered
        pressed: root.down
        focused: root.visualFocus
    }

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: caption

    PC3.ToolTip.text: caption.length > 0 ? label + " — " + caption : label
    PC3.ToolTip.visible: !labelVisible && (hovered || visualFocus)
    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    contentItem: RowLayout {
        spacing: root.spacing

        Kirigami.Icon {
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            implicitHeight: Kirigami.Units.iconSizes.smallMedium
            Layout.alignment: Qt.AlignVCenter | (root.labelVisible ? Qt.AlignLeft : Qt.AlignHCenter)
            Layout.fillWidth: !root.labelVisible

            animated: false
            source: root.iconName
        }

        ColumnLayout {
            visible: root.labelVisible
            spacing: 0
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            PC3.Label {
                text: root.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            PC3.Label {
                visible: root.caption.length > 0
                text: root.caption
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: 0.75
                Layout.fillWidth: true
            }
        }
    }
}
