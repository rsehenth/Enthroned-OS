/*
 * Enthroned Settings - Network and Internet page (Lote 4).
 * Real connectivity state (NetworkManager over D-Bus, read-only) and the
 * native KDE network module for connections. Changing the computer name needs
 * a privileged operation that this application does not perform.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("Network & Internet")

    readonly property var modules: [
        { title: i18n("Network connections"), subtitle: i18n("Wi-Fi, Ethernet, VPN and saved networks."),
          icon: "network-wireless", ids: ["kcm_networkmanagement"] },
        { title: i18n("Proxy"), subtitle: i18n("Network proxy configuration."),
          icon: "preferences-system-network", ids: ["kcm_proxy"], optional: true }
    ]

    Component.onCompleted: kcm.refreshAvailable()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                InfoRow {
                    label: i18n("Connection state")
                    value: !updates.nmAvailable
                        ? i18n("Not verified")
                        : (updates.online ? i18n("Connected") : i18n("No connection"))
                    detail: updates.nmAvailable
                        ? i18n("Reported by NetworkManager (read-only).")
                        : i18n("NetworkManager did not respond in this environment.")
                }
                InfoRow {
                    label: i18n("Network name")
                    value: deviceInfo.deviceName
                    detail: i18n("Changing the computer name requires administrator privileges and is not offered by this interface.")
                }
            }
        }

        ModuleList { modules: root.modules }
    }
}
