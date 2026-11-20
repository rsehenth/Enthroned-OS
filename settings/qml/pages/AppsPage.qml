/*
 * Enthroned Settings - Applications page (F3.1).
 * Entry points to REAL native KDE modules (kcmshell6, via ModuleList). Availability is
 * detected at runtime; unavailable modules stay disabled with an honest note.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("Applications")

    readonly property var modules: [
        { title: i18n("Default applications"),
          subtitle: i18n("System defaults for the browser, file manager and more."),
          icon: "preferences-desktop-default-applications", ids: ["kcm_componentchooser"] },
        { title: i18n("Notifications"),
          subtitle: i18n("Notification preferences per application."),
          icon: "preferences-desktop-notification", ids: ["kcm_notifications"] },
        { title: i18n("Startup applications"),
          subtitle: i18n("Programs that start with the session."),
          icon: "system-run", ids: ["kcm_autostart"], optional: true },
        { title: i18n("Flatpak permissions"),
          subtitle: i18n("Permissions of installed Flatpak applications."),
          icon: "applications-internet", ids: ["kcm_flatpak"] }
    ]

    Component.onCompleted: kcm.refreshAvailable()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        ModuleList { modules: root.modules }

        EmptyState {
            Layout.fillWidth: true
            visible: !kcm.toolPresent
            icon: "applications-other"
            title: i18n("No module can be opened in this environment")
            note: i18n("This page only opens native KDE modules; nothing is simulated.")
        }

        SectionHeading {
            text: i18n("Enthroned experience")
        }

        // F4.9: integration with the F4 default applications and the Welcome
        // assistant. Availability is detected at runtime; no dead shortcuts.
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            readonly property bool available: kcm.hasExecutable("plasma-discover")
                || kcm.hasFlatpakApp("org.kde.discover")

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "system-software-install"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: i18n("App store (KDE Discover)")
                        font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: available
                            ? i18n("Search, install and remove applications with KDE Discover.")
                            : i18n("The app store was not found on this system.")
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
                QQC2.Button {
                    text: i18n("Open")
                    icon.name: "system-software-install"
                    enabled: available
                    onClicked: kcm.launchApp("plasma-discover")
                    Accessible.description: i18n("Opens KDE Discover")
                }
            }
        }

        Kirigami.AbstractCard {
            Layout.fillWidth: true
            readonly property bool available: kcm.hasExecutable("enthroned-welcome")

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "org.enthroned.enthroned-os"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: i18n("Reopen Enthroned Welcome")
                        font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: available
                            ? i18n("Revisit the first-experience assistant any time, including the optional installation.")
                            : i18n("The Enthroned Welcome assistant is not installed on this system.")
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
                QQC2.Button {
                    text: i18n("Open")
                    icon.name: "window-open"
                    enabled: available
                    onClicked: kcm.launchApp("enthroned-welcome")
                    Accessible.description: i18n("Reopens the Enthroned Welcome assistant")
                }
            }
        }

        Kirigami.AbstractCard {
            Layout.fillWidth: true
            readonly property bool installed: kcm.hasFlatpakApp("ai.storyteller.artcraft-launcher")

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "applications-graphics"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: i18n("ArtCraft Launcher (optional)")
                        font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: installed
                            ? i18n("Installed on this system (user Flatpak application).")
                            : i18n("Not installed. It is a voluntary option offered by Enthroned Welcome; nothing is installed without consent.")
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
            }
        }

        // Lote 6: preference for automatic desktop shortcuts. Applies to the
        // install flows Enthroned actually integrates with (currently the
        // optional ArtCraft install); Discover installs keep the explicit
        // launcher action "Adicionar à área de trabalho".
        Kirigami.AbstractCard {
            Layout.fillWidth: true

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "user-desktop"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: i18n("Desktop shortcut on install")
                        font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: i18n("Creates a shortcut for the installed application on your desktop. Updates never create or duplicate shortcuts and no personal file is overwritten.")
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
                QQC2.CheckBox {
                    checked: preferences.createDesktopShortcuts
                    onToggled: preferences.createDesktopShortcuts = checked
                    Accessible.name: i18n("Desktop shortcut on install")
                }
            }
        }

        // Lote 6: the image-level preference module that the base ships
        // (hidden from the main System Settings so the Enthroned experience
        // stays clean). Opening it only surfaces the vendor module; nothing
        // here changes drivers or update sources by itself.
        Kirigami.AbstractCard {
            Layout.fillWidth: true
            readonly property bool available: kcm.toolPresent && kcm.available.indexOf("kcm_ublue") !== -1

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "preferences-system"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        text: i18n("System image tweaks (advanced)")
                        font.bold: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: available
                            ? i18n("Opens the tweaks module that ships with the base image. Use it only if you know what you are changing; system preferences remain in the Enthroned pages.")
                            : i18n("The base image tweaks module is not installed on this system.")
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
                QQC2.Button {
                    text: i18n("Open")
                    icon.name: "window-open"
                    enabled: available
                    onClicked: kcm.launch("kcm_ublue")
                    Accessible.description: i18n("Opens the base image tweaks module")
                }
            }
        }
    }
}
