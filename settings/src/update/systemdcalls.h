/*
 * Enthroned Settings - systemd D-Bus calls (F3.5/F3.7 authorization boundary).
 * All privileged interactions go through org.freedesktop.systemd1 on the
 * system bus. The GUI never invokes sudo/pkexec and never runs mutating
 * commands itself:
 *   - startUnit("enthroned-update-check.service")  read-only check oneshot
 *     (authorized by the Enthroned polkit rule shipped with the image);
 *   - startUnit("uupd-manual.service")             the REAL update unit
 *     already shipped by Aurora (authorized by upstream uupd.rules).
 * unitState() polls unit properties (ActiveState/SubState/Result/
 * ExecMainStatus) - read-only D-Bus.
 * timerInfo() reads uupd.timer properties - read-only D-Bus (F3.8).
 * R93-01 (Lote 9.4): StartUnit returns the queued job; JobRemoved reports how
 * that job ended (done/canceled/failed/dependency/skipped/timeout). The job
 * path is forwarded so a caller can correlate the removal with THE operation
 * it started and never mistake a previous unit state for the new run.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QMap>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

class QDBusObjectPath;

namespace Enthroned {

class SystemdCalls : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit SystemdCalls(QObject* parent = nullptr);

    bool available() const { return m_available; }

    // Virtual (Lote 9.4): the engine integration test injects a subclass.
    // Start a system unit ("replace"). Emits startUnitResult(unit, ok,
    // errorHint) and, when accepted, jobQueued(unit, jobPath).
    Q_INVOKABLE virtual void startUnit(const QString& unit);

    // Poll unit properties. Emits unitState(unit, stateMap).
    // stateMap: activeState, subState, result, execMainStatus (int),
    //           execMainCode (int: 1=CLD_EXITED, 2=CLD_KILLED, 3=CLD_DUMPED),
    //           conditionResult (bool: false = skipped, ExecStart never ran),
    //           execMainExitUsec (quint64: CLOCK_MONOTONIC, 0 when unknown)
    // A failed property read emits the {error: true} map instead of defaults
    // that could read as success (R93-01).
    Q_INVOKABLE virtual void unitState(const QString& unit);

    // Poll timer properties. Emits timerState(unit, timerMap).
    // timerMap: unitFileState, activeState, lastTriggerUSec (qint64),
    //           nextElapseUSec (qint64)
    Q_INVOKABLE virtual void timerState(const QString& unit);

    // Synchronous read-only check used before queueing another start: true
    // when the unit is active/activating/reloading OR its state cannot be
    // read (fail closed - never stack a start on an unknown unit state).
    virtual bool unitActive(const QString& unit);

Q_SIGNALS:
    void availableChanged();
    void startUnitResult(const QString& unit, bool ok, const QString& errorHint);
    void unitState(const QString& unit, const QVariantMap& state);
    void timerState(const QString& unit, const QVariantMap& timer);
    // R93-01: emitted right after StartUnit accepts the job (before any
    // completion), so observers can register the correlation first.
    void jobQueued(const QString& unit, const QString& jobPath);
    // Emitted when a job started by THIS process is removed; result is
    // systemd's JobRemoved result (done/canceled/failed/dependency/skipped/...).
    void jobFinished(const QString& unit, const QString& jobPath, const QString& result);

private Q_SLOTS:
    void onJobRemoved(unsigned int id, const QDBusObjectPath& job,
                      const QString& unit, const QString& result);

private:
    QVariantMap fetchUnitProperties(const QString& unit, const QStringList& names, bool* ok);

protected:
    // Protected so a test double can report availability without a bus.
    bool m_available = false;

private:
    // StartUnit job path -> unit, for correlating JobRemoved with the caller.
    QMap<QString, QString> m_startedJobs;
};

} // namespace Enthroned
