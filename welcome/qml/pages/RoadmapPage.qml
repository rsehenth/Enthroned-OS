/*
 * Enthroned Welcome - Lote 5: product vision & roadmap presentation page.
 * Read-only showcase communicating what Enthroned OS is building, its UX
 * pillars, planned device integration, and realistic future direction.
 * Uses only active Kirigami.Theme colors (no hardcoded colors) and i18n().
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    signal openOnboarding()

    readonly property bool twoColumns: width >= Kirigami.Units.gridUnit * 34
    readonly property bool fourColumns: width >= Kirigami.Units.gridUnit * 42

    spacing: Kirigami.Units.largeSpacing

    // --- A. Visão do Enthroned OS ---
    Kirigami.AbstractCard {
        Layout.fillWidth: true
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "org.enthroned.enthroned-os"
                    implicitWidth: Kirigami.Units.iconSizes.huge
                    implicitHeight: Kirigami.Units.iconSizes.huge
                    Layout.alignment: Qt.AlignTop
                    Accessible.ignored: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        level: 1
                        text: i18n("The Enthroned OS vision")
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: i18n("A Linux desktop designed to deliver a modern experience, ease of use and a refined look on top of Fedora's powerful base — always focused on user experience.")
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.fourColumns ? 4 : (root.twoColumns ? 2 : 1)
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: [
                        { icon: "preferences-desktop-theme", label: i18n("Modern experience") },
                        { icon: "dialog-ok-apply", label: i18n("Ease of use") },
                        { icon: "computer", label: i18n("Powerful Fedora base") },
                        { icon: "preferences-system-windows", label: i18n("Looks and UX focus") }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: pillarRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: Kirigami.Units.smallSpacing * 1.5
                        color: Kirigami.Theme.alternateBackgroundColor

                        // Height follows the content (top/left/right anchors),
                        // never the grid row (Lote 13).
                        RowLayout {
                            id: pillarRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: modelData.icon
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                                Accessible.ignored: true
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: modelData.label
                                elide: Text.ElideRight
                                font.bold: true
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Grupo 1: Em desenvolvimento (B, G, D, E) ---
    SectionHeader {
        title: i18n("In development")
        subtitle: i18n("Pillars already taking shape in the system's current experience.")
    }

    GridLayout {
        Layout.fillWidth: true
        columns: root.twoColumns ? 2 : 1
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.largeSpacing

        RoadmapCard {
            Layout.fillHeight: true
            iconName: "preferences-system-windows"
            title: i18n("Interface and experience")
            statusText: i18n("In development")
            statusTone: "active"
            summary: i18n("An organization designed to make life easier for new users from the very first login.")
            points: [
                i18n("Intuitive, straightforward Start menu"),
                i18n("Settings brought together in one place"),
                i18n("A more familiar file manager")
            ]
        }

        RoadmapCard {
            Layout.fillHeight: true
            iconName: "preferences-desktop-theme"
            title: i18n("Profiles and personalization")
            statusText: i18n("In development")
            statusTone: "active"
            summary: i18n("Classic and Modern profiles to adapt the desktop to different styles of use.")
            points: [
                i18n("Classic: light look with a traditional panel"),
                i18n("Modern: dark look with a centered dock"),
                i18n("Personalization designed for the way you use it")
            ]
        }

        RoadmapCard {
            Layout.fillHeight: true
            iconName: "computer"
            title: i18n("Performance and optimization")
            statusText: i18n("In development")
            statusTone: "active"
            summary: i18n("Smooth flow and less friction in daily use on a modern Fedora-inspired base.")
            points: [
                i18n("A tidy, responsive desktop for everyday use"),
                i18n("Fewer manual steps in common tasks"),
                i18n("An up-to-date base for work and creation")
            ]
        }

        RoadmapCard {
            Layout.fillHeight: true
            iconName: "update-none"
            title: i18n("Simplified updates")
            statusText: i18n("In development")
            statusTone: "active"
            summary: i18n("Update the system from Settings, reducing the reliance on the terminal.")
            points: [
                i18n("A simple, understandable visual experience"),
                i18n("A clear view of what is up to date"),
                i18n("Security and reliability preserved")
            ]
        }
    }

    // --- Grupo 2: Próximos passos (C) ---
    SectionHeader {
        title: i18n("Next steps")
        subtitle: i18n("Planned features to make using peripherals more natural.")
    }

    Kirigami.AbstractCard {
        Layout.fillWidth: true
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "audio-card"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                    Accessible.ignored: true
                }
                Kirigami.Heading {
                    level: 4
                    text: i18n("Intelligent Device Manager")
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                StatusChip {
                    label: i18n("Planned")
                    tone: "planned"
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("The goal is to recognize compatible peripherals automatically and enable extra features without workarounds, bringing controls together in a clear interface.")
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.twoColumns ? 2 : 1
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.bold: true
                        text: i18n("What this step aims to deliver")
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Kirigami.Theme.disabledTextColor
                        text: i18n("• Automatic recognition of compatible peripherals")
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Kirigami.Theme.disabledTextColor
                        text: i18n("• Centralized controls for headsets, spatial audio, special controllers and presets")
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Kirigami.Theme.disabledTextColor
                        text: i18n("• Fewer manual adjustments scattered across the system")
                    }
                }

                // Lote 13: the box height is derived from its own content
                // (anchored to the top/left/right only, never stretched by
                // the grid row), so the card no longer shows a tall blank
                // area next to the bullet list.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: exampleBox.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: Kirigami.Units.smallSpacing * 2
                    color: Kirigami.Theme.alternateBackgroundColor

                    RowLayout {
                        id: exampleBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "audio-headphones"
                            implicitWidth: Kirigami.Units.iconSizes.medium
                            implicitHeight: Kirigami.Units.iconSizes.medium
                            Layout.alignment: Qt.AlignTop
                            Accessible.ignored: true
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.bold: true
                                text: i18n("Example: headphones with spatial audio")
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Kirigami.Theme.disabledTextColor
                                text: i18n("When you plug in headphones that support spatial audio, the project's goal is for the system to detect the model and automatically present those extra features so you can adjust them on the spot.")
                            }
                        }
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
                text: i18n("Project vision: the available controls depend on each device's compatibility, without promising universal support.")
            }
        }
    }

    // --- Grupo 3: Visão futura (F, H) ---
    SectionHeader {
        title: i18n("Future vision")
        subtitle: i18n("Long-term ambitions to broaden what the desktop can do.")
    }

    Kirigami.AbstractCard {
        Layout.fillWidth: true
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "applications-other"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                    Accessible.ignored: true
                }
                Kirigami.Heading {
                    level: 4
                    text: i18n("Enthroned Compatibility Engine")
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                StatusChip {
                    label: i18n("Future vision")
                    tone: "future"
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("An important future step to broaden compatibility with Windows 10/11 programs and simplify installing and using compatible applications.")
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                text: i18n("• Simplify installing and running compatible Windows programs")
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                text: i18n("• Pursue the broadest possible compatibility for everyday software")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: true
                type: Kirigami.MessageType.Information
                icon.name: "dialog-information"
                text: i18n("Realistic scope: the focus is not to promise universal support. Drivers, antivirus and software deeply tied to the Windows kernel may be out of scope.")
            }
        }
    }

    // --- H. Visão futura: fechamento ---
    Kirigami.AbstractCard {
        Layout.fillWidth: true
        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: "org.enthroned.enthroned-os"
                implicitWidth: Kirigami.Units.iconSizes.large
                implicitHeight: Kirigami.Units.iconSizes.large
                Layout.alignment: Qt.AlignTop
                Accessible.ignored: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    level: 3
                    text: i18n("A simpler, more powerful and more intuitive system")
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: i18n("The future vision of Enthroned OS is to deliver a more beautiful, friendlier Linux for users coming from Windows — balancing a modern base, a refined experience and compatibility.")
                }

                RowLayout {
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Button {
                        text: i18n("Go to getting started")
                        icon.name: "go-previous"
                        onClicked: root.openOnboarding()
                        Accessible.description: i18n("Returns to the first steps of the assistant")
                    }
                }
            }
        }
    }

    // --- Shared inline UI components ---
    component SectionHeader: ColumnLayout {
        id: sec
        property string title
        property string subtitle
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing / 2

        Kirigami.Heading {
            level: 3
            text: sec.title
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        QQC2.Label {
            text: sec.subtitle
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }

    component StatusChip: Rectangle {
        id: chip
        property string label
        // active | planned | future
        property string tone: "active"

        readonly property color chipFg: tone === "active"
            ? Kirigami.Theme.positiveTextColor
            : (tone === "planned" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor)
        readonly property color chipBg: tone === "active"
            ? Kirigami.Theme.positiveBackgroundColor
            : (tone === "planned" ? Kirigami.Theme.neutralBackgroundColor : Kirigami.Theme.alternateBackgroundColor)
        readonly property color chipBorder: tone === "future" ? Kirigami.Theme.disabledTextColor : chipFg

        implicitWidth: chipLabel.implicitWidth + Kirigami.Units.largeSpacing
        implicitHeight: chipLabel.implicitHeight + Kirigami.Units.smallSpacing
        radius: Kirigami.Units.smallSpacing * 1.5
        color: chipBg
        border.width: 1
        border.color: chipBorder
        Accessible.ignored: true

        QQC2.Label {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            font.family: Kirigami.Theme.smallFont.family
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            font.bold: true
            color: chip.chipFg
        }
    }

    component RoadmapCard: Kirigami.AbstractCard {
        id: card
        property string iconName
        property string title
        property string statusText
        property string statusTone: "active"
        property string summary
        property var points: []

        Layout.fillWidth: true

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: card.iconName
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                    Accessible.ignored: true
                }
                Kirigami.Heading {
                    level: 4
                    text: card.title
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                StatusChip {
                    label: card.statusText
                    tone: card.statusTone
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: card.summary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing / 2

                Repeater {
                    model: card.points
                    delegate: QQC2.Label {
                        required property string modelData
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Kirigami.Theme.disabledTextColor
                        text: i18n("• %1", modelData)
                    }
                }
            }
        }
    }
}
