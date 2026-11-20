/*
 * Enthroned Settings - ColorSwatch (Lote 15).
 * A selectable colour choice: a filled disc (accent colours) or a themed folder
 * icon (folder colours). Selection is never colour-only: the selected swatch
 * carries a check mark and a ring, and keyboard focus shows a separate outline.
 * Exposed to assistive technology as a radio button named after the colour.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

QQC2.AbstractButton {
    id: root

    property color swatchColor: "transparent"
    // When set, the swatch shows this themed icon instead of a filled disc.
    property string iconName: ""
    property string colorName

    checkable: true
    hoverEnabled: true
    implicitWidth: Kirigami.Units.gridUnit * 2.25
    implicitHeight: Kirigami.Units.gridUnit * 2.25

    Accessible.role: Accessible.RadioButton
    Accessible.name: colorName
    Accessible.checkable: true
    Accessible.checked: checked

    QQC2.ToolTip.text: colorName
    QQC2.ToolTip.visible: hovered || visualFocus
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

    background: Rectangle {
        radius: width / 2
        color: root.hovered ? Qt.alpha(Kirigami.Theme.highlightColor, 0.12) : "transparent"
        border.width: root.visualFocus ? 2 : (root.checked ? 2 : 0)
        border.color: root.visualFocus ? Kirigami.Theme.focusColor : Kirigami.Theme.textColor
    }

    contentItem: Item {
        Rectangle {
            visible: root.iconName.length === 0
            anchors.centerIn: parent
            width: parent.width * 0.62
            height: width
            radius: width / 2
            color: root.swatchColor
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.25)
        }
        Kirigami.Icon {
            visible: root.iconName.length > 0
            anchors.centerIn: parent
            width: parent.width * 0.72
            height: width
            source: root.iconName
            isMask: false
            animated: false
        }
        Kirigami.Icon {
            visible: root.checked && root.iconName.length === 0
            anchors.centerIn: parent
            width: parent.width * 0.36
            height: width
            source: "checkmark"
            isMask: true
            color: "white"
        }
    }
}
