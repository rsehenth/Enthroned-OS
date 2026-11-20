/*
 * Enthroned Settings - ChoiceBox (Lote 15).
 * A combo box bound to one allowlisted setting of PersonalizationController
 * (kwinrc / kdeglobals / Dolphin view properties). choices is [{value, text}];
 * value "" means "KDE default" and restores it by deleting the key, so the
 * default is always reachable and no value is invented.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2

QQC2.ComboBox {
    id: root

    property string settingId
    property var choices: []
    // Re-read whenever the controller reports a change.
    readonly property string stored: {
        personalization.revision;
        return personalization.value(settingId);
    }

    model: choices
    textRole: "text"
    enabled: !personalization.busy

    // A Binding (not a plain assignment) so user selections do not break the link.
    Binding {
        target: root
        property: "currentIndex"
        value: Math.max(0, root.choices.findIndex(c => c.value === root.stored))
        restoreMode: Binding.RestoreNone
    }

    onActivated: index => {
        const picked = choices[index].value;
        if (picked === "") {
            personalization.resetValue(settingId);
        } else {
            personalization.setValue(settingId, picked);
        }
    }
}
