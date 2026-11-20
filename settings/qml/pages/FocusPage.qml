/*
 * Enthroned Settings - focused area page (Lote 6, Modo Simples).
 * One small page per primary area (Tela e resolucao, Som, Notificacoes). It
 * does NOT duplicate any other page: it shows exactly one native KDE module
 * with an explanation, reusing the shared ModuleList/ModuleCard components
 * and the same honest availability detection as every other page.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root

    // Configured by the caller (Main.qml pageModel / component declaration).
    required property string focusTitle
    required property string focusIcon
    required property string focusDescription
    required property var focusModuleIds

    title: focusTitle

    Component.onCompleted: kcm.refreshAvailable()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        ModuleList {
            modules: [
                { title: root.focusTitle,
                  subtitle: root.focusDescription,
                  icon: root.focusIcon,
                  ids: root.focusModuleIds }
            ]
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            text: kcm.toolPresent
                ? i18n("This opens the native KDE settings module for this area. Everything shown there comes from the real system.")
                : i18n("The native module could not be detected in this environment, so nothing is opened. Nothing is simulated.")
        }
    }
}
