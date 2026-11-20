/*
 * Enthroned Welcome - application availability (F4.5 tela 3 / F4.10).
 * Detects what is REALLY installed before offering any action: no fake
 * controls and no buttons pointing at non-existent executables.
 *   - Brave: Flatpak system app (com.brave.Browser) or a native RPM binary;
 *   - Discover: the KDE app store (org.kde.discover.desktop / plasma-discover);
 *   - flatpak CLI presence for user-level installs.
 * Detection is read-only; launching uses the real desktop integration.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QString>

namespace Enthroned {

class AppAvailability : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool braveAvailable READ braveAvailable CONSTANT)
    Q_PROPERTY(bool discoverAvailable READ discoverAvailable CONSTANT)
    Q_PROPERTY(bool flatpakPresent READ flatpakPresent CONSTANT)
    Q_PROPERTY(QString braveDesktopId READ braveDesktopId CONSTANT)
    Q_PROPERTY(QString discoverDesktopId READ discoverDesktopId CONSTANT)

public:
    explicit AppAvailability(QObject* parent = nullptr);

    bool braveAvailable() const;
    bool discoverAvailable() const;
    bool flatpakPresent() const { return m_flatpakPresent; }
    QString braveDesktopId() const { return m_braveDesktopId; }
    QString discoverDesktopId() const { return m_discoverDesktopId; }

    Q_INVOKABLE void launchBrave();
    Q_INVOKABLE void launchDiscover();

Q_SIGNALS:
    void launched(bool ok, const QString& what);

private:
    bool m_flatpakPresent = false;
    QString m_braveDesktopId;
    QString m_discoverDesktopId;
};

} // namespace Enthroned
