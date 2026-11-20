// Lote 10 (P1-1): supervised Settings launch from the desktop context menu.
// A crash inside the launched app must never reach the shell, must be
// detected, retried once, and must end in the fallback binary; a healthy app
// opens on the first attempt; a missing binary falls straight through to the
// next candidate. Lote 10.2 (Gate 10.1): a non-zero normal exit also
// advances, a re-activation while busy is ignored, and destroying the
// launcher with a live child must neither block the GUI thread nor leave the
// kill undone. Fake binaries signal progress with marker files; no Plasma
// library and no real Settings binary is involved.
#include "../src/settingslauncher.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QIODevice>
#include <QProcess>
#include <QTemporaryDir>
#include <QTimer>
#include <cstdio>
#include <cstdlib>
#include <functional>

int g_passed = 0;
int g_failed = 0;

// fprintf, not qDebug: the Release build may silence Qt logging categories
// depending on the environment; the harness output must always be visible.
void check(bool condition, const char* name)
{
    if (condition) {
        ++g_passed;
        fprintf(stderr, "PASS: %s\n", name);
    } else {
        ++g_failed;
        fprintf(stderr, "FAIL: %s\n", name);
    }
}

void failFast(const char* why)
{
    fprintf(stderr, "FATAL: %s\n", why);
    exit(2);
}

bool waitFor(const std::function<bool()>& predicate, int timeoutMs)
{
    QEventLoop loop;
    QTimer timer;
    timer.setSingleShot(true);
    QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
    QTimer poll;
    poll.setInterval(10);
    QObject::connect(&poll, &QTimer::timeout, &loop, [&]() {
        if (predicate()) loop.quit();
    });
    poll.start();
    timer.start(timeoutMs);
    loop.exec();
    return predicate();
}

