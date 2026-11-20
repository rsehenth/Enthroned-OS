/*
 * Enthroned Launcher — application list delegate.
 * Simplified variant of kickoff's AbstractKickoffItemDelegate (Plasma 6.6):
 * icon + name, activation through the model's Q_INVOKABLE
 * trigger(row, actionId, argument) (kicker contract), context menu through the
 * shared AppActions instance (pin / unpin / desktop actions).
 *
 * Lote 3: no per-row Loader (the row layout is the content item directly);
 * search results show the description as a second line, plain lists stay at a
 * single line so more applications fit in a 720p screen.
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
    // Shared AppActions instance (FullRepresentation.itemActions).
    required property var actions

    // Search results carry a useful description (path, runner, generic name).
    property bool showDescription: false

    readonly property ListView view: ListView.view
    readonly property bool isSeparator: model.isSeparator === true
    readonly property string description: model.description ?? ""

    leftPadding: Kirigami.Units.smallSpacing * 2
    rightPadding: Kirigami.Units.smallSpacing * 2
    topPadding: isSeparator ? 0 : Kirigami.Units.smallSpacing
    bottomPadding: isSeparator ? 0 : Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing * 2

    enabled: !isSeparator && model.disabled !== true
    hoverEnabled: true
    highlighted: view ? view.currentIndex === index : false

    // Disabled rows are dimmed; hover / selection / keyboard focus come from
    // the shared state layer.
    opacity: enabled || isSeparator ? 1 : 0.5
    background: ItemBackground {
        visible: !root.isSeparator
        hovered: root.hovered
        pressed: root.down
        selected: root.highlighted
        focused: root.visualFocus
    }

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: isSeparator ? Kirigami.Units.smallSpacing * 2
                                : Math.max(implicitContentHeight + topPadding + bottomPadding,
                                           Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2)

    text: model.display ?? ""
    Accessible.role: Accessible.ListItem
    Accessible.name: text
    Accessible.description: description !== text ? description : ""

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

    contentItem: RowLayout {
        visible: !root.isSeparator
        spacing: root.spacing

        Kirigami.Icon {
            implicitWidth: Kirigami.Units.iconSizes.medium
            implicitHeight: Kirigami.Units.iconSizes.medium
            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

            animated: false
            source: root.model.decoration ?? ""
            isMask: false
        }

        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            PC3.Label {
                id: nameLabel

                text: root.text
                textFormat: Text.PlainText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                Layout.fillWidth: true
                color: Kirigami.Theme.textColor

                // Lote 12: full name on hover when the column is too narrow.
                PC3.ToolTip.text: root.text
                PC3.ToolTip.visible: root.hovered && nameLabel.truncated
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            PC3.Label {
                visible: root.showDescription && root.description.length > 0 && root.description !== root.text
                text: root.description
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: 0.75
                Layout.fillWidth: true
                color: Kirigami.Theme.textColor
            }
        }
    }
}
