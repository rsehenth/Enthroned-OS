/*
 * Enthroned Launcher — full popup (Lote 3 layout).
 *
 *   +--------------------------------------------------------------+
 *   | [logo] [ Pesquisar no computador                           ] |
 *   +-------------+-----------------------------+------------------+
 *   | Fixados     |  Title of the selected pane |  Locais          |
 *   | Todos os    |  pinned grid  |  app list   |   Pasta pessoal  |
 *   |  aplicativos|  (or search results)        |   Documentos ... |
 *   | ----------- |                             |  Ferramentas     |
 *   | Categorias  |                             |   Arquivos ...   |
 *   +-------------+-----------------------------+------------------+
 *   | [avatar] Name / Enthroned OS            [Bloquear] [Energia] |
 *   +--------------------------------------------------------------+
 *
 * Zorin OS influence: category sidebar and a places column.
 * Windows 11 influence: prominent search, pinned grid, account/power footer.
 * Everything is rendered with native Plasma/Kirigami components and the kicker
 * model contracts verified on Plasma 6.6:
 *   - Sidebar rows (RootModel with showAllApps + favorites placeholder):
 *     0 = Favorites (shown as "Fixados"), 1 = All Applications, 2+ =
 *     application categories (rootmodel.cpp row order).
 *   - Content model: rootModel.favoritesModel (pinned), rootModel.modelForRow(row)
 *     (All Applications and categories; re-read on RootModel::refreshed like
 *     kickoff's ApplicationsPage), runnerModel.modelForRow(0) while searching.
 *   - Shortcuts: XDG folders (QStandardPaths) opened with Qt.openUrlExternally
 *     (KIO default handler) and tools triggered through the application model
 *     (only those really installed).
 *   - Footer: user entry (KUser / kcm_users) and session commands
 *     (SystemModel.trigger) — official APIs only, no custom commands.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.components as KirigamiComponents
import org.kde.coreaddons as KCoreAddons
import org.kde.kcmutils as KCM
import org.kde.config as KConfig
import org.kde.kitemmodels as KItemModels

Item {
    id: fullRep

    //BEGIN Size (never larger than the usable screen area)
    readonly property real availableWidth: Screen.desktopAvailableWidth > 0 ? Screen.desktopAvailableWidth : Kirigami.Units.gridUnit * 80
    readonly property real availableHeight: Screen.desktopAvailableHeight > 0 ? Screen.desktopAvailableHeight : Kirigami.Units.gridUnit * 50
    readonly property real screenMargin: Kirigami.Units.gridUnit * 2

    // Lote 15: 46 -> 50 gridUnits. The H6 list was ~300 px because the Places
    // column shared the spare width (see Layout.fillWidth: false there); with that
    // fixed and 50 gridUnits the application list gets ~27 gridUnits. Still bounded
    // by the screen.
    implicitWidth: Math.min(Kirigami.Units.gridUnit * 50, availableWidth - screenMargin)
    implicitHeight: Math.min(Kirigami.Units.gridUnit * 36, availableHeight - screenMargin)

    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumWidth: Math.min(Kirigami.Units.gridUnit * 30, implicitWidth)
    Layout.minimumHeight: Math.min(Kirigami.Units.gridUnit * 22, implicitHeight)

    // Narrow popup: shortcuts collapse to icons and the sidebar slims down.
    readonly property bool compact: width < Kirigami.Units.gridUnit * 36
    // Lote 15: the Places column drops to icon-only before it can squeeze the
    // application list below ~22 gridUnits (sidebar 11 + places 9.5 + gutters).
    readonly property bool placesCompact: compact || width < Kirigami.Units.gridUnit * 45
    //END

    readonly property int paneMargin: Kirigami.Units.smallSpacing * 2

    // Bumped when RootModel::refreshed fires; modelForRow() is not a tracked
    // binding, so everything derived from it depends on this counter.
    property int modelRevision: 0

    readonly property bool searching: searchField.text.trim().length > 0
    readonly property bool showPinned: !searching && sideBar.currentIndex === 0

    readonly property var categoryModel: {
        fullRep.modelRevision;
        return sideBar.currentIndex > 0 ? dedupeProxy : null;
    }
    // Lote 12: raw model of the selected category (or "All applications").
    readonly property var rawCategoryModel: {
        fullRep.modelRevision;
        return sideBar.currentIndex > 0 ? launcher.rootModel.modelForRow(sideBar.currentIndex) : null;
    }
    readonly property var searchModel: launcher.runnerModel.count > 0 ? launcher.runnerModel.modelForRow(0) : null

    // Lote 12: one visible entry per application storage id. Whatever the
    // cause of a duplicate row (an application exported by more than one
    // installation source), only the first row of each id is shown.
    // Lote 9.2 (H4-003): the predicate is PURE — it re-derives "first row
    // with this id" from the model on every call, so category switches,
    // repeated evaluations and data changes all stay deterministic (the old
    // _seenIds set made re-evaluated rows flip true->false and hid apps
    // after switching categories). Cost is O(rows²) per filter pass, fine
    // for launcher category sizes.
    KItemModels.KSortFilterProxyModel {
        id: dedupeProxy

        sourceModel: fullRep.rawCategoryModel
        readonly property int favRole: sourceModel
            ? sourceModel.KItemModels.KRoleNames.role("favoriteId") : -1

        filterRowCallback: (row, parent) => {
            if (dedupeProxy.favRole < 0) {
                return true;
            }
            const model = dedupeProxy.sourceModel;
            const id = String(model.data(model.index(row, 0, parent), dedupeProxy.favRole) ?? "");
            if (id.length === 0) {
                return true;
            }
            for (let earlier = 0; earlier < row; ++earlier) {
                if (String(model.data(model.index(earlier, 0, parent), dedupeProxy.favRole) ?? "") === id) {
                    return false;
                }
            }
            return true;
        }
    }

    onModelRevisionChanged: {
        dedupeProxy.invalidateFilter();
        pinnedDedupe.invalidateFilter();
    }

    // Lote 11B (H4 P2 / "Brave" duplicado nos Fixados): the pinned grid is
    // deduplicated by the application's CANONICAL identity, not by the
    // favoriteId text alone. kicker's `url` role is the resolved .desktop
    // file (AppEntry::url(), symlink-resolved), so a preferred://browser
    // alias row and a directly pinned "applications:<id>.desktop" row share
    // one URL and collapse into a single tile, while genuinely different
    // installations (Flatpak vs. desktop entry with different files) stay.
    // Display-only: the favorites store keeps every entry and its order.
    // The predicate is pure (re-derived per call, same contract as
    // dedupeProxy above; regression-tested by scripts/test-launcher-pinned-dedupe.mjs).
    KItemModels.KSortFilterProxyModel {
        id: pinnedDedupe

        sourceModel: launcher.rootModel.favoritesModel
        readonly property int favRole: sourceModel
            ? sourceModel.KItemModels.KRoleNames.role("favoriteId") : -1
        readonly property int urlRole: sourceModel
            ? sourceModel.KItemModels.KRoleNames.role("url") : -1

        filterRowCallback: (row, parent) => {
            if (pinnedDedupe.favRole < 0) {
                return true;
            }
            const model = pinnedDedupe.sourceModel;
            const urlRole = pinnedDedupe.urlRole;
            const key = (r) => {
                if (urlRole >= 0) {
                    const url = String(model.data(model.index(r, 0, parent), urlRole) ?? "");
                    if (url.length > 0) {
                        return url;
                    }
                }
                return String(model.data(model.index(r, 0, parent), pinnedDedupe.favRole) ?? "");
            };
            const self = key(row);
            if (self.length === 0) {
                return true;
            }
            for (let earlier = 0; earlier < row; ++earlier) {
                if (key(earlier) === self) {
                    return false;
                }
            }
            return true;
        }
    }

    // Models are only attached to the view that is on screen, so the hidden
    // view never creates delegates.
    readonly property var pinnedModel: showPinned ? pinnedDedupe : null
    readonly property var appModel: searching ? searchModel : (showPinned ? null : categoryModel)
    // var (not Item): count / currentIndex are read dynamically.
    readonly property var activeView: showPinned ? pinnedView : appView

    KCoreAddons.KUser {
        id: kuser
    }

    // Shared context menu / activation logic for every delegate.
    AppActions {
        id: itemActions
    }

    // Folder shortcuts need Qt.labs.platform; see XdgFolders.qml.
    Loader {
        id: xdg
        source: "XdgFolders.qml"
    }

    //BEGIN Quick links
    readonly property var folderLinks: {
        const x = xdg.item;
        if (!x) {
            return [];
        }
        const home = String(x.home);
        const links = [];
        if (home.length > 0) {
            links.push({ icon: "user-home", label: i18n("Home folder"), caption: kuser.loginName, url: x.home });
        }
        const others = [
            { icon: "folder-documents", label: i18n("Documents"), url: x.documents },
            { icon: "folder-download", label: i18n("Downloads"), url: x.downloads },
            { icon: "folder-pictures", label: i18n("Pictures"), url: x.pictures },
        ];
        for (const entry of others) {
            // QStandardPaths falls back to $HOME when a user dir is not
            // configured; a second "home" shortcut would be a lie.
            const path = String(entry.url);
            if (path.length > 0 && path !== home) {
                links.push(entry);
            }
        }
        return links;
    }

    // Tools are only listed when the desktop file is really installed.
    // "id" is the preferred entry; "alt" is an optional fallback used when
    // the preferred one is not installed (keeps the link honest on images
    // without the Enthroned settings hub).
    readonly property var toolDefs: [
        { id: "org.kde.dolphin.desktop", icon: "system-file-manager", label: i18n("Files") },
        { id: "org.enthroned.settings.desktop", alt: "systemsettings.desktop", icon: "preferences-system", label: i18n("Settings") },
        { id: "org.kde.discover.desktop", icon: "plasmadiscover", label: i18n("App store") },
        { id: "org.kde.konsole.desktop", icon: "utilities-terminal", label: i18n("Terminal") },
    ]

    readonly property var toolLinks: {
        fullRep.modelRevision;
        const all = launcher.rootModel.count > 1 ? launcher.rootModel.modelForRow(1) : null;
        if (!all || !all.count) {
            return [];
        }
        const rows = fullRep.rowsByFavoriteId(all);
        const links = [];
        for (const def of fullRep.toolDefs) {
            let used = def.id;
            if (rows[used] === undefined && def.alt !== undefined && rows[def.alt] !== undefined) {
                used = def.alt;
            }
            if (rows[used] !== undefined) {
                links.push({ icon: def.icon, label: def.label, row: rows[used] });
            }
        }
        return links;
    }

    // favoriteId -> row for a whole model (single pass, run on refresh only).
    function rowsByFavoriteId(model): var {
        const role = model.KItemModels.KRoleNames.role("favoriteId");
        const rows = {};
        for (let i = 0; i < model.count; ++i) {
            rows[String(model.data(model.index(i, 0), role))] = i;
        }
        return rows;
    }

    function openFolder(url): void {
        Qt.openUrlExternally(url);
        launcher.expanded = false;
    }

    function launchTool(row): void {
        const all = launcher.rootModel.modelForRow(1);
        if (all && all.trigger(row, "", null)) {
            launcher.expanded = false;
        }
    }

    // Lock button: row of the official "lock-screen" session command.
    readonly property int lockRow: {
        const rows = fullRep.rowsByFavoriteId(launcher.systemModel);
        return rows["lock-screen"] !== undefined ? rows["lock-screen"] : -1;
    }
    //END

    function activateCurrent(view): void {
        itemActions.activate(view, view.currentIndex);
    }

    function resetState(): void {
        searchField.clear();
        sideBar.currentIndex = 0;
    }

    // Escape: first clears the query, then closes the menu.
    Keys.onEscapePressed: event => {
        if (searchField.text.length > 0) {
            searchField.clear();
        } else {
            launcher.expanded = false;
        }
        event.accepted = true;
    }

    Connections {
        target: launcher
        function onExpandedChanged() {
            if (launcher.expanded) {
                searchField.forceActiveFocus();
            } else {
                fullRep.resetState();
            }
        }
    }

    Connections {
        target: launcher.rootModel
        function onRefreshed() {
            fullRep.modelRevision++;
        }
    }

    Component.onCompleted: {
        launcher.rootModel.refresh();
        // The popup may be created already expanded (first open).
        if (launcher.expanded) {
            Qt.callLater(() => searchField.forceActiveFocus());
        }
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        //BEGIN Header: brand + search
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: fullRep.paneMargin
            Layout.rightMargin: fullRep.paneMargin
            Layout.topMargin: fullRep.paneMargin
            spacing: Kirigami.Units.smallSpacing * 2

            // The profile's own start icon (Lote 13: E mark in Classic, throne
            // in Modern, written by the layout script into the applet config).
            // 32 px instead of 22 so the original artwork keeps its detail.
            Kirigami.Icon {
                implicitWidth: Kirigami.Units.iconSizes.medium
                implicitHeight: Kirigami.Units.iconSizes.medium
                Layout.alignment: Qt.AlignVCenter
                source: Plasmoid.icon
                animated: false
                Accessible.ignored: true
            }

            PlasmaExtras.SearchField {
                id: searchField

                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.2
                focus: true
                placeholderText: i18n("Search this computer")
                Accessible.name: placeholderText

                Binding {
                    target: launcher
                    property: "searchField"
                    value: searchField
                    restoreMode: Binding.RestoreNone
                }

                // Arrow keys / Enter drive the visible view while the focus
                // stays in the field, so typing never gets interrupted.
                Keys.priority: Keys.AfterItem
                Keys.forwardTo: [fullRep.activeView]
            }
        }
        //END

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            //BEGIN Sidebar: pinned / all apps / categories
            ListView {
                id: sideBar

                Layout.fillHeight: true
                Layout.preferredWidth: fullRep.compact ? Kirigami.Units.gridUnit * 9.5 : Kirigami.Units.gridUnit * 11
                Layout.leftMargin: fullRep.paneMargin

                model: launcher.rootModel
                currentIndex: 0
                clip: true
                activeFocusOnTab: true
                spacing: Kirigami.Units.smallSpacing / 2
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: true
                Accessible.role: Accessible.List
                Accessible.name: i18n("Categories")

                highlightMoveDuration: 0
                PC3.ScrollBar.vertical: PC3.ScrollBar {}

                delegate: T.ItemDelegate {
                    id: sideItem

                    required property var model
                    required property int index

                    // Extra gap + separator before the first real category
                    // (row 2): "Fixados / Todos" above, categories below.
                    readonly property real groupGap: index === 2 ? Kirigami.Units.smallSpacing * 3 : 0

                    width: ListView.view.width
                    implicitWidth: ListView.view.width
                    implicitHeight: Math.max(implicitContentHeight + topPadding + bottomPadding, Kirigami.Units.gridUnit * 2) + groupGap
                    leftPadding: Kirigami.Units.smallSpacing * 2.5
                    rightPadding: Kirigami.Units.smallSpacing * 2
                    topPadding: Kirigami.Units.smallSpacing * 1.5 + groupGap
                    bottomPadding: Kirigami.Units.smallSpacing * 1.5
                    topInset: groupGap
                    spacing: Kirigami.Units.smallSpacing * 2

                    enabled: model.isSeparator !== true
                    hoverEnabled: true
                    highlighted: ListView.view.currentIndex === index
                    text: index === 0 ? i18n("Pinned")
                        : (index === 1 ? i18n("All applications") : (model.display ?? ""))

                    background: ItemBackground {
                        hovered: sideItem.hovered
                        pressed: sideItem.down
                        selected: sideItem.highlighted
                        focused: sideItem.visualFocus
                        indicator: true
                    }

                    Kirigami.Separator {
                        visible: sideItem.groupGap > 0
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: sideItem.groupGap / 2
                    }

                    contentItem: RowLayout {
                        spacing: sideItem.spacing

                        Kirigami.Icon {
                            source: sideItem.model.decoration ?? ""
                            implicitWidth: Kirigami.Units.iconSizes.smallMedium
                            implicitHeight: Kirigami.Units.iconSizes.smallMedium
                            Layout.alignment: Qt.AlignVCenter
                            animated: false
                        }
                        PC3.Label {
                            text: sideItem.text
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.bold: sideItem.highlighted
                            verticalAlignment: Text.AlignVCenter
                            Layout.fillWidth: true
                        }
                    }

                    Accessible.role: Accessible.ListItem
                    Accessible.name: text

                    onClicked: {
                        ListView.view.currentIndex = index;
                        forceActiveFocus(Qt.MouseFocusReason);
                    }
                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()
                }

                Keys.onRightPressed: event => {
                    fullRep.activeView.forceActiveFocus(Qt.TabFocusReason);
                    event.accepted = true;
                }
            }
            //END

            Kirigami.Separator {
                Layout.fillHeight: true
                Layout.leftMargin: fullRep.paneMargin
                Layout.rightMargin: fullRep.paneMargin
            }

            //BEGIN Main pane: title + pinned grid / application list
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 14
                Layout.fillHeight: true
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2

                    Kirigami.Heading {
                        level: 4
                        Layout.fillWidth: true
                        text: fullRep.searching
                            ? i18n("Search results")
                            : (sideBar.currentItem ? sideBar.currentItem.text : "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    PC3.Label {
                        visible: fullRep.showPinned && pinnedView.count > 0 && !fullRep.compact
                        text: i18n("Right-click to organize")
                        font: Kirigami.Theme.smallFont
                        opacity: 0.75
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Pinned applications (Windows 11-style tiles).
                    GridView {
                        id: pinnedView

                        readonly property int columns: Math.max(2, Math.floor(width / (Kirigami.Units.gridUnit * 6.5)))

                        anchors.fill: parent
                        visible: fullRep.showPinned
                        model: fullRep.pinnedModel
                        clip: true
                        activeFocusOnTab: true
                        cellWidth: Math.floor(width / columns)
                        cellHeight: Kirigami.Units.gridUnit * 6.5
                        currentIndex: count > 0 ? 0 : -1
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: true
                        highlightMoveDuration: 0
                        Accessible.role: Accessible.List
                        Accessible.name: i18n("Pinned applications")

                        PC3.ScrollBar.vertical: PC3.ScrollBar {}

                        delegate: AppTileDelegate {
                            width: pinnedView.cellWidth
                            height: pinnedView.cellHeight
                            actions: itemActions
                        }

                        onCountChanged: {
                            if (currentIndex >= count) {
                                currentIndex = count > 0 ? 0 : -1;
                            }
                        }

                        Keys.onReturnPressed: event => {
                            fullRep.activateCurrent(pinnedView);
                            event.accepted = true;
                        }
                        Keys.onEnterPressed: event => {
                            fullRep.activateCurrent(pinnedView);
                            event.accepted = true;
                        }
                        Keys.onUpPressed: event => {
                            if (currentIndex < columns) {
                                searchField.forceActiveFocus(Qt.BacktabFocusReason);
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        }
                        Keys.onLeftPressed: event => {
                            if (currentIndex % columns === 0) {
                                sideBar.forceActiveFocus(Qt.BacktabFocusReason);
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        }
                    }

                    // All applications, one category, or search results.
                    ListView {
                        id: appView

                        anchors.fill: parent
                        visible: !fullRep.showPinned
                        model: fullRep.appModel
                        clip: true
                        activeFocusOnTab: true
                        currentIndex: count > 0 ? 0 : -1
                        reuseItems: true
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: true
                        highlightMoveDuration: 0
                        Accessible.role: Accessible.List
                        Accessible.name: fullRep.searching ? i18n("Search results") : i18n("Applications")

                        PC3.ScrollBar.vertical: PC3.ScrollBar {}

                        delegate: AppListDelegate {
                            width: appView.width - (appView.PC3.ScrollBar.vertical && appView.PC3.ScrollBar.vertical.visible ? appView.PC3.ScrollBar.vertical.width : 0)
                            actions: itemActions
                            showDescription: fullRep.searching
                        }

                        onCountChanged: {
                            if (currentIndex >= count) {
                                currentIndex = count > 0 ? 0 : -1;
                            }
                        }

                        Keys.onReturnPressed: event => {
                            fullRep.activateCurrent(appView);
                            event.accepted = true;
                        }
                        Keys.onEnterPressed: event => {
                            fullRep.activateCurrent(appView);
                            event.accepted = true;
                        }
                        Keys.onUpPressed: event => {
                            if (currentIndex <= 0) {
                                searchField.forceActiveFocus(Qt.BacktabFocusReason);
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        }
                        Keys.onLeftPressed: event => {
                            sideBar.forceActiveFocus(Qt.BacktabFocusReason);
                            event.accepted = true;
                        }

                        section {
                            // "_unset" instead of "" avoids QTBUG-121797 (same
                            // workaround as kickoff's applicationsListView).
                            property: fullRep.searching ? "group" : "_unset"
                            criteria: ViewSection.FullString
                            delegate: PlasmaExtras.ListSectionHeader {
                                required property string section

                                width: appView.width - (appView.PC3.ScrollBar.vertical && appView.PC3.ScrollBar.vertical.visible ? appView.PC3.ScrollBar.vertical.width : 0)
                                text: section.length === 1 ? section.toUpperCase() : section
                            }
                        }
                    }

                    // Empty / searching / no-results states.
                    Loader {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 20)

                        active: fullRep.activeView.count === 0
                        visible: active
                        asynchronous: true

                        sourceComponent: PlasmaExtras.PlaceholderMessage {
                            readonly property bool busy: fullRep.searching && launcher.runnerModel.querying

                            iconName: busy ? "search" : (fullRep.searching ? "edit-none" : "bookmark-new")
                            text: busy ? i18n("Searching…")
                                : (fullRep.searching ? i18n("No results") : i18n("No pinned applications"))
                            explanation: busy ? ""
                                : (fullRep.searching
                                    ? i18n("Try a different search term.")
                                    : i18n("Choose “All applications” in the sidebar, right-click an application and use “Pin to Start menu”."))
                        }
                    }
                }
            }
            //END

            //BEGIN Places column: folders and tools
            Kirigami.Separator {
                visible: places.visible
                Layout.fillHeight: true
                Layout.leftMargin: fullRep.paneMargin
                Layout.rightMargin: fullRep.paneMargin
            }

            ColumnLayout {
                id: places

                visible: fullRep.folderLinks.length + fullRep.toolLinks.length > 0
                Layout.fillHeight: true
                // Lote 15 (root cause of the squeezed list): layouts default to
                // fillWidth: true, so this column shared every spare pixel with the
                // application list (H6: ~300 px list, ~275 px places). It must keep
                // its preferred width and leave the rest to the list.
                Layout.fillWidth: false
                Layout.preferredWidth: fullRep.placesCompact ? Kirigami.Units.gridUnit * 3 : Kirigami.Units.gridUnit * 9.5
                Layout.rightMargin: fullRep.paneMargin
                spacing: Kirigami.Units.smallSpacing / 2

                Kirigami.Heading {
                    visible: !fullRep.placesCompact && fullRep.folderLinks.length > 0
                    level: 5
                    text: i18n("Places")
                    textFormat: Text.PlainText
                    opacity: 0.75
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                }

                Repeater {
                    model: fullRep.folderLinks

                    delegate: QuickLink {
                        required property var modelData

                        iconName: modelData.icon
                        label: modelData.label
                        caption: modelData.caption ?? ""
                        labelVisible: !fullRep.placesCompact
                        onClicked: fullRep.openFolder(modelData.url)
                    }
                }

                Kirigami.Separator {
                    visible: fullRep.folderLinks.length > 0 && fullRep.toolLinks.length > 0
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                }

                Kirigami.Heading {
                    visible: !fullRep.placesCompact && fullRep.toolLinks.length > 0
                    level: 5
                    text: i18n("Tools")
                    textFormat: Text.PlainText
                    opacity: 0.75
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                }

                Repeater {
                    model: fullRep.toolLinks

                    delegate: QuickLink {
                        required property var modelData

                        iconName: modelData.icon
                        label: modelData.label
                        labelVisible: !fullRep.placesCompact
                        onClicked: fullRep.launchTool(modelData.row)
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
            //END
        }

        //BEGIN Footer: account + official session commands
        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.leftMargin: fullRep.paneMargin
            Layout.rightMargin: fullRep.paneMargin
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.leftMargin: fullRep.paneMargin
            Layout.rightMargin: fullRep.paneMargin
            Layout.bottomMargin: fullRep.paneMargin
            spacing: Kirigami.Units.smallSpacing * 2

            KirigamiComponents.AvatarButton {
                id: avatar

                visible: KConfig.KAuthorized.authorizeControlModule("kcm_users")
                implicitWidth: Kirigami.Units.iconSizes.medium
                implicitHeight: Kirigami.Units.iconSizes.medium
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                Layout.alignment: Qt.AlignVCenter

                text: i18n("User settings")
                name: kuser.fullName
                cache: false
                source: kuser.faceIconUrl

                Accessible.name: text

                onClicked: {
                    KCM.KCMLauncher.openSystemSettings("kcm_users");
                    launcher.expanded = false;
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PC3.Label {
                    text: kuser.fullName.length > 0 ? kuser.fullName : kuser.loginName
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.bold: true
                    Layout.fillWidth: true
                }
                PC3.Label {
                    text: "Enthroned OS"
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font: Kirigami.Theme.smallFont
                    opacity: 0.75
                    Layout.fillWidth: true
                }
            }

            PC3.ToolButton {
                id: lockButton

                visible: fullRep.lockRow >= 0
                icon.name: "system-lock-screen"
                text: i18n("Lock")
                display: PC3.AbstractButton.IconOnly
                Accessible.name: text

                PC3.ToolTip.text: text
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                PC3.ToolTip.visible: hovered || activeFocus

                onClicked: {
                    // Official session command (SystemModel::trigger).
                    launcher.systemModel.trigger(fullRep.lockRow, "", null);
                    launcher.expanded = false;
                }
            }

            PC3.ToolButton {
                id: powerButton

                icon.name: "system-shutdown"
                text: i18n("Session and power")
                display: PC3.AbstractButton.TextBesideIcon
                Accessible.name: text
                Accessible.role: Accessible.ButtonMenu

                PC3.ToolTip.text: text
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                PC3.ToolTip.visible: hovered || activeFocus

                onPressed: {
                    powerMenu.visualParent = powerButton;
                    powerMenu.openRelative();
                }
            }
        }
        //END
    }

    PlasmaExtras.Menu {
        id: powerMenu

        placement: {
            switch (Plasmoid.location) {
            case PlasmaCore.Types.LeftEdge:
            case PlasmaCore.Types.RightEdge:
            case PlasmaCore.Types.TopEdge:
                return PlasmaExtras.Menu.BottomPosedRightAlignedPopup;
            default:
                return PlasmaExtras.Menu.TopPosedRightAlignedPopup;
            }
        }
    }

    // Sibling Instantiator: PlasmaExtras.Menu.content only accepts QMenuItem children.
    Instantiator {
        model: launcher.systemModel
        delegate: PlasmaExtras.MenuItem {
            required property int index
            required property var model

            text: model.display
            icon: model.decoration
            onClicked: {
                // Official session commands (SystemModel::trigger); the
                // session decides whether a confirmation is shown.
                launcher.systemModel.trigger(index, "", null);
                launcher.expanded = false;
            }
        }
        onObjectAdded: (index, object) => powerMenu.addMenuItem(object)
        onObjectRemoved: (index, object) => powerMenu.removeMenuItem(object)
    }
}
