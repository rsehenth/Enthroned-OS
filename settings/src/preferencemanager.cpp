/*
 * Enthroned Settings - per-user product preferences (Lote 6).
 * A tiny QSettings-backed store in
 * $XDG_CONFIG_HOME/enthroned-os/preferences.conf. System defaults for the
 * same keys live in /etc/xdg/enthroned-os/preferences.conf and are read by
 * kreadconfig6 (the desktop-shortcut helper); a user's own file always wins.
 * The file is shared with the launcher and Welcome helpers, so keys are
 * stable identifiers, never translatable text.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "preferencemanager.h"

#include <QSettings>
#include <QStandardPaths>

namespace Enthroned {
namespace {

QString preferencesFilePath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/enthroned-os/preferences.conf");
}

} // namespace

PreferenceManager::PreferenceManager(QObject* parent)
    : QObject(parent)
{
    const QSettings settings(preferencesFilePath(), QSettings::IniFormat);
    m_advancedSettingsMode = settings
                                 .value(QStringLiteral("General/AdvancedSettingsMode"), false)
                                 .toBool();
    m_createDesktopShortcuts = settings
                                   .value(QStringLiteral("General/CreateDesktopShortcuts"), true)
                                   .toBool();
}

bool PreferenceManager::advancedSettingsMode() const
{
    return m_advancedSettingsMode;
}

void PreferenceManager::setAdvancedSettingsMode(bool enabled)
{
    if (m_advancedSettingsMode == enabled) {
        return;
    }
    m_advancedSettingsMode = enabled;
    QSettings settings(preferencesFilePath(), QSettings::IniFormat);
    settings.setValue(QStringLiteral("General/AdvancedSettingsMode"), enabled);
    Q_EMIT advancedSettingsModeChanged();
}

bool PreferenceManager::createDesktopShortcuts() const
{
    return m_createDesktopShortcuts;
}

void PreferenceManager::setCreateDesktopShortcuts(bool enabled)
{
    if (m_createDesktopShortcuts == enabled) {
        return;
    }
    m_createDesktopShortcuts = enabled;
    QSettings settings(preferencesFilePath(), QSettings::IniFormat);
    settings.setValue(QStringLiteral("General/CreateDesktopShortcuts"), enabled);
    Q_EMIT createDesktopShortcutsChanged();
}

} // namespace Enthroned
