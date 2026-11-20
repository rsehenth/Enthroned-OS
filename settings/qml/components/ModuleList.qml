/*
 * Enthroned Settings - list of native KDE module shortcuts.
 * `modules` items: { title, subtitle, icon, ids: [candidate module ids], optional: bool }.
 * Shows one honest notice when kcmshell6 is missing; nothing is simulated.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var modules: []

    spacing: Kirigami.Units.largeSpacing
    Layout.fillWidth: true

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: !kcm.toolPresent
        type: Kirigami.MessageType.Information
        text: i18n("kcmshell6 is not available in this environment. The native KDE modules cannot be opened from here.")
    }

    Repeater {
        model: root.modules

        delegate: ModuleCard {
            required property var modelData
            title: modelData.title
            subtitle: modelData.subtitle
            iconName: modelData.icon
            modules: modelData.ids
            hideIfUnavailable: modelData.optional === true
        }
    }
}
