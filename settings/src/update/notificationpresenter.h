/*
 * Enthroned Settings - KDE notifications (F3.11).
 * Native KNotification events, driven ONLY by real events from the engine.
 * Never emits "concluded" without evidence; never triggers a reboot.
 * Runtime NOT RUN (needs a Plasma session) - source implemented.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QString>

namespace Enthroned {

class NotificationPresenter : public QObject
{
    Q_OBJECT
public:
    explicit NotificationPresenter(QObject* parent = nullptr);

    enum class Event {
        UpdateAvailable,
        DownloadFinished,
        UpdateStaged,
        RestartRequired,
        UpdateFailed
    };

    void notify(Event event, const QString& title, const QString& text);

private:
    static QString eventId(Event event);
};

} // namespace Enthroned
