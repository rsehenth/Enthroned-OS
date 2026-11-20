/*
 * Enthroned Settings - shared ProfilePreview component (F4+).
 * Schematic miniature of a profile's panel layout (Classic: solid full-width
 * panel, menu at the left, clock with date; Modern: floating panel, centered
 * cluster, clock with time only). It is a layout illustration, not a
 * screenshot: it uses the CURRENT color scheme, and the wallpaper is the real
 * packaged one when installed. Decorative: the adjacent text carries the info.
 * Kept identical to welcome/qml/components/ProfilePreview.qml (separate binaries).
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: root

    property bool modern: false
    property bool active: false
    property url wallpaper: ""

    Layout.fillWidth: true
    Layout.maximumWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredHeight: width * 9 / 16
    implicitWidth: Kirigami.Units.gridUnit * 14
    implicitHeight: implicitWidth * 9 / 16
    Accessible.ignored: true

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: Kirigami.Units.smallSpacing
        color: Kirigami.Theme.alternateBackgroundColor
        clip: true

        Image {
            anchors.fill: parent
            source: root.wallpaper
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: Kirigami.Units.gridUnit * 28
            visible: status === Image.Ready
        }

        Rectangle {
            id: panel
            readonly property real unit: height * 0.5

            height: parent.height * 0.17
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.modern ? Kirigami.Units.smallSpacing * 1.5 : 0
            radius: root.modern ? Kirigami.Units.smallSpacing * 1.5 : 0
            color: Kirigami.Theme.backgroundColor

            Row {
                id: cluster
                spacing: panel.unit * 0.5
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: root.modern ? undefined : parent.left
                anchors.leftMargin: panel.unit * 0.6
                anchors.horizontalCenter: root.modern ? parent.horizontalCenter : undefined

                Rectangle {
                    width: panel.unit
                    height: panel.unit
                    radius: width * 0.28
                    color: Kirigami.Theme.highlightColor
                }
                Repeater {
                    model: 3
                    Rectangle {
                        width: panel.unit
                        height: panel.unit
                        radius: width * 0.28
                        color: Kirigami.Theme.textColor
                        opacity: 0.4
                    }
                }
            }

            Column {
                anchors.right: parent.right
                anchors.rightMargin: panel.unit * 0.6
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.unit * 0.18

                Rectangle {
                    width: panel.unit * 1.8
                    height: panel.unit * 0.22
                    radius: height / 2
                    color: Kirigami.Theme.textColor
                    opacity: 0.55
                }
                Rectangle {
                    // Classic shows the date under the time; Modern shows time only.
                    visible: !root.modern
                    width: panel.unit * 1.8
                    height: panel.unit * 0.22
                    radius: height / 2
                    color: Kirigami.Theme.textColor
                    opacity: 0.35
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: frame.radius
        color: "transparent"
        border.width: root.active ? Kirigami.Units.smallSpacing / 2 : 1
        border.color: root.active ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
    }
}
