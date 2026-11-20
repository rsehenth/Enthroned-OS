/*
 * Enthroned Settings - System page (Lote 4).
 * Shortcuts to the real native KDE modules (display, sound, notifications,
 * power, virtual desktops) plus the read-only automatic update policy (uupd
 * config + timer state). Device and image details live in "Sobre o dispositivo".
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("System")

    function moduleLabel(enabled) {
        return enabled ? i18n("enabled") : i18n("disabled");
    }

    function timerStateText() {
        if (!updates.serviceAvailable) {
            return i18n("Unavailable (systemd D-Bus not reachable)");
        }
        const fileState = updates.autoUpdates.timerFileState;
        if (fileState === undefined || fileState.length === 0) {
            return i18n("Not verified");
        }
        return fileState === "enabled"
            ? i18n("enabled (uupd.timer)")
            : i18n("%1 (uupd.timer)", fileState);
    }

    readonly property var modules: [
        { title: i18n("Display"), subtitle: i18n("Monitors, resolution, scale and night light."),
          icon: "preferences-desktop-display", ids: ["kcm_kscreen", "kcm_displayconfiguration"] },
        { title: i18n("Sound"), subtitle: i18n("Audio devices and volumes."),
          icon: "audio-card", ids: ["kcm_pulseaudio"] },
        { title: i18n("Notifications"), subtitle: i18n("Notification preferences per application."),
          icon: "preferences-desktop-notification", ids: ["kcm_notifications"] },
        { title: i18n("Power and battery"), subtitle: i18n("Sleep, screen off and power saving."),
          icon: "battery", ids: ["kcm_powerdevilprofilesconfig"], optional: true },
        { title: i18n("Virtual desktops"), subtitle: i18n("Number and names of virtual desktops."),
          icon: "preferences-desktop-virtual", ids: ["kcm_kwin_virtualdesktops"], optional: true }
    ]

    Component.onCompleted: kcm.refreshAvailable()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    source: "computer"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: deviceInfo.deviceName
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Kirigami.Theme.disabledTextColor
                        text: identity.productVersion.length > 0
                            ? i18n("%1 %2", identity.productName, identity.productVersion)
                            : i18n("System identity unavailable")
                    }
                }
                QQC2.Button {
                    text: i18n("About this device")
                    icon.name: "help-about"
                    onClicked: applicationWindow().goTo("about")
                }
            }
        }

        ModuleList { modules: root.modules }

        SectionHeading {
            text: i18n("Automatic updates (current policy)")
        }
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: i18n("Enthroned OS uses the system update schedule (uupd.timer). This screen is informational only; the interface does not change the policy at this stage.")
                    color: Kirigami.Theme.disabledTextColor
                }

                InfoRow {
                    label: i18n("Schedule")
                    value: root.timerStateText()
                    detail: updates.autoUpdates.nextElapseUSec !== undefined
                        && updates.autoUpdates.nextElapseUSec > 0
                        ? i18n("Next scheduled run: %1",
                               new Date(Number(updates.autoUpdates.nextElapseUSec)).toLocaleString())
                        : ""
                }
                InfoRow {
                    label: i18n("Last run (timer)")
                    value: updates.autoUpdates.lastTriggerUSec !== undefined
                        && updates.autoUpdates.lastTriggerUSec > 0
                        ? new Date(Number(updates.autoUpdates.lastTriggerUSec)).toLocaleString()
                        : i18n("Not verified")
                }
                InfoRow {
                    label: i18n("uupd modules")
                    value: updates.autoUpdates.configPresent
                        ? i18n("system: %1 · flatpak: %2 · brew: %3 · distrobox: %4",
                               root.moduleLabel(updates.autoUpdates.modules.system),
                               root.moduleLabel(updates.autoUpdates.modules.flatpak),
                               root.moduleLabel(updates.autoUpdates.modules.brew),
                               root.moduleLabel(updates.autoUpdates.modules.distrobox))
                        : ""
                    detail: updates.autoUpdates.configPresent
                        ? i18n("Source: /etc/uupd/config.json (or /usr/lib/uupd/config.json).")
                        : i18n("The uupd configuration was not found on this system.")
                }
                InfoRow {
                    label: i18n("Run automatic update now")
                    value: updates.autoUpdateRunning
                        ? i18n("in progress (uupd.service)")
                        : i18n("not detected")
                }
            }
        }
    }
}
