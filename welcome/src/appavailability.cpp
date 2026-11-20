/*
 * Enthroned Welcome - application availability implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "appavailability.h"

#include <QDesktopServices>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>

namespace Enthroned {

AppAvailability::AppAvailability(QObject* parent)
    : QObject(parent)
    , m_braveDesktopId(QStringLiteral("com.brave.Browser.desktop"))
    , m_discoverDesktopId(QStringLiteral("org.kde.discover.desktop"))
{
    m_flatpakPresent =
        !QStandardPaths::findExecutable(QStringLiteral("flatpak")).isEmpty();
}

bool AppAvailability::braveAvailable() const
{
    // Covers both the system Flatpak export and a native RPM .desktop file:
    // XDG_DATA_DIRS already includes /var/lib/flatpak/exports/share on Aurora.
    return !QStandardPaths::locate(QStandardPaths::ApplicationsLocation,
                                   m_braveDesktopId)
                .isEmpty();
}

bool AppAvailability::discoverAvailable() const
{
    return !QStandardPaths::locate(QStandardPaths::ApplicationsLocation,
                                   m_discoverDesktopId)
                .isEmpty()
        || !QStandardPaths::findExecutable(QStringLiteral("plasma-discover")).isEmpty();
}

void AppAvailability::launchBrave()
{
    if (!braveAvailable()) {
        Q_EMIT launched(false, m_braveDesktopId);
        return;
    }
    if (m_flatpakPresent
        && QStandardPaths::locate(QStandardPaths::ApplicationsLocation, m_braveDesktopId)
               .contains(QLatin1String("flatpak"))) {
        const bool ok = QProcess::startDetached(
            QStandardPaths::findExecutable(QStringLiteral("flatpak")),
            { QStringLiteral("run"), QStringLiteral("com.brave.Browser") });
        Q_EMIT launched(ok, m_braveDesktopId);
        return;
    }
    QString binary = QStandardPaths::findExecutable(QStringLiteral("brave-browser"));
    if (binary.isEmpty()) {
        binary = QStandardPaths::findExecutable(QStringLiteral("brave"));
    }
    const bool ok = !binary.isEmpty() && QProcess::startDetached(binary, {});
    Q_EMIT launched(ok, m_braveDesktopId);
}

void AppAvailability::launchDiscover()
{
    if (!discoverAvailable()) {
        Q_EMIT launched(false, m_discoverDesktopId);
        return;
    }
    const QString binary = QStandardPaths::findExecutable(QStringLiteral("plasma-discover"));
    if (binary.isEmpty()) {
        // A Flatpak-only Discover installation: route through its desktop file.
        const QString desktop = QStandardPaths::locate(QStandardPaths::ApplicationsLocation,
                                                       m_discoverDesktopId);
        const bool ok = !desktop.isEmpty() && QDesktopServices::openUrl(QUrl::fromLocalFile(desktop));
        Q_EMIT launched(ok, m_discoverDesktopId);
        return;
    }
    const bool ok = QProcess::startDetached(binary, {});
    Q_EMIT launched(ok, m_discoverDesktopId);
}

} // namespace Enthroned
