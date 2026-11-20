/*
 * Exercises the production controller (welcomecontroller.cpp) against the
 * real welcome-state-spec.json resource, twice:
 *   1. an in-memory demo pass (no user state touched), and
 *   2. a REAL persistence round-trip (Lote 11B, H5 P2-6) inside a temporary
 *      XDG_STATE_HOME: interruption with the page preserved, resume on a
 *      "next launch" (a new controller instance, as after a new login),
 *      completion, and the reopen decisions that follow (autostart never
 *      nags a completed user; manual always shows; a corrupt state file
 *      resets instead of crashing or lying).
 * The temp location is isolated: nothing outside XDG_STATE_HOME is written.
 * Run: ctest -R welcome-native-smoke  (or the binary directly)
 * SPDX-License-Identifier: Apache-2.0
 */
#include "welcomecontroller.h"
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QDebug>

using namespace Enthroned;

static int failures = 0;
static int checks = 0;

#define CHECK(cond, message)                                     \
    do {                                                         \
        ++checks;                                                \
        if (!(cond)) {                                           \
            qCritical() << "FAIL:" << message;                   \
            ++failures;                                          \
        }                                                        \
    } while (false)

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);

    // ---------- Part 1: in-memory demo pass (demoMode never persists) ------
    {
        WelcomeController controller(true);
        CHECK(controller.artcraftConsented() == false
                  && controller.phase() == QLatin1String("never-started"),
              "initial state is not a clean, unconsented welcome");
        controller.notifyLaunched();
        controller.next();
        controller.markClosed();
        CHECK(controller.currentPage() == 1
                  && controller.phase() == QLatin1String("interrupted"),
              "interrupted welcome did not preserve its page");
        controller.notifyLaunched();
        controller.finish();
        CHECK(controller.phase() == QLatin1String("started"),
              "finishing before the final page must not complete the walkthrough");
        controller.goTo(controller.pageCount() - 1);
        controller.finish();
        CHECK(controller.phase() == QLatin1String("completed")
                  && controller.artcraftConsented() == false
                  && !WelcomeController::shouldShowOnLaunch(controller.phase(),
                         QStringLiteral("autostart"), false)
                  && WelcomeController::shouldShowOnLaunch(controller.phase(),
                         QStringLiteral("manual"), false),
              "completion/reopening/consent contract failed");
    }

    // ---------- Part 2: real persistence round-trip ------------------------
    QTemporaryDir stateRoot;
    if (!stateRoot.isValid()) {
        qCritical() << "FAIL: could not create the temporary state root";
        return 1;
    }
    // Must be set BEFORE the first QStandardPaths call (paths are cached).
    qputenv("XDG_STATE_HOME", QFile::encodeName(stateRoot.filePath(QStringLiteral("state"))));
    const QString stateFile = stateRoot.filePath(QStringLiteral("state/enthroned-os/welcome-state.json"));

    // Login 1: first launch, walk to step 2 (index 1), unclean interruption
    // (the H5/H4 incident: the window never gets a close event, so no "close"
    // event is applied — the process simply dies with "started" persisted).
    {
        WelcomeController controller(false);
        CHECK(controller.phase() == QLatin1String("never-started"),
              "fresh user state did not start at never-started");
        CHECK(WelcomeController::shouldShowOnLaunch(controller.phase(),
                  QStringLiteral("autostart"), false), "first login did not show the assistant");
        controller.notifyLaunched();
        CHECK(controller.phase() == QLatin1String("started"),
              "first launch did not move to started");
        controller.next();
        // No markClosed(): simulate the kill. The persisted state must already
        // carry the phase and page (save happens on every event).
        CHECK(controller.currentPage() == 1,
              "the walkthrough did not reach page 1 before the kill");
    }
    CHECK(QFile::exists(stateFile), "state file missing after the first session");
    {
        QFile file(stateFile);
        CHECK(file.open(QIODevice::ReadOnly), "state file unreadable");
        const QJsonObject raw = QJsonDocument::fromJson(file.readAll()).object();
        CHECK(raw.value(QStringLiteral("phase")).toString() == QLatin1String("started")
                  && raw.value(QStringLiteral("currentPage")).toInt() == 1,
              "persisted record lost the interrupted page");
    }

    // Login 2: a new controller (as after a new login) must RESUME: autostart
    // shows, the page and any earlier choices survive, resuming keeps "started".
    {
        WelcomeController controller(false);
        CHECK(controller.phase() == QLatin1String("started")
                  && controller.currentPage() == 1,
              "resume did not restore the interrupted phase/page");
        CHECK(WelcomeController::shouldShowOnLaunch(controller.phase(),
                  QStringLiteral("autostart"), false),
              "autostart refuses to resume an interrupted walkthrough");
        controller.notifyLaunched();
        CHECK(controller.phase() == QLatin1String("started"),
              "resuming a started walkthrough must keep it started");
        CHECK(controller.currentPage() == 1, "resume lost the current page");
        controller.next();
        controller.markClosed();
    }
    {
        WelcomeController controller(false);
        CHECK(controller.phase() == QLatin1String("interrupted") && controller.currentPage() == 2,
              "ordinary close must persist the interruption and current page");
        CHECK(WelcomeController::shouldShowOnLaunch(controller.phase(),
                  QStringLiteral("autostart"), false), "ordinary close must allow login resume");
        controller.notifyLaunched();
        controller.goTo(controller.pageCount() - 1);
        controller.finish();
        CHECK(controller.phase() == QLatin1String("completed"),
              "finishing after resume did not complete the walkthrough");
    }

    // After completion the walkthrough must never reopen on autostart,
    // while a manual reopen still works without resetting the phase.
    {
        WelcomeController controller(false);
        CHECK(controller.phase() == QLatin1String("completed"),
              "completed phase did not persist");
        CHECK(!WelcomeController::shouldShowOnLaunch(controller.phase(),
                  QStringLiteral("autostart"), false),
              "autostart reopened a completed walkthrough");
        CHECK(WelcomeController::shouldShowOnLaunch(controller.phase(),
                  QStringLiteral("manual"), false),
              "manual reopen refused for a completed walkthrough");
        controller.notifyLaunched();
        CHECK(controller.phase() == QLatin1String("completed"),
              "manual revisit must not reset the completed phase");
        // Simulate an unexpected exit during a manual revisit.
    }
    {
        WelcomeController controller(false);
        CHECK(!WelcomeController::shouldShowOnLaunch(controller.phase(),
                  QStringLiteral("autostart"), false),
              "a crash during a completed revisit must not reenable autostart");
        controller.dismiss();
        CHECK(controller.phase() == QLatin1String("completed"),
              "dismissing a revisit must preserve completion");
    }

    // Legacy completion and interruption remain readable as version 1.
    const auto writeState = [&stateFile](const QByteArray& data) {
        QFile file(stateFile);
        CHECK(file.open(QIODevice::WriteOnly | QIODevice::Truncate), "cannot write the test state");
        CHECK(file.write(data) == data.size(), "the test state was only partially written");
    };
    writeState(R"({"version":1,"phase":"completed","currentPage":4,"manualReopen":true})");
    {
        WelcomeController controller(false);
        CHECK(controller.phase() == QLatin1String("completed")
                  && !WelcomeController::shouldShowOnLaunch(controller.phase(),
                         QStringLiteral("autostart"), false),
              "legacy manualReopen must not reenable autostart for completed users");
    }
    writeState(R"({"version":1,"phase":"interrupted","currentPage":3,"artcraftConsented":true,"artcraftInstallState":"done"})");
    {
        WelcomeController controller(false);
        CHECK(WelcomeController::shouldShowOnLaunch(controller.phase(),
                  QStringLiteral("autostart"), false), "a legacy interruption should resume");
        controller.notifyLaunched();
        CHECK(controller.currentPage() == 3 && controller.artcraftConsented()
                  && controller.artcraftInstallState() == QLatin1String("done"),
              "legacy resume lost the page or preferences");
        controller.dismiss();
        CHECK(controller.phase() == QLatin1String("dismissed") && controller.currentPage() == 3,
              "dismissal must preserve the current page independently of completion");
    }
    {
        WelcomeController controller(false);
        CHECK(controller.phase() == QLatin1String("dismissed") && controller.currentPage() == 3,
              "dismissal did not persist across logins");
        CHECK(!WelcomeController::shouldShowOnLaunch(controller.phase(),
                   QStringLiteral("autostart"), false)
                  && WelcomeController::shouldShowOnLaunch(controller.phase(),
                         QStringLiteral("manual"), false),
              "dismissed users must retain manual launch and suppress autostart");
        controller.notifyLaunched();
        CHECK(controller.artcraftConsented()
                  && controller.artcraftInstallState() == QLatin1String("done"),
              "manual reopening lost preferences");
        controller.markClosed();
    }
    {
        WelcomeController controller(false);
        CHECK(controller.phase() == QLatin1String("dismissed")
                  && !WelcomeController::shouldShowOnLaunch(controller.phase(),
                         QStringLiteral("autostart"), false),
              "closing a manual revisit must not reenable autostart");
        controller.notifyLaunched();
        controller.goTo(controller.pageCount() - 1);
        controller.finish();
        CHECK(controller.phase() == QLatin1String("completed"),
              "a dismissed user can later finish the walkthrough manually");
    }

    // A corrupted state file resets to the initial state instead of crashing
    // or blocking the user (and the autostart then still shows the assistant).
    {
        QFile file(stateFile);
        CHECK(file.open(QIODevice::WriteOnly | QIODevice::Truncate),
              "could not overwrite the state file for the corruption test");
        file.write("{ this is not json");
        file.close();
        WelcomeController controller(false);
        CHECK(controller.phase() == QLatin1String("never-started"),
              "corrupt state did not reset to the initial state");
        CHECK(WelcomeController::shouldShowOnLaunch(controller.phase(),
                  QStringLiteral("autostart"), false),
              "autostart refuses to show after a state reset");
    }

    // Gate 12.1: hostile or damaged state files never crash the controller, never
    // suppress the assistant for an unreadable record, and never mix two lives.
    {
        const QList<QByteArray> damaged = {
            QByteArray(),                                                   // empty file
            QByteArrayLiteral("[]"),                                        // wrong root type
            QByteArrayLiteral("null"),
            QByteArrayLiteral(R"({"version":"1","phase":"completed"})"),    // version as string
            QByteArrayLiteral(R"({"version":2,"phase":"completed"})"),      // unknown version
            QByteArrayLiteral(R"({"version":1,"phase":42})"),               // phase not a string
            QByteArrayLiteral(R"({"version":1,"phase":"skipped"})"),        // unknown phase
            QByteArrayLiteral(R"({"version":1})"),                          // phase missing
            QByteArrayLiteral(R"({"version":1,"phase":"completed")"),       // truncated
            QByteArray(70000, 'x'),                                         // garbage blob
        };
        for (int i = 0; i < damaged.size(); ++i) {
            writeState(damaged.at(i));
            WelcomeController controller(false);
            CHECK(controller.phase() == QLatin1String("never-started")
                      && controller.currentPage() == 0 && !controller.artcraftConsented()
                      && controller.artcraftInstallState() == QLatin1String("idle")
                      && WelcomeController::shouldShowOnLaunch(controller.phase(),
                             QStringLiteral("autostart"), false),
                  qPrintable(QStringLiteral("damaged state #%1 must reset every field").arg(i)));
        }
        // Out-of-range or mistyped fields inside an otherwise valid record are clamped.
        writeState(R"({"version":1,"phase":"interrupted","currentPage":999,"artcraftConsented":"yes","artcraftInstallState":"hacked"})");
        {
            WelcomeController controller(false);
            CHECK(controller.phase() == QLatin1String("interrupted") && controller.currentPage() == 0
                      && !controller.artcraftConsented()
                      && controller.artcraftInstallState() == QLatin1String("idle"),
                  "out-of-range page and mistyped preferences must be sanitized");
        }
        writeState(R"({"version":1,"phase":"dismissed","currentPage":-3})");
        {
            WelcomeController controller(false);
            CHECK(controller.phase() == QLatin1String("dismissed") && controller.currentPage() == 0
                      && !WelcomeController::shouldShowOnLaunch(controller.phase(),
                             QStringLiteral("autostart"), false),
                  "a negative page must not discard a valid dismissal");
        }
    }
    // A directory where the state file belongs: no crash, initial state, saving is a no-op.
    {
        QFile::remove(stateFile);
        CHECK(QDir().mkpath(stateFile), "could not create the directory fixture");
        WelcomeController controller(false);
        controller.notifyLaunched();
        controller.next();
        CHECK(controller.phase() == QLatin1String("started") && QFileInfo(stateFile).isDir(),
              "an unwritable state location must keep the session alive without touching the directory");
        QDir(stateFile).removeRecursively();
    }
    // Guard: finish() only works on the last page, so a stray call cannot complete the walkthrough.
    {
        QFile::remove(stateFile);
        WelcomeController controller(false);
        controller.notifyLaunched();
        controller.finish();
        CHECK(controller.phase() == QLatin1String("started"),
              "finish() before the last page must not complete the walkthrough");
        controller.markClosed();
        WelcomeController next(false);
        CHECK(next.phase() == QLatin1String("interrupted"),
              "closing mid-way must leave a resumable record");
    }
    // Two controllers (e.g. a stale second login session) interleaving saves must always leave a
    // parseable, coherent record and never an orphan temporary file.
    {
        QFile::remove(stateFile);
        WelcomeController first(false);
        WelcomeController second(false);
        first.notifyLaunched();
        bool coherent = true;
        for (int i = 0; i < 200 && coherent; ++i) {
            (i % 2 ? first : second).goTo(i % WelcomeController::kPageCount);
            QFile file(stateFile);
            coherent = file.open(QIODevice::ReadOnly)
                && QJsonDocument::fromJson(file.readAll()).isObject();
        }
        CHECK(coherent, "interleaved writers left an unreadable state file");
        int leftovers = 0;
        for (const QFileInfo& entry : QDir(QFileInfo(stateFile).absolutePath()).entryInfoList(QDir::Files)) {
            if (entry.fileName() != QFileInfo(stateFile).fileName()) {
                ++leftovers;
            }
        }
        CHECK(leftovers == 0, "atomic writes left temporary files behind");
    }

    if (failures > 0) {
        qCritical() << "welcome-native-smoke FAILED:" << failures << "check(s)";
        return 1;
    }
    qInfo() << "welcome-native-smoke:" << checks << "passed, 0 failed";
    return 0;
}
