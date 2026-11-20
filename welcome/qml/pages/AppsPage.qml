/*
 * Enthroned Welcome - step 3: browser and app store (F4.5 tela 3 / F4.2/F4.3).
 * Real actions only when the application is actually installed; unavailable
 * apps show an honest state instead of dead buttons.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string resultMessage: ""

    Kirigami.Heading {
        level: 2
        text: i18n("Browser and applications")
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: i18n("Enthroned OS ships with the Brave browser as the default browser and KDE Discover as the app store. Other applications can be installed whenever you want, straight from the store.")
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: root.resultMessage.length > 0
        type: Kirigami.MessageType.Information
        text: root.resultMessage
        showCloseButton: true
    }

    Kirigami.AbstractCard {
        Layout.fillWidth: true
        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: "web-browser"
                implicitWidth: Kirigami.Units.iconSizes.medium
                implicitHeight: Kirigami.Units.iconSizes.medium
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label {
                    text: i18n("Brave Browser — default browser")
                    font.bold: true
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: apps.braveAvailable
                    text: i18n("Installed on this system. Internet links open in Brave.")
                    color: Kirigami.Theme.disabledTextColor
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: !apps.braveAvailable
                    text: i18n("Not installed yet. The system installs it automatically as soon as there is a connection — or you can install it now from the store.")
                    color: Kirigami.Theme.disabledTextColor
                }
            }
            QQC2.Button {
                visible: apps.braveAvailable
                text: i18n("Open Brave")
                icon.name: "arrow-right"
                onClicked: apps.launchBrave()
                Accessible.description: i18n("Opens the Brave browser")
            }
        }
    }

    Kirigami.AbstractCard {
        Layout.fillWidth: true
        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: "system-software-install"
                implicitWidth: Kirigami.Units.iconSizes.medium
                implicitHeight: Kirigami.Units.iconSizes.medium
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label {
                    text: i18n("KDE Discover — app store")
                    font.bold: true
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: apps.discoverAvailable
                    text: i18n("Search, install, open and remove applications, with updates handled by the KDE store.")
                    color: Kirigami.Theme.disabledTextColor
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: !apps.discoverAvailable
                    text: i18n("The app store was not found on this system.")
                    color: Kirigami.Theme.disabledTextColor
                }
            }
            QQC2.Button {
                visible: apps.discoverAvailable
                text: i18n("Open the store")
                icon.name: "system-software-install"
                onClicked: apps.launchDiscover()
                Accessible.description: i18n("Opens the KDE Discover app store")
            }
        }
    }

    Connections {
        target: apps
        function onLaunched(ok, what) {
            root.resultMessage = ok
                ? i18n("Application opened.")
                : i18n("Could not open %1 right now.", what);
        }
    }
}
