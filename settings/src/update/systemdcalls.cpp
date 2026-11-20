/*
 * Enthroned Settings - systemd D-Bus implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "systemdcalls.h"
#include "systemdpropertymap.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QScopedPointer>

#include <KLocalizedString>

namespace Enthroned {

namespace {
const auto kService = QStringLiteral("org.freedesktop.systemd1");
const auto kManagerPath = QStringLiteral("/org/freedesktop/systemd1");
const auto kManagerInterface = QStringLiteral("org.freedesktop.systemd1.Manager");
const auto kPropsInterface = QStringLiteral("org.freedesktop.DBus.Properties");

QDBusInterface* manager()
{
    return new QDBusInterface(kService, kManagerPath, kManagerInterface,
                              QDBusConnection::systemBus());
}
} // namespace

SystemdCalls::SystemdCalls(QObject* parent)
    : QObject(parent)
{
    m_available = QDBusConnection::systemBus().isConnected();
    // R93-01: registered BEFORE any StartUnit can run, so a job that finishes
    // immediately (e.g. the unit was already running) is still observed.
    if (m_available) {
        QDBusConnection::systemBus().connect(kService, kManagerPath, kManagerInterface,
            QStringLiteral("JobRemoved"), this,
            SLOT(onJobRemoved(unsigned int, QDBusObjectPath, QString, QString)));
    }
}

QVariantMap SystemdCalls::fetchUnitProperties(const QString& unit,
                                              const QStringList& names, bool* ok)
{
    QVariantMap result;
    QDBusInterface managerIface(kService, kManagerPath, kManagerInterface,
                                QDBusConnection::systemBus());
    if (!managerIface.isValid()) {
        if (m_available) {
            m_available = false;
            Q_EMIT availableChanged();
        }
        if (ok) *ok = false;
        return result;
    }
    const QDBusReply<QDBusObjectPath> path = managerIface.call(QStringLiteral("LoadUnit"), unit);
    if (!path.isValid()) {
        if (ok) *ok = false;
        return result;
    }

    QDBusInterface props(kService, path.value().path(), kPropsInterface,
                         QDBusConnection::systemBus());
    if (!props.isValid()) {
        if (ok) *ok = false;
        return result;
    }
    // R93-01: every requested property must be read or the whole query fails.
    // A missing property used to be dropped here and later replaced by a
    // success default (conditionResult=true); now the caller sees ok=false
    // and treats the state as unknown.
    bool allRead = true;
    const QString exitClock = QStringLiteral("ExecMainExitTimestampMonotonic");
    const QString serviceInterface = systemdPropertyInterface(exitClock);
    const bool readsProcessOutcome = names.contains(exitClock);
    QVariantMap serviceProperties;
    if (readsProcessOutcome) {
        // Fetch the process outcome and exit clock in one D-Bus reply.
        const QDBusReply<QVariantMap> reply = props.call(QStringLiteral("GetAll"), serviceInterface);
        if (reply.isValid()) {
            serviceProperties = reply.value();
        }
    }
    for (const QString& name : names) {
        const QString interface = systemdPropertyInterface(name);
        if (readsProcessOutcome && interface == serviceInterface) {
            if (serviceProperties.contains(name)) {
                result.insert(name, serviceProperties.value(name));
            } else if (name != exitClock) {
                allRead = false;
            }
            continue;
        }
        const QDBusReply<QDBusVariant> value =
            props.call(QStringLiteral("Get"), interface, name);
        if (value.isValid()) {
            result.insert(name, value.value().variant());
        } else {
            allRead = false;
        }
    }
    if (ok) *ok = allRead;
    return result;
}

void SystemdCalls::startUnit(const QString& unit)
{
    QScopedPointer<QDBusInterface> iface(manager());
    if (!iface || !iface->isValid()) {
        if (m_available) {
            m_available = false;
            Q_EMIT availableChanged();
        }
        Q_EMIT startUnitResult(unit, false, i18n("systemd D-Bus is unavailable"));
        return;
    }
    const QDBusReply<QDBusObjectPath> reply =
        iface->call(QStringLiteral("StartUnit"), unit, QStringLiteral("replace"));
    if (reply.isValid()) {
        // R93-01: keep the returned job so JobRemoved can be correlated with
        // THIS start request instead of any unit state from a previous run.
        const QString jobPath = reply.value().path();
        m_startedJobs.insert(jobPath, unit);
        Q_EMIT jobQueued(unit, jobPath);
        Q_EMIT startUnitResult(unit, true, QString());
    } else {
        Q_EMIT startUnitResult(unit, false, reply.error().message().left(200));
    }
}

void SystemdCalls::onJobRemoved(unsigned int /*id*/, const QDBusObjectPath& job,
                                const QString& unit, const QString& result)
{
    const QString jobPath = job.path();
    if (!m_startedJobs.contains(jobPath)) {
        return; // a job this process did not start; not our correlation
    }
    m_startedJobs.remove(jobPath);
    Q_EMIT jobFinished(unit, jobPath, result);
}

