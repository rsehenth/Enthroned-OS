// Lote 9.4 (R93-01/R93-02): UpdateEngine integration test with Qt doubles.
// Drives the REAL UpdateEngine against a scripted SystemdCalls subclass, a
// fake bootc and a fake flatpak program, both injected as absolute binary
// overrides (G95-01: PATH and /usr/bin/bootc are never consulted, so no real
// bootc or flatpak is ever started). No systemd unit is ever started. Covers:
//   R93-01/H4-007 - ConditionResult handling (false condition never succeeds),
//     exit 0/77/1, signals, and StartUnit job correlation: a terminal unit
//     state read BEFORE JobRemoved is never classified (stale state), a job
//     removed as canceled/dependency/skipped fails the operation instead.
//   R93-02/H4-006 - Flatpak operation identity: the mandatory regression
//     (A starts -> A completes system -> A starts user -> A times out -> B is
//     requested -> A's user process answers LATE) must not let A's old result
//     or old progress conclude or modify B; exactly one finalization per
//     operation; retry while the previous user process is still running is
//     refused; success and failure paths refresh history/app list.
// Needs Qt (Core, DBus) and KF6 (I18n, Notifications); runs in the build (CTest).
#include "../src/update/updateengine.h"
#include "../src/update/systemdcalls.h"
#include "../src/update/systemdpropertymap.h"
#include "../src/bootcstatusprovider.h"
#include "../src/flatpakupdatesprovider.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSaveFile>
#include <QTemporaryDir>
#include <QTimer>
#include <QVariantMap>

#include <cstdlib>
#include <functional>

using namespace Enthroned;

namespace {

// ---- fake systemd -----------------------------------------------------------

class FakeSystemdCalls : public SystemdCalls
{
public:
    FakeSystemdCalls()
    {
        m_available = true; // no D-Bus in the test; the double is "available"
        defaultState.insert(QStringLiteral("activeState"), QStringLiteral("inactive"));
        defaultState.insert(QStringLiteral("subState"), QStringLiteral("dead"));
        defaultState.insert(QStringLiteral("result"), QStringLiteral("success"));
        defaultState.insert(QStringLiteral("execMainCode"), 1);
        defaultState.insert(QStringLiteral("execMainStatus"), 0);
        defaultState.insert(QStringLiteral("conditionResult"), true);
    }

    // Scripted terminal answers per unit; consumed in order, then defaultState.
    QHash<QString, QList<QVariantMap>> scripted;
    // unitActive() answers; default false (never running).
    QHash<QString, bool> unitActiveAnswers;
    // JobRemoved result emitted synchronously after an accepted start;
    // empty = keep the job pending until emitPendingJobRemoved().
    QString autoJobResult = QStringLiteral("done");
    bool startOk = true;
    int startUnitCalls = 0;
    QString pendingJobUnit;
    QString pendingJobPath;

    void startUnit(const QString& unit) override
    {
        ++startUnitCalls;
        if (!startOk) {
            Q_EMIT startUnitResult(unit, false, QStringLiteral("start refused"));
            return;
        }
        const QString jobPath =
            QStringLiteral("/org/freedesktop/systemd1/job/%1").arg(++jobCounter);
        Q_EMIT jobQueued(unit, jobPath);
        Q_EMIT startUnitResult(unit, true, QString());
        if (!autoJobResult.isEmpty()) {
            Q_EMIT jobFinished(unit, jobPath, autoJobResult);
        } else {
            pendingJobUnit = unit;
            pendingJobPath = jobPath;
        }
    }

    void unitState(const QString& unit) override
    {
        QVariantMap state;
        if (scripted.contains(unit) && !scripted[unit].isEmpty()) {
            state = scripted[unit].takeFirst();
        } else {
            state = defaultState;
        }
        // The 1-arg poller override hides the inherited 2-arg signal; qualify
        // the base signal explicitly (same lookup the production class uses).
        Q_EMIT SystemdCalls::unitState(unit, state);
    }

    bool unitActive(const QString& unit) override
    {
        return unitActiveAnswers.value(unit, false);
    }

    void timerState(const QString&) override
    {
        // No timer information in the test environment.
    }

    void setUnavailable()
    {
        m_available = false;
        Q_EMIT availableChanged();
    }

    void emitPendingJobRemoved(const QString& result)
    {
        if (pendingJobPath.isEmpty()) {
            return;
        }
        const QString unit = pendingJobUnit;
        const QString path = pendingJobPath;
        pendingJobUnit.clear();
        pendingJobPath.clear();
        Q_EMIT jobFinished(unit, path, result);
    }

