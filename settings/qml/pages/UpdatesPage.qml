/*
 * Enthroned Settings - System Updates page (F3.4/F3.6/F3.9/F3.10).
 * States come exclusively from the update engine (event-driven state machine);
 * percentages only when a real source provides them, otherwise an
 * indeterminate indicator. Buttons are only enabled when the underlying
 * mechanism exists. Demo mode is clearly labeled and never mixes data.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("System updates")

    property string view: "main" // main | details | history | rollback

    function stateTitle(state) {
        switch (state) {
        case "unknown": return updates.lastCheck.timestampMs > 0
            ? i18n("Update availability unknown") : i18n("Not verified yet");
        case "checking": return i18n("Checking for updates…");
        case "upToDate": return i18n("System up to date");
        case "updatesAvailable": return i18n("Updates available");
        case "updating": return i18n("Update in progress");
        case "preparing": return i18n("Preparing new version");
        case "deploymentPending": return i18n("Deployment confirmation pending");
        case "updateConfirmed": return i18n("System update completed");
        case "rollingBack": return i18n("Reverting to previous version");
        case "restartRequired": return i18n("Restart required");
        case "failed": return updates.lastOperationWasCheck
            ? i18n("Could not verify updates") : i18n("Failed");
        case "noNetwork": return i18n("No connection");
        case "serviceUnavailable": return i18n("Service unavailable");
        }
        return i18n("Not verified yet");
    }

    function stateDetail(state) {
        switch (state) {
        case "unknown": return updates.lastCheck.timestampMs > 0
            ? i18n("Use “Check for updates” to verify current availability.")
            : i18n("No check has been performed yet, so the system is NOT known to be up to date. Use “Check for updates” to verify.");
        case "checking": return i18n("Querying the update mechanisms (read-only).");
        case "upToDate": return i18n("No updates available right now.");
        case "updatesAvailable": return i18n("Review the list below and choose what to update: everything, system only or applications only.");
        case "updating": return i18n("The update is running through the official Enthroned OS mechanisms with real progress.");
        case "preparing": return i18n("The new version was downloaded and is being prepared for the next boot.");
        case "deploymentPending": return i18n("The update command finished. A new deployment status is needed to determine whether to restart.");
        case "updateConfirmed": return i18n("Deployment status confirmed; no restart is pending.");
        case "rollingBack": return i18n("The system is being reverted to the previous deployment (bootc rollback).");
        case "restartRequired": return i18n("A change is staged for the next boot. Restart the computer when convenient to apply it.");
        case "failed": return updates.lastOperationWasCheck
            ? i18n("The verification did not finish, so it is NOT known whether updates exist. Nothing was installed or changed. Try “Check for updates” again.")
            : i18n("The last operation ended with an error. See the details and try again.");
        case "noNetwork": return i18n("Not enough network connection to check for updates.");
        case "serviceUnavailable": return i18n("The systemd D-Bus is not reachable in this environment; the center works with local data only.");
        }
        return "";
    }

    function stateIcon(state) {
        switch (state) {
        case "checking": return "emblem-synchronizing";
        case "deploymentPending": return "dialog-information";
        case "updateConfirmed":
        case "upToDate": return "dialog-ok-apply";
        case "updatesAvailable": return "download";
        case "updating":
        case "preparing": return "emblem-synchronizing";
        case "rollingBack": return "edit-undo";
        case "restartRequired": return "system-reboot";
        case "failed": return "dialog-error";
        case "noNetwork": return "network-disconnect";
        case "serviceUnavailable": return "dialog-warning";
        }
        return "dialog-question";
    }

    function blockReasonText(reason) {
        switch (reason) {
        case "policy": return i18n("Running updates is blocked by policy at this stage of the project (check only). Mutation requires a validated deployment with the update authorization enabled.");
        case "origin-foreign": return i18n("This installation uses an image that is not from Enthroned OS. To avoid replacing the system with a generic image, system updates are blocked in this center.");
        case "origin-unknown": return i18n("The origin of the system image could not be confirmed (bootc unavailable). As a safety measure, system updates stay blocked until the origin can be read.");
        }
        return "";
    }

    function sourceIcon(source) {
        if (source === "system") return "computer";
        if (source === "flatpak") return "applications-internet";
        if (source === "check") return "view-refresh";
        return "applications-system";
    }

    function kindTitle(kind) {
        switch (kind) {
        case "engine-check-started": return i18n("Check started");
        case "check-no-update": return i18n("Check: no updates");
        case "check-update-available": return i18n("Check: update available");
        case "check-failed": return i18n("Check failed");
        case "engine-update-started": return i18n("Update started");
        case "engine-rollback-started": return i18n("Rollback started");
        case "rollback-success": return i18n("Rollback finished");
        case "rollback-failed": return i18n("Rollback failed");
        case "flatpak-update-success": return i18n("Applications updated");
        case "flatpak-update-failed": return i18n("Application update failed");
        case "preflight-blocked": return i18n("Operation refused by preflight");
        case "staged-origin-blocked": return i18n("Staged image outside the Enthroned channel");
        case "module-completed": return i18n("Module finished");
        case "module-failed": return i18n("Module failed");
        case "update-success": return i18n("Update command finished");
        case "deployment-confirmed": return i18n("System update completed");
        case "update-failed-with-errors": return i18n("Update finished with errors");
        case "staged-deployment-detected": return i18n("Deployment staged");
        case "staged-deployment-cleared": return i18n("Deployment status queried");
        case "update-rejected": return i18n("Run blocked by policy");
        case "reboot-requested": return i18n("Restart requested");
        case "systemd-unavailable": return i18n("Service unavailable");
        case "update": return i18n("Flatpak updated");
        case "install": return i18n("Flatpak installed");
        case "remove": return i18n("Flatpak removed");
        }
        return kind;
    }

    function formatEventTime(entry) {
        const ts = entry.ts;
        if (typeof ts === "number" && ts > 0) {
            return new Date(ts).toLocaleString();
        }
        if (entry.timestampMs !== undefined) {
            return new Date(entry.timestampMs).toLocaleString();
        }
        if (entry.timestamp !== undefined) {
            return entry.timestamp;
        }
        return "";
    }

    Component.onCompleted: updates.refreshAll()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // ============ MAIN VIEW ============
        ColumnLayout {
            visible: root.view === "main"
            spacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true

            Kirigami.AbstractCard {
                Layout.fillWidth: true
                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.largeSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing

                        StatusIcon {
                            updateState: updates.state
                            iconName: root.stateIcon(updates.state)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            // Unmistakable demo marker next to the state (F4+); the window
                            // banner in Main.qml stays as the long explanation.
                            Rectangle {
                                visible: updates.demoMode
                                implicitWidth: demoLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                                implicitHeight: demoLabel.implicitHeight + Kirigami.Units.smallSpacing
                                radius: height / 2
                                color: Kirigami.Theme.neutralBackgroundColor
                                border.width: 1
                                border.color: Kirigami.Theme.neutralTextColor
                                Accessible.ignored: true
                                QQC2.Label {
                                    id: demoLabel
                                    anchors.centerIn: parent
                                    text: i18n("Demo mode")
                                    font: Kirigami.Theme.smallFont
                                    color: Kirigami.Theme.neutralTextColor
                                }
                            }
                            Kirigami.Heading {
                                level: 2
                                text: root.stateTitle(updates.state)
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Kirigami.Theme.disabledTextColor
                                text: root.stateDetail(updates.state)
                            }
                        }
                        QQC2.BusyIndicator {
                            visible: updates.busy
                            running: updates.busy
                        }
                    }

                    // Restart pending: highlighted but calm; the action is the Reinicializar button.
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: updates.restartPending
                        type: Kirigami.MessageType.Warning
                        icon.name: "system-reboot"
                        text: i18n("A restart is still required for the staged change. Save your work before restarting.")
                    }

                    // Failure: say what happened and what can be done next.
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: updates.state === "failed"
                        type: Kirigami.MessageType.Error
                        icon.name: "dialog-error"
                        text: i18n("The last operation did not finish. Open “View details” to see what happened and try again whenever you want.")
                    }

                    // Lote 8: honest explanation while no official Enthroned
                    // image origin is configured for this installation.
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: !updates.demoMode && !updates.channelConfigured
                        type: Kirigami.MessageType.Information
                        icon.name: "emblem-information"
                        text: i18n("The official Enthroned OS update channel is not configured on this system yet: no published image origin is declared for this installation. The check still works with the development channel, and generic Fedora or CentOS images stay blocked; installing channel updates requires the official registry to be configured first.")
                    }

                    // Lote 8: the pending deployment does not come from the
                    // Enthroned channel origin.
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: updates.state !== "deploymentPending" && updates.stagedOriginBlocked
                        type: Kirigami.MessageType.Warning
                        icon.name: "emblem-locked"
                        text: i18n("The staged deployment does not come from the Enthroned channel origin. New update runs are blocked until this is resolved; use the recovery option below or the command line if you know what you are doing.")
                    }

                    // Progress per source (only while an operation runs).
                    // Lote 8: the rows shown follow the running mode (full,
                    // system only or applications only).
                    ColumnLayout {
                        visible: updates.state === "updating" || updates.state === "preparing"
                        spacing: Kirigami.Units.smallSpacing
                        Layout.fillWidth: true

                        Repeater {
                            model: [
                                {
                                    source: "system",
                                    label: i18n("System (bootc)"),
                                    visible: updates.updateMode === ""
                                             || updates.updateMode === "full"
                                             || updates.updateMode === "system"
                                },
                                {
                                    source: "flatpak",
                                    label: i18n("Applications (Flatpak)"),
                                    visible: updates.updateMode === ""
                                             || updates.updateMode === "full"
                                             || updates.updateMode === "apps"
                                }
                            ]

                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                visible: modelData.visible

                                property var lastEvent: {
                                    const entries = updates.eventLog;
                                    for (let i = entries.length - 1; i >= 0; i--) {
                                        if (entries[i].source === modelData.source
                                            && (entries[i].rawType === "bootc-progress"
                                                || entries[i].rawType === "flatpak-progress"
                                                || entries[i].rawType === "module-completed"
                                                || entries[i].rawType === "module-failed")) {
                                            return entries[i];
                                        }
                                    }
                                    return null;
                                }

                                QQC2.Label {
                                    text: modelData.label
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                    elide: Text.ElideRight
                                }
                                QQC2.ProgressBar {
                                    visible: lastEvent !== null
                                        && lastEvent.progressPercent !== undefined
                                        && lastEvent.progressPercent >= 0
                                    from: 0
                                    to: 100
                                    value: lastEvent !== null && lastEvent.progressPercent !== undefined
                                        ? lastEvent.progressPercent : 0
                                    Layout.fillWidth: true
                                }
                                QQC2.BusyIndicator {
                                    visible: lastEvent === null
                                        || lastEvent.progressPercent === undefined
                                        || lastEvent.progressPercent < 0
                                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                    running: visible
                                }
                                QQC2.Label {
                                    visible: lastEvent !== null
                                        && lastEvent.progressPercent !== undefined
                                        && lastEvent.progressPercent >= 0
                                    text: lastEvent !== null
                                        ? Math.round(lastEvent.progressPercent) + "%"
                                        : ""
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                                    horizontalAlignment: Text.AlignRight
                                }
                                QQC2.Label {
                                    visible: lastEvent !== null
                                        && lastEvent.currentItem !== undefined
                                        && lastEvent.currentItem.length > 0
                                    text: lastEvent !== null ? lastEvent.currentItem : ""
                                    elide: Text.ElideMiddle
                                    Layout.maximumWidth: Kirigami.Units.gridUnit * 12
                                    color: Kirigami.Theme.disabledTextColor
                                }
                            }
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Kirigami.Theme.disabledTextColor
                            text: i18n("Indeterminate indicators appear when the source does not provide a reliable percentage. No progress is simulated with a timer.")
                        }
                    }

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Layout.fillWidth: true

                        QQC2.Button {
                            readonly property bool awaitingDeployment: updates.state === "deploymentPending"
                            text: awaitingDeployment ? i18n("Refresh deployment status") : i18n("Check for updates")
                            icon.name: "view-refresh"
                            enabled: awaitingDeployment ? !updates.demoMode : updates.canCheck
                            onClicked: awaitingDeployment ? updates.refreshDeploymentStatus() : updates.checkForUpdates()
                        }
                        QQC2.Button {
                            text: i18n("Update now")
                            icon.name: "update-none"
                            visible: updates.state === "updatesAvailable"
                                || updates.state === "restartRequired"
                                || updates.state === "failed"
                                || updates.demoMode
                            enabled: updates.canUpdate || (updates.demoMode && !updates.busy)
                            onClicked: {
                                if (updates.demoMode) {
                                    updates.requestUpdate();
                                } else {
                                    updateDialog.open();
                                }
                            }
                            Accessible.description: i18n("Runs the full update (system image and applications) after confirmation and system authorization")
                        }
                        QQC2.Button {
                            text: i18n("System only")
                            icon.name: "computer"
                            visible: updates.state === "updatesAvailable"
                                || updates.state === "restartRequired"
                                || updates.state === "failed"
                                || updates.demoMode
                            enabled: updates.canUpdate || (updates.demoMode && !updates.busy)
                            onClicked: {
                                if (updates.demoMode) {
                                    updates.requestSystemUpdate();
                                } else {
                                    systemUpdateDialog.open();
                                }
                            }
                            Accessible.description: i18n("Runs the system image update only, without touching applications")
                        }
                        QQC2.Button {
                            text: i18n("Applications only")
                            icon.name: "applications-internet"
                            visible: updates.state === "updatesAvailable"
                                || updates.state === "restartRequired"
                                || updates.state === "failed"
                                || updates.demoMode
                            enabled: updates.canUpdate || (updates.demoMode && !updates.busy)
                            onClicked: {
                                if (updates.demoMode) {
                                    updates.requestAppUpdates();
                                } else {
                                    appsUpdateDialog.open();
                                }
                            }
                            Accessible.description: i18n("Updates the Flatpak applications only, without touching the system image")
                        }
                        QQC2.Button {
                            text: i18n("View details")
                            icon.name: "documentinfo"
                            onClicked: root.view = "details"
                        }
                        QQC2.Button {
                            text: i18n("Restart")
                            icon.name: "system-reboot"
                            visible: updates.restartPending
                            enabled: updates.canReboot
                            onClicked: rebootDialog.open()
                            Accessible.description: i18n("Restarts the computer after confirmation to apply the new version")
                        }
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: !updates.demoMode && (updates.imageOrigin === "foreign"
                            || (updates.updateBlockReason.length > 0
                                && (updates.state === "updatesAvailable"
                                    || updates.state === "restartRequired"
                                    || updates.state === "failed")))
                        type: updates.updateBlockReason.indexOf("origin") === 0
                            ? Kirigami.MessageType.Warning : Kirigami.MessageType.Information
                        icon.name: "emblem-locked"
                        text: root.blockReasonText(updates.updateBlockReason)
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: updates.autoUpdateRunning && updates.state !== "updating"
                        type: Kirigami.MessageType.Warning
                        icon.name: "emblem-synchronizing"
                        text: i18n("An automatic update (uupd.service) is running in the background. The center does not start another concurrent operation.")
                    }
                }
            }

            // Versions (real bootc data). The available system version is only
            // known once bootc has staged it, so it is never guessed.
            Kirigami.AbstractCard {
                Layout.fillWidth: true
                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing
                    InfoRow {
                        label: i18n("Installed version")
                        value: bootc.available ? bootc.bootedVersion : ""
                        detail: bootc.available ? bootc.bootedTimestamp : i18n("bootc unavailable in this environment.")
                    }
                    InfoRow {
                        readonly property bool stagedDetailsAvailable: updates.restartPending && bootc.available && bootc.stagedPresent
                        label: i18n("Staged new version")
                        visible: updates.state !== "deploymentPending"
                        value: stagedDetailsAvailable
                            ? (bootc.stagedVersion.length > 0 ? bootc.stagedVersion : i18n("present"))
                            : (bootc.available && !updates.restartPending ? i18n("None") : "")
                        detail: stagedDetailsAvailable
                            ? i18n("It will be applied at the next restart.")
                            : (updates.state === "updatesAvailable"
                                ? i18n("There is a new image in the channel; the exact version is only known after the download.")
                                : "")
                    }
                    // Lote 11B (H5 P2-4b/P2-6): the technical origin (the real
                    // deployment reference from the bootc cache) is kept apart
                    // from the trust classification below. An empty or invalid
                    // reference is never presented as trusted: when bootc is
                    // unavailable the row says so and the classification stays
                    // "unknown", which blocks mutating updates by policy.
                    InfoRow {
                        label: i18n("Image reference")
                        value: bootc.available && bootc.bootedImage.length > 0
                            ? bootc.bootedImage : ""
                        detail: bootc.available
                            ? (bootc.bootedTransport.length > 0
                                ? i18n("Transport: %1", bootc.bootedTransport)
                                : "")
                            : i18n("bootc unavailable in this environment.")
                    }
                    InfoRow {
                        label: i18n("Image origin")
                        value: updates.imageOrigin === "enthroned" ? i18n("Enthroned (verified)")
                            : updates.imageOrigin === "unverified" ? i18n("Unverified (development channel)")
                            : updates.imageOrigin === "foreign" ? i18n("Outside Enthroned OS")
                            : i18n("Unknown (origin could not be read)")
                    }
                    InfoRow {
                        label: i18n("Last check")
                        value: updates.lastCheck.timestampMs > 0
                            ? Qt.formatDateTime(new Date(updates.lastCheck.timestampMs), "dd/MM/yyyy HH:mm")
                            : i18n("Never (no check was performed)")
                        detail: updates.lastCheck.timestampMs > 0
                            ? (updates.lastCheck.outcome === "ok"
                                ? i18n("Check finished")
                                : i18n("Check ended with failure"))
                            : ""
                    }
                    InfoRow {
                        label: i18n("Connection")
                        value: updates.nmAvailable
                            ? (updates.online ? i18n("Connected") : i18n("Offline"))
                            : i18n("Unknown")
                        detail: ""
                    }
                }
            }

            // What will be updated: the system image (bootc) and the applications
            // (Flatpak) come from separate backend sources.
            SectionHeading {
                visible: updates.availableUpdates.length > 0
                text: i18n("What will be updated")
            }
            Repeater {
                model: [
                    { key: "system", title: i18n("System (bootc image)"), icon: "computer" },
                    { key: "apps", title: i18n("Applications (Flatpak)"), icon: "applications-internet" }
                ]
                delegate: Kirigami.AbstractCard {
                    id: groupCard
                    required property var modelData
                    readonly property var rows: modelData.key === "system" ? updates.systemUpdates : updates.appUpdates
                    Layout.fillWidth: true
                    visible: rows.length > 0
                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing
                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: groupCard.modelData.icon
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                            }
                            QQC2.Label {
                                text: groupCard.modelData.title
                                font.bold: true
                                Layout.fillWidth: true
                            }
                        }
                        Repeater {
                            model: groupCard.rows
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                QQC2.Label {
                                    text: modelData.id
                                    Layout.fillWidth: true
                                    elide: Text.ElideMiddle
                                }
                                QQC2.Label {
                                    visible: modelData.version.length > 0
                                    text: modelData.version
                                    color: Kirigami.Theme.disabledTextColor
                                }
                                QQC2.Label {
                                    text: modelData.detail
                                    color: Kirigami.Theme.disabledTextColor
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: Kirigami.Units.gridUnit * 13
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                QQC2.Button {
                    flat: true
                    icon.name: "view-history"
                    text: i18n("History")
                    onClicked: root.view = "history"
                }
                QQC2.Button {
                    flat: true
                    icon.name: "edit-undo"
                    text: i18n("Recovery (rollback)")
                    onClicked: root.view = "rollback"
                }
            }

            // Demo controls (demo mode only).
            Kirigami.AbstractCard {
                Layout.fillWidth: true
                visible: updates.demoMode
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: i18n("Demo scenario:")
                    }
                    QQC2.ComboBox {
                        id: scenarioBox
                        model: updates.demoScenarios()
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 15
                    }
                    QQC2.Button {
                        text: i18n("Load scenario")
                        icon.name: "view-refresh"
                        onClicked: updates.startDemoScenario(scenarioBox.currentText)
                    }
                    QQC2.Button {
                        text: i18n("Cancel (demo)")
                        icon.name: "dialog-cancel"
                        enabled: updates.busy
                        onClicked: updates.cancelDemo()
                    }
                }
            }
        }

        // ============ DETAILS VIEW ============
        ColumnLayout {
            visible: root.view === "details"
            spacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true

            QQC2.Button {
                flat: true
                icon.name: "go-previous"
                text: i18n("Back")
                onClicked: root.view = "main"
            }

            SectionHeading { text: i18n("Available items") }
            Kirigami.AbstractCard {
                Layout.fillWidth: true
                visible: updates.availableUpdates.length > 0
                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Repeater {
                        model: updates.availableUpdates
                        delegate: QQC2.Label {
                            required property var modelData
                            text: "• " + modelData.id
                                + (modelData.version.length > 0 ? " (" + modelData.version + ")" : "")
                                + " — " + modelData.detail
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
            EmptyState {
                Layout.fillWidth: true
                visible: updates.availableUpdates.length === 0 && !updates.busy
                icon: "dialog-ok-apply"
                title: i18n("No pending items listed right now")
            }

            SectionHeading { text: i18n("Events this session") }
            Kirigami.AbstractCard {
                Layout.fillWidth: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 12
                contentItem: ListView {
                    id: eventList
                    clip: true
                    model: updates.eventLog
                    spacing: Kirigami.Units.smallSpacing

                    delegate: RowLayout {
                        required property var modelData
                        width: eventList.width
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: root.sourceIcon(modelData.source)
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                        QQC2.Label {
                            text: root.formatEventTime(modelData)
                            color: Kirigami.Theme.disabledTextColor
                        }
                        QQC2.Label {
                            text: "[" + modelData.source + "]"
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: modelData.rawType
                                + (modelData.description !== undefined && modelData.description.length > 0
                                    ? " — " + modelData.description : "")
                                + (modelData.progressPercent !== undefined
                                    ? " (" + Math.round(modelData.progressPercent) + "%)" : "")
                            color: modelData.severity === "Error"
                                ? Kirigami.Theme.negativeTextColor
                                : (modelData.severity === "Warning"
                                    ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor)
                        }
                    }

                    EmptyState {
                        anchors.centerIn: parent
                        visible: eventList.count === 0
                        icon: "emblem-synchronizing"
                        title: i18n("No events recorded this session")
                    }
                }
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                text: i18n("Detailed technical messages stay in the system journal (journalctl -u uupd-manual.service). The center shows only what is needed to decide.")
            }
        }

        // ============ HISTORY VIEW ============
        ColumnLayout {
            visible: root.view === "history"
            spacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true

            QQC2.Button {
                flat: true
                icon.name: "go-previous"
                text: i18n("Back")
                onClicked: root.view = "main"
            }

            SectionHeading { text: i18n("Update history") }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                text: i18n("Real sources: the uupd journal (uupd.service and uupd-manual.service), the Flatpak history and operations started in this center. No success is inferred from a single log line.")
            }

            ListView {
                id: historyList
                Layout.fillWidth: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 18
                clip: true
                spacing: Kirigami.Units.smallSpacing
                model: updates.history

                delegate: Kirigami.AbstractCard {
                    required property var modelData
                    width: historyList.width
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: modelData.kind === "module-failed"
                                || modelData.kind === "update-failed-with-errors"
                                || modelData.kind === "check-failed"
                                ? "dialog-error"
                                : (modelData.kind === "deployment-confirmed"
                                    || modelData.kind === "staged-deployment-detected"
                                    ? "dialog-ok-apply" : "view-history")
                            implicitWidth: Kirigami.Units.iconSizes.smallMedium
                            implicitHeight: Kirigami.Units.iconSizes.smallMedium
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 2
                            QQC2.Label {
                                text: root.kindTitle(modelData.kind)
                                font.bold: true
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: (modelData.title !== undefined ? modelData.title : "")
                                    + (modelData.detail !== undefined && modelData.detail.length > 0
                                        ? " — " + modelData.detail : "")
                                color: Kirigami.Theme.disabledTextColor
                            }
                        }
                        QQC2.Label {
                            text: root.formatEventTime(modelData)
                            color: Kirigami.Theme.disabledTextColor
                        }
                        QQC2.Label {
                            text: modelData.source
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: historyList.count === 0
                    icon: "view-history"
                    title: i18n("No update events found in the allowed sources")
                }
            }
        }

        // ============ ROLLBACK VIEW ============
        ColumnLayout {
            visible: root.view === "rollback"
            spacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true

            QQC2.Button {
                flat: true
                icon.name: "go-previous"
                text: i18n("Back")
                onClicked: root.view = "main"
            }

            SectionHeading { text: i18n("Recover to the previous deployment") }

            Kirigami.AbstractCard {
                Layout.fillWidth: true
                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    InfoRow {
                        label: i18n("Running deployment")
                        value: bootc.available
                            ? (bootc.bootedVersion.length > 0 ? bootc.bootedVersion : i18n("Not verified"))
                            : ""
                        detail: bootc.bootedTimestamp
                    }
                    InfoRow {
                        label: i18n("Previous deployment")
                        value: bootc.available && bootc.rollbackPresent
                            ? bootc.rollbackVersion
                            : ""
                        detail: bootc.available && bootc.rollbackPresent
                            ? i18n("Rollback possible via bootc (a previous deployment is present on the system).")
                            : i18n("No previous deployment identifiable right now.")
                    }
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: !(bootc.available && bootc.rollbackPresent) && !updates.demoMode
                type: Kirigami.MessageType.Information
                icon.name: "emblem-information"
                text: i18n("No previous deployment is identifiable right now, so there is nothing to roll back to yet. After the first applied update the previous version stays available on the system.")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: !updates.demoMode && !updates.canRollback
                    && bootc.available && bootc.rollbackPresent
                type: Kirigami.MessageType.Information
                icon.name: "emblem-locked"
                text: i18n("Running a rollback requires the update authorization and a confirmed image origin; both are currently unavailable, so the button below stays disabled.")
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                QQC2.Button {
                    text: i18n("Roll back to the previous version")
                    icon.name: "edit-undo"
                    enabled: (updates.canRollback && !updates.busy)
                        || (updates.demoMode && !updates.busy)
                    onClicked: {
                        if (updates.demoMode) {
                            updates.requestRollback();
                        } else {
                            rollbackDialog.open();
                        }
                    }
                    Accessible.description: i18n("Prepares the previous deployment after confirmation; the switch happens at the next restart")
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("What a rollback covers and what it does not:\n• Covers: the system deployment (base image + image packages), switching to the previous deployment at boot.\n• Does not cover: personal files, Flatpak applications, user extensions and most user settings — that data lives outside the image and is not reverted.\n• Requirements: a previous deployment on the system (bootc status) and a restart after the rollback.\n• Authorization: the run goes through the fixed enthroned-rollback.service unit via systemd, never through a command typed by the interface.")
            }
        }
    }

    QQC2.Dialog {
        id: updateDialog
        modal: true
        title: i18n("Update now")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        parent: applicationWindow().overlay

        ColumnLayout {
            width: Math.min(Kirigami.Units.gridUnit * 26, applicationWindow().width - Kirigami.Units.gridUnit * 4)
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Scope of the operation:")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("• System image via bootc (uupd)\n• Flatpak applications\n• Brew and Distrobox, when installed and enabled in the uupd configuration")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                text: i18n("The run is performed by the Enthroned OS uupd-manual.service via systemd D-Bus, with the existing polkit authorization (uupd.rules). The computer does NOT restart automatically; restarting is always your decision, later, in the center.")
            }
        }
        onAccepted: updates.requestUpdate()
    }

    QQC2.Dialog {
        id: rebootDialog
        modal: true
        title: i18n("Restart now")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        parent: applicationWindow().overlay

        ColumnLayout {
            width: Math.min(Kirigami.Units.gridUnit * 24, applicationWindow().width - Kirigami.Units.gridUnit * 4)
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("The computer will restart to apply the staged new version. Save your work before continuing.")
            }
        }
        onAccepted: updates.requestReboot()
    }

    QQC2.Dialog {
        id: systemUpdateDialog
        modal: true
        title: i18n("Update system only")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        parent: applicationWindow().overlay

        ColumnLayout {
            width: Math.min(Kirigami.Units.gridUnit * 26, applicationWindow().width - Kirigami.Units.gridUnit * 4)
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Scope of the operation:")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("• The Enthroned OS system image only (kernel, security fixes, Plasma, libraries, drivers and image applications), via a transactional bootc upgrade.\n• Applications are NOT touched; your files and settings stay in place.")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                text: i18n("The run is performed by the fixed enthroned-system-update.service unit via systemd, authorized by the Enthroned polkit rule. The computer does NOT restart automatically; restarting is always your decision, later, in the center.")
            }
        }
        onAccepted: updates.requestSystemUpdate()
    }

    QQC2.Dialog {
        id: appsUpdateDialog
        modal: true
        title: i18n("Update applications only")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        parent: applicationWindow().overlay

        ColumnLayout {
            width: Math.min(Kirigami.Units.gridUnit * 26, applicationWindow().width - Kirigami.Units.gridUnit * 4)
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Scope of the operation:")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("• Flatpak applications for the system installation and for your user installation.\n• The system image is NOT touched and no restart is needed. Nothing is removed; your app data stays in place.")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                text: i18n("The system installation runs through the fixed enthroned-flatpak-update.service unit; your user installation runs in your session with a fixed command. Neither accepts arguments from this interface.")
            }
        }
        onAccepted: updates.requestAppUpdates()
    }

    QQC2.Dialog {
        id: rollbackDialog
        modal: true
        title: i18n("Roll back to the previous version")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        parent: applicationWindow().overlay

        ColumnLayout {
            width: Math.min(Kirigami.Units.gridUnit * 26, applicationWindow().width - Kirigami.Units.gridUnit * 4)
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("The next boot will switch to the previous system deployment. Save your work before continuing.")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                text: i18n("Personal files, Flatpak applications and most settings are not reverted; the rollback covers the system image only. The run is performed by the fixed enthroned-rollback.service unit, and the switch happens at the restart you confirm afterwards.")
            }
        }
        onAccepted: updates.requestRollback()
    }
}