void SystemdCalls::unitState(const QString& unit)
{
    bool ok = false;
    const QVariantMap props = fetchUnitProperties(
        unit,
        { QStringLiteral("ActiveState"), QStringLiteral("SubState"),
          QStringLiteral("Result"), QStringLiteral("ExecMainStatus"),
          QStringLiteral("ExecMainCode"), QStringLiteral("ConditionResult"),
          QStringLiteral("ExecMainExitTimestampMonotonic") },
        &ok);

    if (!ok) {
        // R93-01: unknown state is never reported as a success-shaped state.
        Q_EMIT unitState(unit, QVariantMap{ { QStringLiteral("error"), true } });
        return;
    }

    QVariantMap state;
    state.insert(QStringLiteral("activeState"), props.value(QStringLiteral("ActiveState")).toString());
    state.insert(QStringLiteral("subState"), props.value(QStringLiteral("SubState")).toString());
    state.insert(QStringLiteral("result"), props.value(QStringLiteral("Result")).toString());
    state.insert(QStringLiteral("execMainStatus"), props.value(QStringLiteral("ExecMainStatus")).toInt());
    state.insert(QStringLiteral("execMainCode"), props.value(QStringLiteral("ExecMainCode")).toInt());
    state.insert(QStringLiteral("execMainExitUsec"),
                 props.value(QStringLiteral("ExecMainExitTimestampMonotonic")).toULongLong());
    // ConditionResult comes from the Unit interface (R93-01); with the
    // fail-closed fetch above it is always present here. No success default.
    state.insert(QStringLiteral("conditionResult"),
                 props.value(QStringLiteral("ConditionResult")).toBool());
    Q_EMIT unitState(unit, state);
}

bool SystemdCalls::unitActive(const QString& unit)
{
    bool ok = false;
    const QVariantMap props =
        fetchUnitProperties(unit, { QStringLiteral("ActiveState") }, &ok);
    if (!ok) {
        return true; // fail closed: an unreadable state must not allow a new start
    }
    const QString state = props.value(QStringLiteral("ActiveState")).toString();
    return state == QLatin1String("active") || state == QLatin1String("activating")
        || state == QLatin1String("reloading");
}

void SystemdCalls::timerState(const QString& unit)
{
    bool ok = false;
    const QVariantMap props = fetchUnitProperties(
        unit,
        { QStringLiteral("UnitFileState"), QStringLiteral("ActiveState"),
          QStringLiteral("LastTriggerUSec"), QStringLiteral("NextElapseUSecRealtime") },
        &ok);
    if (!ok) {
        Q_EMIT timerState(unit, QVariantMap{ { QStringLiteral("error"), true } });
        return;
    }

    QVariantMap timer;
    timer.insert(QStringLiteral("unitFileState"), props.value(QStringLiteral("UnitFileState")).toString());
    timer.insert(QStringLiteral("activeState"), props.value(QStringLiteral("ActiveState")).toString());
    timer.insert(QStringLiteral("lastTriggerUSec"), props.value(QStringLiteral("LastTriggerUSec")).toLongLong());
    timer.insert(QStringLiteral("nextElapseUSec"), props.value(QStringLiteral("NextElapseUSecRealtime")).toLongLong());
    Q_EMIT timerState(unit, timer);
}

} // namespace Enthroned
