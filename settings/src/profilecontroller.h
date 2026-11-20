/*
 * Enthroned Settings - appearance profile controller (F3.3).
 * Thin QML-facing wrapper over the existing user-level tool
 * /usr/bin/enthroned-profile (status/list/apply/restore), which applies
 * profiles through the official KDE mechanism (plasma-apply-lookandfeel).
 * This reuses the F2.1 infrastructure; no second profile mechanism is created.
 * All operations are user-level (no root), asynchronous, read-only except
 * apply/restore which the user triggers explicitly after UI confirmation.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

namespace Enthroned {

class ProfileController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool toolPresent READ toolPresent CONSTANT)
    Q_PROPERTY(QString activeProfile READ activeProfile NOTIFY activeChanged)
    Q_PROPERTY(QString activeLabel READ activeLabel NOTIFY activeChanged)
    Q_PROPERTY(bool canRestore READ canRestore NOTIFY activeChanged)
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY activeChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit ProfileController(QObject* parent = nullptr);

    bool toolPresent() const { return m_toolPresent; }
    QString activeProfile() const { return m_activeProfile; }
    QString activeLabel() const;
    bool canRestore() const { return m_canRestore; }
    QVariantList profiles() const { return m_profiles; }
    bool busy() const { return m_busy; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void apply(const QString& profileId);
    Q_INVOKABLE void restore();

Q_SIGNALS:
    void activeChanged();
    void busyChanged();
    // ok=false carries a human-readable message for the UI.
    void applyFinished(bool ok, const QString& message);

private:
    void setBusy(bool busy);
    void runTool(const QStringList& arguments, bool mutating);
    void parseStatus(const QString& output);
    void refreshList();

    bool m_toolPresent = false;
    bool m_busy = false;
    bool m_canRestore = false;
    QString m_activeProfile;
    QVariantList m_profiles;
};

} // namespace Enthroned
