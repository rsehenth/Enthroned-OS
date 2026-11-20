/*
 * Enthroned Launcher — shared item actions (Lote 3).
 * One instance per popup (created in FullRepresentation.qml). Holds the single
 * context menu and the activation / pin / reorder logic used by every list,
 * grid and shortcut delegate, so delegates stay thin and nothing is duplicated.
 *
 * Menu pattern (verified against plasma-desktop/applets/kickoff ActionMenu.qml,
 * Plasma 6.6): the PlasmaExtras.Menu is a *property value* and the Instantiator
 * is a sibling child of a plain Item. Never nest an Instantiator inside the
 * Menu: Menu.content only accepts QMenuItem children ("Cannot assign object of
 * type QQmlInstantiator to list property content; expected QMenuItem").
 *
 * Favorites go through the kicker favorites model (KActivitiesStats):
 * isFavorite / addFavorite / removeFavorite / moveRow, the same calls kickoff
 * uses. Desktop-file actions come from the model's own actionList and are
 * triggered through the model's trigger(row, actionId, argument).
 *
 * SPDX-License-Identifier: Apache-2.0
 */

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.extras as PlasmaExtras
import "ShortcutCommand.js" as ShortcutCmd

Item {
    id: root

    visible: false

    // State of the menu that is (or was last) open.
    property var actionList: null
    property var sourceView: null
    property int sourceIndex: -1
    property string sourceFavoriteId: ""

    readonly property var favorites: launcher.rootModel.favoritesModel

    // Lote 6: one-shot runner for the desktop-shortcut helper. The helper
    // itself enforces every policy (real installed launcher, no hidden
    // entries, never overwrites a personal file, real XDG Desktop folder).
    // DataSource lives in the plasma5support module on Plasma 6 (it left
    // org.kde.plasma.core); the old import broke the AppActions /
    // FullRepresentation type chain when the popup opened.
    readonly property P5Support.DataSource shortcutRunner: P5Support.DataSource {
        engine: "executable"
    }

    // Lote 9.2 (H4-011): the helper source currently awaiting its result.
    // Kept as state so the result can be consumed and the source
    // disconnected, letting the helper run again in the same popup.
    property string _pendingShortcutCommand: ""

    // Lote 9.2 (H4-002/H4-011): validation, quoting and the connect /
    // disconnect cycle live in ShortcutCommand.js (shared with the Node
    // regression tests). A malformed id is rejected without ever touching
    // the shell.
    function createDesktopShortcut(): void {
        root._pendingShortcutCommand = ShortcutCmd.request(
            root.shortcutRunner, root._pendingShortcutCommand, root.sourceFavoriteId);
    }

    Connections {
        target: root.shortcutRunner
        function onNewData(source, data) {
            root._pendingShortcutCommand = ShortcutCmd.consume(
                root.shortcutRunner, root._pendingShortcutCommand, source);
            const exitCode = Number(data["exit code"] ?? -1);
            if (exitCode !== 0) {
                console.warn(`enthroned-desktop-shortcut failed (exit ${exitCode}): ${source}`);
            }
        }
    }

    readonly property PlasmaExtras.Menu menu: PlasmaExtras.Menu {
        visualParent: null
        placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
    }

    // Lote 12: resolves (view, index) to the underlying kicker model row,
    // unwrapping the read-only dedupe proxy so trigger() always runs on the
    // real model (the proxy itself has no trigger()).
    function modelRowFor(view, index): var {
        if (!view || !view.model || index < 0) {
            return null;
        }
        const model = view.model;
        if (model.trigger !== undefined) {
            return { model: model, row: index };
        }
        if (model.mapToSource !== undefined && model.sourceModel) {
            const sourceIndex = model.mapToSource(model.index(index, 0));
            return { model: model.sourceModel, row: sourceIndex.row };
        }
        return null;
    }

    // Lote 11B: the pinned grid renders through the dedupe proxy, so proxy
    // rows must be mapped back to favorites-model rows before reorder calls.
    function sourceRowOf(view, index): int {
        const resolved = modelRowFor(view, index);
        return resolved ? resolved.row : index;
    }

    // True when the view shows the favorites model directly or through the
    // pinned dedupe proxy (reordering only makes sense in the pinned list).
    function isPinnedView(view): bool {
        if (!view || !root.favorites) {
            return false;
        }
        return view.model === root.favorites || view.model?.sourceModel === root.favorites;
    }

    // Official launch contract (AbstractModel::trigger); closes the popup when
    // the model asks for it.
    function activate(view, index): void {
        const resolved = root.modelRowFor(view, index);
        if (resolved && resolved.model.trigger && resolved.row >= 0
                && resolved.model.trigger(resolved.row, "", null)) {
            launcher.expanded = false;
        }
    }

    function hasFavoriteId(model): bool {
        return model && model.favoriteId !== undefined && model.favoriteId !== null
            && String(model.favoriteId).length > 0;
    }

    // delegate: any delegate exposing model, view and index. x/y are optional
    // (keyboard menu opens relative to the delegate).
    function open(delegate, x, y): void {
        const model = delegate.model;
        const view = delegate.view;
        if (!model || !view) {
            return;
        }

        const items = [];
        if (model.hasActionList === true && model.actionList) {
            for (const entry of Array.from(model.actionList)) {
                items.push(entry);
            }
        }

        const fav = root.favorites;
        const favId = hasFavoriteId(model) ? String(model.favoriteId) : "";
        if (fav && fav.enabled && favId.length > 0) {
            if (items.length > 0) {
                items.push({ type: "separator" });
            }
            if (fav.isFavorite(favId)) {
                items.push({ text: i18n("Unpin from Start menu"), icon: "bookmark-remove", actionId: "_enthroned_unpin" });
                // Reordering only makes sense inside the pinned list itself
                // (direct favorites model or its dedupe proxy, Lote 11B).
                if (root.isPinnedView(view)) {
                    if (delegate.index > 0) {
                        items.push({ text: i18n("Move to start"), icon: "go-first", actionId: "_enthroned_move_first" });
                        items.push({ text: i18n("Move earlier"), icon: "go-previous", actionId: "_enthroned_move_prev" });
                    }
                    if (delegate.index < view.count - 1) {
                        items.push({ text: i18n("Move later"), icon: "go-next", actionId: "_enthroned_move_next" });
                    }
                }
            } else {
                items.push({ text: i18n("Pin to Start menu"), icon: "bookmark-new", actionId: "_enthroned_pin" });
            }
            // Lote 6: explicit manual shortcut action (always offered for real
            // application launchers, independent of the automatic preference).
            if (favId.endsWith(".desktop")) {
                items.push({ text: i18n("Add to desktop"), icon: "user-desktop", actionId: "_enthroned_pin_desktop" });
            }
        }

        if (items.length === 0) {
            return;
        }

        root.sourceView = view;
        root.sourceIndex = delegate.index;
        root.sourceFavoriteId = favId;
        root.actionList = items;
        root.menu.visualParent = delegate;
        if (x !== undefined && y !== undefined) {
            root.menu.open(x, y);
        } else {
            root.menu.openRelative();
        }
    }

    function move(to): void {
        const view = root.sourceView;
        if (!view || to < 0 || to >= view.count || to === root.sourceIndex) {
            return;
        }
        // Lote 11B: delegate indexes are proxy rows; kicker's moveRow works
        // on favorites-model rows. Map both ends through the proxy.
        const fromSource = root.sourceRowOf(view, root.sourceIndex);
        const toSource = root.sourceRowOf(view, to);
        if (fromSource < 0 || fromSource === toSource) {
            return;
        }
        root.favorites.moveRow(fromSource, toSource);
        view.currentIndex = to;
    }

    function trigger(action): void {
        const id = action.actionId ?? "";
        switch (id) {
        case "_enthroned_pin":
            root.favorites.addFavorite(root.sourceFavoriteId);
            return;
        case "_enthroned_unpin":
            root.favorites.removeFavorite(root.sourceFavoriteId);
            return;
        case "_enthroned_pin_desktop":
            root.createDesktopShortcut();
            return;
        case "_enthroned_move_first":
            root.move(0);
            return;
        case "_enthroned_move_prev":
            root.move(root.sourceIndex - 1);
            return;
        case "_enthroned_move_next":
            root.move(root.sourceIndex + 1);
            return;
        }
        // Desktop-file / runner action: let the model run it (unwrapping the
        // dedupe proxy when present, Lote 12).
        const resolved = root.modelRowFor(root.sourceView, root.sourceIndex);
        if (resolved && resolved.model.trigger
                && resolved.model.trigger(resolved.row, id, action.actionArgument)) {
            launcher.expanded = false;
        }
    }

    Instantiator {
        active: root.actionList !== null
        model: root.actionList
        delegate: PlasmaExtras.MenuItem {
            required property var modelData

            text: modelData.text ?? ""
            enabled: modelData.type !== "title" && (modelData.enabled ?? true)
            separator: modelData.type === "separator"
            section: modelData.type === "title"
            icon: modelData.icon ?? null
            onClicked: root.trigger(modelData)
        }
        onObjectAdded: (index, object) => root.menu.addMenuItem(object)
        onObjectRemoved: (index, object) => root.menu.removeMenuItem(object)
    }
}
