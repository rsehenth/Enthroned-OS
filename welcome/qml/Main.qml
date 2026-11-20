/*
 * Enthroned Welcome - main window (F4.4/F4.5).
 * Five short steps, keyboard-navigable, all colors from the active Enthroned
 * color scheme. The controller owns progress persistence; closing the window
 * marks the walkthrough interrupted so the next login can resume it.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "components"
import "pages"

Kirigami.ApplicationWindow {
    id: root

    width: 960
    height: 660
    minimumWidth: 720
    minimumHeight: 520
    title: i18n("Welcome to Enthroned OS")

    readonly property list<Component> pageComponents: [
        welcomeComponent, styleComponent, appsComponent, artcraftComponent, finishComponent
    ]
    readonly property var stepTitles: [
        i18n("Welcome"),
        i18n("Your style"),
        i18n("Browser and applications"),
        i18n("Creativity tools"),
        i18n("All set")
    ]
    readonly property bool isFirst: welcome.currentPage === 0
    readonly property bool isLast: welcome.currentPage === welcome.pageCount - 1
    readonly property bool showingRoadmap: viewTabs.currentIndex === 1

    onClosing: function (close) {
        welcome.markClosed();
        close.accepted = true;
    }

    pageStack.initialPage: Kirigami.Page {
        padding: 0
        contentItem: ColumnLayout {
        spacing: 0

        // --- Header: view tabs + step indicator ---
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "org.enthroned.enthroned-os"
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                }
                Kirigami.Heading {
                    level: 4
                    text: root.showingRoadmap ? i18n("Roadmap and system vision") : root.stepTitles[welcome.currentPage]
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                QQC2.TabBar {
                    id: viewTabs
                    Layout.alignment: Qt.AlignVCenter

                    QQC2.TabButton {
                        text: i18n("Getting started")
                        icon.name: "go-home"
                        width: implicitWidth
                        Accessible.description: i18n("Shows the five-step welcome assistant")
                    }
                    QQC2.TabButton {
                        text: i18n("Roadmap")
                        icon.name: "documentinfo"
                        width: implicitWidth
                        Accessible.description: i18n("Presents the vision and next steps of Enthroned OS")
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                visible: !root.showingRoadmap

                StepDots {
                    Layout.fillWidth: true
                    current: welcome.currentPage
                    count: welcome.pageCount
                }
                QQC2.Label {
                    text: i18n("Step %1 of %2", welcome.currentPage + 1, welcome.pageCount)
                    color: Kirigami.Theme.disabledTextColor
                    Accessible.name: text
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // --- Content ---
        QQC2.ScrollView {
            id: scroller
            visible: !root.showingRoadmap
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Kirigami.Units.largeSpacing
            contentWidth: availableWidth

            // F4+: readable measure on wide windows, centered; fills narrow ones.
            Loader {
                id: pageLoader
                width: Math.min(scroller.availableWidth, Kirigami.Units.gridUnit * 42)
                x: (scroller.availableWidth - width) / 2
                sourceComponent: root.pageComponents[welcome.currentPage]
            }
        }

        QQC2.ScrollView {
            id: roadmapScroller
            visible: root.showingRoadmap
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Kirigami.Units.largeSpacing
            contentWidth: availableWidth

            Item {
                width: roadmapScroller.availableWidth
                implicitHeight: roadmapPage.implicitHeight

                RoadmapPage {
                    id: roadmapPage
                    width: Math.min(parent.width, Kirigami.Units.gridUnit * 48)
                    x: Math.max(0, (parent.width - width) / 2)
                    onOpenOnboarding: viewTabs.currentIndex = 0
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // --- Footer navigation ---
        QQC2.Pane {
            Layout.fillWidth: true
            padding: Kirigami.Units.largeSpacing

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: i18n("Skip assistant")
                    onClicked: welcome.dismiss()
                    Accessible.description: i18n("Stops the assistant from opening automatically at login")
                }

                QQC2.Button {
                    text: i18n("Back")
                    icon.name: "go-previous"
                    visible: !root.showingRoadmap && !root.isFirst
                    onClicked: welcome.back()
                    Accessible.description: i18n("Goes back to the previous step")
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    visible: welcome.demoMode
                    text: i18n("Demo mode — no real installation is performed.")
                    color: Kirigami.Theme.neutralTextColor
                    wrapMode: Text.WordWrap
                    Layout.maximumWidth: 320
                }
                QQC2.Button {
                    visible: root.showingRoadmap
                    text: i18n("Back to getting started")
                    icon.name: "go-previous"
                    onClicked: viewTabs.currentIndex = 0
                    Accessible.description: i18n("Returns to the initial setup assistant")
                }
                QQC2.Button {
                    visible: !root.showingRoadmap
                    text: root.isFirst ? i18n("Get started") : (root.isLast ? i18n("Finish") : i18n("Continue"))
                    icon.name: root.isLast ? "dialog-ok-apply" : "go-next"
                    onClicked: root.isLast ? welcome.finish() : welcome.next()
                    Accessible.description: root.isLast
                        ? i18n("Finishes the initial setup and opens the desktop")
                        : i18n("Advances to the next step")
                }
            }
        }
    }
    }

    Component { id: welcomeComponent; WelcomePage {} }
    Component { id: styleComponent; StylePage {} }
    Component { id: appsComponent; AppsPage {} }
    Component { id: artcraftComponent; ArtcraftPage {} }
    Component { id: finishComponent; FinishPage {} }
}
