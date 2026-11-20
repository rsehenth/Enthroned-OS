/*
 * Enthroned Settings - native KCM launcher (F3.1 Apps/Devices pages).
 * Entry points to REAL KDE System Settings modules via kcmshell6. Availability
 * is detected with `kcmshell6 --list`; unavailable modules stay disabled with
 * an honest "indisponivel" state. No fake controls.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QStringList>

namespace Enthroned {

class KcmLauncher : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool toolPresent READ toolPresent CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // Module ids reported by `kcmshell6 --list`. QML bindings that read this
    // property re-evaluate when the asynchronous refresh finishes (a plain
    // isAvailable() call in a binding would not).
    Q_PROPERTY(QStringList available READ available NOTIFY availableChanged)

public:
    explicit KcmLauncher(QObject* parent = nullptr);

    bool toolPresent() const { return m_toolPresent; }
    bool busy() const { return m_busy; }
    QStringList available() const { return m_available; }

    Q_INVOKABLE void refreshAvailable();
    Q_INVOKABLE bool isAvailable(const QString& module) const;
    Q_INVOKABLE void launch(const QString& module);

    // F4.9: entry points to real Enthroned applications (not KCM modules).
    // Availability is detected honestly; unknown programs never launch.
    Q_INVOKABLE bool hasExecutable(const QString& program) const;
    Q_INVOKABLE bool hasFlatpakApp(const QString& appId) const;
    Q_INVOKABLE void launchApp(const QString& program);

Q_SIGNALS:
    void busyChanged();
    void availableChanged();
    void launched(bool ok, const QString& module);

private:
    void setBusy(bool busy);
    bool m_toolPresent = false;
    bool m_busy = false;
    QStringList m_available;
};

} // namespace Enthroned
