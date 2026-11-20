/*
 * Enthroned Welcome - step 1: system identity and what the desktop is (F4.5).
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    spacing: Kirigami.Units.largeSpacing

    // Lote 13: the owner's original full logo (installed by the image under
    // /usr/share/enthroned-os/branding); the "E" mark is the fallback when the
    // file is missing (development runs). Space is reserved from the artwork's
    // fixed aspect (1983 x 793) so the step does not shift while it loads.
    Item {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredHeight: Layout.preferredWidth * 793 / 1983
        Accessible.role: Accessible.Graphic
        Accessible.name: i18n("Enthroned OS")

        Image {
            id: wordmark
            anchors.fill: parent
            source: "file:///usr/share/enthroned-os/branding/enthroned-wordmark.png"
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            visible: status === Image.Ready
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.huge
            height: width
            source: "org.enthroned.enthroned-os"
            visible: wordmark.status === Image.Error || wordmark.status === Image.Null
        }
    }

    Kirigami.Heading {
        level: 1
        text: i18n("Welcome to Enthroned OS")
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        text: i18n("Your computer is ready. Enthroned OS is a Linux desktop with the KDE Plasma environment: a menu in the corner of the panel, windows that are easy to organize and everything you need to get started.")
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: Kirigami.Theme.disabledTextColor
        text: i18n("This assistant presents the system in five short steps. You can close it any time and resume later where you left off — nothing is lost.")
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: welcome.phase === "interrupted" || welcome.phase === "started"
        type: Kirigami.MessageType.Information
        icon.name: "view-history"
        text: i18n("You have already started this assistant. Continue where you left off.")
    }

    QQC2.Button {
        Layout.alignment: Qt.AlignHCenter
        text: i18n("Using this desktop")
        icon.name: "dialog-information"
        onClicked: welcome.next()
        Accessible.description: i18n("Advances to the style step")
    }
}