int main(int argc, char** argv)
{
    fprintf(stderr, "smoke: enter main\n");
    QCoreApplication app(argc, argv);
    QTemporaryDir work;
    if (!work.isValid()) {
        failFast("temporary work dir unavailable");
    }
    const QString fakeBin = work.filePath(QStringLiteral("bin"));
    if (!QDir().mkpath(fakeBin)) {
        failFast("cannot create the fake bin dir");
    }
    auto writeFake = [&fakeBin](const QString& name, const QString& body) {
        const QString path = fakeBin + QStringLiteral("/") + name;
        QFile fake(path);
        if (!fake.open(QIODevice::WriteOnly | QIODevice::Text)) {
            fprintf(stderr, "FATAL: cannot write the fake %s\n", qPrintable(name));
            exit(2);
        }
        fake.write(QStringLiteral("#!/bin/sh\n%1\n").arg(body).toUtf8());
        fake.close();
        fake.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        return path;
    };
    auto marker = [&work](const QString& name) {
        return work.filePath(name);
    };
    SettingsLauncher launcher;
    // A launch chain must be fully finished (or failed) before the next one:
    // the previous candidate may still be winding down when its marker lands.
    auto launchAndWaitIdle = [&launcher](const QStringList& candidates) {
        launcher.launch(candidates);
        waitFor([&launcher]() { return !launcher.isBusy(); }, 10000);
    };

    // Healthy app: opens on the first attempt.
    writeFake(QStringLiteral("app-ok"),
              QStringLiteral("touch \"%1\"\nexit 0\n").arg(marker(QStringLiteral("ok1"))));
    launcher.launch({ fakeBin + QStringLiteral("/app-ok") });
    check(waitFor([&]() { return QFile::exists(marker(QStringLiteral("ok1"))); }, 5000),
          "normal open: first candidate runs");
    waitFor([&launcher]() { return !launcher.isBusy(); }, 10000);

    // Crash + retry: the crash is followed by the repeated candidate (the
    // plugin's real chain is [settings, settings, systemsettings]).
    writeFake(QStringLiteral("app-crash-then-ok"),
              QStringLiteral("if [ -f \"%1\" ]; then touch \"%2\"; else touch \"%1\"; kill -SEGV $$; fi\n")
                  .arg(marker(QStringLiteral("crash1")), marker(QStringLiteral("retry-ok"))));
    launchAndWaitIdle({ fakeBin + QStringLiteral("/app-crash-then-ok"),
                        fakeBin + QStringLiteral("/app-crash-then-ok") });
    check(QFile::exists(marker(QStringLiteral("retry-ok"))),
          "failure + retry: second attempt succeeds after the crash");

    // Repeated crash: the chain ends at the fallback candidate.
    writeFake(QStringLiteral("app-always-crash"),
              QStringLiteral("touch \"%1\"\nkill -SEGV $$\n").arg(marker(QStringLiteral("crash-again"))));
    writeFake(QStringLiteral("app-fallback"),
              QStringLiteral("touch \"%1\"\nexit 0\n").arg(marker(QStringLiteral("fallback-ok"))));
    launchAndWaitIdle({ fakeBin + QStringLiteral("/app-always-crash"),
                        fakeBin + QStringLiteral("/app-always-crash"),
                        fakeBin + QStringLiteral("/app-fallback") });
    check(QFile::exists(marker(QStringLiteral("fallback-ok"))),
          "repeated failure: fallback candidate reached");

    // Missing binary: FailedToStart advances to the working candidate.
    writeFake(QStringLiteral("app-fallback2"),
              QStringLiteral("touch \"%1\"\nexit 0\n").arg(marker(QStringLiteral("fallback2-ok"))));
    launchAndWaitIdle({ work.filePath(QStringLiteral("does-not-exist")),
                        fakeBin + QStringLiteral("/app-fallback2") });
    check(QFile::exists(marker(QStringLiteral("fallback2-ok"))),
          "missing binary: next candidate used");

    // Lote 10.2: a normal exit with a non-zero code also advances (the app
    // refused to run; the user still gets a window).
    writeFake(QStringLiteral("app-exit3"), QStringLiteral("exit 3\n"));
    writeFake(QStringLiteral("app-after3"),
              QStringLiteral("touch \"%1\"\nexit 0\n").arg(marker(QStringLiteral("after3-ok"))));
    launchAndWaitIdle({ fakeBin + QStringLiteral("/app-exit3"),
                        fakeBin + QStringLiteral("/app-after3") });
    check(QFile::exists(marker(QStringLiteral("after3-ok"))),
          "non-zero exit: next candidate used");

    // Lote 10.2: a re-activation while the chain is busy is ignored (no
    // second process over the running one).
    const QString busyMarker = marker(QStringLiteral("busy-first"));
    const QString secondMarker = marker(QStringLiteral("busy-second"));
    writeFake(QStringLiteral("app-slow"),
              QStringLiteral("sleep 1\ntouch \"%1\"\n").arg(busyMarker));
    writeFake(QStringLiteral("app-second"),
              QStringLiteral("touch \"%1\"\n").arg(secondMarker));
    launcher.launch({ fakeBin + QStringLiteral("/app-slow") });
    check(launcher.isBusy(), "concurrent: chain busy after the first launch");
    launcher.launch({ fakeBin + QStringLiteral("/app-second") });
    check(!QFile::exists(secondMarker), "concurrent: second chain not started while busy");
    waitFor([&launcher]() { return !launcher.isBusy(); }, 10000);
    check(QFile::exists(busyMarker) && !QFile::exists(secondMarker),
          "concurrent: only the first chain ran");

    // Lote 10.2: destroying the launcher with a live child must not run a
    // blocking kill()/waitForFinished() on the calling (GUI) thread. The fake
    // ignores SIGTERM on purpose (exec keeps the inherited SIG_IGN across the
    // image change): the pre-10.2 implementation would block in the QProcess
    // destructor until its internal wait gave up. The pid marker is written
    // AFTER the trap so seeing it proves the trap is armed, and the stdio
    // redirect drops the inherited output pipe (ctest waits for its EOF).
    const QString stuckPid = marker(QStringLiteral("stuck-pid"));
    writeFake(QStringLiteral("app-stuck"),
              QStringLiteral("trap '' TERM\necho $$ > \"%1\"\nexec >/dev/null 2>&1\nexec sleep 30\n")
                  .arg(stuckPid));
    auto *doomed = new SettingsLauncher();
    doomed->launch({ fakeBin + QStringLiteral("/app-stuck") });
    check(waitFor([&]() { return QFile::exists(stuckPid); }, 5000),
          "teardown: child with live process started");
    QElapsedTimer teardownClock;
    teardownClock.start();
    delete doomed;
    check(teardownClock.elapsed() < 5000,
          "teardown: destruction with a SIGTERM-ignoring child does not block");
    // Clean the TERM-immune fake up (the launcher cannot terminate a child
    // that ignores SIGTERM - bounded leak by design, never a GUI freeze).
    QFile stuckPidFile(stuckPid);
    if (!stuckPidFile.open(QIODevice::ReadOnly)) {
        failFast("cannot read the stuck child pid");
    }
    const QString stuckProcess = QString::fromUtf8(stuckPidFile.readAll()).trimmed();
    stuckPidFile.close();
    QProcess::execute(QStringLiteral("kill"), { QStringLiteral("-9"), stuckProcess });

    // Lote 10.2: with a regular child, teardown asks it to exit - no orphan
    // is left running after the plugin goes away. exec turns the shell into
    // the (killable) sleeper so the pid file tracks exactly that process.
    const QString dyingPid = marker(QStringLiteral("dying-pid"));
    writeFake(QStringLiteral("app-dying"),
              QStringLiteral("echo $$ > \"%1\"\nexec >/dev/null 2>&1\nexec sleep 30\n").arg(dyingPid));
    auto *closing = new SettingsLauncher();
    closing->launch({ fakeBin + QStringLiteral("/app-dying") });
    check(waitFor([&]() { return QFile::exists(dyingPid); }, 5000),
          "teardown: killable child started");
    QFile dyingPidFile(dyingPid);
    if (!dyingPidFile.open(QIODevice::ReadOnly)) {
        failFast("cannot read the dying child pid");
    }
    const QString dyingProcess = QString::fromUtf8(dyingPidFile.readAll()).trimmed();
    dyingPidFile.close();
    delete closing;
    check(waitFor([&]() {
              return QProcess::execute(QStringLiteral("kill"),
                                       { QStringLiteral("-0"), dyingProcess }) != 0;
          }, 5000),
          "teardown: the live child is terminated with the launcher");

    // After every chain the launcher is idle again and accepts a new launch.
    const QString idleMarker = marker(QStringLiteral("ok-later"));
    writeFake(QStringLiteral("app-ok-later"),
              QStringLiteral("touch \"%1\"\nexit 0\n").arg(idleMarker));
    launcher.launch({ fakeBin + QStringLiteral("/app-ok-later") });
    check(waitFor([&]() { return QFile::exists(idleMarker); }, 5000),
          "launcher idle: accepts a new launch after the previous one");

    fprintf(stderr, "----------------------------------------\n");
    fprintf(stderr, "settingslauncher-smoke: %d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
