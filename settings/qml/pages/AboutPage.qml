/*
 * Enthroned Settings - About this device (Lote 4).
 * Real data only: hardware from DeviceInfoProvider (collected off the UI
 * thread), identity from the F1 identity files, deployments from bootc.
 * Missing values read "Indisponível"; while the collector runs they read
 * "Coletando…". The device name is read-only here (renaming needs privileges).
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("About this device")

    property bool showAdvanced: false

    function hw(value) {
        return deviceInfo.ready ? value : i18n("Collecting…");
    }

    function storageText() {
        const volumes = deviceInfo.storage;
        const lines = [];
        for (let i = 0; i < volumes.length; i++) {
            lines.push(i18n("%1 free of %2 (%3)", volumes[i].free, volumes[i].total, volumes[i].mount));
        }
        return lines.join("\n");
    }

    function originText() {
        switch (updates.imageOrigin) {
        case "enthroned": return i18n("Enthroned channel image (verified)");
        case "unverified": return i18n("Unverified: the channel does not declare an Enthroned reference yet (development)");
        case "foreign": return i18n("Image not from Enthroned OS — system updates blocked");
        }
        return i18n("Could not read the origin (bootc unavailable)");
    }

    function selinuxText() {
        switch (deviceInfo.selinux) {
        case "enforcing": return i18n("Active (enforcing)");
        case "permissive": return i18n("Permissive");
        }
        return "";
    }

    function specsText() {
        const unknown = i18n("Unavailable");
        function v(s) { return s && s.length > 0 ? s : unknown; }
        return [
            i18n("Device name: %1", v(deviceInfo.deviceName)),
            i18n("Processor: %1", v(deviceInfo.cpu)),
            i18n("Memory (RAM): %1", v(deviceInfo.memory)),
            i18n("Graphics card: %1", v(deviceInfo.gpus.join(", "))),
            i18n("Storage: %1", v(storageText().replace(/\n/g, "; "))),
            i18n("Architecture: %1", v(identity.architecture)),
            i18n("Kernel: %1", v(identity.kernel)),
            i18n("System: %1 %2", v(identity.productName), v(identity.productVersion)),
            i18n("Channel: %1", v(identity.channel))
        ].join("\n");
    }

    Component.onCompleted: deviceInfo.refresh()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // Lote 13: the OS carries the original wordmark; the device row below
        // uses a generic computer icon so the two identities stay distinct.
        BrandWordmark {
            logoWidth: Kirigami.Units.gridUnit * 15
            Layout.alignment: Qt.AlignLeft
            Layout.bottomMargin: Kirigami.Units.smallSpacing
        }

        RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true
            Kirigami.Icon {
                source: "computer"
                implicitWidth: Kirigami.Units.iconSizes.huge
                implicitHeight: Kirigami.Units.iconSizes.huge
                Accessible.ignored: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Heading {
                    level: 1
                    text: deviceInfo.deviceName.length > 0 ? deviceInfo.deviceName : i18n("This computer")
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: root.hw(deviceInfo.deviceModel)
                    color: Kirigami.Theme.disabledTextColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    visible: !deviceInfo.ready || deviceInfo.deviceModel.length > 0
                }
            }
            QQC2.Button {
                text: i18n("Copy specifications")
                icon.name: "edit-copy"
                onClicked: {
                    deviceInfo.copyToClipboard(root.specsText());
                    applicationWindow().showPassiveNotification(i18n("Specifications copied."));
                }
                Accessible.description: i18n("Copies the device specifications to the clipboard")
            }
        }

        SectionHeading {
            text: i18n("Device specifications")
        }
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                InfoRow { label: i18n("Device name"); value: deviceInfo.deviceName }
                InfoRow { label: i18n("Processor"); value: root.hw(deviceInfo.cpu) }
                InfoRow {
                    label: i18n("Memory (RAM)")
                    value: root.hw(deviceInfo.memory)
                    detail: deviceInfo.ready && deviceInfo.memory.length > 0
                        ? i18n("Usable memory as reported by the kernel.") : ""
                }
                InfoRow { label: i18n("Graphics card"); value: root.hw(deviceInfo.gpus.join("\n")) }
                InfoRow { label: i18n("Storage"); value: root.hw(root.storageText()) }
                InfoRow { label: i18n("Architecture"); value: identity.architecture }
                InfoRow { label: i18n("Kernel"); value: identity.kernel }
            }
        }

        SectionHeading {
            text: i18n("Enthroned OS specifications")
        }
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                InfoRow { label: i18n("Edition"); value: identity.productName }
                InfoRow { label: i18n("Version"); value: identity.productVersion }
                InfoRow {
                    label: i18n("Channel")
                    value: identity.channel
                    detail: identity.channelDescription
                }
                InfoRow { label: i18n("Stage"); value: identity.phase }
                InfoRow { label: i18n("Operating system"); value: identity.osPrettyName }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Kirigami.Heading {
                level: 3
                text: i18n("Advanced details")
                Layout.fillWidth: true
            }
            QQC2.Button {
                flat: true
                icon.name: root.showAdvanced ? "arrow-up" : "arrow-down"
                text: root.showAdvanced ? i18n("Hide") : i18n("Show")
                onClicked: root.showAdvanced = !root.showAdvanced
                Accessible.description: i18n("Shows or hides technical details of the image and deployments")
            }
        }
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            visible: root.showAdvanced
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                InfoRow {
                    label: i18n("Technical base")
                    value: identity.baseImage
                    detail: i18n("The upstream image Enthroned OS is based on.")
                }
                InfoRow {
                    label: i18n("Running image")
                    value: bootc.available ? bootc.bootedImage : ""
                    detail: root.originText()
                }
                InfoRow {
                    label: i18n("Running deployment (booted)")
                    value: bootc.available
                        ? (bootc.bootedVersion.length > 0 ? bootc.bootedVersion : i18n("Not verified"))
                        : ""
                    detail: bootc.available
                        ? bootc.bootedTimestamp
                        : (bootc.bootcPresent
                            ? i18n("bootc is present, but the query failed: %1", bootc.errorHint)
                            : i18n("bootc was not found on this system."))
                }
                InfoRow {
                    label: i18n("Staged deployment")
                    value: bootc.available && bootc.stagedPresent
                        ? (bootc.stagedVersion.length > 0 ? bootc.stagedVersion : i18n("present"))
                        : ""
                    detail: bootc.available && bootc.stagedPresent ? bootc.stagedTimestamp : ""
                }
                InfoRow {
                    label: i18n("Previous deployment (rollback)")
                    value: bootc.available && bootc.rollbackPresent ? bootc.rollbackVersion : ""
                    detail: bootc.available && bootc.rollbackPresent
                        ? i18n("Available for recovery (see System updates → Recovery).")
                        : ""
                }
                InfoRow {
                    label: i18n("SELinux")
                    value: deviceInfo.ready ? root.selinuxText() : i18n("Collecting…")
                }
            }
        }

        SectionHeading {
            text: i18n("About this distribution")
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("Enthroned OS is its own Linux distribution with a bootable image infrastructure based on Fedora Linux (Kinoite), KDE Plasma and the bootc/OCI model with atomic updates and rollback. The experience draws on the simplicity of Zorin OS and the familiarity of Windows 11, with its own identity and code. No compatibility with Windows applications or drivers is promised.")
        }

        SectionHeading {
            text: i18n("Documentation and licensing")
        }
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                InfoRow {
                    label: i18n("Bundled documentation")
                    value: i18n("/usr/share/doc/enthroned-os (when installed)")
                }
                InfoRow {
                    label: i18n("License of the original code")
                    value: i18n("To be defined (pending product decision)")
                    detail: i18n("Third parties: see docs/licensing/THIRD-PARTY.md in the project repository.")
                }
                InfoRow {
                    label: i18n("Project")
                    value: "Enthroned OS"
                    detail: i18n("Immutable desktop system based on bootc/OCI and KDE Plasma.")
                }
            }
        }
    }
}
