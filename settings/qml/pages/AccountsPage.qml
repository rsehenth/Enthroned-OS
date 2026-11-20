/*
 * Enthroned Settings - Accounts page (Lote 4).
 * Current user from the session environment and the native KDE users module,
 * which owns passwords, photo and login options (no credentials are handled here).
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("Accounts")

    readonly property var modules: [
        { title: i18n("User accounts"), subtitle: i18n("Name, picture, password and login options."),
          icon: "system-users", ids: ["kcm_users"] }
    ]

    Component.onCompleted: kcm.refreshAvailable()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                InfoRow { label: i18n("Current user"); value: deviceInfo.userName }
            }
        }

        ModuleList { modules: root.modules }
    }
}
