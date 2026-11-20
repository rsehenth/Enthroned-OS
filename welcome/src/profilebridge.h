/*
 * Enthroned Welcome - appearance profile bridge (F4.5 tela 2).
 * Reuses the F2.1 user-level tool /usr/bin/enthroned-profile (status/apply),
 * which applies profiles through the official KDE mechanism
 * (plasma-apply-lookandfeel). No second profile mechanism is created; no
 * profile is ever applied automatically - applying is always an explicit
 * user action triggered from the UI.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QString>

namespace Enthroned {

class ProfileBridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool toolPresent READ toolPresent CONSTANT)
    Q_PROPERTY(QString activeProfile READ activeProfile NOTIFY activeChanged)
    Q_PROPERTY(QString activeLabel READ activeLabel NOTIFY activeChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit ProfileBridge(QObject* parent = nullptr);
    ~ProfileBridge() override;

    bool toolPresent() const { return m_toolPresent; }
    QString activeProfile() const { return m_activeProfile; }
    QString activeLabel() const;
    bool busy() const { return m_busy; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void apply(const QString& profileId);

Q_SIGNALS:
    void activeChanged();
    void busyChanged();
    // ok=false carries a human-readable message for the UI.
    void applyFinished(bool ok, const QString& message);

private:
    void runTool(const QStringList& arguments, bool mutating);
    void parseStatus(const QString& output);
    void setBusy(bool busy);

    bool m_toolPresent = false;
    bool m_busy = false;
    QString m_activeProfile;
    QPointer<QProcess> m_process;
};

} // namespace Enthroned
