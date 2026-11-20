/*
 * Enthroned Welcome - step 5: honest summary (F4.5 tela 5).
 * Only real, detected states are shown; a pending optional install is
 * reported as pending, never as done. Finishing records the completed phase
 * and stops future autostarts.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    function profileText() {
        if (profiles.activeLabel.length > 0) {
            return profiles.activeLabel;
        }
        return i18n("Plasma default (no Enthroned profile applied)");
    }

    function artcraftText() {
        if (welcome.artcraftInstallState === "done") {
            return i18n("Installed");
        }
        if (welcome.artcraftInstallState === "failed") {
            return i18n("Installation not finished — you can try again later from Settings");
        }
        if (welcome.artcraftConsented) {
            return i18n("Pending — you chose to install; finish later from Settings or by reopening this assistant");
        }
        return i18n("Not requested (optional)");
    }

    function braveText() {
        return apps.braveAvailable
            ? i18n("Installed — default browser")
            : i18n("Pending — it will be installed automatically once there is a connection, or from the store");
    }

    function discoverText() {
        return apps.discoverAvailable
            ? i18n("Installed — app store")
            : i18n("Not found on this system");
    }

    Kirigami.Heading {
        level: 2
        text: i18n("All set")
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: i18n("Summary of your choices:")
    }

    Kirigami.AbstractCard {
        Layout.fillWidth: true
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            InfoRow { label: i18n("Appearance profile"); value: root.profileText() }
            Kirigami.Separator { Layout.fillWidth: true }
            InfoRow {
                label: i18n("Browser (Brave)")
                value: root.braveText()
                statusIcon: apps.braveAvailable ? "dialog-ok-apply" : "chronometer"
                statusColor: apps.braveAvailable ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
            }
            Kirigami.Separator { Layout.fillWidth: true }
            InfoRow {
                label: i18n("App store (KDE Discover)")
                value: root.discoverText()
                statusIcon: apps.discoverAvailable ? "dialog-ok-apply" : "dialog-information"
                statusColor: apps.discoverAvailable ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
            }
            Kirigami.Separator { Layout.fillWidth: true }
            InfoRow {
                label: i18n("ArtCraft Launcher (optional)")
                value: root.artcraftText()
                statusIcon: welcome.artcraftInstallState === "done" ? "dialog-ok-apply"
                    : (welcome.artcraftInstallState === "failed" ? "dialog-error"
                        : (welcome.artcraftConsented ? "chronometer" : ""))
                statusColor: welcome.artcraftInstallState === "done" ? Kirigami.Theme.positiveTextColor
                    : (welcome.artcraftInstallState === "failed" ? Kirigami.Theme.negativeTextColor
                        : Kirigami.Theme.neutralTextColor)
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.disabledTextColor
        text: i18n("You can open the store to install more applications, reopen this assistant from Enthroned Settings and adjust any option later — nothing here is final.")
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.alignment: Qt.AlignHCenter

        QQC2.Button {
            visible: apps.discoverAvailable
            text: i18n("Open the app store")
            icon.name: "system-software-install"
            onClicked: apps.launchDiscover()
            Accessible.description: i18n("Opens the KDE Discover app store")
        }
    }

    component InfoRow: RowLayout {
        id: row
        property string label
        property string value
        // Optional status mark: only set from real, detected states. The value
        // text always states the status too, so color/icon never stand alone.
        property string statusIcon: ""
        property color statusColor: Kirigami.Theme.textColor
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            text: row.label
            font.bold: true
            wrapMode: Text.WordWrap
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            Layout.maximumWidth: Kirigami.Units.gridUnit * 12
            Layout.alignment: Qt.AlignTop
        }
        Kirigami.Icon {
            // Keeps the value column aligned across rows when no mark applies.
            opacity: row.statusIcon.length > 0 ? 1 : 0
            source: row.statusIcon
            color: row.statusColor
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            implicitHeight: Kirigami.Units.iconSizes.smallMedium
            Layout.alignment: Qt.AlignTop
            Accessible.ignored: true
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: row.value
        }
    }
}