    // Terminal service states used by the scenarios.
    static QVariantMap successTerminal()
    {
        return { { QStringLiteral("activeState"), QStringLiteral("inactive") },
                 { QStringLiteral("subState"), QStringLiteral("dead") },
                 { QStringLiteral("result"), QStringLiteral("success") },
                 { QStringLiteral("execMainCode"), 1 },
                 { QStringLiteral("execMainStatus"), 0 },
                 { QStringLiteral("conditionResult"), true } };
    }
    static QVariantMap exitStatusTerminal(int status)
    {
        auto state = successTerminal();
        state.insert(QStringLiteral("result"), QStringLiteral("exit-code"));
        state.insert(QStringLiteral("execMainStatus"), status);
        return state;
    }

private:
    QVariantMap defaultState;
    quint64 jobCounter = 0;
};

// ---- helpers ----------------------------------------------------------------

int failures = 0;
int checks = 0;

void check(bool condition, const QString& description)
{
    ++checks;
    if (condition) {
        qInfo().noquote() << "PASS:" << description;
    } else {
        qCritical().noquote() << "FAIL:" << description;
        ++failures;
    }
}

// G95-01: test preconditions (fake bootc isolation) abort the run immediately
// with an explicit message instead of failing later with confusing state
// assertions. Note: std::exit skips the QTemporaryDir cleanup (CI is
// ephemeral; no scenario with a live fake process reaches failFast).
void failFast(const QString& message)
{
    qCritical().noquote() << "FAIL (fatal):" << message;
    std::exit(1);
}

bool waitFor(const std::function<bool()>& condition, int timeoutMs)
{
    QElapsedTimer timer;
    timer.start();
    while (!condition()) {
        if (timer.elapsed() > timeoutMs) {
            return false;
        }
        QCoreApplication::processEvents(QEventLoop::AllEvents, 25);
    }
    return true;
}

int countEvents(const UpdateEngine& engine, const QString& rawType,
                const QString& resultFilter = QString())
{
    int count = 0;
    const QVariantList log = engine.eventLog();
    for (const QVariant& entry : log) {
        const QVariantMap map = entry.toMap();
        if (map.value(QStringLiteral("rawType")).toString() != rawType) {
            continue;
        }
        if (!resultFilter.isEmpty()
            && map.value(QStringLiteral("result")).toString() != resultFilter) {
            continue;
        }
        ++count;
    }
    return count;
}

QVariantMap terminalState(bool conditionResult, const QString& result,
                          int execMainCode, int execMainStatus)
{
    return { { QStringLiteral("activeState"),
               execMainCode == 0 ? QStringLiteral("failed") : QStringLiteral("inactive") },
             { QStringLiteral("subState"), QStringLiteral("dead") },
             { QStringLiteral("result"), result },
             { QStringLiteral("execMainCode"), execMainCode },
             { QStringLiteral("execMainStatus"), execMainStatus },
             { QStringLiteral("conditionResult"), conditionResult } };
}

} // namespace

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);

    QTemporaryDir work;
    if (!work.isValid()) {
        qCritical() << "Cannot create the test work directory";
        return 1;
    }

    // Test isolation: no real user configuration is read or written.
    qputenv("HOME", work.filePath(QStringLiteral("home")).toUtf8());
    qputenv("XDG_CONFIG_HOME", work.filePath(QStringLiteral("home/.config")).toUtf8());
    qputenv("XDG_STATE_HOME", work.filePath(QStringLiteral("home/.local/state")).toUtf8());
    QDir().mkpath(work.filePath(QStringLiteral("home/.config")));
    // The engine reads the mutation gate from the environment (never from the
    // UI); the test sets it exactly like a validated deployment would.
    qputenv("ENTHRONED_SETTINGS_ALLOW_MUTATION", "1");

    // Fake bootc injected as an ABSOLUTE PATH override (G95-01): the mutation
    // gate needs an available booted image; with no expected channel
    // references the origin classifies as unverified (allowed by policy). The
    // fake only touches its marker and prints status JSON - nothing else.
    // PATH is left untouched on purpose: /usr/bin/bootc and PATH are never
    // consulted with the override, and a marker assertion proves the fake (not
    // a real bootc) actually ran.
    const QString fakeBin = work.filePath(QStringLiteral("bin"));
    QDir().mkpath(fakeBin);
    const QString fakeBootcPath = fakeBin + QStringLiteral("/bootc");
    const QString bootcMarker = work.filePath(QStringLiteral("bootc-ran"));
    {
        QFile bootc(fakeBootcPath);
        if (!bootc.open(QIODevice::WriteOnly | QIODevice::Text)) {
            failFast(QStringLiteral("cannot write the fake bootc at %1").arg(fakeBootcPath));
        }
        // JSON mirrors the REAL bootc 1.x status schema: status.booted.image
        // is ImageStatus { image: ImageReference { image, transport },
        // version, ... } - the version is a SIBLING of the ImageReference
        // object, never nested inside it.
        bootc.write(QStringLiteral("#!/bin/sh\ntouch \"%1\"\n"
                                   "printf '%s' '{\"status\":{\"booted\":{\"image\":"
                                   "{\"image\":{\"image\":\"quay.io/enthroned/test-os:stable\","
                                   "\"transport\":\"registry\"},\"version\":\"1.0\"}},"
                                   "\"staged\":{},\"rollback\":{}}}'\n"
                                   "exit 0\n").arg(bootcMarker).toUtf8());
        bootc.close();
        if (!bootc.setPermissions(QFile::ReadUser | QFile::WriteUser | QFile::ExeUser)
            || !QFileInfo(fakeBootcPath).isExecutable()) {
            failFast(QStringLiteral("the fake bootc at %1 is not executable - aborting "
                                    "instead of risking a real bootc invocation").arg(fakeBootcPath));
        }
    }

    // Fake flatpak program (never a real flatpak). The marker file records
    // whether an UPDATE run actually executed; listings (remote-ls) and
    // history runs never touch it. It is written ONCE here so every engine
    // (including the read-only check scenarios) injects the fake via the
    // flatpakBinaryOverride seam: the real /usr/bin/flatpak must never be
    // executed by this test, not even for a cached listing.
    const QString updateMarker = work.filePath(QStringLiteral("user-update-ran"));
    const QString fakeFlatpakPath = work.filePath(QStringLiteral("fake-flatpak"));
    const auto writeFakeFlatpak = [&work, &updateMarker, &fakeFlatpakPath](const QString& body) {
        QFile program(fakeFlatpakPath);
        program.remove();
        if (!program.open(QIODevice::WriteOnly | QIODevice::Text)) {
            qCritical() << "Cannot write the fake flatpak";
            return false;
        }
        program.write(QStringLiteral("#!/bin/sh\n"
                                     "if [ \"$1\" = \"update\" ]; then touch \"%2\"; fi\n%1\n")
                          .arg(body, updateMarker)
                          .toUtf8());
        program.close();
        return program.setPermissions(QFile::ReadUser | QFile::WriteUser | QFile::ExeUser);
    };
    if (!writeFakeFlatpak(QStringLiteral("exit 0\n"))) {
        failFast(QStringLiteral("cannot prepare the fake flatpak program"));
    }

    const QString checkUnit = QStringLiteral("enthroned-update-check.service");
    const QString flatpakUnit = QStringLiteral("enthroned-flatpak-update.service");

    // ---- R93-01: the property->interface mapping (pure part) ----------------
    // ConditionResult belongs to org.freedesktop.systemd1.Unit; reading it
    // from the Service interface is the audited defect (Unknown interface).
    check(Enthroned::systemdPropertyInterface(QStringLiteral("ConditionResult"))
              == QStringLiteral("org.freedesktop.systemd1.Unit"),
          QStringLiteral("ConditionResult is read from the Unit interface"));
    check(Enthroned::systemdPropertyInterface(QStringLiteral("ActiveState"))
              == QStringLiteral("org.freedesktop.systemd1.Unit"),
          QStringLiteral("ActiveState is read from the Unit interface"));
    check(Enthroned::systemdPropertyInterface(QStringLiteral("Result"))
              == QStringLiteral("org.freedesktop.systemd1.Service"),
          QStringLiteral("Result is read from the Service interface"));
    check(Enthroned::systemdPropertyInterface(QStringLiteral("ExecMainStatus"))
              == QStringLiteral("org.freedesktop.systemd1.Service"),
          QStringLiteral("ExecMainStatus is read from the Service interface"));
    check(Enthroned::systemdPropertyInterface(QStringLiteral("LastTriggerUSec"))
              == QStringLiteral("org.freedesktop.systemd1.Timer"),
          QStringLiteral("LastTriggerUSec is read from the Timer interface"));

    // ---- R93-01: check-flow outcomes (0/77/1, condition, signal) -------------
    {
        struct Case { QString name; QVariantMap terminal; QString expectedState; int expectSuccessEvents; };
        const Case cases[] = {
            { QStringLiteral("check exit 0 -> update available"),
              FakeSystemdCalls::successTerminal(), QStringLiteral("updatesAvailable"), 1 },
            { QStringLiteral("check exit 77 -> no update (77 stays check-only)"),
              FakeSystemdCalls::exitStatusTerminal(77), QStringLiteral("upToDate"), 1 },
            { QStringLiteral("check exit 1 -> failed"),
              FakeSystemdCalls::exitStatusTerminal(1), QStringLiteral("failed"), 0 },
            { QStringLiteral("check condition=false -> Skipped, never success"),
              terminalState(false, QStringLiteral("success"), 1, 0),
              QStringLiteral("failed"), 0 },
            { QStringLiteral("check killed by signal -> failed"),
              terminalState(true, QStringLiteral("signal"), 2, 15),
              QStringLiteral("failed"), 0 },
        };
        for (const Case& c : cases) {
            FakeSystemdCalls systemd;
            systemd.scripted[checkUnit].append(c.terminal);
            UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                                fakeBootcPath, 400, 30);
            engine.checkForUpdates();
            waitFor([&engine, &c]() { return engine.state() == c.expectedState; }, 5000);
            check(engine.state() == c.expectedState,
                  c.name + QStringLiteral(" (state=%1)").arg(engine.state()));
            check(countEvents(engine, QStringLiteral("check-update-available"))
                      + countEvents(engine, QStringLiteral("check-no-update"))
                      == c.expectSuccessEvents,
                  c.name + QStringLiteral(" (success events)"));
        }
    }

    // ---- R93-01: stale terminal state BEFORE JobRemoved is never classified -
    {
        FakeSystemdCalls systemd;
        systemd.autoJobResult.clear(); // job stays pending until the test emits it
        systemd.scripted[checkUnit].append(FakeSystemdCalls::successTerminal()); // stale
        systemd.scripted[checkUnit].append(FakeSystemdCalls::successTerminal()); // real
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                            fakeBootcPath, 400, 30);
        engine.checkForUpdates();
        // Let the poll consume the stale terminal answer.
        waitFor([&systemd, &checkUnit]() { return systemd.scripted[checkUnit].size() <= 1; }, 5000);
        QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        check(engine.state() == QStringLiteral("checking"),
              QStringLiteral("stale inactive state does not classify while the job is pending (state=%1)")
                  .arg(engine.state()));
        // The job completes NOW; the fresh terminal state belongs to this run.
        systemd.emitPendingJobRemoved(QStringLiteral("done"));
        waitFor([&engine]() { return engine.state() == QStringLiteral("updatesAvailable"); }, 5000);
        check(engine.state() == QStringLiteral("updatesAvailable"),
              QStringLiteral("job-done correlation classifies the fresh state (state=%1)")
                  .arg(engine.state()));
    }

    // ---- R93-01: job removed as canceled / dependency -> not a success ------
    for (const QString& jobResult : { QStringLiteral("canceled"), QStringLiteral("dependency") }) {
        FakeSystemdCalls systemd;
        systemd.autoJobResult = jobResult;
        systemd.scripted[checkUnit].append(FakeSystemdCalls::successTerminal()); // stale
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                            fakeBootcPath, 400, 30);
        engine.checkForUpdates();
        waitFor([&engine]() { return engine.state() == QStringLiteral("failed"); }, 5000);
        check(engine.state() == QStringLiteral("failed"),
              QStringLiteral("check start job %1 -> failed, stale state never classified (state=%2)")
                  .arg(jobResult, engine.state()));
        check(countEvents(engine, QStringLiteral("check-update-available")) == 0
                  && countEvents(engine, QStringLiteral("check-no-update")) == 0,
              QStringLiteral("check start job %1 emits no success event").arg(jobResult));
    }

    // ---- R93-02: full successful apps flow ----------------------------------
    {
        writeFakeFlatpak(QStringLiteral("exit 0\n"));
        FakeSystemdCalls systemd;
        systemd.scripted[flatpakUnit].append(FakeSystemdCalls::successTerminal());
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd,
                            work.filePath(QStringLiteral("fake-flatpak")),
                            fakeBootcPath, 2000, 30);
        engine.setStoragePreflightMinimums(0, 0);
        engine.refreshAll();
        waitFor([&engine]() { return engine.bootc()->available(); }, 5000);
        // G95-01 isolation evidence: the fake bootc must be the only bootc
        // ever consulted. A missing marker or a status that does not match the
        // fake means a real bootc leaked into the test; abort with an explicit
        // message instead of failing later on confusing state assertions.
        if (!engine.bootc()->available()) {
            failFast(QStringLiteral("fake bootc did not answer status (hint=%1) - the "
                                    "mutating scenarios cannot run without it")
                         .arg(engine.bootc()->errorHint()));
        }
        if (!QFile::exists(bootcMarker)) {
            failFast(QStringLiteral("fake bootc marker is missing: the fake was never "
                                    "executed and a real bootc may have been used"));
        }
        check(engine.bootc()->bootcPresent(),
              QStringLiteral("fake bootc is present to the engine"));
        check(engine.bootc()->bootedImage()
                  == QStringLiteral("quay.io/enthroned/test-os:stable"),
              QStringLiteral("booted status comes from the fake bootc (image=%1)")
                  .arg(engine.bootc()->bootedImage()));
        check(engine.bootc()->bootedVersion() == QStringLiteral("1.0"),
              QStringLiteral("booted status version comes from the fake bootc"));
        check(!engine.bootc()->stagedPresent() && !engine.bootc()->rollbackPresent(),
              QStringLiteral("fake bootc reports no staged/rollback deployment"));
        // Precondition made explicit (never silent): the fake image must be
        // mutable under the channel policy of the running environment (empty
        // expected-image list -> unverified -> allowed). A channel file that
        // lists other references would classify the fake as foreign and abort
        // here instead of producing unrelated failures below.
        if (!engine.updateBlockReason().isEmpty()) {
            failFast(QStringLiteral("channel/image precondition not met "
                                    "(updateBlockReason=%1): the fake bootc image must "
                                    "classify as allowed by the release-channel policy")
                         .arg(engine.updateBlockReason()));
        }
        engine.requestAppUpdates();
        waitFor([&engine]() { return engine.state() == QStringLiteral("upToDate"); }, 10000);
        check(engine.state() == QStringLiteral("upToDate"),
              QStringLiteral("apps flow success -> upToDate (state=%1)").arg(engine.state()));
        check(countEvents(engine, QStringLiteral("flatpak-update-success"),
                          QStringLiteral("Success")) == 1,
              QStringLiteral("apps flow success finalizes exactly once"));
        check(QFile::exists(updateMarker),
              QStringLiteral("apps flow success ran the user update stage"));
        check(!engine.busy(),
              QStringLiteral("apps flow success releases the busy state"));
    }

    // ---- R93-02: system stage failure never starts the user stage -----------
    QFile::remove(updateMarker);
    {
        writeFakeFlatpak(QStringLiteral("exit 0\n"));
        FakeSystemdCalls systemd;
        systemd.scripted[flatpakUnit].append(FakeSystemdCalls::exitStatusTerminal(1));
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd,
                            work.filePath(QStringLiteral("fake-flatpak")),
                            fakeBootcPath, 2000, 30);
        engine.setStoragePreflightMinimums(0, 0);
        engine.refreshAll();
        waitFor([&engine]() { return engine.bootc()->available(); }, 5000);
        engine.requestAppUpdates();
        waitFor([&engine]() { return engine.state() == QStringLiteral("failed"); }, 10000);
        check(engine.state() == QStringLiteral("failed"),
              QStringLiteral("flatpak system stage exit 1 -> failed (state=%1)").arg(engine.state()));
        check(!QFile::exists(updateMarker),
              QStringLiteral("failed system stage never runs the user update"));
        check(countEvents(engine, QStringLiteral("flatpak-update-success")) == 0,
              QStringLiteral("failed system stage emits no success event"));
    }

    // ---- R93-02: start job canceled at the flatpak system stage -------------
    QFile::remove(updateMarker);
    {
        writeFakeFlatpak(QStringLiteral("exit 0\n"));
        FakeSystemdCalls systemd;
        systemd.autoJobResult = QStringLiteral("canceled");
        systemd.scripted[flatpakUnit].append(FakeSystemdCalls::successTerminal()); // stale
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd,
                            work.filePath(QStringLiteral("fake-flatpak")),
                            fakeBootcPath, 2000, 30);
        engine.setStoragePreflightMinimums(0, 0);
        engine.refreshAll();
        waitFor([&engine]() { return engine.bootc()->available(); }, 5000);
        engine.requestAppUpdates();
        waitFor([&engine]() { return engine.state() == QStringLiteral("failed"); }, 10000);
        check(engine.state() == QStringLiteral("failed"),
              QStringLiteral("flatpak start job canceled -> failed (state=%1)").arg(engine.state()));
        check(!QFile::exists(updateMarker),
              QStringLiteral("canceled start job never runs the user update"));
    }

    // ---- R93-02 MANDATORY REGRESSION: A timeout -> B requested -> A answers late
    QFile::remove(updateMarker);
    {
        // The fake user update prints progress, keeps "running" well past the
        // deadline, prints another progress line late and only then exits 0.
        writeFakeFlatpak(QStringLiteral("printf '50%% (1/2)\\n'; sleep 1; "
                                       "printf '75%% (2/2)\\n'; sleep 5\n"));
        FakeSystemdCalls systemd;
        systemd.scripted[flatpakUnit].append(FakeSystemdCalls::successTerminal());
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd,
                            work.filePath(QStringLiteral("fake-flatpak")),
                            fakeBootcPath, 300, 30);
        engine.setStoragePreflightMinimums(0, 0);
        engine.refreshAll();
        waitFor([&engine]() { return engine.bootc()->available(); }, 5000);

        // A: apps flow; the system stage completes and the user stage hangs.
        engine.requestAppUpdates();
        waitFor([&engine]() { return engine.state() == QStringLiteral("failed"); }, 10000);
        check(engine.state() == QStringLiteral("failed"),
              QStringLiteral("A: watch timeout at the user stage -> failed (state=%1)")
                  .arg(engine.state()));
        check(QFile::exists(updateMarker),
              QStringLiteral("A: the user update process is still alive (not canceled)"));

        const int progressAfterTimeout = countEvents(engine, QStringLiteral("flatpak-progress"));

        // B: requested while A's user process is still running - must be
        // refused instead of stacking an incompatible operation.
        engine.requestAppUpdates();
        QCoreApplication::processEvents(QEventLoop::AllEvents, 100);
        check(engine.state() == QStringLiteral("failed"),
              QStringLiteral("B: refused while A's user update still runs (state=%1)")
                  .arg(engine.state()));
        check(systemd.startUnitCalls == 1,
              QStringLiteral("B: no new unit start while A's user update still runs (starts=%1)")
                  .arg(systemd.startUnitCalls));
        check(countEvents(engine, QStringLiteral("concurrent-operation-detected")) >= 1,
              QStringLiteral("B: refusal recorded as concurrent-operation-detected"));

        // A's user process answers LATE with success.
        waitFor([&engine]() { return countEvents(engine, QStringLiteral("flatpak-update-success")) >= 1; },
                15000);
        QCoreApplication::processEvents(QEventLoop::AllEvents, 100);
        check(engine.state() == QStringLiteral("failed"),
              QStringLiteral("A's late user success does not conclude B or reopen A (state=%1)")
                  .arg(engine.state()));
        check(countEvents(engine, QStringLiteral("flatpak-update-success"),
                          QStringLiteral("Success")) == 0,
              QStringLiteral("A's late user success is never a machine result"));
        check(countEvents(engine, QStringLiteral("flatpak-progress")) == progressAfterTimeout,
              QStringLiteral("A's late user progress never reaches the UI (progress events=%1)")
                  .arg(countEvents(engine, QStringLiteral("flatpak-progress"))));
        // The late result also must not refresh as if the operation concluded:
        // no new history merge happened for it (pushEvent only).
        check(systemd.startUnitCalls == 1,
              QStringLiteral("late A result triggers no new start (starts=%1)")
                  .arg(systemd.startUnitCalls));
    }

    // ---- R93-02: refuse to stack while the previous system unit runs --------
    {
        writeFakeFlatpak(QStringLiteral("exit 0\n"));
        FakeSystemdCalls systemd;
        systemd.unitActiveAnswers[flatpakUnit] = true; // left running by a timed-out op
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd,
                            work.filePath(QStringLiteral("fake-flatpak")),
                            fakeBootcPath, 2000, 30);
        engine.setStoragePreflightMinimums(0, 0);
        engine.refreshAll();
        waitFor([&engine]() { return engine.bootc()->available(); }, 5000);
        engine.requestAppUpdates();
        QCoreApplication::processEvents(QEventLoop::AllEvents, 100);
        // Lote 11B (H5 P2-5): refreshAll() answered bootc-status-ok, which is
        // NOT a check, so the machine honestly rests in "unknown" (never
        // verified) instead of "upToDate"; the refusal must not move it.
        check(engine.state() == QStringLiteral("unknown"),
              QStringLiteral("running flatpak unit blocks a new apps flow (state=%1)")
                  .arg(engine.state()));
        check(systemd.startUnitCalls == 0,
              QStringLiteral("running flatpak unit start is never queued (starts=%1)")
                  .arg(systemd.startUnitCalls));
        check(countEvents(engine, QStringLiteral("concurrent-operation-detected")) == 1,
              QStringLiteral("running flatpak unit refusal recorded"));
    }

    // Lote 12: systemd is simulated and the provider reads a real, atomic fixture.
    const QString cacheDir = work.filePath(QStringLiteral("bootc-cache"));
    QDir().mkpath(cacheDir);
    const QString cachePath = cacheDir + QStringLiteral("/status.json");
    const auto writeCache = [&cachePath](const QByteArray& data) {
        QSaveFile file(cachePath);
        if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size()
            || !file.commit()) {
            failFast(QStringLiteral("could not publish the status fixture"));
        }
    };
    const auto writeCapture = [&writeCache](const QString& capture, bool staged,
                                             const QString& bootedVersion = QStringLiteral("1.0")) {
        const QString stagedEntry = staged ? QStringLiteral(R"({"image":{"image":{"image":"quay.io/enthroned/test-os:next"},"version":"2.0"}})")
                                           : QStringLiteral("null");
        writeCache(QStringLiteral(R"({"enthronedCaptureUsec":"%1","status":{"booted":{"image":{"image":{"image":"quay.io/enthroned/test-os:stable"},"version":"%2"}},"staged":%3}})")
                       .arg(capture, bootedVersion, stagedEntry).toUtf8());
    };
    const QString fullUnit = QStringLiteral("uupd-manual.service");
    auto completedUpdate = FakeSystemdCalls::successTerminal();
    completedUpdate.insert(QStringLiteral("execMainExitUsec"), 200);
    check(Enthroned::systemdPropertyInterface(QStringLiteral("ExecMainExitTimestampMonotonic"))
              == QLatin1String("org.freedesktop.systemd1.Service"),
          QStringLiteral("update exit clock comes from the Service interface"));
    {
        writeCapture(QStringLiteral("100"), false);
        FakeSystemdCalls systemd;
        systemd.scripted[checkUnit].append(FakeSystemdCalls::exitStatusTerminal(77));
        systemd.scripted[fullUnit].append(completedUpdate);
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                            QString(), 2000, 30, nullptr, cachePath);
        engine.refreshAll();
        check(engine.bootc()->available() && engine.bootc()->bootedVersion() == QLatin1String("1.0")
                  && engine.state() == QLatin1String("unknown"),
              QStringLiteral("valid boot capture shows installed version without a check"));
        engine.checkForUpdates();
        const auto lastCheck = engine.lastCheck();
        check(engine.state() == QLatin1String("upToDate") && !lastCheck.isEmpty(),
              QStringLiteral("check exit 77 sets a real last-check result"));
        engine.requestUpdate();
        check(engine.state() == QLatin1String("deploymentPending")
                  && engine.bootc()->available() && !engine.canReboot()
                  && engine.lastCheck() == lastCheck,
              QStringLiteral("successful unit with old cache stays pending and preserves last check"));
        engine.checkForUpdates();
        engine.requestUpdate();
        check(systemd.startUnitCalls == 2 && engine.state() == QLatin1String("deploymentPending"),
              QStringLiteral("pending confirmation cannot be replaced by another operation"));

        writeCapture(QStringLiteral("199"), true);
        engine.refreshAll();
        check(engine.state() == QLatin1String("deploymentPending") && !engine.canReboot(),
              QStringLiteral("a late publication sampled before exit cannot request restart"));
        writeCapture(QStringLiteral("200"), false);
        engine.refreshAll();
        check(engine.state() == QLatin1String("deploymentPending"),
              QStringLiteral("a sample equal to the exit timestamp is insufficient"));

        QFile::remove(cachePath);
        engine.refreshAll();
        check(engine.state() == QLatin1String("deploymentPending") && !engine.bootc()->available(),
              QStringLiteral("unpublished status stays pending"));
        writeCache(QByteArrayLiteral("{invalid JSON"));
        engine.refreshAll();
        check(engine.state() == QLatin1String("deploymentPending") && !engine.bootc()->available(),
              QStringLiteral("invalid status stays pending"));
        writeCapture(QStringLiteral("not-a-timestamp"), false);
        engine.refreshAll();
        check(engine.state() == QLatin1String("deploymentPending") && engine.bootc()->available(),
              QStringLiteral("valid deployment with invalid clock can describe only the boot"));
        writeCapture(QStringLiteral("201"), true);
        check(waitFor([&engine]() { return engine.state() == QLatin1String("restartRequired"); }, 3000)
                  && engine.canReboot() && engine.lastCheck() == lastCheck,
              QStringLiteral("fresh staged publication triggers restart through the watcher"));
        writeCapture(QStringLiteral("100"), false);
        engine.refreshAll();
        check(engine.state() == QLatin1String("restartRequired") && engine.restartPending(),
              QStringLiteral("boot capture cannot clear a confirmed restart"));
        writeCapture(QStringLiteral("202"), false);
        engine.refreshDeploymentStatus();
        check(engine.state() == QLatin1String("unknown") && !engine.restartPending()
                  && engine.lastCheck() == lastCheck,
              QStringLiteral("G12.4 a newer no-stage capture clears the restart without claiming a successful check"));
    }
    {
        writeCapture(QStringLiteral("201"), false); // published by the time the unit finishes
        FakeSystemdCalls systemd;
        systemd.scripted[fullUnit].append(completedUpdate);
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                            QString(), 2000, 30, nullptr, cachePath);
        engine.refreshAll();
        engine.requestUpdate();
        check(engine.state() == QLatin1String("updateConfirmed") && engine.lastCheck().isEmpty()
                  && !engine.canReboot(),
              QStringLiteral("fresh no-stage status confirms the operation without claiming a check"));
    }
    {
        writeCapture(QStringLiteral("201"), true);
        FakeSystemdCalls systemd;
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                            QString(), 2000, 30, nullptr, cachePath);
        engine.refreshAll();
        engine.requestUpdate(); // no execMainExitUsec in the fake service answer
        check(engine.state() == QLatin1String("deploymentPending"),
              QStringLiteral("missing unit exit timestamp cannot confirm staging"));
    }
    {
        writeCapture(QStringLiteral("100"), true);
        FakeSystemdCalls systemd;
        systemd.scripted[fullUnit].append(FakeSystemdCalls::exitStatusTerminal(1));
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                            QString(), 2000, 30, nullptr, cachePath);
        engine.refreshAll();
        engine.requestUpdate();
        check(engine.state() == QLatin1String("failed")
                  && countEvents(engine, QStringLiteral("update-success")) == 0,
              QStringLiteral("unit failure is preserved when an older cache reports staging"));
    }
    // Gate 12.1: sequences of operations, reopening and failure after a confirmed restart.
    {
        // An earlier operation's confirmation can never confirm a later one.
        writeCapture(QStringLiteral("100"), false);
        FakeSystemdCalls systemd;
        auto second = completedUpdate;
        second.insert(QStringLiteral("execMainExitUsec"), 400);
        systemd.scripted[fullUnit].append(completedUpdate);
        systemd.scripted[fullUnit].append(second);
        systemd.scripted[fullUnit].append(FakeSystemdCalls::successTerminal()); // no exit timestamp
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                            QString(), 2000, 30, nullptr, cachePath);
        engine.refreshAll();
        engine.requestUpdate();
        writeCapture(QStringLiteral("201"), false);
        engine.refreshAll();
        check(engine.state() == QLatin1String("updateConfirmed"),
              QStringLiteral("G12.1 operation 1 is confirmed by its own later capture"));
        engine.requestUpdate(); // exits at 400; the 201 capture belongs to operation 1
        check(engine.state() == QLatin1String("deploymentPending"),
              QStringLiteral("G12.1 operation 2 is not confirmed by the capture of operation 1"));
        engine.refreshAll();
        check(engine.state() == QLatin1String("deploymentPending"),
              QStringLiteral("G12.1 re-reading the same old capture keeps operation 2 pending"));
        writeCapture(QStringLiteral("401"), false);
        engine.refreshAll();
        check(engine.state() == QLatin1String("updateConfirmed"),
              QStringLiteral("G12.1 operation 2 is confirmed only by a capture after its exit"));
        engine.requestUpdate(); // no exit timestamp at all
        check(engine.state() == QLatin1String("deploymentPending"),
              QStringLiteral("G12.1 a later operation without a timestamp cannot reuse the earlier exit"));
    }
    const auto historyHasFailure = [](const UpdateEngine& engine) {
        for (const QVariant& row : engine.history()) {
            const auto entry = row.toMap();
            if (entry.value(QStringLiteral("kind")).toString() == QLatin1String("update-failed-with-errors")
                && entry.value(QStringLiteral("title")).toString().contains(QLatin1String("42"))) {
                return true;
            }
        }
        return false;
    };
    {
        // A confirmed restart survives a later failed operation and status refreshes.
        writeCapture(QStringLiteral("100"), false);
        FakeSystemdCalls systemd;
        systemd.scripted[fullUnit].append(completedUpdate);
        systemd.scripted[fullUnit].append(FakeSystemdCalls::exitStatusTerminal(42));
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                            QString(), 2000, 30, nullptr, cachePath);
        engine.refreshAll();
        engine.requestUpdate();
        writeCapture(QStringLiteral("201"), true);
        check(waitFor([&engine]() { return engine.state() == QLatin1String("restartRequired"); }, 3000),
              QStringLiteral("G12.1 restart confirmed by a fresh staged capture"));
        const int successesBefore = countEvents(engine, QStringLiteral("update-success"));
        const int stagedEvents = countEvents(engine, QStringLiteral("staged-deployment-detected"));
        engine.requestUpdate(); // allowed by canUpdate() in restartRequired
        check(engine.state() == QLatin1String("failed")
                  && engine.restartPending() && engine.canReboot()
                  && countEvents(engine, QStringLiteral("update-success")) == successesBefore
                  && countEvents(engine, QStringLiteral("update-failed-with-errors")) == 1,
              QStringLiteral("G12.4 the failed second operation keeps the confirmed restart and error"));
        writeCapture(QStringLiteral("301"), true);
        engine.refreshAll();
        check(engine.state() == QLatin1String("failed") && engine.restartPending()
                  && countEvents(engine, QStringLiteral("staged-deployment-detected")) == stagedEvents,
              QStringLiteral("G12.4 a valid staged refresh preserves the error without duplicating staging"));
        check(waitFor([&]() { return historyHasFailure(engine); }, 3000),
              QStringLiteral("G12.4 full refresh retains the failed operation in history"));

        check(QFile::remove(cachePath), QStringLiteral("G12.4 remove the synthetic capture"));
        engine.refreshDeploymentStatus();
        check(!engine.bootc()->available() && engine.restartPending()
                  && engine.state() == QLatin1String("failed") && historyHasFailure(engine),
              QStringLiteral("G12.4 missing status preserves the known staging, error and history"));
        writeCapture(QStringLiteral("200"), false);
        engine.refreshDeploymentStatus();
        check(engine.restartPending() && engine.state() == QLatin1String("failed"),
              QStringLiteral("G12.4 older no-stage capture cannot clear the pending restart"));
        writeCapture(QStringLiteral("302"), false);
        engine.refreshDeploymentStatus();
        check(!engine.restartPending() && !engine.canReboot() && engine.state() == QLatin1String("failed"),
              QStringLiteral("G12.4 newer no-stage capture clears only the restart"));
        writeCapture(QStringLiteral("303"), true);
        engine.refreshDeploymentStatus();
        check(engine.restartPending() && engine.state() == QLatin1String("failed"),
              QStringLiteral("G12.4 newly observed staging preserves the previous failure"));
    }
    {
        FakeSystemdCalls reopenedSystemd;
        UpdateEngine reopened({ QStringLiteral("--plain") }, &reopenedSystemd, fakeFlatpakPath,
                              QString(), 2000, 30, nullptr, cachePath);
        reopened.refreshAll();
        check(reopened.state() == QLatin1String("restartRequired") && reopened.canReboot()
                  && waitFor([&]() { return historyHasFailure(reopened); }, 3000),
              QStringLiteral("G12.4 reopening restores staging and the persisted failure in history"));
        reopenedSystemd.setUnavailable();
        reopened.checkForUpdates();
        check(reopened.state() == QLatin1String("serviceUnavailable") && reopened.restartPending()
                  && !reopened.canReboot() && reopenedSystemd.startUnitCalls == 0,
              QStringLiteral("G12.4 unavailable service remains visible alongside staging and cannot reboot"));
    }
    {
        // Reopening the Update Center rebuilds the state from the published capture only.
        writeCapture(QStringLiteral("201"), true);
        {
            FakeSystemdCalls systemd;
            UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                                QString(), 2000, 30, nullptr, cachePath);
            engine.refreshAll();
            check(engine.state() == QLatin1String("restartRequired") && engine.canReboot(),
                  QStringLiteral("G12.1 reopen with a staged capture shows the restart [state=%1 avail=%2 staged=%3]").arg(engine.state()).arg(engine.bootc()->available()).arg(engine.bootc()->stagedPresent()));
        }
        writeCapture(QStringLiteral("100"), false, QStringLiteral("2.0")); // new boot, new monotonic clock
        {
            FakeSystemdCalls systemd;
            UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                                QString(), 2000, 30, nullptr, cachePath);
            engine.refreshAll();
            check(engine.state() == QLatin1String("unknown") && !engine.restartPending() && !engine.canReboot()
                      && engine.bootc()->bootedVersion() == QLatin1String("2.0")
                      && countEvents(engine, QStringLiteral("deployment-confirmed")) == 0,
              QStringLiteral("G12.4 reopen after boot shows the installed version without a pending restart"));
        }
        writeCache(QByteArrayLiteral("{\"status\":"));
        {
            FakeSystemdCalls systemd;
            UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                                QString(), 2000, 30, nullptr, cachePath);
            engine.refreshAll();
            check(!engine.bootc()->available() && !engine.canReboot()
                      && engine.state() != QLatin1String("updateConfirmed")
                      && engine.state() != QLatin1String("restartRequired"),
                  QStringLiteral("G12.1 reopen with a malformed capture claims nothing"));
        }
    }
    {
        qunsetenv("ENTHRONED_SETTINGS_ALLOW_MUTATION");
        writeCapture(QStringLiteral("100"), true);
        FakeSystemdCalls systemd;
        UpdateEngine engine({ QStringLiteral("--plain") }, &systemd, fakeFlatpakPath,
                            QString(), 2000, 30, nullptr, cachePath);
        engine.refreshAll();
        engine.requestUpdate();
        engine.requestSystemUpdate();
        check(systemd.startUnitCalls == 0 && engine.restartPending() && !engine.canUpdate() && !engine.canReboot(),
              QStringLiteral("G12.4 closed channel reports staging and keeps mutation and reboot blocked"));
    }

    // The remaining fake user process (regression scenario) is a child QProcess
    // owned by the destroyed engine: its destructor terminates it; no real
    // update ever ran.

    if (failures > 0) {
        qCritical() << "FAILED:" << failures << "check(s)";
        return 1;
    }
    qInfo() << "update-engine-integration-smoke:" << checks << "passed, 0 failed";
    return 0;
}
