/*
 * Enthroned Welcome - step 4: optional ArtCraft Launcher (F4.5 tela 4 / F4.6/F4.8).
 * Entirely voluntary: the checkbox starts UNCHECKED, absence of a choice is
 * never consent, "Agora não" never installs anything and the assistant stays
 * fully usable without it. Installing requires a second explicit confirmation
 * and only proceeds through the gated backend (see artcraftinstaller.h).
 * No ArtCraft brand assets are used; the launcher is described factually and
 * linked to its official page.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    function installerStateText() {
        switch (artcraft.state) {
        case "checking": return i18n("Querying the official release…");
        case "downloading": return artcraft.progress >= 0
            ? i18n("Downloading… %1%", artcraft.progress)
            : i18n("Downloading…");
        case "verifying": return i18n("Verifying the package (SHA-256)…");
        case "installing": return i18n("Installing…");
        case "done": return i18n("ArtCraft Launcher installed.");
        case "cancelled": return artcraft.message.length > 0
            ? artcraft.message
            : i18n("The installation was canceled.");
        case "failed": return artcraft.message.length > 0 ? artcraft.message : i18n("The installation failed.");
        case "blocked": return artcraft.message;
        default: return "";
        }
    }

    Kirigami.Heading {
        level: 2
        text: i18n("Creativity and productivity tools")
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: i18n("ArtCraft Launcher is an optional manager for discovering and installing the Craft App Suite applications — free and open-source tools, each one installed on its own. Covered areas include:")
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.disabledTextColor
        text: i18n("• Photography and image editing\n• Graphic and vector design\n• Video editing and production\n• Documents and presentations\n• Spreadsheets and productivity tools\n• PDFs")
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.disabledTextColor
        text: i18n("The launcher is an independent project in early development (alpha) and is not part of the base system. The current catalog and the details of each application are on the official page.")
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        QQC2.Button {
            flat: true
            text: i18n("Learn more")
            icon.name: "documentinfo"
            onClicked: Qt.openUrlExternally("https://github.com/storytold/craft-launcher")
            Accessible.description: i18n("Opens the official ArtCraft Launcher page")
        }
        QQC2.Button {
            text: i18n("Not now")
            icon.name: "go-next-skip"
            onClicked: {
                if (welcome.artcraftConsented) {
                    welcome.declineArtcraft();
                }
                welcome.next();
            }
            Accessible.description: i18n("Leaves the option unchecked and continues without installing anything")
        }
    }

    // F4+: the optional choice lives on its own neutral surface, visually
    // separate from the information above; nothing here is pre-selected.
    Kirigami.AbstractCard {
        Layout.fillWidth: true
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                id: consentBox
                checked: welcome.artcraftConsented
                text: i18n("I want to install ArtCraft Launcher")
                onToggled: checked ? welcome.consentArtcraft() : welcome.declineArtcraft()
                Accessible.description: i18n("Entirely voluntary option, unchecked by default")
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: welcome.artcraftConsented
                text: i18n("If you continue, Enthroned will download the official installer (user Flatpak) from the project's official release, verify the SHA-256 checksum and install it into your profile — without asking for a password and without changing the system. No application from the suite is installed automatically: you choose later, inside the launcher.")
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        visible: welcome.artcraftConsented
        && welcome.artcraftInstallState !== "done"
        && artcraft.state !== "checking"
        && artcraft.state !== "downloading"
        && artcraft.state !== "verifying"
        && artcraft.state !== "installing"

        QQC2.Button {
            text: i18n("Install now")
            icon.name: "install"
            onClicked: confirmDialog.open()
            Accessible.description: i18n("Starts the optional installation after confirmation")
        }
        QQC2.Label {
            visible: welcome.artcraftInstallState === "failed" || welcome.artcraftInstallState === "pending"
            text: i18n("You can also install it later.")
            color: Kirigami.Theme.disabledTextColor
        }
    }

    // Lote 6: honest cancellation while the optional install is in flight.
    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        visible: artcraft.state === "checking"
            || artcraft.state === "downloading"
            || artcraft.state === "verifying"
            || artcraft.state === "installing"

        QQC2.Button {
            flat: true
            text: i18n("Cancel")
            icon.name: "dialog-cancel"
            onClicked: artcraft.cancel()
            Accessible.description: i18n("Cancels the running installation; nothing on the system is changed")
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: installerStateText().length > 0
        type: artcraft.state === "done"
            ? Kirigami.MessageType.Positive
            : (artcraft.state === "failed" ? Kirigami.MessageType.Error : Kirigami.MessageType.Information)
        text: installerStateText()
    }

    QQC2.ProgressBar {
        Layout.fillWidth: true
        visible: artcraft.state === "downloading" && artcraft.progress >= 0
        from: 0
        to: 100
        value: artcraft.progress
    }
    QQC2.BusyIndicator {
        Layout.alignment: Qt.AlignHCenter
        visible: artcraft.state === "checking"
            || (artcraft.state === "downloading" && artcraft.progress < 0)
            || artcraft.state === "verifying"
            || artcraft.state === "installing"
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: welcome.demoMode
        type: Kirigami.MessageType.Warning
        icon.name: "data-warning"
        text: i18n("Demo mode — nothing is actually downloaded or installed.")
    }

    QQC2.Dialog {
        id: confirmDialog
        modal: true
        title: i18n("Install ArtCraft Launcher?")
        standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No
        parent: applicationWindow().overlay

        ColumnLayout {
            width: Math.min(Kirigami.Units.gridUnit * 24, applicationWindow().width - Kirigami.Units.gridUnit * 4)
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("The official ArtCraft Launcher package (alpha project) will be downloaded from the project's official page, with checksum verification and installation into your user profile.\n\nNothing else is installed. You can remove it later from the app store.")
            }
        }

        onAccepted: artcraft.install()
    }
}
