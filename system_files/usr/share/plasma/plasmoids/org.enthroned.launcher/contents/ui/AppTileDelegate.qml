/*
 * Enthroned Launcher — pinned application tile (Windows 11-style grid cell).
 * Same contract as AppListDelegate (kicker model trigger, shared AppActions
 * menu); only the layout differs: large icon above a two-line name.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

T.ItemDelegate {
    id: root

    required property var model
    required property int index
    required property var actions

    readonly property GridView view: GridView.view
    readonly property string description: model.description ?? ""

    // Gaps between tiles come from the insets so the state layer never touches
    // the neighbouring cell.
    leftInset: Kirigami.Units.smallSpacing / 2
    rightInset: Kirigami.Units.smallSpacing / 2
    topInset: Kirigami.Units.smallSpacing / 2
    bottomInset: Kirigami.Units.smallSpacing / 2
    padding: Kirigami.Units.smallSpacing * 2
    spacing: Kirigami.Units.smallSpacing

    enabled: model.disabled !== true
    hoverEnabled: true
    highlighted: view ? view.currentIndex === index : false
    opacity: enabled ? 1 : 0.5

    background: ItemBackground {
        hovered: root.hovered
        pressed: root.down
        selected: root.highlighted
        focused: root.visualFocus
    }

    text: model.display ?? ""
    Accessible.role: Accessible.ListItem
    Accessible.name: text
    Accessible.description: description !== text ? description : ""

    PC3.ToolTip.text: description.length > 0 && description !== text ? description : ""
    PC3.ToolTip.visible: hovered && PC3.ToolTip.text.length > 0
    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay

    function openMenu(x, y): void {
        actions.open(root, x, y);
    }

    onClicked: {
        if (view) {
            view.currentIndex = index;
        }
        forceActiveFocus(Qt.MouseFocusReason);
        actions.activate(view, index);
    }
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    Keys.onMenuPressed: openMenu()

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            if (root.view) {
                root.view.currentIndex = root.index;
            }
            root.openMenu(point.position.x, point.position.y);
        }
    }

    TapHandler {
        acceptedDevices: PointerDevice.TouchScreen
        onLongPressed: root.openMenu(point.position.x, point.position.y)
    }

    contentItem: ColumnLayout {
        spacing: root.spacing

        Kirigami.Icon {
            // Lote 15: 48 -> 56 so thin brand glyphs (the E) keep presence;
            // the 64 px hicolor PNG is downscaled, so it stays sharp.
            implicitWidth: Math.round(Kirigami.Units.iconSizes.large * 7 / 6)
            implicitHeight: Math.round(Kirigami.Units.iconSizes.large * 7 / 6)
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

            animated: false
            source: root.model.decoration ?? ""
            isMask: false
        }

        PC3.Label {
            text: root.text
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            color: Kirigami.Theme.textColor
        }
    }
}
