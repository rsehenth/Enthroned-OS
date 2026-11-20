/*
 * Enthroned Settings - ToggleBox (Lote 15).
 * A switch bound to one boolean allowlisted setting. defaultOn is the value
 * the application uses while the key is unset (Dolphin: hidden files off,
 * previews on), so the switch always shows what the user actually gets.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2

QQC2.Switch {
    id: root

    property string settingId
    property bool defaultOn: false
    readonly property string stored: {
        personalization.revision;
        return personalization.value(settingId);
    }

    enabled: !personalization.busy

    Binding {
        target: root
        property: "checked"
        value: root.stored === "" ? root.defaultOn : root.stored === "true"
        restoreMode: Binding.RestoreNone
    }

    onToggled: personalization.setValue(settingId, checked ? "true" : "false")
}
