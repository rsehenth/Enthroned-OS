/*
 * Enthroned Settings - SectionHeading (Lote 13).
 * One heading style for every group of settings: level 3, semibold, with more
 * space above than below so a heading binds to the group that follows it
 * (the parent layout already supplies the small gap below). Exposed to
 * assistive technology as a heading.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.Heading {
    level: 3
    font.weight: Font.DemiBold
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.topMargin: Kirigami.Units.gridUnit * 0.75
    Accessible.role: Accessible.Heading
}
