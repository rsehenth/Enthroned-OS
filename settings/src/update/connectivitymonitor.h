/*
 * Enthroned Settings - connectivity monitor (F3.4 "Sem conexao").
 * Read-only NetworkManager D-Bus state check. Never mutates anything.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>

#include <functional>
#include <vector>

namespace Enthroned {

class ConnectivityMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool online READ online NOTIFY onlineChanged)
    Q_PROPERTY(bool nmAvailable READ nmAvailable NOTIFY onlineChanged)

public:
    explicit ConnectivityMonitor(QObject* parent = nullptr);

    bool online() const { return m_online; }
    bool nmAvailable() const { return m_nmAvailable; }

    // Async. `then` (optional) runs once the answer to THIS refresh (or a newer one)
    // has been applied, so callers can act on fresh state without blocking the UI.
    void refresh(std::function<void()> then = {});

Q_SIGNALS:
    void onlineChanged();

private:
    // nmAvailable == false also means "not known yet": never reported as online or offline.
    bool m_online = false;
    bool m_nmAvailable = false;
    quint64 m_generation = 0;
    std::vector<std::function<void()>> m_pending;
};

} // namespace Enthroned
