/*
 * Enthroned Settings - SettingsPage (Gate 13.1).
 * Base for every settings page: a Kirigami.ScrollablePage whose content keeps
 * a comfortable reading width on large windows (cards stop stretching across
 * a 1080p screen) while the scrollbar stays at the window edge. The reading
 * width is measured in gridUnits, so it follows the user's font/scale setting.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import org.kde.kirigami as Kirigami

Kirigami.ScrollablePage {
    id: root

    // contentInset is defined once, by the main window (same value the header uses).
    leftPadding: applicationWindow().contentInset
    rightPadding: applicationWindow().contentInset
    topPadding: Kirigami.Units.largeSpacing
    bottomPadding: Kirigami.Units.gridUnit
}
