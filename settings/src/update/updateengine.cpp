/*
 * Enthroned Settings - update engine implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "updateengine.h"

#include "../bootcstatusprovider.h"
#include "../flatpakupdatesprovider.h"
#include "../systemidentityprovider.h"
#include "connectivitymonitor.h"
#include "historylog.h"
#include "imageorigin.h"
#include "journalprogresssource.h"
#include "notificationpresenter.h"
#include "storagepreflight.h"
#include "systemdcalls.h"
#include "systemdoutcome.h"
#include "updateevent.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>
#include <QStorageInfo>
#include <KLocalizedString>

#include <algorithm>

namespace Enthroned {

namespace {
constexpr auto kCheckUnit = "enthroned-update-check.service";
constexpr auto kManualUnit = "uupd-manual.service";
constexpr auto kAutoUnit = "uupd.service";
constexpr auto kTimerUnit = "uupd.timer";
// Lote 8: Enthroned-owned units with FIXED commands (no arguments from the
// UI, ever). Authorized for wheel users by the Enthroned polkit rule.
constexpr auto kSystemUnit = "enthroned-system-update.service";
constexpr auto kFlatpakUnit = "enthroned-flatpak-update.service";
constexpr auto kRollbackUnit = "enthroned-rollback.service";
constexpr int kEventLogCap = 200;
// Storage preflight thresholds. bootc writes the new deployment to the
// sysroot (/ostree); Flatpak writes to /var (system installation).
constexpr qint64 kMinBootcFreeBytes = 2LL * 1024 * 1024 * 1024; // 2 GiB
constexpr qint64 kMinVarFreeBytes = 1LL * 1024 * 1024 * 1024;   // 1 GiB

QVariantMap updateRow(const QString& source, const QString& id,
                      const QString& version, const QString& detail)
{
    QVariantMap row;
    row.insert(QStringLiteral("source"), source);
    row.insert(QStringLiteral("id"), id);
    row.insert(QStringLiteral("version"), version);
    row.insert(QStringLiteral("detail"), detail);
    return row;
}

// H4-007: one user-facing sentence per semantic outcome; only Completed can
// read as success anywhere in the engine.
QString unitFailureText(UnitOutcome outcome, int exitStatus, const QString& what)
{
    switch (outcome) {
    case UnitOutcome::Skipped:
        return i18n("%1 did not run: the unit condition was not satisfied").arg(what);
    case UnitOutcome::TimedOut:
        return i18n("%1 timed out").arg(what);
    case UnitOutcome::Killed:
        return i18n("%1 was terminated by a signal").arg(what);
    case UnitOutcome::NotExecuted:
        return i18n("%1 did not execute (the unit failed before ExecStart)").arg(what);
    case UnitOutcome::ExitedWithError:
    case UnitOutcome::Completed:
        break;
    }
    return i18n("%1 ended with errors (code %2)").arg(what).arg(exitStatus);
}
} // namespace

UpdateEngine::UpdateEngine(const QStringList& arguments,
                           SystemdCalls* systemdOverride,
                           const QString& flatpakBinaryOverride,
                           const QString& bootcBinaryOverride,
                           qint64 watchTimeoutMs,
                           int pollIntervalMs,
                           QObject* parent,
                           const QString& bootcStatusFileOverride)
    : QObject(parent)
{
    m_demoMode = arguments.contains(QLatin1String("--demo"))
        || qEnvironmentVariable("ENTHRONED_SETTINGS_DEMO") == QLatin1String("1");
    m_mutationAllowed = !m_demoMode
        && qEnvironmentVariable("ENTHRONED_SETTINGS_ALLOW_MUTATION") == QLatin1String("1");

    if (m_demoMode) {
        const int scenarioIndex = arguments.indexOf(QLatin1String("--demo-scenario"));
        const QString scenario = scenarioIndex >= 0 ? arguments.value(scenarioIndex + 1) : QString();
        m_demoScenarioName = !scenario.isEmpty()
            ? scenario
            : qEnvironmentVariable("ENTHRONED_SETTINGS_DEMO_SCENARIO", QStringLiteral("update-available"));
    }

    // Lote 9.4 seams: tests inject a SystemdCalls double and fake
    // flatpak/bootc programs; production keeps the real calls (no real update
    // is ever started by a test binary).
    m_watchTimeoutMs = watchTimeoutMs > 0 ? watchTimeoutMs : kDefaultWatchTimeoutMs;
    m_systemd = systemdOverride ? systemdOverride : new SystemdCalls(this);
    m_connectivity = new ConnectivityMonitor(this);
    m_bootc = new BootcStatusProvider(bootcBinaryOverride, this, bootcStatusFileOverride);
    m_flatpak = new FlatpakUpdatesProvider(flatpakBinaryOverride, this);
    m_historyLog = new HistoryLog(this);
    m_notifications = new NotificationPresenter(this);
    m_journal = new JournalProgressSource(m_spec, this);
    m_expectedImages = SystemIdentityProvider().expectedImageReferences();
    m_minBootcFreeBytes = kMinBootcFreeBytes;
    m_minVarFreeBytes = kMinVarFreeBytes;

    m_pollTimer.setInterval(pollIntervalMs > 0 ? pollIntervalMs : kDefaultPollIntervalMs);
    connect(&m_pollTimer, &QTimer::timeout, this, &UpdateEngine::pollWatchedUnit);

    loadSpec();
    connectProviders();

    if (m_demoMode) {
        m_demoTimer.setSingleShot(true);
        connect(&m_demoTimer, &QTimer::timeout, this, &UpdateEngine::demoTimerTick);
        startDemoScenario(m_demoScenarioName);
    }
}

bool UpdateEngine::loadSpec()
{
    QFile specFile(QStringLiteral(":/src/update/update-state-spec.json"));
    QString error;
    if (!specFile.open(QIODevice::ReadOnly) || !m_spec.loadSpec(specFile.readAll(), &error)) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("spec-error");
        event.severity = UpdateSeverity::Error;
        event.description = error.isEmpty()
            ? i18n("State machine spec unavailable")
            : error;
        pushEvent(event);
        return false;
    }
    return true;
}

void UpdateEngine::connectProviders()
{
    // bootc status -> normalized events (source of truth for staged/restart).
    connect(m_bootc, &BootcStatusProvider::statusResult, this,
            [this](bool ok, bool staged) {
        if (m_operationId != 0
            && (m_watchKind == UpdateWatchKind::UpdateFull
                || m_watchKind == UpdateWatchKind::UpdateSystem
                || m_watchKind == UpdateWatchKind::Rollback)) {
            return; // The unit outcome precedes any deployment confirmation.
        }
        const bool awaitingDeployment = m_state == QLatin1String("deploymentPending");
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = ok ? QStringLiteral("bootc-status-ok")
                           : QStringLiteral("bootc-status-unavailable");
        event.description = ok
            ? i18n("Deployment status queried")
            : m_bootc->errorHint();
        event.severity = ok ? UpdateSeverity::Info : UpdateSeverity::Warning;
        event.operationId = QStringLiteral("bootc-status");
        if (!ok) {
            applyEvent(event);
            return;
        }
        if (awaitingDeployment && !hasFreshDeployment()) {
            return;
        }

        const quint64 captureUsec = m_bootc->captureUsec();
        if (captureUsec < m_lastDeploymentCaptureUsec) {
            return;
        }
        const bool wasStaged = m_stagedDeploymentPending;
        // Only a newer observation can supersede a confirmed staged deployment.
        if (wasStaged && !staged && captureUsec == m_lastDeploymentCaptureUsec) {
            return;
        }
        m_lastDeploymentCaptureUsec = captureUsec;
        m_stagedDeploymentPending = staged;
        if (staged) {
            // Lote 8: the staged deployment must still come from the
            // Enthroned channel origin; flag anything else for the UI.
            const bool wasOriginBlocked = m_stagedOriginBlocked;
            const QString origin = ImageOrigin::classify(m_bootc->stagedImageRef(),
                                                         m_expectedImages);
            m_stagedOriginBlocked = !ImageOrigin::allowsUpdate(origin);
            if (m_stagedOriginBlocked && !wasOriginBlocked) {
                UpdateEvent blockedEvent;
                blockedEvent.source = QStringLiteral("engine");
                blockedEvent.rawType = QStringLiteral("staged-origin-blocked");
                blockedEvent.severity = UpdateSeverity::Warning;
                blockedEvent.description = i18n(
                    "The staged deployment does not come from the Enthroned channel origin");
                applyEvent(blockedEvent);
            }
            if (!wasStaged || awaitingDeployment) {
                event.rawType = QStringLiteral("staged-deployment-detected");
                event.phase = UpdatePhase::WaitingRestart;
                event.description = i18n("New deployment staged");
                applyEvent(event);
            }
            if (!wasStaged || m_stagedOriginBlocked != wasOriginBlocked) {
                Q_EMIT stateChanged();
            }
            return;
        }

        m_stagedOriginBlocked = false;
        if (awaitingDeployment) {
            event.rawType = QStringLiteral("deployment-confirmed");
            event.description = i18n("Deployment status confirmed; no restart is pending.");
            event.phase = UpdatePhase::Completed;
            event.result = UpdateResult::Success;
        } else if (wasStaged && !m_lastOperationWasRollback) {
            event.rawType = QStringLiteral("staged-deployment-cleared");
        }
        applyEvent(event);
        if (wasStaged) {
            Q_EMIT stateChanged();
        }
    });
    connect(m_bootc, &BootcStatusProvider::availableChanged, this, &UpdateEngine::refreshAutoUpdates);
    // The booted image origin gates canUpdate/updateBlockReason, both bound to stateChanged.
    connect(m_bootc, &BootcStatusProvider::availableChanged, this, &UpdateEngine::stateChanged);

    // systemd availability
    connect(m_systemd, &SystemdCalls::availableChanged, this,
            &UpdateEngine::serviceAvailabilityChanged);
    connect(m_systemd, &SystemdCalls::availableChanged, this, &UpdateEngine::stateChanged);

    // connectivity (used by offline guards and the UI)
    connect(m_connectivity, &ConnectivityMonitor::onlineChanged, this,
            &UpdateEngine::connectivityChanged);

    // journal events -> machine + log
    connect(m_journal, &JournalProgressSource::updateEvent, this,
            [this](const QVariantMap& map) {
        const UpdateEvent event = UpdateEvent::fromVariantMap(map);
        if (event.rawType != QLatin1String("update-success")) {
            applyEvent(event); // Completion comes from the correlated unit result.
        }
    });

    // history sources -> pending lists -> merge
    connect(m_journal, &JournalProgressSource::historyFetched, this,
            [this](const QVariantList& journalEntries) {
        m_pendingJournalHistory = journalEntries;
        mergeHistory();
    });
    connect(m_flatpak, &FlatpakUpdatesProvider::historyFetched, this,
            [this](const QVariantList& flatpakEntries) {
        m_pendingFlatpakHistory = flatpakEntries;
        mergeHistory();
    });

    // Lote 8: user-installation Flatpak update progress (fixed command).
    connect(m_flatpak, &FlatpakUpdatesProvider::userUpdateProgress, this,
            [this](int percent, const QString& item) {
        // R93-02: only the user stage of the CURRENT operation may drive the
        // UI; late progress of a timed-out operation is dropped, never merged
        // into another operation's indicator.
        if (m_operationId == 0 || !m_flatpakUserStageActive
            || m_userStageOpId != m_operationId
            || m_watchKind != UpdateWatchKind::UpdateFlatpak) {
            return;
        }
        UpdateEvent event;
        event.source = QStringLiteral("flatpak");
        event.rawType = QStringLiteral("flatpak-progress");
        event.phase = UpdatePhase::Downloading;
        event.progressPercent = percent; // < 0 keeps the indicator indeterminate
        event.currentItem = item;
        event.description = item.isEmpty()
            ? i18n("Updating user applications")
            : i18n("Updating %1").arg(item);
        applyEvent(event);
    });
    connect(m_flatpak, &FlatpakUpdatesProvider::userUpdateFinished, this,
            [this](bool ok, const QString& errorHint) {
        // R93-02: the user stage finalizes ONLY the operation that started it.
        // A result of a timed-out operation (its id is no longer current, or
        // no operation is running) is recorded without moving the machine,
        // without ending another operation and without a refresh on its behalf.
        const bool ownsResult = m_operationId != 0 && m_flatpakUserStageActive
            && m_userStageOpId == m_operationId
            && m_watchKind == UpdateWatchKind::UpdateFlatpak
            && m_updateMode == QLatin1String("apps");
        if (!ownsResult) {
            UpdateEvent event;
            event.source = QStringLiteral("flatpak");
            event.rawType = ok ? QStringLiteral("flatpak-update-success")
                               : QStringLiteral("flatpak-update-failed");
            event.severity = ok ? UpdateSeverity::Info : UpdateSeverity::Error;
            event.description = ok ? i18n("User applications updated")
                                   : errorHint;
            pushEvent(event);
            return;
        }
        m_flatpakUserStageActive = false;
        m_userStageOpId = 0;
        m_lastOperationWasUpdate = false;
        UpdateEvent event;
        event.source = QStringLiteral("flatpak");
        event.rawType = ok ? QStringLiteral("flatpak-update-success")
                           : QStringLiteral("flatpak-update-failed");
        event.phase = ok ? UpdatePhase::Completed : UpdatePhase::Failed;
        event.severity = ok ? UpdateSeverity::Info : UpdateSeverity::Error;
        event.result = ok ? UpdateResult::Success : UpdateResult::Failure;
        event.description = ok
            ? i18n("Applications updated")
            : (errorHint.isEmpty() ? i18n("The application update ended with errors")
                                   : errorHint);
        applyEvent(event);
        endOperation();
        if (!ok) {
            m_notifications->notify(NotificationPresenter::Event::UpdateFailed,
                i18n("Application update failed"),
                i18n("The application update ended with errors. See the details in System updates."));
        }
        refreshAll();
    });

    // flatpak listing contributes rows to the available updates view
    connect(m_flatpak, &FlatpakUpdatesProvider::availableChanged, this, [this]() {
        QVariantList rows;
        if (m_state != QLatin1String("deploymentPending")
            && m_bootc->available() && m_bootc->stagedPresent()) {
            const QString version = m_bootc->stagedVersion().isEmpty()
                ? i18n("new image from the current channel")
                : m_bootc->stagedVersion();
            rows.append(updateRow(QStringLiteral("system"), QStringLiteral("bootc-image"),
                                  version, i18n("System image (bootc)")));
        }
        for (const QVariant& app : m_flatpak->updates()) {
            const QVariantMap appMap = app.toMap();
            rows.append(updateRow(QStringLiteral("flatpak"), appMap.value(QStringLiteral("id")).toString(),
                                  appMap.value(QStringLiteral("version")).toString(),
                                  appMap.value(QStringLiteral("origin")).toString()));
        }
        m_availableUpdates = rows;
        Q_EMIT updatesChanged();
    });

    // check unit lifecycle
    connect(m_systemd, &SystemdCalls::startUnitResult, this,
            [this](const QString& unit, bool ok, const QString& errorHint) {
        if (unit == QLatin1String(kCheckUnit)) {
            if (!ok) {
                m_checkUnitStarted = false;
                endOperation();
                // Fresh connectivity decides the event type; the answer is async (<= 5 s).
                m_connectivity->refresh([this, errorHint]() {
                    UpdateEvent event;
                    event.source = QStringLiteral("check");
                    event.rawType = m_connectivity->nmAvailable() && !m_connectivity->online()
                        ? QStringLiteral("check-failed")
                        : QStringLiteral("systemd-unavailable");
                    event.severity = UpdateSeverity::Error;
                    event.description = errorHint.isEmpty()
                        ? i18n("Could not start the check")
                        : errorHint;
                    event.operationId = QStringLiteral("check");
                    applyEvent(event);
                });
            }
            return;
        }
        if (unit == QLatin1String(kManualUnit) || unit == QLatin1String(kSystemUnit)
            || unit == QLatin1String(kFlatpakUnit) || unit == QLatin1String(kRollbackUnit)) {
            if (!ok) {
                UpdateEvent event;
                event.source = QStringLiteral("engine");
                event.rawType = QStringLiteral("systemd-unavailable");
                event.severity = UpdateSeverity::Error;
                event.description = errorHint;
                event.operationId = QStringLiteral("update");
                applyEvent(event);
                endOperation();
            }
        }
    });

    connect(m_systemd, qOverload<const QString&, const QVariantMap&>(&SystemdCalls::unitState), this,
            [this](const QString& unit, const QVariantMap& state) {
        if (state.contains(QStringLiteral("error"))) {
            return;
        }
        // H4-004: track the automatic updater on EVERY answer, whatever unit
        // is being watched. Transitional and terminal states update the flag
        // symmetrically; refreshAll() and mutatingFlowGate() query this unit.
        if (unit == QLatin1String(kAutoUnit)) {
            const QString autoState = state.value(QStringLiteral("activeState")).toString();
            const bool running = autoState != QLatin1String("inactive")
                && autoState != QLatin1String("failed");
            if (m_autoUpdateRunning != running) {
                m_autoUpdateRunning = running;
                Q_EMIT autoUpdatesChanged();
            }
        }
        if (unit != m_watchedUnit) {
            return;
        }
        const QString activeState = state.value(QStringLiteral("activeState")).toString();
        if (activeState != QLatin1String("inactive") && activeState != QLatin1String("failed")) {
            return; // still working; the deadline is enforced by pollWatchedUnit()
        }
        // R93-01: the StartUnit job of this operation has not been reported
        // removed yet. A terminal state read now can still be the leftover of
        // a PREVIOUS run (e.g. the unit was already inactive, or the job is
        // queued behind dependencies): wait for jobFinished before classifying.
        if (!m_watchJobPath.isEmpty()) {
            return;
        }
        const UnitOutcome outcome = classifyUnitOutcome(state);
        const int exitStatus = state.value(QStringLiteral("execMainStatus")).toInt();
        m_journal->stop();

        switch (m_watchKind) {
        case UpdateWatchKind::Check:
            endOperation();
            handleCheckFinished(outcome, exitStatus);
            break;
        case UpdateWatchKind::UpdateFull:
        case UpdateWatchKind::UpdateSystem:
            endOperation();
            handleSystemUpdateFinished(outcome, exitStatus,
                state.value(QStringLiteral("execMainExitUsec")).toULongLong());
            break;
        case UpdateWatchKind::UpdateFlatpak:
            // H4-006: only the SYSTEM unit watch ends here; the operation
            // (mode, deadline, history) stays alive until the --user stage
            // finishes and the flow is finalized exactly once.
            stopWatch();
            handleFlatpakSystemUnitFinished(outcome, exitStatus);
            break;
        case UpdateWatchKind::Rollback:
            endOperation();
            handleRollbackFinished(outcome, exitStatus);
            break;
        }
    });

    connect(m_systemd, &SystemdCalls::jobQueued, this,
            [this](const QString& unit, const QString& jobPath) {
        // R93-01: remember the job of the unit being watched so JobRemoved can
        // be correlated with THIS start request.
        if (unit == m_watchedUnit) {
            m_watchJobPath = jobPath;
        }
    });

    connect(m_systemd, &SystemdCalls::jobFinished, this,
            [this](const QString& unit, const QString& jobPath, const QString& result) {
        if (jobPath.isEmpty() || jobPath != m_watchJobPath || unit != m_watchedUnit) {
            return; // a job of another (e.g. already timed-out) operation
        }
        m_watchJobPath.clear();
        if (result == QLatin1String("done")) {
            // The requested start completed; the terminal unit state read now
            // belongs to THIS operation. Classify immediately (the poll timer
            // keeps running as a backup for the state transition itself).
            m_systemd->unitState(m_watchedUnit);
            return;
        }
        handleStartJobFailed(result);
    });

    connect(m_systemd, qOverload<const QString&, const QVariantMap&>(&SystemdCalls::timerState), this,
            [this](const QString& unit, const QVariantMap& timer) {
        if (unit != QLatin1String(kTimerUnit) || timer.contains(QStringLiteral("error"))) {
            return;
        }
        m_autoUpdates.insert(QStringLiteral("timerFileState"),
                             timer.value(QStringLiteral("unitFileState")));
        m_autoUpdates.insert(QStringLiteral("timerActiveState"),
                             timer.value(QStringLiteral("activeState")));
        m_autoUpdates.insert(QStringLiteral("lastTriggerUSec"),
                             timer.value(QStringLiteral("lastTriggerUSec")));
        m_autoUpdates.insert(QStringLiteral("nextElapseUSec"),
                             timer.value(QStringLiteral("nextElapseUSec")));
        Q_EMIT autoUpdatesChanged();
    });
}

void UpdateEngine::handleCheckFinished(UnitOutcome outcome, int exitStatus)
{
    UpdateEvent event;
    event.source = QStringLiteral("check");
    event.operationId = QStringLiteral("check");
    if (outcome == UnitOutcome::ExitedWithError && exitStatus == 77) {
        // Documented "no update" exit of the read-only check unit
        // (enthroned-update-check.service); still a successful check.
        event.rawType = QStringLiteral("check-no-update");
        event.description = i18n("No updates available");
        event.phase = UpdatePhase::Completed;
        event.result = UpdateResult::Success;
    } else if (outcome == UnitOutcome::Completed) {
        event.rawType = QStringLiteral("check-update-available");
        event.description = i18n("Update available");
        event.phase = UpdatePhase::FetchingInfo;
    } else {
        event.rawType = QStringLiteral("check-failed");
        event.description = unitFailureText(outcome, exitStatus, i18n("Check"));
        event.phase = UpdatePhase::Failed;
        event.severity = UpdateSeverity::Error;
        event.result = UpdateResult::Failure;
        // Apply once fresh connectivity is known so offlineDetected is accurate.
        m_connectivity->refresh([this, event]() {
            setLastCheckNow(QStringLiteral("falha"));
            applyEvent(event);
            refreshAll();
        });
        return;
    }
    setLastCheckNow(QStringLiteral("ok"));
    applyEvent(event);
    refreshAll();
}

void UpdateEngine::handleSystemUpdateFinished(UnitOutcome outcome, int exitStatus, quint64 exitUsec)
{
    // The completed unit and the resulting deployment are independent observations.
    m_lastOperationWasUpdate = true;
    m_lastOperationWasRollback = false;
    const bool systemOnly = m_watchKind == UpdateWatchKind::UpdateSystem;
    if (outcome == UnitOutcome::Completed) {
        if (m_state != QLatin1String("failed")) {
            m_systemUpdateExitUsec = exitUsec;
            UpdateEvent event;
            event.source = QStringLiteral("system");
            event.rawType = QStringLiteral("update-success");
            event.phase = UpdatePhase::Validating;
            event.description = i18n("Update command finished; deployment status is pending.");
            applyEvent(event);
        }
    } else {
        UpdateEvent event;
        event.source = QStringLiteral("system");
        event.rawType = QStringLiteral("update-failed-with-errors");
        event.phase = UpdatePhase::Failed;
        event.severity = UpdateSeverity::Error;
        event.result = UpdateResult::Failure;
        event.description = unitFailureText(outcome, exitStatus,
            systemOnly ? i18n("System update") : i18n("Update"));
        applyEvent(event);
        m_notifications->notify(NotificationPresenter::Event::UpdateFailed,
            i18n("Update failed"),
            i18n("The system update ended with errors. See the details in System updates."));
    }
    refreshAll();
}

void UpdateEngine::handleFlatpakSystemUnitFinished(UnitOutcome outcome, int exitStatus)
{
    // The system installation unit ran; the user installation follows in the
    // session. Applications never require a reboot. Only a unit that really
    // executed and completed starts the user stage (H4-006/H4-007).
    if (outcome == UnitOutcome::Completed) {
        startUserFlatpakUpdate();
        return;
    }
    m_lastOperationWasUpdate = false;
    UpdateEvent event;
    event.source = QStringLiteral("flatpak");
    event.rawType = QStringLiteral("flatpak-update-failed");
    event.phase = UpdatePhase::Failed;
    event.severity = UpdateSeverity::Error;
    event.result = UpdateResult::Failure;
    event.description = unitFailureText(outcome, exitStatus, i18n("The application update"));
    applyEvent(event);
    endOperation();
    m_notifications->notify(NotificationPresenter::Event::UpdateFailed,
        i18n("Application update failed"),
        i18n("The application update ended with errors. See the details in System updates."));
    refreshAll();
}

void UpdateEngine::handleRollbackFinished(UnitOutcome outcome, int exitStatus)
{
    m_lastOperationWasRollback = outcome == UnitOutcome::Completed;
    m_lastOperationWasUpdate = false;
    if (outcome == UnitOutcome::Completed) {
        UpdateEvent event;
        event.source = QStringLiteral("system");
        event.rawType = QStringLiteral("rollback-success");
        event.phase = UpdatePhase::WaitingRestart;
        event.result = UpdateResult::Success;
        event.description = i18n("Rollback prepared");
        applyEvent(event);
    } else {
        UpdateEvent event;
        event.source = QStringLiteral("system");
        event.rawType = QStringLiteral("rollback-failed");
        event.phase = UpdatePhase::Failed;
        event.severity = UpdateSeverity::Error;
        event.result = UpdateResult::Failure;
        event.description = unitFailureText(outcome, exitStatus, i18n("Rollback"));
        applyEvent(event);
    }
    refreshAll();
}

void UpdateEngine::startUserFlatpakUpdate()
{
    // R93-02: the user stage belongs to THIS operation only; its result is
    // matched against this id.
    m_flatpakUserStageActive = true;
    m_userStageOpId = m_operationId;
    if (m_flatpak->updateUserInstallations()) {
        return;
    }
    // Provider refused (missing flatpak or an update already running):
    // treat as failure so the machine never waits forever.
    m_flatpakUserStageActive = false;
    m_userStageOpId = 0;
    m_lastOperationWasUpdate = false;
    UpdateEvent event;
    event.source = QStringLiteral("flatpak");
    event.rawType = QStringLiteral("flatpak-update-failed");
    event.phase = UpdatePhase::Failed;
    event.severity = UpdateSeverity::Error;
    event.result = UpdateResult::Failure;
    event.description = i18n("The application update could not start");
    applyEvent(event);
    endOperation();
    refreshAll();
}

void UpdateEngine::handleStartJobFailed(const QString& jobResult)
{
    // R93-01: the start job of the watched unit was removed without "done"
    // (canceled/failed/dependency/skipped/timeout). The requested start never
    // produced a new execution, so the operation fails on the job result; the
    // unit's current properties may still show the PREVIOUS run and are not
    // classified.
    m_journal->stop();
    const bool wasCheck = m_watchKind == UpdateWatchKind::Check;
    const bool wasFlatpak = m_watchKind == UpdateWatchKind::UpdateFlatpak;
    const bool wasRollback = m_watchKind == UpdateWatchKind::Rollback;
    m_lastOperationWasUpdate = !wasCheck && !wasFlatpak && !wasRollback;
    m_lastOperationWasRollback = false;
    UpdateEvent event;
    event.source = wasFlatpak ? QStringLiteral("flatpak") : QStringLiteral("engine");
    event.rawType = wasCheck ? QStringLiteral("check-failed")
        : wasFlatpak ? QStringLiteral("flatpak-update-failed")
        : wasRollback ? QStringLiteral("rollback-failed")
        : QStringLiteral("update-failed-with-errors");
    event.phase = UpdatePhase::Failed;
    event.severity = UpdateSeverity::Error;
    event.result = UpdateResult::Failure;
    event.description = i18n("%1 did not run: the start job ended with \"%2\"")
                            .arg(m_watchedUnit, jobResult);
    if (wasCheck) {
        setLastCheckNow(QStringLiteral("falha"));
        applyEvent(event);
    } else {
        applyEvent(event);
        m_notifications->notify(NotificationPresenter::Event::UpdateFailed,
            wasFlatpak ? i18n("Application update failed") : i18n("Update failed"),
            i18n("The update operation did not complete. See the details in System updates."));
    }
    endOperation();
    refreshAll();
}

bool UpdateEngine::startBlockedByRunningUnit(const QString& unit)
{
    // R93-01/R93-02: a timed-out operation leaves its unit running. Queueing
    // another start would stack operations and abandon the running one, so a
    // running (or unreadable - fail closed) unit blocks the new flow.
    if (!m_systemd->unitActive(unit)) {
        return false;
    }
    UpdateEvent event;
    event.source = QStringLiteral("engine");
    event.rawType = QStringLiteral("concurrent-operation-detected");
    event.severity = UpdateSeverity::Warning;
    event.description = i18n(
        "Operation skipped: %1 is still running or its state could not be read", unit);
    event.operationId = QStringLiteral("update");
    applyEvent(event);
    return true;
}

bool UpdateEngine::busy() const
{
    const QString state = m_state;
    return state == QLatin1String("checking") || state == QLatin1String("updating")
        || state == QLatin1String("preparing") || state == QLatin1String("rollingBack");
}

bool UpdateEngine::canCheck() const
{
    return !busy() && m_state != QLatin1String("deploymentPending");
}

QString UpdateEngine::imageOrigin() const
{
    if (!m_bootc->available()) {
        return QStringLiteral("unknown");
    }
    return ImageOrigin::classify(m_bootc->bootedImage(), m_expectedImages);
}

QString UpdateEngine::updateBlockReason() const
{
    if (m_demoMode) {
        return QStringLiteral("demo");
    }
    if (!m_mutationAllowed) {
        return QStringLiteral("policy");
    }
    const QString origin = imageOrigin();
    if (origin == QLatin1String("foreign")) {
        return QStringLiteral("origin-foreign");
    }
    if (!ImageOrigin::allowsUpdate(origin)) {
        return QStringLiteral("origin-unknown");
    }
    return QString();
}

QVariantList UpdateEngine::updatesFrom(const QString& source) const
{
    QVariantList rows;
    for (const QVariant& row : m_availableUpdates) {
        if (row.toMap().value(QStringLiteral("source")).toString() == source) {
            rows.append(row);
        }
    }
    return rows;
}

bool UpdateEngine::canUpdate() const
{
    if (!updateBlockReason().isEmpty() || busy()) {
        return false;
    }
    return m_state == QLatin1String("updatesAvailable")
        || (m_state == QLatin1String("restartRequired") && m_lastOperationWasUpdate)
        || m_state == QLatin1String("failed");
}

bool UpdateEngine::canRollback() const
{
    if (busy() || !m_systemd->available()) {
        return false;
    }
    if (m_demoMode) {
        return true;
    }
    if (!m_mutationAllowed || !updateBlockReason().isEmpty()) {
        return false;
    }
    return m_bootc->available() && m_bootc->rollbackPresent()
        && (m_state == QLatin1String("restartRequired")
            || m_state == QLatin1String("updatesAvailable")
            || m_state == QLatin1String("upToDate")
            || m_state == QLatin1String("updateConfirmed")
            || m_state == QLatin1String("failed"));
}

bool UpdateEngine::canReboot() const
{
    return m_mutationAllowed && !m_demoMode
        && restartPending() && canCheck() && m_operationId == 0
        && m_systemd->available();
}

bool UpdateEngine::restartPending() const
{
    return m_stagedDeploymentPending || m_state == QLatin1String("restartRequired");
}

bool UpdateEngine::serviceAvailable() const
{
    return m_systemd->available();
}

QString UpdateEngine::storagePreflightProblem(bool includeBootc, bool includeVar) const
{
    // H4-001: QStorageInfo has no exists(); validity is isValid()/isReady()
    // and an undeterminable size is an explicit unreadable preflight failure,
    // never a silent pass (the decision lives in storagepreflight.h).
    if (includeBootc) {
        const QStorageInfo sysroot(QStringLiteral("/ostree"));
        switch (storagePreflightCheck(sysroot.isValid(), sysroot.isReady(),
                                      sysroot.bytesAvailable(), m_minBootcFreeBytes)) {
        case StoragePreflight::Insufficient:
            return i18n("Not enough free space for the system update (the bootc storage needs at least 2 GiB free)");
        case StoragePreflight::Unreadable:
            return i18n("The bootc storage is unavailable; the system update cannot verify free space");
        case StoragePreflight::Ok:
            break;
        }
    }
    if (includeVar) {
        const QStorageInfo var(QStringLiteral("/var"));
        switch (storagePreflightCheck(var.isValid(), var.isReady(),
                                      var.bytesAvailable(), m_minVarFreeBytes)) {
        case StoragePreflight::Insufficient:
            return i18n("Not enough free space for the application update (the storage for applications needs at least 1 GiB free)");
        case StoragePreflight::Unreadable:
            return i18n("The application storage is unavailable; the application update cannot verify free space");
        case StoragePreflight::Ok:
            break;
        }
    }
    return QString();
}

bool UpdateEngine::mutatingFlowGate(const QString& operationId)
{
    if (m_demoMode) {
        return true; // demo flows never touch the system
    }
    if (m_state == QLatin1String("deploymentPending")) {
        return false;
    }
    if (busy()) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("concurrent-operation-detected");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n("Operation skipped: another operation is in progress");
        event.operationId = operationId;
        applyEvent(event);
        return false;
    }
    if (!m_mutationAllowed) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("update-rejected");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n(
            "Update run blocked by policy at this stage (mutation flags disabled)");
        event.operationId = operationId;
        applyEvent(event);
        return false;
    }
    // Never mutate an image that is not the Enthroned channel (foreign Fedora
    // image) or whose origin could not be read; updates run from the booted origin.
    if (!updateBlockReason().isEmpty()) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("update-rejected");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n("Update run blocked: image origin unverified (%1)")
                                .arg(updateBlockReason());
        event.operationId = operationId;
        applyEvent(event);
        return false;
    }
    // A staged deployment that does not come from the Enthroned channel
    // origin blocks every new mutating run until it is resolved.
    if (m_stagedOriginBlocked) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("update-rejected");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n(
            "Update run blocked: the staged deployment does not come from the Enthroned channel origin");
        event.operationId = operationId;
        applyEvent(event);
        return false;
    }
    // H4-004: re-read the automatic updater right before mutating; the guard
    // below decides on fresh state (unitState() answers synchronously). The
    // hard cross-process serialization stays with uupd's own lockfile and the
    // bootc/Flatpak locks; this flag keeps the UI honest about them.
    m_systemd->unitState(QLatin1String(kAutoUnit));
    if (m_autoUpdateRunning) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("concurrent-operation-detected");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n(
            "Operation skipped: an automatic update (uupd.service) is running in the background");
        event.operationId = operationId;
        applyEvent(event);
        return false;
    }
    if (!m_systemd->available()) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("systemd-unavailable");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n("systemd D-Bus unavailable in this environment");
        event.operationId = operationId;
        applyEvent(event);
        return false;
    }
    return true;
}

void UpdateEngine::setState(const QString& state)
{
    if (m_state == state) {
        return;
    }
    const QString previous = m_state;
    m_state = state;
    Q_EMIT stateChanged();

    // Gate 12.1: discovering a staged deployment at startup (previous == unknown)
    // restores the state silently; every Settings launch must not notify again.
    if (!m_demoMode && state == QLatin1String("restartRequired")
        && previous != QLatin1String("restartRequired") && previous != QLatin1String("unknown")) {
        if (m_lastOperationWasRollback) {
            // The restart switches BACK to the previous version; say so.
            m_notifications->notify(NotificationPresenter::Event::RestartRequired,
                i18n("Recovery prepared"),
                i18n("The previous version is prepared. Restart the computer to switch to it."));
        } else {
            m_notifications->notify(NotificationPresenter::Event::RestartRequired,
                i18n("Restart required"),
                i18n("A new system version has been staged. Restart the computer to apply it."));
        }
    }
    if (state == QLatin1String("failed")) {
        m_notifications->notify(NotificationPresenter::Event::UpdateFailed,
            i18n("Update failed"),
            i18n("An update operation failed. See the details in System updates."));
    }
}

void UpdateEngine::pushEvent(const UpdateEvent& event)
{
    const QVariantMap map = event.toVariantMap();
    m_eventLog.append(map);
    while (m_eventLog.size() > kEventLogCap) {
        m_eventLog.removeFirst();
    }
    Q_EMIT eventLogChanged();
}

bool UpdateEngine::hasFreshDeployment() const
{
    return m_systemUpdateExitUsec != 0 && m_bootc->available()
        && m_bootc->captureUsec() > m_systemUpdateExitUsec;
}

QVariantMap UpdateEngine::buildContext(const UpdateEvent& event) const
{
    QVariantMap context;
    context.insert(QStringLiteral("stagedDeployment"), m_stagedDeploymentPending);
    context.insert(QStringLiteral("freshDeployment"), m_demoMode || hasFreshDeployment());
    context.insert(QStringLiteral("mutationAllowed"), m_mutationAllowed || m_demoMode);
    context.insert(QStringLiteral("mutationBlocked"), !(m_mutationAllowed || m_demoMode));
    context.insert(QStringLiteral("demoMode"), m_demoMode);
    // Demo fixtures evaluate the rollback path with a fictional previous
    // deployment; in real mode the guard needs bootc to confirm it.
    context.insert(QStringLiteral("rollbackAvailable"),
                   m_demoMode
                       || ((m_bootc->available() && m_bootc->rollbackPresent())
                           && m_mutationAllowed));
    context.insert(QStringLiteral("offlineDetected"),
                   m_connectivity->nmAvailable() && !m_connectivity->online());
    context.insert(QStringLiteral("phaseDownloading"),
                   event.phase == UpdatePhase::Downloading);
    context.insert(QStringLiteral("phasePreparing"),
                   event.phase == UpdatePhase::Preparing || event.phase == UpdatePhase::Applying
                       || event.phase == UpdatePhase::Validating);
    context.insert(QStringLiteral("phaseApplying"),
                   event.phase == UpdatePhase::Applying);
    return context;
}

void UpdateEngine::applyEvent(const UpdateEvent& event)
{
    pushEvent(event);

    // Lote 11B (H5 P2-5): remember the operation kind from the lifecycle
    // events themselves, so the "failed" state can be titled "Could not
    // verify updates" when the interrupted operation was a check (covers
    // the real flows and the demo scenarios alike).
    if (event.rawType == QLatin1String("engine-check-started")) {
        m_lastOperationWasCheck = true;
    } else if (event.rawType == QLatin1String("engine-update-started")
               || event.rawType == QLatin1String("engine-rollback-started")
               || event.rawType == QLatin1String("flatpak-progress")) {
        m_lastOperationWasCheck = false;
    }

    // Progress notifications (real events only; demo keeps the banner).
    if (event.rawType == QLatin1String("bootc-download-finished") && !m_demoMode) {
        m_notifications->notify(NotificationPresenter::Event::DownloadFinished,
            i18n("Download finished"),
            i18n("The new version image was downloaded. Preparation is still in progress."));
    }
    if (event.rawType == QLatin1String("check-update-available") && !m_demoMode) {
        m_notifications->notify(NotificationPresenter::Event::UpdateAvailable,
            i18n("Update available"),
            i18n("New updates are available for Enthroned OS."));
    }

    // history-worthy outcomes
    if (!m_demoMode && (event.rawType == QLatin1String("update-success")
        || event.rawType == QLatin1String("deployment-confirmed")
        || event.rawType == QLatin1String("update-failed-with-errors")
        || event.rawType == QLatin1String("module-failed")
        || event.rawType == QLatin1String("staged-deployment-detected")
        || event.rawType == QLatin1String("engine-update-started")
        || event.rawType == QLatin1String("engine-check-started")
        || event.rawType == QLatin1String("engine-rollback-started")
        || event.rawType == QLatin1String("rollback-success")
        || event.rawType == QLatin1String("rollback-failed")
        || event.rawType == QLatin1String("flatpak-update-success")
        || event.rawType == QLatin1String("flatpak-update-failed")
        || event.rawType == QLatin1String("preflight-blocked")
        || event.rawType == QLatin1String("staged-origin-blocked")
        || event.rawType == QLatin1String("check-no-update")
        || event.rawType == QLatin1String("check-update-available")
        || event.rawType == QLatin1String("check-failed")
        || event.rawType == QLatin1String("update-rejected")
        || event.rawType == QLatin1String("concurrent-operation-detected")
        || event.rawType == QLatin1String("systemd-unavailable"))) {
        m_historyLog->append(event.source, event.rawType,
                             event.description.isEmpty() ? event.rawType : event.description,
                             event.currentItem);
        mergeHistory();
    }

    const QVariantMap context = buildContext(event);
    const QString newState = m_spec.step(m_state, event, context);
    setState(newState);
}

void UpdateEngine::setLastCheckNow(const QString& outcome)
{
    m_lastCheck.clear();
    m_lastCheck.insert(QStringLiteral("timestampMs"), QDateTime::currentMSecsSinceEpoch());
    m_lastCheck.insert(QStringLiteral("outcome"), outcome);
    Q_EMIT lastCheckChanged();
}

void UpdateEngine::refreshDeploymentStatus()
{
    if (!m_demoMode) {
        m_bootc->refresh();
    }
}

void UpdateEngine::refreshAll()
{
    if (m_demoMode) {
        return;
    }
    m_bootc->refresh();
    m_flatpak->refreshUpdates();
    m_connectivity->refresh();
    m_systemd->timerState(QLatin1String(kTimerUnit));
    m_systemd->unitState(QLatin1String(kAutoUnit));
    refreshAutoUpdates();

    // journal history (system updates) and flatpak history feed the merge.
    m_journal->fetchHistory({ QLatin1String(kAutoUnit), QLatin1String(kManualUnit),
                              QLatin1String(kSystemUnit), QLatin1String(kFlatpakUnit),
                              QLatin1String(kRollbackUnit) }, 300);
    m_flatpak->fetchHistory();
}

void UpdateEngine::mergeHistory()
{
    QVariantList merged;
    for (const QVariant& entry : m_historyLog->readRecent(100)) {
        merged.append(entry);
    }
    for (const QVariant& entry : m_pendingJournalHistory) {
        merged.append(entry);
    }
    for (const QVariant& entry : m_pendingFlatpakHistory) {
        merged.append(entry);
    }
    // Newest first; entries without numeric timestamp keep relative order.
    std::stable_sort(merged.begin(), merged.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap().value(QStringLiteral("ts"), qint64(0)).toLongLong()
             > b.toMap().value(QStringLiteral("ts"), qint64(0)).toLongLong();
    });
    while (merged.size() > 200) {
        merged.removeLast();
    }
    m_history = merged;
    Q_EMIT historyChanged();
}

void UpdateEngine::refreshAutoUpdates()
{
    // uupd module policy: /etc/uupd/config.json overrides /usr/lib/uupd/config.json
    const QStringList candidates = {
        QStringLiteral("/etc/uupd/config.json"),
        QStringLiteral("/usr/lib/uupd/config.json")
    };
    QVariantMap modules;
    bool configFound = false;
    for (const QString& path : candidates) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            continue;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (!doc.isObject()) {
            continue;
        }
        const QJsonObject modulesObj = doc.object()
            .value(QStringLiteral("modules")).toObject();
        modules.insert(QStringLiteral("system"),
                       !modulesObj.value(QStringLiteral("system")).toObject()
                           .value(QStringLiteral("disable")).toBool());
        modules.insert(QStringLiteral("flatpak"),
                       !modulesObj.value(QStringLiteral("flatpak")).toObject()
                           .value(QStringLiteral("disable")).toBool());
        modules.insert(QStringLiteral("brew"),
                       !modulesObj.value(QStringLiteral("brew")).toObject()
                           .value(QStringLiteral("disable")).toBool());
        modules.insert(QStringLiteral("distrobox"),
                       !modulesObj.value(QStringLiteral("distrobox")).toObject()
                           .value(QStringLiteral("disable")).toBool());
        configFound = true;
        break;
    }
    m_autoUpdates.insert(QStringLiteral("configPresent"), configFound);
    m_autoUpdates.insert(QStringLiteral("modules"), modules);
    m_autoUpdates.insert(QStringLiteral("configSource"),
                         configFound ? i18n("/etc/uupd/config.json or /usr/lib/uupd/config.json")
                                     : QString());
    Q_EMIT autoUpdatesChanged();
}

void UpdateEngine::checkForUpdates()
{
    if (m_demoMode) {
        startDemoScenario(m_demoScenarioName);
        return;
    }
    if (m_state == QLatin1String("deploymentPending")) {
        return;
    }
    if (busy()) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("concurrent-operation-detected");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n("Check skipped: an operation is in progress");
        applyEvent(event);
        return;
    }
    if (!m_systemd->available()) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("systemd-unavailable");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n("systemd D-Bus unavailable in this environment");
        applyEvent(event);
        return;
    }
    // R93-01/R93-02: a check unit still running from a timed-out operation
    // must not be stacked with a new start.
    if (startBlockedByRunningUnit(QLatin1String(kCheckUnit))) {
        return;
    }
    UpdateEvent event;
    event.source = QStringLiteral("engine");
    event.rawType = QStringLiteral("engine-check-started");
    event.phase = UpdatePhase::Checking;
    event.description = i18n("Checking for updates");
    applyEvent(event);
    startCheckUnit();
}

void UpdateEngine::startCheckUnit()
{
    m_checkUnitStarted = true;
    m_watchKind = UpdateWatchKind::Check;
    m_watchedUnit = QLatin1String(kCheckUnit);
    m_watchDeadlineMs = QDateTime::currentMSecsSinceEpoch() + m_watchTimeoutMs;
    m_pollTimer.start();
    m_systemd->startUnit(QLatin1String(kCheckUnit));
}

void UpdateEngine::startUpdateFlow(UpdateWatchKind kind, const QString& unit,
                                   const QString& modeLabel)
{
    // R93-02: identity of this operation; every stage and callback of the
    // flow is attributed to it until the flow is finalized.
    m_operationId = ++m_operationSeq;
    m_watchKind = kind;
    m_watchedUnit = unit;
    m_updateMode = modeLabel;
    // R93-02: real-clock deadline for the WHOLE operation (both stages).
    m_watchDeadlineMs = QDateTime::currentMSecsSinceEpoch() + m_watchTimeoutMs;
    Q_EMIT stateChanged();
    m_pollTimer.start();
    if (kind == UpdateWatchKind::UpdateFull || kind == UpdateWatchKind::UpdateSystem) {
        // Real progress arrives through the journal: uupd forwards bootc
        // --progress-fd JSON; the bootc helper writes the same JSON lines
        // straight to the journal (see the enthroned-system-update helper).
        m_journal->follow(unit);
    }
    m_systemd->startUnit(unit);
}

void UpdateEngine::requestUpdate()
{
    if (m_demoMode) {
        startDemoScenario(QStringLiteral("downloading"));
        return;
    }
    if (!mutatingFlowGate(QStringLiteral("update"))) {
        return;
    }
    // uupd keeps its own lockfile; the gate above still avoids double-starts.
    // R93-01/R93-02: a uupd-manual unit still running from a timed-out
    // operation must not be stacked with a new start.
    if (startBlockedByRunningUnit(QLatin1String(kManualUnit))) {
        return;
    }
    UpdateEvent event;
    event.source = QStringLiteral("engine");
    event.rawType = QStringLiteral("engine-update-started");
    event.phase = UpdatePhase::Initializing;
    event.description = i18n("Update started via %1").arg(QLatin1String(kManualUnit));
    event.operationId = QStringLiteral("update");
    m_lastOperationWasUpdate = true;
    m_lastOperationWasRollback = false;
    applyEvent(event);
    startUpdateFlow(UpdateWatchKind::UpdateFull, QLatin1String(kManualUnit), QStringLiteral("full"));
}

void UpdateEngine::requestSystemUpdate()
{
    if (m_demoMode) {
        startDemoScenario(QStringLiteral("system-update"));
        return;
    }
    if (!mutatingFlowGate(QStringLiteral("update"))) {
        return;
    }
    // System-only preflight: the bootc storage must have room. Applications
    // are not touched by this flow.
    const QString storage = storagePreflightProblem(true, false);
    if (!storage.isEmpty()) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("preflight-blocked");
        event.severity = UpdateSeverity::Warning;
        event.description = storage;
        event.operationId = QStringLiteral("update");
        applyEvent(event);
        return;
    }
    // R93-01/R93-02: an enthroned-system-update unit still running from a
    // timed-out operation must not be stacked with a new start.
    if (startBlockedByRunningUnit(QLatin1String(kSystemUnit))) {
        return;
    }
    UpdateEvent event;
    event.source = QStringLiteral("engine");
    event.rawType = QStringLiteral("engine-update-started");
    event.phase = UpdatePhase::Initializing;
    event.description = i18n("System update started via %1").arg(QLatin1String(kSystemUnit));
    event.operationId = QStringLiteral("update");
    m_lastOperationWasUpdate = true;
    m_lastOperationWasRollback = false;
    applyEvent(event);
    startUpdateFlow(UpdateWatchKind::UpdateSystem, QLatin1String(kSystemUnit),
                    QStringLiteral("system"));
}

void UpdateEngine::requestAppUpdates()
{
    if (m_demoMode) {
        startDemoScenario(QStringLiteral("apps-update"));
        return;
    }
    if (!mutatingFlowGate(QStringLiteral("update"))) {
        return;
    }
    // Applications never touch the bootc storage; /var must have room for
    // the system installation (the user installation lives in $HOME).
    const QString storage = storagePreflightProblem(false, true);
    if (!storage.isEmpty()) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("preflight-blocked");
        event.severity = UpdateSeverity::Warning;
        event.description = storage;
        event.operationId = QStringLiteral("update");
        applyEvent(event);
        return;
    }
    // R93-02: a previous application update whose user stage is still running
    // makes a new apps flow unsafe (flatpak serializes the installations on
    // its own lock): refuse instead of stacking a second operation.
    if (m_flatpak->userUpdateRunning()) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("concurrent-operation-detected");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n(
            "Operation skipped: the previous application update is still running");
        event.operationId = QStringLiteral("update");
        applyEvent(event);
        return;
    }
    // R93-01/R93-02: an enthroned-flatpak-update unit still running from a
    // timed-out operation must not be stacked with a new start.
    if (startBlockedByRunningUnit(QLatin1String(kFlatpakUnit))) {
        return;
    }
    UpdateEvent event;
    event.source = QStringLiteral("flatpak");
    event.rawType = QStringLiteral("engine-update-started");
    event.phase = UpdatePhase::Initializing;
    event.description = i18n("Application update started via %1").arg(QLatin1String(kFlatpakUnit));
    event.operationId = QStringLiteral("update");
    m_lastOperationWasUpdate = false;
    m_lastOperationWasRollback = false;
    applyEvent(event);
    startUpdateFlow(UpdateWatchKind::UpdateFlatpak, QLatin1String(kFlatpakUnit),
                    QStringLiteral("apps"));
}

void UpdateEngine::requestRollback()
{
    if (m_demoMode) {
        startDemoScenario(QStringLiteral("rollback-success"));
        return;
    }
    if (!mutatingFlowGate(QStringLiteral("rollback"))) {
        return;
    }
    if (!(m_bootc->available() && m_bootc->rollbackPresent())) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("update-rejected");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n("Rollback blocked: no previous deployment is available");
        event.operationId = QStringLiteral("rollback");
        applyEvent(event);
        return;
    }
    // R93-01/R93-02: an enthroned-rollback unit still running from a
    // timed-out operation must not be stacked with a new start.
    if (startBlockedByRunningUnit(QLatin1String(kRollbackUnit))) {
        return;
    }
    UpdateEvent event;
    event.source = QStringLiteral("engine");
    event.rawType = QStringLiteral("engine-rollback-started");
    event.phase = UpdatePhase::Initializing;
    event.description = i18n("Rollback started via %1").arg(QLatin1String(kRollbackUnit));
    event.operationId = QStringLiteral("rollback");
    m_lastOperationWasRollback = true;
    m_lastOperationWasUpdate = false;
    applyEvent(event);
    startUpdateFlow(UpdateWatchKind::Rollback, QLatin1String(kRollbackUnit),
                    QStringLiteral("rollback"));
}

void UpdateEngine::pollWatchedUnit()
{
    // H4-006: the deadline follows the OPERATION (mode), not just the watched
    // unit, so the --user Flatpak stage stays bounded too.
    if (m_watchedUnit.isEmpty() && m_updateMode.isEmpty()) {
        m_pollTimer.stop();
        return;
    }
    // R93-02: real-clock deadline. A delayed tick or a blocking D-Bus call
    // cannot stretch the watch by slowing a tick counter down.
    if (QDateTime::currentMSecsSinceEpoch() >= m_watchDeadlineMs) {
        const bool wasUpdate = m_watchKind != UpdateWatchKind::Check;
        endOperation();
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = wasUpdate ? QStringLiteral("update-failed-with-errors")
                                  : QStringLiteral("check-failed");
        event.severity = UpdateSeverity::Error;
        event.description = i18n(
            "Watch timeout reached; the underlying operation was NOT canceled and may still be running");
        applyEvent(event);
        return;
    }
    if (!m_watchedUnit.isEmpty()) {
        m_systemd->unitState(m_watchedUnit);
    }
}

void UpdateEngine::stopWatch()
{
    // Ends only the unit watch (H4-006): a multi-stage operation keeps its
    // mode, its deadline and the poll timer across the stages.
    m_watchedUnit.clear();
}

void UpdateEngine::endOperation()
{
    m_pollTimer.stop();
    m_watchedUnit.clear();
    m_watchJobPath.clear();
    m_watchDeadlineMs = 0;
    // R93-02: no operation is active anymore; late stage results (e.g. the
    // user process of a timed-out update) can no longer finalize anything.
    m_operationId = 0;
    m_userStageOpId = 0;
    m_flatpakUserStageActive = false;
    if (!m_updateMode.isEmpty()) {
        m_updateMode.clear();
        Q_EMIT stateChanged();
    }
}

void UpdateEngine::requestReboot()
{
    if (!canReboot()) {
        return;
    }
    QDBusInterface login1(QStringLiteral("org.freedesktop.login1"),
                          QStringLiteral("/org/freedesktop/login1"),
                          QStringLiteral("org.freedesktop.login1.Manager"),
                          QDBusConnection::systemBus());
    if (!login1.isValid()) {
        UpdateEvent event;
        event.source = QStringLiteral("engine");
        event.rawType = QStringLiteral("systemd-unavailable");
        event.severity = UpdateSeverity::Warning;
        event.description = i18n("logind D-Bus unavailable");
        applyEvent(event);
        return;
    }
    m_historyLog->append(QStringLiteral("engine"), QStringLiteral("reboot-requested"),
                         i18n("Restart requested by the user (confirmed in the UI)"), QString());
    login1.call(QStringLiteral("Reboot"), false);
}

QStringList UpdateEngine::demoScenarios() const
{
    QDir dir(QStringLiteral(":/src/update/demo/scenarios"));
    QStringList names;
    const QStringList files = dir.entryList({ QStringLiteral("*.json") }, QDir::Files, QDir::Name);
    for (const QString& file : files) {
        names.append(file.chopped(5));
    }
    return names;
}

void UpdateEngine::startDemoScenario(const QString& name)
{
    const QString path = QStringLiteral(":/src/update/demo/scenarios/%1.json").arg(name);
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject()) {
        return;
    }
    const QJsonObject root = doc.object();
    m_demoScenarioName = name;
    m_demoScenarioTitle = root.value(QStringLiteral("title")).toString(name);
    Q_EMIT demoScenarioChanged();

    m_demoSteps.clear();
    const QJsonArray steps = root.value(QStringLiteral("steps")).toArray();
    for (const QJsonValue& value : steps) {
        m_demoSteps.append(value.toObject().toVariantMap());
    }

    // Demo resets the visible log to the scenario; the banner marks fake data.
    m_eventLog.clear();
    m_state = QStringLiteral("unknown");
    m_lastOperationWasRollback = false;
    m_lastOperationWasUpdate = false;
    Q_EMIT stateChanged();
    Q_EMIT eventLogChanged();

    m_demoStep = 0;
    m_demoTimer.start(0);
}

void UpdateEngine::demoTimerTick()
{
    if (!m_demoMode || m_demoStep >= m_demoSteps.size()) {
        return;
    }
    const QVariantMap step = m_demoSteps.at(m_demoStep);
    const QVariantList events = step.value(QStringLiteral("events")).toList();
    for (const QVariant& value : events) {
        UpdateEvent event = UpdateEvent::fromVariantMap(value.toMap());
        event.timestampMs = QDateTime::currentMSecsSinceEpoch();
        applyEvent(event);
    }
    m_demoStep++;
    const int delayMs = m_demoStep < m_demoSteps.size()
        ? m_demoSteps.at(m_demoStep).value(QStringLiteral("delayMs"), 300).toInt()
        : 0;
    if (m_demoStep < m_demoSteps.size() && delayMs > 0) {
        m_demoTimer.start(delayMs);
    }
}

void UpdateEngine::cancelDemo()
{
    if (!m_demoMode) {
        return;
    }
    UpdateEvent event;
    event.source = QStringLiteral("engine");
    event.rawType = QStringLiteral("cancel-requested");
    event.phase = UpdatePhase::Failed;
    event.severity = UpdateSeverity::Warning;
    event.result = UpdateResult::Cancelled;
    event.description = i18n("Cancellation requested (demo)");
    applyEvent(event);
}

} // namespace Enthroned
