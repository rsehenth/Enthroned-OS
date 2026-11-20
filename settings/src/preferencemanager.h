/*
 * Enthroned Settings - per-user product preferences (Lote 6).
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>

namespace Enthroned {

class PreferenceManager : public QObject
{
    Q_OBJECT
    // Advanced-mode toggle of the navigation (Modo Simples is the default).
    Q_PROPERTY(bool advancedSettingsMode READ advancedSettingsMode
                   WRITE setAdvancedSettingsMode NOTIFY advancedSettingsModeChanged)
    // Whether installing an app through an Enthroned-integrated flow places a
    // shortcut on the real user Desktop directory (default true).
    Q_PROPERTY(bool createDesktopShortcuts READ createDesktopShortcuts
                   WRITE setCreateDesktopShortcuts NOTIFY createDesktopShortcutsChanged)

public:
    explicit PreferenceManager(QObject* parent = nullptr);

    bool advancedSettingsMode() const;
    void setAdvancedSettingsMode(bool enabled);

    bool createDesktopShortcuts() const;
    void setCreateDesktopShortcuts(bool enabled);

Q_SIGNALS:
    void advancedSettingsModeChanged();
    void createDesktopShortcutsChanged();

private:
    bool m_advancedSettingsMode = false;
    bool m_createDesktopShortcuts = true;
};

} // namespace Enthroned
