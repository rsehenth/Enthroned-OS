/*
 * Enthroned Settings - shared StatusIcon component (F4+).
 * Icon on a soft tone disc that summarizes the update-engine state at a glance.
 * The tone is only a reinforcement: every use sits next to a text title, so the
 * state is never conveyed by color alone. Colors come from the active scheme.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root

    // Update-engine state id (see update-state-spec.json) and the icon to show.
    property string updateState: "unknown"
    property string iconName: "dialog-question"

    // positive | neutral | negative | info | idle
    readonly property string tone: {
        switch (root.updateState) {
        case "upToDate": return "positive";
        case "restartRequired": return "neutral";
        case "failed": return "negative";
        case "checking":
        case "updating":
        case "preparing":
        case "updatesAvailable": return "info";
        }
        // unknown / noNetwork / serviceUnavailable: neutral gray, never implies an update.
        return "idle";
    }
    readonly property color toneColor: {
        switch (root.tone) {
        case "positive": return Kirigami.Theme.positiveTextColor;
        case "neutral": return Kirigami.Theme.neutralTextColor;
        case "negative": return Kirigami.Theme.negativeTextColor;
        case "info": return Kirigami.Theme.highlightColor;
        }
        return Kirigami.Theme.disabledTextColor;
    }

    implicitWidth: Kirigami.Units.iconSizes.huge
    implicitHeight: Kirigami.Units.iconSizes.huge
    Accessible.ignored: true

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.toneColor
        opacity: 0.16
    }
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: root.toneColor
    }
    Kirigami.Icon {
        anchors.centerIn: parent
        source: root.iconName
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium
        width: implicitWidth
        height: implicitHeight
    }
}
