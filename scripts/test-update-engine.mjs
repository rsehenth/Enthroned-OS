#!/usr/bin/env node
/*
 * Lote 9.2 - host mirror of the compiled update-engine decisions.
 * No Qt/KF6 toolchain exists on this host, so settings/tests/native-smoke.cpp
 * (the authoritative, compiled regression) cannot run here. This mirror
 * re-implements the same pure decisions and runs the SAME case matrices the
 * native smoke test runs in the build:
 *   - H4-001: storagePreflightCheck (storagepreflight.h)
 *   - H4-007: classifyUnitOutcome (systemdoutcome.h)
 *   - H4-007: the check-flow event mapping in updateengine.cpp
 *   - H4-004: the uupd.service running rule in updateengine.cpp
 * Keep the three lists in sync with settings/tests/native-smoke.cpp.
 *
 * Run: node scripts/test-update-engine.mjs
 * SPDX-License-Identifier: Apache-2.0
 */

// ---- mirror of settings/src/update/storagepreflight.h ----
function storagePreflightCheck(isValid, isReady, bytesAvailable, minBytes) {
    if (!isValid || !isReady || bytesAvailable < 0) {
        return "Unreadable";
    }
    return bytesAvailable < minBytes ? "Insufficient" : "Ok";
}

// ---- mirror of settings/src/update/systemdoutcome.h ----
function classifyUnitOutcome(state) {
    const result = state.result ?? "";
    const execMainCode = state.execMainCode ?? 0;
    const execMainStatus = state.execMainStatus ?? 0;
    const conditionResult = state.conditionResult ?? true;
    if (conditionResult === false) {
        return "Skipped";
    }
    if (result === "timeout") {
        return "TimedOut";
    }
    if (execMainCode === 2 || execMainCode === 3
        || result === "signal" || result === "core-dump") {
        return "Killed";
    }
    if (execMainCode === 1) {
        if (execMainStatus === 0) {
            return result === "success" ? "Completed" : "NotExecuted";
        }
        if (execMainStatus === 203) {
            return "NotExecuted"; // systemd: the child could not be executed
        }
        return "ExitedWithError";
    }
    return "NotExecuted";
}

// ---- mirror of the check-flow mapping in updateengine.cpp ----
function checkEvent(outcome, exitStatus) {
    if (outcome === "ExitedWithError" && exitStatus === 77) {
        return "check-no-update";
    }
    if (outcome === "Completed") {
        return "check-update-available";
    }
    return "check-failed";
}

// ---- mirror of the uupd.service rule in updateengine.cpp ----
function autoUpdaterRunning(activeState) {
    return activeState !== "inactive" && activeState !== "failed";
}

