/*
 * Enthroned Launcher — start menu of the Enthroned OS desktop.
 * Native KDE Plasma applet (Qt/QML) built on the same model contracts used by
 * the stock Application Launcher (plasma-desktop/applets/kickoff, Plasma 6.6)
 * through the org.kde.plasma.private.kicker module:
 *   - RootModel: real application list, categories, per-instance favorites
 *     (KActivitiesStats store via favoritesModel.initForClient).
 *   - RunnerModel: KRunner-backed search (apps, files, settings…).
 *   - SystemModel: official session commands (lock/logout/suspend/reboot/
 *     shutdown) via Q_INVOKABLE trigger(row, actionId, argument).
 * No resident services, no polling, no web engines.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker

PlasmoidItem {
    id: launcher

    //BEGIN Models (same wiring as plasma-desktop/applets/kickoff main.qml)
    readonly property Kicker.RootModel rootModel: Kicker.RootModel {
        autoPopulate: false
        appletInterface: launcher

        appNameFormat: 0 // NameOnly; the generic name is shown as description
        flat: true // categories, but no subcategories
        sorted: true
        showSeparators: false
        showTopLevelItems: true

        showAllApps: true
        showAllAppsCategorized: false
        showRecentApps: false
        showRecentDocs: false
        showPowerSession: false
        showFavoritesPlaceholder: true

        Component.onCompleted: {
            favoritesModel.initForClient("org.enthroned.launcher.favorites.instance-" + Plasmoid.id);

            if (!Plasmoid.configuration.favoritesPortedToKAstats) {
                if (favoritesModel.count < 1) {
                    favoritesModel.portOldFavorites(Plasmoid.configuration.favorites);
                }
                Plasmoid.configuration.favoritesPortedToKAstats = true;
            }
        }
    }

    readonly property Kicker.RunnerModel runnerModel: Kicker.RunnerModel {
        query: launcher.searchField ? launcher.searchField.text : ""
        appletInterface: launcher
        mergeResults: true
        favoritesModel: launcher.rootModel.favoritesModel
    }

    readonly property Kicker.SystemModel systemModel: Kicker.SystemModel {
        favoritesModel: launcher.rootModel.systemFavoritesModel
    }
    //END

    // Set in FullRepresentation.qml; bound into RunnerModel.query above.
    property Item searchField: null

    Plasmoid.icon: Plasmoid.configuration.icon

    preferredRepresentation: compactRepresentation
    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation { focus: true }

    Component.onCompleted: {
        Plasmoid.activationTogglesExpanded = true;
    }
}
