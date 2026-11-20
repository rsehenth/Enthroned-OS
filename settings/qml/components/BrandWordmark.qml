/*
 * Enthroned Settings - BrandWordmark (Lote 13).
 * The owner's original full "Enthroned OS" logo, derived from
 * assets/EnthronedLogo-2.png by scripts/gen-brand-assets.py and installed by
 * the image under /usr/share/enthroned-os/branding. It is shown unmodified
 * (never stretched or recolored) and falls back to the "E" mark when the file
 * is not installed (development runs). Space is reserved from the artwork's
 * fixed aspect ratio, so nothing shifts when the image finishes loading.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root

    property real logoWidth: Kirigami.Units.gridUnit * 14
    // EnthronedLogo-2.png is 1983 x 793.
    readonly property real aspect: 793 / 1983

    implicitWidth: logoWidth
    implicitHeight: logoWidth * aspect

    Accessible.role: Accessible.Graphic
    Accessible.name: i18n("Enthroned OS")

    Image {
        id: wordmark
        anchors.fill: parent
        source: "file:///usr/share/enthroned-os/branding/enthroned-wordmark.png"
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        horizontalAlignment: Image.AlignLeft
        smooth: true
        mipmap: true
        visible: status === Image.Ready
    }

    Kirigami.Icon {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(root.height, Kirigami.Units.iconSizes.huge)
        height: width
        source: "org.enthroned.enthroned-os"
        visible: wordmark.status === Image.Error || wordmark.status === Image.Null
    }
}
