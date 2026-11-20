/*
 * Enthroned Settings - Home dashboard (Lote 4).
 * Light summary of real data only: computer name, system version, network,
 * update state, active visual profile and a hardware summary. Missing data is
 * shown as "Indisponível"/"Não verificado" or "Coletando…", never invented.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("Home")

    function updateStateTitle(state) {
        switch (state) {
        case "unknown": return i18n("Unknown state");
        case "checking": return i18n("Checking for updates…");
        case "upToDate": return i18n("System up to date");
        case "updatesAvailable": return i18n("Updates available");
        case "updating": return i18n("Update in progress");
        case "preparing": return i18n("Preparing new version");
        case "restartRequired": return i18n("Restart required");
        case "failed": return i18n("Last operation failed");
        case "noNetwork": return i18n("No connection");
        case "serviceUnavailable": return i18n("Service unavailable");
        }
        return i18n("Unknown state");
    }

    function updateStateIcon(state) {
        switch (state) {
        case "checking": return "emblem-synchronizing";
        case "upToDate": return "dialog-ok-apply";
        case "updatesAvailable": return "download";
        case "updating":
        case "preparing": return "emblem-synchronizing";
        case "restartRequired": return "system-reboot";
        case "failed": return "dialog-error";
        case "noNetwork": return "network-disconnect";
        case "serviceUnavailable": return "dialog-warning";
        }
        return "dialog-question";
    }

    function networkText() {
        if (!updates.nmAvailable) {
            return i18n("Not verified");
        }
        return updates.online ? i18n("Connected") : i18n("No connection");
    }

    // The engine exposes stable tokens ("ok"/"falha") as data; translate at
    // the display boundary so the session language wins.
    function outcomeText(outcome) {
        return outcome === "falha" ? i18n("failed") : outcome;
    }

    function hw(value) {
        return deviceInfo.ready ? value : i18n("Collecting…");
    }

    function storageSummary() {
        const volumes = deviceInfo.storage;
        if (volumes.length === 0) {
            return "";
        }
        return i18n("%1 free of %2", volumes[0].free, volumes[0].total);
    }

    // A tile either opens a native KDE module (when it exists) or another page.
    readonly property var shortcuts: [
        { title: i18n("Network & Internet"), note: i18n("Wi-Fi and connections"), icon: "network-wireless", page: "network" },
        { title: i18n("Bluetooth"), note: i18n("Pair devices"), icon: "preferences-system-bluetooth",
          ids: ["kcm_bluetooth"], page: "devices" },
        { title: i18n("Display"), note: i18n("Resolution and scale"), icon: "preferences-desktop-display",
          ids: ["kcm_kscreen", "kcm_displayconfiguration"], page: "display" },
        { title: i18n("Sound"), note: i18n("Volume and devices"), icon: "audio-card",
          ids: ["kcm_pulseaudio"], page: "sound" },
        { title: i18n("Personalization"), note: i18n("Profile, theme and wallpaper"), icon: "preferences-desktop-theme",
          page: "appearance" },
        { title: i18n("System updates"), note: i18n("Check for and install updates"), icon: "update-none",
          page: "updates" }
    ]

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // --- Identity ---
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "org.enthroned.enthroned-os"
                    implicitWidth: Kirigami.Units.iconSizes.huge
                    implicitHeight: Kirigami.Units.iconSizes.huge
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading {
                        level: 2
                        text: deviceInfo.deviceName.length > 0 ? deviceInfo.deviceName : i18n("This computer")
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Kirigami.Theme.disabledTextColor
                        text: identity.productVersion.length > 0
                            ? i18n("%1 %2 · channel %3", identity.productName, identity.productVersion, identity.channel)
                            : i18n("System identity unavailable")
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Kirigami.Theme.disabledTextColor
                        text: profiles.activeLabel.length > 0
                            ? i18n("Active appearance profile: %1", profiles.activeLabel)
                            : i18n("Appearance profile: no active Enthroned profile")
                    }
                }
                QQC2.Button {
                    text: i18n("About this device")
                    icon.name: "help-about"
                    onClicked: applicationWindow().goTo("about")
                }
            }
        }

        // --- Network + updates ---
        GridLayout {
            columns: root.width > Kirigami.Units.gridUnit * 40 ? 2 : 1
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true

            Kirigami.AbstractCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Icon {
                        source: updates.nmAvailable && updates.online ? "network-connect" : "network-disconnect"
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        QQC2.Label {
                            text: i18n("Network")
                            font.bold: true
                        }
                        QQC2.Label {
                            text: root.networkText()
                            color: Kirigami.Theme.disabledTextColor
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    QQC2.Button {
                        text: i18n("Open")
                        icon.name: "go-next"
                        onClicked: applicationWindow().goTo("network")
                        Accessible.description: i18n("Opens the Network & Internet page")
                    }
                }
            }

            Kirigami.AbstractCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    StatusIcon {
                        updateState: updates.state
                        iconName: root.updateStateIcon(updates.state)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        QQC2.Label {
                            text: root.updateStateTitle(updates.state)
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Kirigami.Theme.disabledTextColor
                            text: updates.lastCheck.outcome !== undefined
                                ? i18n("Last check this session: %1", root.outcomeText(updates.lastCheck.outcome))
                                : i18n("No check this session yet.")
                        }
                    }
                    QQC2.BusyIndicator {
                        visible: updates.busy
                        running: updates.busy
                    }
                    QQC2.Button {
                        text: i18n("Check")
                        icon.name: "view-refresh"
                        enabled: updates.canCheck
                        onClicked: updates.checkForUpdates()
                    }
                    QQC2.Button {
                        text: i18n("Open")
                        icon.name: "go-next"
                        onClicked: applicationWindow().goTo("updates")
                        Accessible.description: i18n("Opens the System updates page")
                    }
                }
            }
        }

        // --- Frequent shortcuts ---
        SectionHeading {
            text: i18n("Frequent settings")
        }
        GridLayout {
            columns: root.width > Kirigami.Units.gridUnit * 40 ? 2 : 1
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true

            Repeater {
                model: root.shortcuts
                delegate: ShortcutTile {
                    id: tile
                    required property var modelData
                    title: modelData.title
                    note: modelData.note
                    iconName: modelData.icon
                    onActivated: {
                        const listed = kcm.available;
                        const ids = modelData.ids !== undefined ? modelData.ids : [];
                        for (let i = 0; i < ids.length; i++) {
                            if (kcm.toolPresent && listed.indexOf(ids[i]) !== -1) {
                                kcm.launch(ids[i]);
                                return;
                            }
                        }
                        applicationWindow().goTo(modelData.page);
                    }
                }
            }
        }

        // --- Hardware summary ---
        SectionHeading {
            text: i18n("Hardware summary")
        }
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                InfoRow { label: i18n("Processor"); value: root.hw(deviceInfo.cpu) }
                InfoRow { label: i18n("Memory (RAM)"); value: root.hw(deviceInfo.memory) }
                InfoRow { label: i18n("Graphics card"); value: root.hw(deviceInfo.gpus.join("\n")) }
                InfoRow { label: i18n("Storage"); value: root.hw(root.storageSummary()) }
                QQC2.Button {
                    text: i18n("View full specifications")
                    icon.name: "go-next"
                    flat: true
                    onClicked: applicationWindow().goTo("about")
                }
            }
        }
    }
}
