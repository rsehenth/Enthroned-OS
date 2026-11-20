/*
 * Enthroned Settings - update engine (F3.4/F3.5/F3.6/F3.7, Lote 8).
 * Orchestrates read-only providers, the declarative state machine and the
 * authorization boundary:
 *   - Mutating operations (system update via bootc, full update via
 *     uupd-manual.service, Flatpak updates, rollback, reboot via logind)
 *     are BLOCKED BY DEFAULT. They require:
 *       a) not running in demo mode, and
 *       b) ENTHRONED_SETTINGS_ALLOW_MUTATION=1 in the environment
 *     (set by a validated deployment, never by the UI itself).
 *   - No sudo/pkexec; all privileged actions go through systemd D-Bus units
 *     with FIXED commands (uupd-manual.service exists upstream in Aurora and
 *     is polkit-authorized by its own uupd.rules; the enthroned-* units are
 *     polkit-authorized by the Enthroned rule and never take arguments).
 *   - No fake progress: percentages only from real bootc progress events;
 *     otherwise indeterminate.
 *   - Preflight before every mutating run: free storage, image origin and a
 *     concurrent-operation guard.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include "updatestatemachine.h"
#include "connectivitymonitor.h"
#include "systemdoutcome.h"

class QProcess;

namespace Enthroned {

class SystemdCalls;
class JournalProgressSource;
class BootcStatusProvider;
class FlatpakUpdatesProvider;
class HistoryLog;
class NotificationPresenter;

// Lote 8: which mutating flow is running (drives progress labels and the
// finishing logic). Nothing here is user-typed data; the mode only selects
// between fixed units.
enum class UpdateWatchKind {
    Check,
    UpdateFull,     // uupd-manual.service (system + apps per uupd config)
    UpdateSystem,   // enthroned-system-update.service (bootc only)
    UpdateFlatpak,  // enthroned-flatpak-update.service, then user install
    Rollback        // enthroned-rollback.service
};

class UpdateEngine : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool demoMode READ demoMode CONSTANT)
    Q_PROPERTY(QString demoScenarioTitle READ demoScenarioTitle NOTIFY demoScenarioChanged)
    Q_PROPERTY(bool mutationAllowed READ mutationAllowed CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(bool canCheck READ canCheck NOTIFY stateChanged)
    Q_PROPERTY(bool canUpdate READ canUpdate NOTIFY stateChanged)
    Q_PROPERTY(bool canRollback READ canRollback NOTIFY stateChanged)
    Q_PROPERTY(bool canReboot READ canReboot NOTIFY stateChanged)
    Q_PROPERTY(bool restartPending READ restartPending NOTIFY stateChanged)
    Q_PROPERTY(QVariantList availableUpdates READ availableUpdates NOTIFY updatesChanged)
    Q_PROPERTY(QVariantList eventLog READ eventLog NOTIFY eventLogChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(QVariantMap autoUpdates READ autoUpdates NOTIFY autoUpdatesChanged)
    Q_PROPERTY(QVariantMap lastCheck READ lastCheck NOTIFY lastCheckChanged)
    Q_PROPERTY(bool serviceAvailable READ serviceAvailable NOTIFY serviceAvailabilityChanged)
    Q_PROPERTY(bool online READ online NOTIFY connectivityChanged)
    Q_PROPERTY(bool nmAvailable READ nmAvailable NOTIFY connectivityChanged)
    Q_PROPERTY(bool autoUpdateRunning READ autoUpdateRunning NOTIFY autoUpdatesChanged)
    // Lote 4: system (bootc image) and application (Flatpak) updates are kept
    // apart in the backend even though the UI presents them together.
    Q_PROPERTY(QVariantList systemUpdates READ systemUpdates NOTIFY updatesChanged)
    Q_PROPERTY(QVariantList appUpdates READ appUpdates NOTIFY updatesChanged)
    // enthroned | unverified | foreign | unknown (see imageorigin.h)
    Q_PROPERTY(QString imageOrigin READ imageOrigin NOTIFY stateChanged)
    // Empty when an update may start; otherwise why it is blocked:
    // demo | policy | origin-foreign | origin-unknown
    Q_PROPERTY(QString updateBlockReason READ updateBlockReason NOTIFY stateChanged)
    // Lote 8: full | system | apps | rollback while a mutating flow runs;
    // empty otherwise. Drives which progress rows the UI shows.
    Q_PROPERTY(QString updateMode READ updateMode NOTIFY stateChanged)
    // Lote 8: the staged deployment's image origin failed the channel check.
    Q_PROPERTY(bool stagedOriginBlocked READ stagedOriginBlocked NOTIFY stateChanged)
    // Lote 8: false while release-channel.json declares no Enthroned image
    // origin; the UI must then explain that no official channel exists.
    Q_PROPERTY(bool channelConfigured READ channelConfigured CONSTANT)
    // Lote 11B (H5 P2-5): true while the last started operation was a CHECK,
    // so a "failed" state can be titled "Could not verify updates" (the check
    // found nothing to install) instead of a generic "Failed".
    Q_PROPERTY(bool lastOperationWasCheck READ lastOperationWasCheck NOTIFY stateChanged)

public:
    // Defaults shared with the integration test (Lote 9.4 seams): production
    // bounds one update run at one hour and polls every 2 seconds.
    static constexpr qint64 kDefaultWatchTimeoutMs = 3600000;
    static constexpr int kDefaultPollIntervalMs = 2000;

    // Lote 9.4 testability seams: production constructs the engine with the
    // defaults (real SystemdCalls, real flatpak/bootc binary resolution, 1 h
    // deadline, 2 s poll). The integration test injects a SystemdCalls double,
    // fake flatpak and bootc program paths and short timers; no real unit or
    // update is ever started by a test.
    explicit UpdateEngine(const QStringList& arguments,
                          SystemdCalls* systemdOverride = nullptr,
                          const QString& flatpakBinaryOverride = QString(),
                          const QString& bootcBinaryOverride = QString(),
                          qint64 watchTimeoutMs = kDefaultWatchTimeoutMs,
                          int pollIntervalMs = kDefaultPollIntervalMs,
                          QObject* parent = nullptr,
                          const QString& bootcStatusFileOverride = QString());

    // Lote 9.5.1 testability seam: replaces the minimum-free-bytes thresholds
    // of the storage preflight (tests pass 0 so the outcome is deterministic
    // regardless of the runner's /ostree and /var size; the real filesystem is
    // still measured). Plain method, not invokable from QML; production code
    // never calls it.
    void setStoragePreflightMinimums(qint64 bootcBytes, qint64 varBytes)
    {
        m_minBootcFreeBytes = bootcBytes;
        m_minVarFreeBytes = varBytes;
    }

    QString state() const { return m_state; }
    bool demoMode() const { return m_demoMode; }
    QString demoScenarioTitle() const { return m_demoScenarioTitle; }
    bool mutationAllowed() const { return m_mutationAllowed; }
    bool busy() const;
    bool canCheck() const;
    bool canUpdate() const;
    bool canRollback() const;
    bool canReboot() const;
    bool restartPending() const;
    QVariantList availableUpdates() const { return m_availableUpdates; }
    QVariantList eventLog() const { return m_eventLog; }
    QVariantList history() const { return m_history; }
    QVariantMap autoUpdates() const { return m_autoUpdates; }
    QVariantMap lastCheck() const { return m_lastCheck; }
    bool serviceAvailable() const;
    bool online() const { return m_connectivity->online(); }
    bool nmAvailable() const { return m_connectivity->nmAvailable(); }
    bool autoUpdateRunning() const { return m_autoUpdateRunning; }
    QVariantList systemUpdates() const { return updatesFrom(QStringLiteral("system")); }
    QVariantList appUpdates() const { return updatesFrom(QStringLiteral("flatpak")); }
    QString imageOrigin() const;
    QString updateBlockReason() const;
    QString updateMode() const { return m_updateMode; }
    bool stagedOriginBlocked() const { return m_stagedOriginBlocked; }
    bool channelConfigured() const { return !m_expectedImages.isEmpty(); }
    bool lastOperationWasCheck() const { return m_lastOperationWasCheck; }
    // Single bootc status instance shared with the rest of the UI.
    BootcStatusProvider* bootc() const { return m_bootc; }

    Q_INVOKABLE void refreshAll();
    Q_INVOKABLE void refreshDeploymentStatus();
    Q_INVOKABLE void checkForUpdates();
    // Full update: system image + applications via uupd-manual.service.
    Q_INVOKABLE void requestUpdate();
    // Lote 8: system image only (bootc upgrade, fixed unit). Applications
    // are NOT touched unless the user asks for them explicitly.
    Q_INVOKABLE void requestSystemUpdate();
    // Lote 8: applications only (system installation via unit, then the user
    // installation in the session). The system image is NOT touched.
    Q_INVOKABLE void requestAppUpdates();
    // Lote 8: explicit, protected rollback to the previous deployment.
    Q_INVOKABLE void requestRollback();
    Q_INVOKABLE void requestReboot();
    Q_INVOKABLE QStringList demoScenarios() const;
    Q_INVOKABLE void startDemoScenario(const QString& name);
    Q_INVOKABLE void cancelDemo();

private:
    bool loadSpec();
    void connectProviders();
    void applyEvent(const UpdateEvent& event);
    QVariantMap buildContext(const UpdateEvent& event) const;
    bool hasFreshDeployment() const;
    void setState(const QString& state);
    void pushEvent(const UpdateEvent& event);
    void setLastCheckNow(const QString& outcome);
    void mergeHistory();
    QVariantList updatesFrom(const QString& source) const;

    // Common gate for every mutating flow. Returns false (after emitting the
    // rejection event) when the flow must not start.
    bool mutatingFlowGate(const QString& operationId);
    // Storage preflight; returns empty when OK, otherwise a user-facing hint.
    QString storagePreflightProblem(bool includeBootc, bool includeVar) const;
    void startUpdateFlow(UpdateWatchKind kind, const QString& unit, const QString& modeLabel);
    void handleCheckFinished(UnitOutcome outcome, int exitStatus);
    void handleSystemUpdateFinished(UnitOutcome outcome, int exitStatus, quint64 exitUsec);
    void handleFlatpakSystemUnitFinished(UnitOutcome outcome, int exitStatus);
    void handleRollbackFinished(UnitOutcome outcome, int exitStatus);
    void startUserFlatpakUpdate();
    // R93-01: the StartUnit job for the watched unit was removed without
    // reaching "done" (canceled/failed/dependency/skipped/timeout): the
    // requested start never produced a new execution, so the operation fails
    // with the job result instead of classifying a possibly stale unit state.
    void handleStartJobFailed(const QString& jobResult);
    // R93-01/R93-02: refuses to queue a new start while the target unit is
    // still running from a previous (e.g. timed-out) operation. Emits the
    // rejection event and returns true when the start must not proceed.
    bool startBlockedByRunningUnit(const QString& unit);

Q_SIGNALS:
    void stateChanged();
    void serviceAvailabilityChanged();
    void connectivityChanged();
    void updatesChanged();
    void eventLogChanged();
    void historyChanged();
    void autoUpdatesChanged();
    void lastCheckChanged();
    void demoScenarioChanged();

private Q_SLOTS:
    void pollWatchedUnit();
    void demoTimerTick();

private:
    // Real check/update flows.
    void startCheckUnit();
    void stopWatch();
    void endOperation();
    void refreshAutoUpdates();

    UpdateStateMachine m_spec;
    SystemdCalls* m_systemd = nullptr;
    JournalProgressSource* m_journal = nullptr;
    ConnectivityMonitor* m_connectivity = nullptr;
    BootcStatusProvider* m_bootc = nullptr;
    FlatpakUpdatesProvider* m_flatpak = nullptr;
    HistoryLog* m_historyLog = nullptr;
    NotificationPresenter* m_notifications = nullptr;
    QTimer m_pollTimer;
    QTimer m_demoTimer;

    QString m_state = QStringLiteral("unknown");
    bool m_demoMode = false;
    bool m_mutationAllowed = false;
    QString m_demoScenarioName;
    QString m_demoScenarioTitle;
    int m_demoStep = 0;
    QVector<QVariantMap> m_demoSteps;

    QString m_watchedUnit;
    UpdateWatchKind m_watchKind = UpdateWatchKind::Check;
    // R93-01: the StartUnit job of the watched unit; non-empty while the job
    // has not been reported removed, so a terminal unit state read before the
    // JobRemoved signal can never be mistaken for THIS operation's result.
    QString m_watchJobPath;
    // R93-02: real-clock deadline for the whole operation (system + user
    // stages), independent of timer tick counting.
    qint64 m_watchDeadlineMs = 0;
    // R93-02: operation identity. Every mutating flow gets a new id; the
    // Flatpak user stage and its progress/result are attributed to the exact
    // operation that started them, so a late result from a timed-out
    // operation can never finalize a different one.
    quint64 m_operationSeq = 0;
    quint64 m_operationId = 0;
    quint64 m_userStageOpId = 0;
    bool m_flatpakUserStageActive = false;
    bool m_autoUpdateRunning = false;
    bool m_lastOperationWasUpdate = false;
    bool m_lastOperationWasRollback = false;
    bool m_checkUnitStarted = false;
    bool m_lastOperationWasCheck = false;
    bool m_stagedDeploymentPending = false;
    quint64 m_lastDeploymentCaptureUsec = 0;
    quint64 m_systemUpdateExitUsec = 0;
    bool m_stagedOriginBlocked = false;
    QString m_updateMode;
    qint64 m_watchTimeoutMs = kDefaultWatchTimeoutMs;
    // Lote 9.5.1: storage preflight minimums (production values set in the
    // constructor; tests may lower them via setStoragePreflightMinimums).
    qint64 m_minBootcFreeBytes = 0;
    qint64 m_minVarFreeBytes = 0;

    QVariantList m_availableUpdates;
    QVariantList m_eventLog;
    QVariantList m_history;
    QVariantMap m_autoUpdates;
    QVariantMap m_lastCheck;
    QVariantList m_pendingJournalHistory;
    QVariantList m_pendingFlatpakHistory;
    QStringList m_expectedImages;
};

} // namespace Enthroned
