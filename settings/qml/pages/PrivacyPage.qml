/*
 * Enthroned Settings - Privacy and security page (Lote 4).
 * Real facts about the running system (SELinux mode, read-only /usr) plus
 * shortcuts to the native KDE privacy modules. No toggle here pretends to
 * secure anything: protection lives in SELinux, the immutable image and the
 * KDE modules linked below.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("Privacy & security")

    function selinuxText() {
        if (!deviceInfo.ready) {
            return i18n("Collecting…");
        }
        switch (deviceInfo.selinux) {
        case "enforcing": return i18n("Active (enforcing)");
        case "permissive": return i18n("Permissive (logs, but does not block)");
        }
        return "";
    }

    function usrText() {
        if (!deviceInfo.ready) {
            return i18n("Collecting…");
        }
        return deviceInfo.usrReadOnly
            ? i18n("Read-only (immutable system)")
            : i18n("Writable");
    }

    readonly property var modules: [
        { title: i18n("Screen locking"), subtitle: i18n("When and how the screen locks."),
          icon: "system-lock-screen", ids: ["kcm_kscreenlocker"] },
        { title: i18n("Password wallet (KWallet)"), subtitle: i18n("Storage for passwords and keys."),
          icon: "kwalletmanager", ids: ["kcm_kwallet", "kcm_kwallet5"], optional: true },
        { title: i18n("Flatpak application permissions"), subtitle: i18n("What each Flatpak application can access."),
          icon: "applications-internet", ids: ["kcm_flatpak"], optional: true },
        { title: i18n("Recent files history"), subtitle: i18n("What the system remembers about files and applications used."),
          icon: "document-open-recent", ids: ["kcm_recentFiles"], optional: true },
        { title: i18n("File search (Baloo)"), subtitle: i18n("Indexing and folders excluded from search."),
          icon: "system-search", ids: ["kcm_baloofile"], optional: true },
        { title: i18n("Firewall"), subtitle: i18n("System network rules."),
          icon: "security-high", ids: ["kcm_firewall"], optional: true }
    ]

    Component.onCompleted: kcm.refreshAvailable()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        SectionHeading {
            text: i18n("System security")
        }
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                InfoRow {
                    label: i18n("SELinux")
                    value: root.selinuxText()
                    detail: deviceInfo.ready && deviceInfo.selinux === "unavailable"
                        ? i18n("The SELinux state could not be read in this environment.")
                        : ""
                }
                InfoRow {
                    label: i18n("File system (/usr)")
                    value: root.usrText()
                    detail: i18n("Enthroned OS is immutable: the system changes through atomic images, not by installing packages on top of the base system.")
                }
            }
        }

        SectionHeading {
            text: i18n("Privacy")
        }
        ModuleList { modules: root.modules }
    }
}
