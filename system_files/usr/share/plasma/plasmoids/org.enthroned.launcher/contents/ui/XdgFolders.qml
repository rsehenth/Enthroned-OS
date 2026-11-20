/*
 * Enthroned Launcher — XDG user folders.
 * Loaded through a Loader (FullRepresentation.qml) on purpose: if the
 * Qt.labs.platform module is missing on a given image, only the folder
 * shortcuts disappear; the rest of the menu keeps working (a failing import in
 * FullRepresentation itself would reproduce "Type FullRepresentation
 * unavailable").
 *
 * Values come from QStandardPaths, which reads the user's XDG user-dirs
 * configuration; nothing is hardcoded.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick
import Qt.labs.platform as Platform

QtObject {
    readonly property url home: Platform.StandardPaths.writableLocation(Platform.StandardPaths.HomeLocation)
    readonly property url documents: Platform.StandardPaths.writableLocation(Platform.StandardPaths.DocumentsLocation)
    readonly property url downloads: Platform.StandardPaths.writableLocation(Platform.StandardPaths.DownloadLocation)
    readonly property url pictures: Platform.StandardPaths.writableLocation(Platform.StandardPaths.PicturesLocation)
}
