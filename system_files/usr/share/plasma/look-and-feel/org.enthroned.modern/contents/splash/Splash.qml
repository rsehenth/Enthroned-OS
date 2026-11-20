/*
 * Enthroned Modern splash screen.
 * Structure mirrors the official Breeze splash screen
 * (lookandfeel/org.kde.breeze/contents/splash/Splash.qml, KDE Plasma 6.6):
 * stage-driven fade-in, centered logo, rotating busy indicator.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: root
    color: "#120428"

    property int stage

    onStageChanged: {
        if (stage == 2) {
            introAnimation.running = true;
        } else if (stage == 5) {
            introAnimation.target = busyIndicator;
            introAnimation.from = 1;
            introAnimation.to = 0;
            introAnimation.running = true;
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        Image {
            id: logo
            readonly property real size: Kirigami.Units.gridUnit * 22

            anchors.centerIn: parent
            width: size
            height: size * sourceSize.height / Math.max(1, sourceSize.width)
            fillMode: Image.PreserveAspectFit

            asynchronous: true
            // Lote 13: the owner's original wordmark (deep violet background).
            source: "images/enthroned-wordmark.png"
        }

        Image {
            id: busyIndicator
            y: parent.height - (parent.height - logo.y - logo.height) / 2 - height / 2
            anchors.horizontalCenter: parent.horizontalCenter
            asynchronous: true
            source: "images/busy-ring.svg"
            sourceSize.height: Kirigami.Units.gridUnit * 2
            sourceSize.width: Kirigami.Units.gridUnit * 2
            RotationAnimator on rotation {
                id: rotationAnimator
                from: 0
                to: 360
                // Deliberately not tied to the user animation-scale preference:
                // the splash must spin consistently during startup.
                duration: 2000
                loops: Animation.Infinite
                running: Kirigami.Units.longDuration > 1
            }
        }

        Text {
            color: "#ECE7F4"
            anchors {
                bottom: parent.bottom
                right: parent.right
                margins: Kirigami.Units.gridUnit
            }
            text: "Enthroned OS"
            Accessible.name: text
            Accessible.role: Accessible.StaticText
        }
    }

    OpacityAnimator {
        id: introAnimation
        running: false
        target: content
        from: 0
        to: 1
        duration: Kirigami.Units.veryLongDuration * 2
        easing.type: Easing.InOutQuad
    }
}
