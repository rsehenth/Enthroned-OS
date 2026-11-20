/*
 * Enthroned Settings - main window (Lote 4: general settings hub).
 * Native Qt Quick/Kirigami. Twelve areas in a left navigation; the pages are
 * created on demand by the Loader. Search is local (search.js over the
 * in-memory SearchIndex). Narrow windows collapse the navigation to icons.
 * All colors come from the active Enthroned color scheme (none hardcoded).
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "pages"
import "search.js" as Search

Kirigami.ApplicationWindow {
    id: root

    width: 1120
    height: 740
    minimumWidth: Kirigami.Units.gridUnit * 28
    minimumHeight: Kirigami.Units.gridUnit * 24
    title: i18n("Enthroned Settings")

    // Gate 13.1: each page is introduced by the header below, so the empty
    // global toolbar (a blank 45 px strip) is not needed.
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    // Under this width the navigation shows icons only (toggle with the menu button).
    readonly property bool compact: width < Kirigami.Units.gridUnit * 42
    property bool navExpanded: false
    readonly property bool navCollapsed: compact && !navExpanded

    readonly property var pageModel: [
        // --- Modo Simples (default): primary areas ---
        { id: "home", title: i18n("Home"), icon: "go-home", component: homeComponent,
          keywords: i18n("home overview summary dashboard overview") },
        { id: "appearance", title: i18n("Personalization"), icon: "preferences-desktop-theme", component: appearanceComponent,
          keywords: i18n("personalization appearance profile classic modern light dark theme wallpaper colors") },
        { id: "display", title: i18n("Display & resolution"), icon: "preferences-desktop-display", component: displayComponent,
          keywords: i18n("display monitor resolution scale brightness night light screen"), simple: true },
        { id: "sound", title: i18n("Sound"), icon: "audio-card", component: soundComponent,
          keywords: i18n("sound audio volume speaker microphone headset"), simple: true },
        { id: "notifications", title: i18n("Notifications"), icon: "preferences-desktop-notification", component: notificationsComponent,
          keywords: i18n("notifications do not disturb alerts"), simple: true },
        { id: "updates", title: i18n("System updates"), icon: "update-none", component: updatesComponent,
          keywords: i18n("system updates update check bootc uupd flatpak version restart") },
        // --- Modo Avançado: every area, reachable through the toggle and search ---
        { id: "system", title: i18n("System"), icon: "computer", component: systemComponent,
          keywords: i18n("system display sound power notifications automatic update"), advanced: true },
        { id: "devices", title: i18n("Bluetooth & devices"), icon: "preferences-system-bluetooth", component: devicesComponent,
          keywords: i18n("bluetooth devices mouse keyboard touchpad printers"), advanced: true },
        { id: "network", title: i18n("Network & Internet"), icon: "network-wireless", component: networkComponent,
          keywords: i18n("network internet wifi wi-fi ethernet vpn connection"), advanced: true },
        { id: "apps", title: i18n("Applications"), icon: "applications-other", component: appsComponent,
          keywords: i18n("applications programs default store discover flatpak"), advanced: true },
        { id: "accounts", title: i18n("Accounts"), icon: "system-users", component: accountsComponent,
          keywords: i18n("accounts user password login"), advanced: true },
        { id: "time", title: i18n("Time & language"), icon: "preferences-system-time", component: timeComponent,
          keywords: i18n("time language date zone region formats"), advanced: true },
        { id: "accessibility", title: i18n("Accessibility"), icon: "preferences-desktop-accessibility", component: accessibilityComponent,
          keywords: i18n("accessibility screen reader magnifier text contrast"), advanced: true },
        { id: "privacy", title: i18n("Privacy & security"), icon: "security-high", component: privacyComponent,
          keywords: i18n("privacy security locking selinux wallet firewall"), advanced: true },
        { id: "about", title: i18n("About this device"), icon: "help-about", component: aboutComponent,
          keywords: i18n("about version license identity specifications hardware"), advanced: true }
    ]

    // Modo Simples shows only the primary areas; the toggle below the
    // navigation reveals every area. Search always covers all of them.
    readonly property var visiblePages: preferences.advancedSettingsMode
        ? pageModel
        : pageModel.filter(page => !page.advanced)

    // Gate 13.1: pages and their header share one reading width; wider
    // windows get equal side insets instead of stretched cards.
    readonly property real contentMaxWidth: Kirigami.Units.gridUnit * 56
    readonly property real contentInset: Math.max(Kirigami.Units.gridUnit,
                                                   (pageLoader.width - contentMaxWidth) / 2)

    property string currentPageId: "home"
    property string searchFilter: ""

    readonly property bool searching: !navCollapsed && searchFilter.trim().length > 0
    readonly property var searchResults: Search.run(searchIndex.entries, searchFilter, 30)

    SearchIndex {
        id: searchIndex
        pages: root.pageModel
    }

    function goTo(pageId) {
        currentPageId = pageId;
        if (compact) {
            navExpanded = false;
        }
    }

    function currentModuleFor(entry) {
        if (entry.ids === undefined || !kcm.toolPresent) {
            return "";
        }
        const listed = kcm.available;
        for (let i = 0; i < entry.ids.length; i++) {
            if (listed.indexOf(entry.ids[i]) !== -1) {
                return entry.ids[i];
            }
        }
        return "";
    }

    // Module entries open the native KDE module directly when it exists, and
    // always show the related page behind it (which explains any absence).
    function openEntry(entry) {
        const module = currentModuleFor(entry);
        if (module.length > 0) {
            kcm.launch(module);
        }
        goTo(entry.page);
        searchField.text = "";
    }

    function componentFor(pageId) {
        for (let i = 0; i < pageModel.length; i++) {
            if (pageModel[i].id === pageId) {
                return pageModel[i].component;
            }
        }
        return pageModel[0].component;
    }

    Component { id: homeComponent; HomePage {} }
    Component { id: systemComponent; SystemPage {} }
    Component { id: devicesComponent; DevicesPage {} }
    Component { id: networkComponent; NetworkPage {} }
    Component { id: appearanceComponent; AppearancePage {} }
    Component { id: appsComponent; AppsPage {} }
    Component { id: accountsComponent; AccountsPage {} }
    Component { id: timeComponent; TimeLanguagePage {} }
    Component { id: accessibilityComponent; AccessibilityPage {} }
    Component { id: privacyComponent; PrivacyPage {} }
    Component { id: updatesComponent; UpdatesPage {} }
    Component { id: aboutComponent; AboutPage {} }
    // Modo Simples: one focused page per primary area (no page duplication).
    Component { id: displayComponent; FocusPage {
        focusTitle: i18n("Display & resolution")
        focusIcon: "preferences-desktop-display"
        focusDescription: i18n("Monitors, resolution, scale and night light.")
        focusModuleIds: ["kcm_kscreen", "kcm_displayconfiguration"]
    } }
    Component { id: soundComponent; FocusPage {
        focusTitle: i18n("Sound")
        focusIcon: "audio-card"
        focusDescription: i18n("Audio devices and volumes.")
        focusModuleIds: ["kcm_pulseaudio"]
    } }
    Component { id: notificationsComponent; FocusPage {
        focusTitle: i18n("Notifications")
        focusIcon: "preferences-desktop-notification"
        focusDescription: i18n("Notification preferences per application.")
        focusModuleIds: ["kcm_notifications"]
    } }

    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: {
            root.navExpanded = true;
            Qt.callLater(searchField.forceActiveFocus);
        }
    }

    Connections {
        target: kcm
        function onLaunched(ok, module) {
            if (!ok) {
                root.showPassiveNotification(i18n("Could not open the KDE module %1.", module));
            }
        }
    }

    // Lote 6: returning to Modo Simples never leaves the user stranded on an
    // advanced page — the Home page is shown instead.
    Connections {
        target: preferences
        function onAdvancedSettingsModeChanged() {
            if (preferences.advancedSettingsMode) {
                return;
            }
            for (let i = 0; i < root.pageModel.length; i++) {
                if (root.pageModel[i].id === root.currentPageId && root.pageModel[i].advanced) {
                    root.goTo("home");
                    return;
                }
            }
        }
    }

    pageStack.initialPage: Kirigami.Page {
        padding: 0
        contentItem: RowLayout {
            spacing: 0

            // --- Sidebar (navigation) ---
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: root.navCollapsed
                    ? Kirigami.Units.gridUnit * 3.5
                    : Kirigami.Units.gridUnit * 14
                color: Kirigami.Theme.alternateBackgroundColor

                Kirigami.Separator {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.navCollapsed ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.ToolButton {
                            visible: root.compact
                            icon.name: "application-menu"
                            onClicked: root.navExpanded = !root.navExpanded
                            Accessible.name: i18n("Show or hide the navigation")
                            QQC2.ToolTip.text: Accessible.name
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        Kirigami.Icon {
                            visible: !root.navCollapsed
                            source: "org.enthroned.enthroned-os"
                            implicitWidth: Kirigami.Units.iconSizes.medium
                            implicitHeight: Kirigami.Units.iconSizes.medium
                        }
                        Kirigami.Heading {
                            visible: !root.navCollapsed
                            level: 3
                            text: i18n("Settings")
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Kirigami.SearchField {
                        id: searchField
                        visible: !root.navCollapsed
                        Layout.fillWidth: true
                        placeholderText: i18n("Search settings")
                        onTextChanged: root.searchFilter = text
                        onAccepted: {
                            if (root.searchResults.length > 0) {
                                root.openEntry(root.searchResults[0]);
                            }
                        }
                        Keys.onDownPressed: if (resultsList.count > 0) resultsList.forceActiveFocus()
                        Keys.onEscapePressed: text = ""
                        Accessible.name: placeholderText
                    }
                    QQC2.ToolButton {
                        visible: root.navCollapsed
                        Layout.alignment: Qt.AlignHCenter
                        icon.name: "edit-find"
                        onClicked: {
                            root.navExpanded = true;
                            Qt.callLater(searchField.forceActiveFocus);
                        }
                        Accessible.name: i18n("Search settings")
                        QQC2.ToolTip.text: Accessible.name
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    // Lote 6: collapsed-mode toggle for the advanced areas.
                    QQC2.ToolButton {
                        visible: root.navCollapsed
                        Layout.alignment: Qt.AlignHCenter
                        icon.name: preferences.advancedSettingsMode ? "view-collapse" : "preferences-system"
                        onClicked: preferences.advancedSettingsMode = !preferences.advancedSettingsMode
                        Accessible.name: preferences.advancedSettingsMode
                            ? i18n("Hide advanced settings")
                            : i18n("Show advanced settings")
                        QQC2.ToolTip.text: Accessible.name
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    // Page navigation (Modo Simples by default; the toggle at
                    // the bottom reveals the advanced areas).
                    ListView {
                        id: navList
                        visible: !root.searching
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.visiblePages
                        currentIndex: -1
                        activeFocusOnTab: true
                        keyNavigationEnabled: true
                        keyNavigationWraps: true
                        spacing: Kirigami.Units.smallSpacing
                        Keys.onReturnPressed: if (currentItem) currentItem.clicked()
                        Keys.onEnterPressed: if (currentItem) currentItem.clicked()
                        Accessible.role: Accessible.List
                        Accessible.name: i18n("Settings areas")

                        delegate: QQC2.ItemDelegate {
                            id: navItem
                            required property var modelData
                            required property int index
                            width: navList.width
                            highlighted: root.currentPageId === modelData.id
                            hoverEnabled: true
                            leftPadding: Kirigami.Units.largeSpacing
                            rightPadding: Kirigami.Units.largeSpacing
                            // Lote 13: >= 36 px tall (design token control "touch")
                            // so navigation is comfortable with pointer and touch.
                            topPadding: Kirigami.Units.smallSpacing * 2
                            bottomPadding: Kirigami.Units.smallSpacing * 2
                            readonly property bool keyFocus: navItem.visualFocus
                                || (navList.activeFocus && navList.currentIndex === index)

                            // One state layer (hover / selected / pressed), an accent bar so
                            // selection does not rely on color alone, and a focus ring.
                            background: Item {
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Kirigami.Units.smallSpacing * 1.5
                                    color: Kirigami.Theme.highlightColor
                                    opacity: navItem.down ? 0.22 : (navItem.highlighted ? 0.16 : (navItem.hovered ? 0.10 : 0))
                                    Behavior on opacity {
                                        NumberAnimation { duration: Kirigami.Units.shortDuration }
                                    }
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Kirigami.Units.smallSpacing / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Kirigami.Units.smallSpacing * 0.75
                                    height: parent.height * 0.5
                                    radius: width / 2
                                    color: Kirigami.Theme.highlightColor
                                    visible: navItem.highlighted
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Kirigami.Units.smallSpacing * 1.5
                                    color: "transparent"
                                    border.width: Kirigami.Units.smallSpacing / 2
                                    border.color: Kirigami.Theme.focusColor
                                    visible: navItem.keyFocus
                                }
                            }

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.largeSpacing
                                Kirigami.Icon {
                                    source: navItem.modelData.icon
                                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                    Layout.alignment: root.navCollapsed ? Qt.AlignHCenter : Qt.AlignLeft
                                    Layout.fillWidth: root.navCollapsed
                                }
                                QQC2.Label {
                                    visible: !root.navCollapsed
                                    text: navItem.modelData.title
                                    elide: Text.ElideRight
                                    font.bold: navItem.highlighted
                                    Layout.fillWidth: true
                                }
                            }

                            QQC2.ToolTip.text: modelData.title
                            QQC2.ToolTip.visible: root.navCollapsed && hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

                            onClicked: {
                                root.goTo(modelData.id);
                                navList.currentIndex = index;
                            }

                            Accessible.name: modelData.title
                            Accessible.role: Accessible.MenuItem
                        }
                    }

                    Kirigami.Separator {
                        visible: !root.navCollapsed
                        Layout.fillWidth: true
                    }

                    // Lote 6: easily identifiable control between Modo
                    // Simples (default) and Modo Avançado. The choice is
                    // remembered per user in enthroned-os/preferences.conf.
                    QQC2.ItemDelegate {
                        visible: !root.navCollapsed
                        Layout.fillWidth: true
                        hoverEnabled: true
                        highlighted: preferences.advancedSettingsMode
                        leftPadding: Kirigami.Units.largeSpacing
                        topPadding: Kirigami.Units.smallSpacing * 1.5
                        bottomPadding: Kirigami.Units.smallSpacing * 1.5

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.largeSpacing
                            Kirigami.Icon {
                                source: preferences.advancedSettingsMode ? "view-collapse" : "preferences-system"
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                            }
                            QQC2.Label {
                                text: preferences.advancedSettingsMode
                                    ? i18n("Hide advanced settings")
                                    : i18n("Show advanced settings")
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Kirigami.Icon {
                                source: preferences.advancedSettingsMode ? "dialog-ok-apply" : "arrow-down"
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                                Accessible.ignored: true
                            }
                        }

                        Accessible.role: Accessible.Button
                        Accessible.name: preferences.advancedSettingsMode
                            ? i18n("Hide advanced settings")
                            : i18n("Show advanced settings")

                        onClicked: preferences.advancedSettingsMode = !preferences.advancedSettingsMode
                    }

                    // Search results
                    ListView {
                        id: resultsList
                        visible: root.searching
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.searchResults
                        currentIndex: 0
                        activeFocusOnTab: true
                        keyNavigationEnabled: true
                        spacing: Kirigami.Units.smallSpacing
                        Keys.onReturnPressed: if (currentItem) currentItem.clicked()
                        Keys.onEnterPressed: if (currentItem) currentItem.clicked()
                        Keys.onEscapePressed: searchField.text = ""
                        Accessible.role: Accessible.List
                        Accessible.name: i18n("Search results")

                        delegate: QQC2.ItemDelegate {
                            id: resultItem
                            required property var modelData
                            required property int index
                            width: resultsList.width
                            hoverEnabled: true
                            highlighted: resultsList.activeFocus && resultsList.currentIndex === index
                            readonly property bool opensModule: root.currentModuleFor(modelData).length > 0

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.largeSpacing
                                Kirigami.Icon {
                                    source: resultItem.modelData.icon
                                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    QQC2.Label {
                                        text: resultItem.modelData.title
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    QQC2.Label {
                                        visible: resultItem.modelData.pageTitle.length > 0
                                        text: resultItem.modelData.pageTitle
                                        elide: Text.ElideRight
                                        color: Kirigami.Theme.disabledTextColor
                                        font: Kirigami.Theme.smallFont
                                        Layout.fillWidth: true
                                    }
                                    // Lote 6: in Modo Simples, results that
                                    // belong to the advanced areas carry a
                                    // clear badge (they still open normally).
                                    QQC2.Label {
                                        visible: resultItem.modelData.advanced === true
                                            && !preferences.advancedSettingsMode
                                        text: i18n("Advanced")
                                        elide: Text.ElideRight
                                        color: Kirigami.Theme.disabledTextColor
                                        font: Kirigami.Theme.smallFont
                                        Layout.fillWidth: true
                                    }
                                }
                                Kirigami.Icon {
                                    visible: resultItem.opensModule
                                    source: "window-open"
                                    implicitWidth: Kirigami.Units.iconSizes.small
                                    implicitHeight: Kirigami.Units.iconSizes.small
                                }
                            }

                            onClicked: root.openEntry(modelData)

                            Accessible.name: resultItem.opensModule
                                ? i18n("%1, opens the KDE module", modelData.title)
                                : modelData.title
                            Accessible.role: Accessible.MenuItem
                        }

                        QQC2.Label {
                            anchors.centerIn: parent
                            visible: resultsList.count === 0
                            width: parent.width - Kirigami.Units.largeSpacing * 2
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: i18n("No settings found")
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }

                    QQC2.Label {
                        visible: !root.navCollapsed
                        Layout.fillWidth: true
                        text: identity.productVersion.length > 0
                            ? i18n("Enthroned OS %1 · channel %2", identity.productVersion, identity.channel)
                            : i18n("Enthroned OS · identity unavailable")
                        elide: Text.ElideRight
                        color: Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont
                        leftPadding: Kirigami.Units.largeSpacing
                    }
                }
            }

            // --- Content column ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.largeSpacing
                    visible: updates.demoMode
                    type: Kirigami.MessageType.Warning
                    icon.name: "data-warning"
                    text: i18n("Demo mode — no update will run. The data shown is fictional.")
                    showCloseButton: false
                }

                // Gate 13.1: active area header, aligned with the page content.
                RowLayout {
                    id: pageHeader
                    readonly property var entry: root.pageModel.find(page => page.id === root.currentPageId)
                    Layout.fillWidth: true
                    Layout.leftMargin: root.contentInset
                    Layout.rightMargin: root.contentInset
                    Layout.topMargin: Kirigami.Units.gridUnit
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        source: pageHeader.entry ? pageHeader.entry.icon : ""
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        Accessible.ignored: true
                    }
                    Kirigami.Heading {
                        level: 1
                        text: pageHeader.entry ? pageHeader.entry.title : ""
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Accessible.role: Accessible.Heading
                    }
                }

                // Pages are instantiated on demand and released when another is chosen.
                Loader {
                    id: pageLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: root.componentFor(root.currentPageId)
                }
            }
        }
    }
}
