/*
 * Enthroned Settings - KDE notifications implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "notificationpresenter.h"

#include <KNotification>

namespace Enthroned {

NotificationPresenter::NotificationPresenter(QObject* parent)
    : QObject(parent)
{
}

QString NotificationPresenter::eventId(Event event)
{
    switch (event) {
    case Event::UpdateAvailable:  return QStringLiteral("update-available");
    case Event::DownloadFinished: return QStringLiteral("download-finished");
    case Event::UpdateStaged:     return QStringLiteral("update-staged");
    case Event::RestartRequired:  return QStringLiteral("restart-required");
    case Event::UpdateFailed:     return QStringLiteral("update-failed");
    }
    return QStringLiteral("update-available");
}

void NotificationPresenter::notify(Event event, const QString& title, const QString& text)
{
    auto* notification = new KNotification(eventId(event),
                                           KNotification::CloseOnTimeout, this);
    notification->setComponentName(QStringLiteral("enthronedsettings"));
    notification->setTitle(title);
    notification->setText(text);
    notification->sendEvent();
}

} // namespace Enthroned
