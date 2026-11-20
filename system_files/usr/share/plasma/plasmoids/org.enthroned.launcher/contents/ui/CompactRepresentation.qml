/*
 * Enthroned Launcher — compact (panel) representation.
 * Square icon button that toggles the popup; mirrors the essential parts of
 * the stock kickoff compact representation (Plasma 6.6): hover highlight,
 * Accessible button role, click toggles expanded.
 * F4+: rounded state layer (hover / pressed / menu open) so the start button
 * reads as a button in both Classic and Modern panels.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

MouseArea {
    id: root

    hoverEnabled: true

    implicitWidth: Kirigami.Units.iconSizes.large
    implicitHeight: Kirigami.Units.iconSizes.large

    // Square button that follows the panel thickness.
    Layout.fillHeight: true
    Layout.preferredWidth: height
    Layout.minimumWidth: Layout.preferredWidth

    Accessible.name: Plasmoid.title
    Accessible.role: Accessible.Button
    Accessible.onPressAction: launcher.expanded = !launcher.expanded

    property bool wasExpanded: false
    onPressed: wasExpanded = launcher.expanded
    onClicked: launcher.expanded = !wasExpanded

    Rectangle {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing / 2
        radius: Kirigami.Units.smallSpacing * 1.5
        color: Kirigami.Theme.highlightColor
        opacity: root.pressed ? 0.24 : (launcher.expanded ? 0.18 : (root.containsMouse ? 0.12 : 0))

        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    // Lote 14 (H6 P1): the brand glyphs are tall and slender and the PNGs are
    // already cropped to the artwork, so the start button looked small because
    // the old 4px margin + roundToIconSize turned a 40px (Modern) / 36px
    // (Classic) cell into a 32px icon. Fill the button (3px inset, inside the
    // 2px state layer) and keep the exact size; Kirigami.Icon picks the 48px
    // PNG and scales it down smoothly.
    Kirigami.Icon {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing * 0.75

        source: Plasmoid.icon
        active: root.containsMouse
        roundToIconSize: false
    }
}
