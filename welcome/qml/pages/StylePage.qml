/*
 * Enthroned Welcome - step 2: appearance profile choice (F4.5 tela 2).
 * Integrates with the existing enthroned-profile mechanism (F2.1). Applying a
 * profile ALWAYS requires an explicit user action with confirmation; nothing
 * is applied automatically when the page opens, and the current profile is
 * shown honestly. The KDE look-and-feel mechanism does not guarantee full
 * reversal of individual preferences - the text says so.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

ColumnLayout {
    id: root

    property string pendingProfileId: ""
    property string lastResultMessage: ""
    property bool lastResultOk: false

    function requestApply(profileId) {
        root.pendingProfileId = profileId;
        applyDialog.open();
    }

    Kirigami.Heading {
        level: 2
        text: i18n("Your style")
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: profiles.activeLabel.length > 0
            ? i18n("Current profile: %1. Choosing another profile is optional and always depends on your confirmation.", profiles.activeLabel)
            : i18n("Current profile: the Plasma default. Choose one of the Enthroned profiles below or keep the current one.")
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: root.lastResultMessage.length > 0
        type: root.lastResultOk ? Kirigami.MessageType.Positive : Kirigami.MessageType.Error
        text: root.lastResultMessage
        showCloseButton: true
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: !profiles.toolPresent
        type: Kirigami.MessageType.Information
        icon.name: "dialog-information"
        text: i18n("The profile tool is not available in this environment. The same profiles remain in System Settings → Colors & Themes → Look and Feel.")
    }

    GridLayout {
        columns: root.width > 720 ? 2 : 1
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.largeSpacing
        Layout.fillWidth: true

        Repeater {
            model: [
                { id: "org.enthroned.classic", title: "Enthroned Classic",
                  subtitle: i18n("Light theme, solid panel at the bottom, menu on the left and clock with date. Inspired by Zorin OS."),
                  scheme: i18n("Color scheme: Enthroned Light"),
                  wallpaper: "file:///usr/share/wallpapers/EnthronedVigilia/contents/screenshot.png" },
                { id: "org.enthroned.modern", title: "Enthroned Modern",
                  subtitle: i18n("Dark theme, centered floating panel and clock with time only. Inspired by Windows 11."),
                  scheme: i18n("Color scheme: Enthroned Dark"),
                  wallpaper: "file:///usr/share/wallpapers/EnthronedVigilia/contents/screenshot.png" }
            ]

            delegate: Kirigami.AbstractCard {
                id: profileCard
                required property var modelData
                readonly property bool isActive: profiles.activeProfile === modelData.id

                Layout.fillWidth: true

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    ProfilePreview {
                        modern: profileCard.modelData.id === "org.enthroned.modern"
                        active: profileCard.isActive
                        wallpaper: profileCard.modelData.wallpaper
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Heading {
                            level: 3
                            text: modelData.title
                            Layout.fillWidth: true
                        }
                        Kirigami.Icon {
                            visible: profileCard.isActive
                            source: "dialog-ok-apply"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        QQC2.Label {
                            visible: profileCard.isActive
                            text: i18n("Active")
                            color: Kirigami.Theme.positiveTextColor
                            font.bold: true
                        }
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: modelData.subtitle
                        color: Kirigami.Theme.disabledTextColor
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: modelData.scheme
                        color: Kirigami.Theme.disabledTextColor
                    }

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        QQC2.Button {
                            text: i18n("Apply profile")
                            icon.name: "view-restore"
                            enabled: profiles.toolPresent && !profiles.busy && !profileCard.isActive
                            onClicked: root.requestApply(modelData.id)
                            Accessible.description: i18n("Applies the appearance profile after confirmation")
                        }
                        QQC2.Label {
                            visible: profiles.busy
                            text: i18n("Applying…")
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }
                }
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.disabledTextColor
        text: i18n("Switching uses Plasma's official mechanism (look-and-feel). You can go back by applying another profile or theme in System Settings; KDE does not guarantee full reversal of every individual preference.")
    }

    QQC2.Dialog {
        id: applyDialog
        modal: true
        title: i18n("Apply appearance profile")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        parent: applicationWindow().overlay

        ColumnLayout {
            width: 400
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("The profile will be applied through Plasma's official mechanism. The session may reapply the panel and desktop layout.")
            }
        }

        onAccepted: profiles.apply(root.pendingProfileId)
    }

    Connections {
        target: profiles
        function onApplyFinished(ok, message) {
            root.lastResultOk = ok;
            root.lastResultMessage = ok
                ? i18n("Profile applied through the official Plasma mechanism.")
                : i18n("Could not apply the profile: %1", message);
        }
    }
}