let failures = 0;
function expect(desc, actual, expected) {
    const ok = JSON.stringify(actual) === JSON.stringify(expected);
    console.log(`${ok ? "PASS" : "FAIL"}: ${desc}`);
    if (!ok) {
        console.log(`  expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
        ++failures;
    }
}

const GiB = 1024 * 1024 * 1024;
// Same matrix as native-smoke.cpp (H4-001).
const storageCases = [
    { valid: true, ready: true, bytes: 3 * GiB, min: 2 * GiB, expected: "Ok" },
    { valid: true, ready: true, bytes: 1 * GiB, min: 2 * GiB, expected: "Insufficient" },
    { valid: true, ready: true, bytes: 2 * GiB - 1, min: 2 * GiB, expected: "Insufficient" },
    { valid: true, ready: true, bytes: -1, min: 2 * GiB, expected: "Unreadable" },
    { valid: true, ready: false, bytes: 100, min: 2 * GiB, expected: "Unreadable" },
    { valid: false, ready: true, bytes: 100, min: 2 * GiB, expected: "Unreadable" },
    { valid: false, ready: false, bytes: -1, min: 2 * GiB, expected: "Unreadable" },
];
for (const c of storageCases) {
    expect(`H4-001 storage valid=${c.valid} ready=${c.ready} bytes=${c.bytes}`,
        storagePreflightCheck(c.valid, c.ready, c.bytes, c.min), c.expected);
}

// Same matrix as native-smoke.cpp (H4-007).
const outcomeCases = [
    { state: { activeState: "inactive", result: "success", execMainCode: 1, execMainStatus: 0, conditionResult: true }, expected: "Completed" },
    { state: { activeState: "inactive", result: "success", execMainCode: 1, execMainStatus: 77, conditionResult: true }, expected: "ExitedWithError" },
    { state: { activeState: "inactive", result: "success", execMainCode: 1, execMainStatus: 1, conditionResult: true }, expected: "ExitedWithError" },
    { state: { activeState: "failed", result: "exit-code", execMainCode: 1, execMainStatus: 1, conditionResult: true }, expected: "ExitedWithError" },
    { state: { activeState: "failed", result: "signal", execMainCode: 2, execMainStatus: 15, conditionResult: true }, expected: "Killed" },
    { state: { activeState: "failed", result: "core-dump", execMainCode: 3, execMainStatus: 11, conditionResult: true }, expected: "Killed" },
    { state: { activeState: "failed", result: "timeout", execMainCode: 2, execMainStatus: 9, conditionResult: true }, expected: "TimedOut" },
    { state: { activeState: "inactive", result: "success", execMainCode: 1, execMainStatus: 0, conditionResult: false }, expected: "Skipped" },
    { state: { activeState: "failed", result: "exit-code", execMainCode: 1, execMainStatus: 203, conditionResult: true }, expected: "NotExecuted" },
    { state: { activeState: "inactive", result: "success", execMainCode: 0, execMainStatus: 0, conditionResult: true }, expected: "NotExecuted" },
    { state: { activeState: "failed", result: "dependency", execMainCode: 0, execMainStatus: 0, conditionResult: true }, expected: "NotExecuted" },
    { state: { activeState: "failed", result: "start-limit", execMainCode: 0, execMainStatus: 0, conditionResult: true }, expected: "NotExecuted" },
];
for (const c of outcomeCases) {
    expect(`H4-007 outcome result=${c.state.result} code=${c.state.execMainCode} status=${c.state.execMainStatus} condition=${c.state.conditionResult}`,
        classifyUnitOutcome(c.state), c.expected);
}

// Check-flow semantics: only exit 0 and exit 77 produce success events.
expect("H4-007 check exit 0 -> update available", checkEvent("Completed", 0), "check-update-available");
expect("H4-007 check exit 77 -> no update", checkEvent("ExitedWithError", 77), "check-no-update");
expect("H4-007 check exit 1 -> failed", checkEvent("ExitedWithError", 1), "check-failed");
expect("H4-007 check skipped -> failed (never success)", checkEvent("Skipped", 0), "check-failed");
expect("H4-007 check not-executed -> failed", checkEvent("NotExecuted", 0), "check-failed");
expect("H4-007 check timed out -> failed", checkEvent("TimedOut", 0), "check-failed");
expect("H4-007 check killed -> failed", checkEvent("Killed", 0), "check-failed");

// uupd.service states observed by the engine (H4-004).
expect("H4-004 activating blocks", autoUpdaterRunning("activating"), true);
expect("H4-004 active blocks", autoUpdaterRunning("active"), true);
expect("H4-004 reloading blocks", autoUpdaterRunning("reloading"), true);
expect("H4-004 inactive releases", autoUpdaterRunning("inactive"), false);
expect("H4-004 failed releases", autoUpdaterRunning("failed"), false);

// ---- Lote 9.4 mirrors -------------------------------------------------------
// Keep in sync with settings/src/update/systemdpropertymap.h and
// settings/src/update/updateengine.cpp (R93-01/R93-02 decisions).

// R93-01: the D-Bus interface that serves each polled property. The audited
// defect read ConditionResult from the Service interface, where it does not
// exist, and replaced the failed read with "true".
function systemdPropertyInterface(name) {
    if (name === "Result" || name === "ExecMainStatus" || name === "ExecMainCode"
        || name === "ExecMainExitTimestampMonotonic") {
        return "org.freedesktop.systemd1.Service";
    }
    if (name === "LastTriggerUSec" || name === "NextElapseUSecRealtime") {
        return "org.freedesktop.systemd1.Timer";
    }
    return "org.freedesktop.systemd1.Unit";
}
expect("R93-01 ConditionResult lives on the Unit interface",
    systemdPropertyInterface("ConditionResult"), "org.freedesktop.systemd1.Unit");
expect("R93-01 ActiveState lives on the Unit interface",
    systemdPropertyInterface("ActiveState"), "org.freedesktop.systemd1.Unit");
expect("R93-01 ExecMainStatus lives on the Service interface",
    systemdPropertyInterface("ExecMainStatus"), "org.freedesktop.systemd1.Service");
expect("R93-01 Result lives on the Service interface",
    systemdPropertyInterface("Result"), "org.freedesktop.systemd1.Service");
expect("Lote 12 ExecMainExitTimestampMonotonic lives on the Service interface",
    systemdPropertyInterface("ExecMainExitTimestampMonotonic"), "org.freedesktop.systemd1.Service");
expect("R93-01 LastTriggerUSec lives on the Timer interface",
    systemdPropertyInterface("LastTriggerUSec"), "org.freedesktop.systemd1.Timer");

// R93-01: fetchUnitProperties fails closed - any unreadable property makes
// the whole state unknown instead of success-shaped defaults.
function fetchOk(reads) { // reads: {name: readSuccessfully}
    return Object.values(reads).every(Boolean);
}
expect("R93-01 missing ConditionResult fails the whole state read",
    fetchOk({ ActiveState: true, Result: true, ExecMainCode: true,
              ExecMainStatus: true, ConditionResult: false }), false);
expect("R93-01 all properties read -> state usable",
    fetchOk({ ActiveState: true, Result: true, ExecMainCode: true,
              ExecMainStatus: true, ConditionResult: true }), true);

// R93-01: a terminal unit state is only classified when the operation's
// StartUnit job was already removed; otherwise it may be a previous run.
function classifiesTerminalState(jobPending) {
    return !jobPending;
}
expect("R93-01 terminal state with the job still queued is NOT classified",
    classifiesTerminalState(true), false);
expect("R93-01 terminal state after JobRemoved is classified",
    classifiesTerminalState(false), true);

// R93-01: a start job removed without "done" fails the operation per flow.
function jobFailureEvent(kind, jobResult) {
    if (jobResult === "done") {
        return null; // the fresh unit state is classified instead
    }
    if (kind === "Check") return "check-failed";
    if (kind === "UpdateFlatpak") return "flatpak-update-failed";
    if (kind === "Rollback") return "rollback-failed";
    return "update-failed-with-errors";
}
expect("R93-01 canceled check job -> check-failed",
    jobFailureEvent("Check", "canceled"), "check-failed");
expect("R93-01 dependency check job -> check-failed",
    jobFailureEvent("Check", "dependency"), "check-failed");
expect("R93-01 canceled flatpak job -> flatpak-update-failed",
    jobFailureEvent("UpdateFlatpak", "canceled"), "flatpak-update-failed");
expect("R93-01 dependency update job -> update-failed-with-errors",
    jobFailureEvent("UpdateSystem", "dependency"), "update-failed-with-errors");
expect("R93-01 dependency rollback job -> rollback-failed",
    jobFailureEvent("Rollback", "dependency"), "rollback-failed");
expect("R93-01 done job delegates to the unit classification",
    jobFailureEvent("Check", "done"), null);

// R93-02: the Flatpak user stage result finalizes ONLY the operation that
// started it (identity). opId==0 means no operation is running (e.g. after a
// watch timeout), so a late result is recorded without moving the machine.
function userResultOwnsResult(opId, userStageOpId, stageActive, kind, mode) {
    return opId !== 0 && stageActive
        && userStageOpId === opId
        && kind === "UpdateFlatpak" && mode === "apps";
}
expect("R93-02 user result of the current operation finalizes it",
    userResultOwnsResult(1, 1, true, "UpdateFlatpak", "apps"), true);
expect("R93-02 late user result after the operation timed out (opId=0) is record-only",
    userResultOwnsResult(0, 1, true, "UpdateFlatpak", "apps"), false);
expect("R93-02 user result of operation A does not finalize operation B",
    userResultOwnsResult(2, 1, true, "UpdateFlatpak", "apps"), false);
expect("R93-02 user result without a started user stage is record-only",
    userResultOwnsResult(2, 2, false, "UpdateFlatpak", "apps"), false);
expect("R93-02 user result in another flow is record-only",
    userResultOwnsResult(1, 1, true, "UpdateSystem", "system"), false);

// R93-02: progress of the user stage only reaches the UI for the current
// operation; late progress of a timed-out operation is dropped.
function progressApplies(opId, userStageOpId, stageActive, kind) {
    return opId !== 0 && stageActive
        && userStageOpId === opId && kind === "UpdateFlatpak";
}
expect("R93-02 progress of the current user stage applies",
    progressApplies(1, 1, true, "UpdateFlatpak"), true);
expect("R93-02 late progress after the timeout does not apply",
    progressApplies(0, 1, true, "UpdateFlatpak"), false);
expect("R93-02 progress of another operation does not apply",
    progressApplies(2, 1, true, "UpdateFlatpak"), false);

// R93-02: a new apps flow is refused while the previous user process runs.
function appsFlowRefused(userUpdateRunning) {
    return userUpdateRunning;
}
expect("R93-02 retry while the previous user update still runs is refused",
    appsFlowRefused(true), true);
expect("R93-02 retry with an idle provider proceeds",
    appsFlowRefused(false), false);

// R93-02: the watch deadline is a real clock deadline, not a tick count.
function deadlineReached(nowMs, deadlineMs) {
    return nowMs >= deadlineMs;
}
expect("R93-02 deadline is evaluated on the wall clock",
    deadlineReached(1000, 999), true);
expect("R93-02 before the deadline the watch continues",
    deadlineReached(998, 999), false);

if (failures > 0) {
    console.error(`FAILED: ${failures} case(s)`);
    process.exit(1);
}
console.log("ALL CHECKS PASSED");
