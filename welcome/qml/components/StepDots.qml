/*
 * Enthroned Welcome - step progress indicator.
 * F4+: segmented bar (one segment per step) instead of 4px dots: easier to
 * read at a glance and at high DPI. Pure Kirigami.Theme colors; completed and
 * current steps share the accent, pending steps are a neutral track. Exposes
 * an Accessible name per step so progress is never conveyed by color alone.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property int current: 0
    property int count: 5

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: root.count

        delegate: Rectangle {
            required property int index
            readonly property bool active: index === root.current
            readonly property bool done: index < root.current

            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.5
            radius: height / 2
            color: (active || done) ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
            opacity: active ? 1 : (done ? 0.6 : 0.2)

            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.shortDuration }
            }

            Accessible.role: Accessible.Indicator
            Accessible.name: index < root.current
                ? i18n("Step %1 completed", index + 1)
                : (active ? i18n("Step %1 current", index + 1) : i18n("Step %1 pending", index + 1))
        }
    }
}
