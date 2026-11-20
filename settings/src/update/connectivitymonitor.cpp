/*
 * Enthroned Settings - connectivity monitor implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "connectivitymonitor.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>

namespace Enthroned {

namespace {
// org.freedesktop.NetworkManager State values that mean "has connectivity".
constexpr quint32 kStateConnectedLocal = 50;
constexpr quint32 kStateConnectedSite = 60;
constexpr quint32 kStateConnectedGlobal = 70;
} // namespace

ConnectivityMonitor::ConnectivityMonitor(QObject* parent)
    : QObject(parent)
{
}

void ConnectivityMonitor::refresh(std::function<void()> then)
{
    const quint64 generation = ++m_generation;
    if (then) {
        m_pending.push_back(std::move(then));
    }
    // No system bus at all: there is no NetworkManager to ask and no pending
    // call that could ever finish. Fail closed (nm stays unavailable, never
    // "offline" without evidence) and run the pending callbacks now, or the
    // classification paths that wait on connectivity never resume.
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        const auto callbacks = std::move(m_pending);
        m_pending.clear();
        for (const auto& callback : callbacks) {
            callback();
        }
        return;
    }
    // Async raw call: QDBusInterface introspects and call() blocks the GUI thread
    // (up to the 25 s default) when NetworkManager is slow or absent.
    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.NetworkManager"),
        QStringLiteral("/org/freedesktop/NetworkManager"),
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    message << QStringLiteral("org.freedesktop.NetworkManager") << QStringLiteral("State");
    auto* watcher = new QDBusPendingCallWatcher(
        bus.asyncCall(message, 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, generation](QDBusPendingCallWatcher* call) {
        call->deleteLater();
        if (generation != m_generation) {
            return; // superseded: a newer refresh owns the state and the pending callbacks
        }
        const QDBusPendingReply<QDBusVariant> state = *call;
        if (state.isError()) {
            // No NetworkManager: never claim "offline" without evidence.
            if (m_nmAvailable) {
                m_nmAvailable = false;
                Q_EMIT onlineChanged();
            }
        } else {
            const quint32 value = state.value().variant().toUInt();
            const bool online = value == kStateConnectedLocal
                || value == kStateConnectedSite
                || value == kStateConnectedGlobal;
            if (online != m_online || !m_nmAvailable) {
                m_online = online;
                m_nmAvailable = true;
                Q_EMIT onlineChanged();
            }
        }
        // Callbacks may call refresh() again, so detach the list first.
        const auto callbacks = std::move(m_pending);
        m_pending.clear();
        for (const auto& callback : callbacks) {
            callback();
        }
    });
}

} // namespace Enthroned
