/*
 * Enthroned Settings - clickable tile (Home shortcuts). Keyboard reachable
 * (Tab, Enter/Space), with a visible focus ring and a hover/pressed layer.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.AbstractCard {
    id: root

    property string title
    property string note
    property string iconName
    property bool enabledTile: true

    signal activated()

    Layout.fillWidth: true
    opacity: enabledTile ? 1.0 : 0.6
    activeFocusOnTab: enabledTile
    Keys.onReturnPressed: if (enabledTile) root.activated()
    Keys.onEnterPressed: if (enabledTile) root.activated()
    Keys.onSpacePressed: if (enabledTile) root.activated()

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.smallSpacing * 2
        color: Kirigami.Theme.highlightColor
        opacity: !root.enabledTile ? 0 : (area.pressed ? 0.16 : (area.containsMouse ? 0.08 : 0))
        z: 1
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.smallSpacing * 2
        color: "transparent"
        border.width: Kirigami.Units.smallSpacing / 2
        border.color: Kirigami.Theme.focusColor
        visible: root.activeFocus
        z: 2
    }

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
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: root.note
                color: Kirigami.Theme.disabledTextColor
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
        Kirigami.Icon {
            source: "go-next"
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabledTile
        cursorShape: Qt.PointingHandCursor
        z: 3
        onClicked: {
            root.forceActiveFocus(Qt.MouseFocusReason);
            root.activated();
        }
    }

    Accessible.name: root.title
    Accessible.description: root.note
    Accessible.role: Accessible.Button
}
