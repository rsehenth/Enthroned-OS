/*
 * Enthroned Launcher — shared interaction-state background (F4+).
 * One place for the hover / selected / pressed / keyboard-focus look used by
 * the category sidebar and the application list, so both read as one system.
 * Colors come only from the active Enthroned scheme; durations follow the
 * global Plasma animation speed (zero when the user disables animations).
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root

    property bool hovered: false
    property bool pressed: false
    property bool selected: false
    property bool focused: false
    // Accent bar on the leading edge: makes the selection readable without color.
    property bool indicator: false

    readonly property real cornerRadius: Kirigami.Units.smallSpacing * 1.5

    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: Kirigami.Theme.highlightColor
        opacity: root.pressed ? 0.22 : (root.selected ? 0.16 : (root.hovered ? 0.10 : 0))

        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Kirigami.Units.smallSpacing / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.smallSpacing * 0.75
        height: parent.height * 0.5
        radius: width / 2
        color: Kirigami.Theme.highlightColor
        opacity: root.indicator && root.selected ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: "transparent"
        border.width: Kirigami.Units.smallSpacing / 2
        border.color: Kirigami.Theme.focusColor
        visible: root.focused
    }
}
