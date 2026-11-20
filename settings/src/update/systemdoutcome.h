/*
 * Enthroned Settings - systemd unit outcome classification (Lote 9.2, H4-007).
 * Pure mapping from polled unit properties (SystemdCalls::unitState) to a
 * semantic outcome, so the compiled smoke test can cover condition-skipped,
 * signalled, timed out, spawn-failed and exit-code finishes without a running
 * systemd. Callers must only classify TERMINAL states (ActiveState inactive
 * or failed); a running unit is waited for, not classified.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QString>
#include <QVariantMap>

namespace Enthroned {

enum class UnitOutcome {
    Completed,       // ExecStart ran and exited 0 with Result=success
    ExitedWithError, // ExecStart ran, exit code != 0 (77 keeps its special check-flow meaning)
    Killed,          // ExecStart died by signal or core dump
    TimedOut,        // systemd stopped the unit on its start timeout
    Skipped,         // a Condition*= was not satisfied; ExecStart never ran
    NotExecuted      // failed before ExecStart (spawn/exec failure, dependency, start-limit, protocol...)
};

inline UnitOutcome classifyUnitOutcome(const QVariantMap& state)
{
    // systemd ExecMainCode: 1 = CLD_EXITED, 2 = CLD_KILLED, 3 = CLD_DUMPED.
    const QString result = state.value(QStringLiteral("result")).toString();
    const int execMainCode = state.value(QStringLiteral("execMainCode")).toInt();
    const int execMainStatus = state.value(QStringLiteral("execMainStatus")).toInt();

    // A false ConditionResult means the unit was skipped: no exit code in the
    // world proves anything ran (H4-007).
    if (!state.value(QStringLiteral("conditionResult"), true).toBool()) {
        return UnitOutcome::Skipped;
    }
    if (result == QLatin1String("timeout")) {
        return UnitOutcome::TimedOut;
    }
    if (execMainCode == 2 || execMainCode == 3
        || result == QLatin1String("signal") || result == QLatin1String("core-dump")) {
        return UnitOutcome::Killed;
    }
    if (execMainCode == 1) {
        if (execMainStatus == 0) {
            return result == QLatin1String("success") ? UnitOutcome::Completed
                                                      : UnitOutcome::NotExecuted;
        }
        // systemd's fixed convention: 203 is returned when the child could
        // not be executed at all (spawn/exec failure), not by the program.
        if (execMainStatus == 203) {
            return UnitOutcome::NotExecuted;
        }
        return UnitOutcome::ExitedWithError;
    }
    // Terminal without an executed ExecStart (dependency, start-limit,
    // protocol...): never reported as a completed operation.
    return UnitOutcome::NotExecuted;
}

} // namespace Enthroned
