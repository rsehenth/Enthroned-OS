/*
 * Enthroned Settings - systemd D-Bus property to interface mapping (Lote 9.4, R93-01).
 * Pure mapping so the compiled tests can pin WHERE each polled property lives:
 * ConditionResult is a property of org.freedesktop.systemd1.Unit (every unit
 * type has it), NOT of org.freedesktop.systemd1.Service - reading it from the
 * Service interface fails and used to be silently replaced by "true". Result,
 * ExecMainCode, ExecMainStatus and ExecMainExitTimestampMonotonic belong
 * to the Service interface. Timer
 * properties belong to org.freedesktop.systemd1.Timer. Everything else is
 * served by the Unit interface.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QString>

namespace Enthroned {

inline QString systemdPropertyInterface(const QString& propertyName)
{
    if (propertyName == QLatin1String("Result")
        || propertyName == QLatin1String("ExecMainStatus")
        || propertyName == QLatin1String("ExecMainCode")
        || propertyName == QLatin1String("ExecMainExitTimestampMonotonic")) {
        return QStringLiteral("org.freedesktop.systemd1.Service");
    }
    if (propertyName == QLatin1String("LastTriggerUSec")
        || propertyName == QLatin1String("NextElapseUSecRealtime")) {
        return QStringLiteral("org.freedesktop.systemd1.Timer");
    }
    // ConditionResult, ActiveState, SubState, UnitFileState and every other
    // generic unit property live on the Unit interface (R93-01).
    return QStringLiteral("org.freedesktop.systemd1.Unit");
}

} // namespace Enthroned
