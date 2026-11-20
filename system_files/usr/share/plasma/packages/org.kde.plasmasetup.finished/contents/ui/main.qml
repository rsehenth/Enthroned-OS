// Enthroned OS first-boot setup completion page.
// Derived from plasma-setup org.kde.plasmasetup.finished (GPL-2.0-or-later),
// customized to present Enthroned OS identity without Aurora/Konqi mascots.
//
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.plasmasetup.components as PlasmaSetupComponents
import org.kde.plasmasetup

PlasmaSetupComponents.SetupModule {
    id: root

    nextEnabled: true

    property string existingUserFinishedMessage: i18nc(
        "%1 is the distro name",
        "Your device is now ready.<br /><br />Enjoy <b>%1</b>!",
        InitialStartUtil.distroName
    )

    property string newUserFinishedMessage: i18nc(
        "%1 is the distro name",
        "Your device is now ready.<br /><br />After clicking <b>Finish</b> you will be able to sign in to your new account.<br /><br />Enjoy <b>%1</b>!",
        InitialStartUtil.distroName
    )

    contentItem: ColumnLayout {
        id: mainColumn

        ColumnLayout {
            Layout.alignment: Qt.AlignCenter
            spacing: Kirigami.Units.largeSpacing

            // Lote 13: the owner's original "E" mark (installed hicolor icon).
            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                source: "org.enthroned.enthroned-os"
            }

            Label {
                id: finishedMessage
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                text: AccountController.hasExistingUsers
                        ? root.existingUserFinishedMessage
                        : root.newUserFinishedMessage
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
