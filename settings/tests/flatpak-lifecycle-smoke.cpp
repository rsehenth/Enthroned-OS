// Lote 9.2 (H4-005): lifecycle of the user Flatpak update process.
// Runs the REAL FlatpakUpdatesProvider against a fake `flatpak` program
// injected by absolute path (never a real flatpak): killed by signal
// (errorOccurred(Crashed) BEFORE finished), exit 1, exit 0 and
// FailedToStart. Each case must produce EXACTLY ONE userUpdateFinished
// result and leave the provider idle - the audited bug dereferenced a
// cleared member when a crashed process emitted errorOccurred(Crashed)
// followed by finished().
// Needs Qt (Core) and KF6::I18n; runs in the build (CTest).
#include "../src/flatpakupdatesprovider.h"

#include <QCoreApplication>
#include <QDebug>
#include <QEventLoop>
#include <QFile>
#include <QProcess>
#include <QTemporaryDir>
#include <QTimer>

using namespace Enthroned;

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);

    QTemporaryDir fakeDir;
    if (!fakeDir.isValid()) {
        qCritical() << "Cannot create the fake flatpak directory";
        return 1;
    }
    const QString fakeProgram = fakeDir.filePath(QStringLiteral("flatpak"));

    int failures = 0;
    auto writeFake = [&fakeDir](const QString& body, bool executable) {
        QFile program(fakeDir.filePath(QStringLiteral("flatpak")));
        program.remove();
        if (!program.open(QIODevice::WriteOnly | QIODevice::Text)) {
            qCritical() << "Cannot write the fake flatpak";
            return false;
        }
        program.write(QStringLiteral("#!/bin/sh\n%1\n").arg(body).toUtf8());
        program.close();
        if (executable) {
            program.setPermissions(QFile::ReadUser | QFile::WriteUser | QFile::ExeUser);
        }
        return true;
    };

    struct Case { const char* name; const char* body; bool executable; bool expectOk; int expectResults; };
    const Case cases[] = {
        { "crashed (killed by signal)", "kill -9 $$", true, false, 1 },
        { "exit 1", "exit 1", true, false, 1 },
        { "exit 0", "exit 0", true, true, 1 },
        { "failed to start (no exec bit)", "exit 0", false, false, 1 },
    };

    for (const Case& c : cases) {
        if (!writeFake(QString::fromUtf8(c.body), c.executable)) {
            ++failures;
            continue;
        }
        // The fake program is injected by PATH-free absolute path: a real
        // flatpak on the machine is never invoked by this test.
        FlatpakUpdatesProvider provider(fakeProgram);
        if (!provider.updateUserInstallations()) {
            qCritical() << "FAIL:" << c.name << "- provider refused to start";
            ++failures;
            continue;
        }
        int results = 0;
        bool ok = true;
        QEventLoop loop;
        QObject::connect(&provider, &FlatpakUpdatesProvider::userUpdateFinished,
                         [&](bool success, const QString&) {
            ++results;
            ok = success;
            loop.quit();
        });
        QTimer::singleShot(10000, &loop, &QEventLoop::quit);
        loop.exec();

        if (results != c.expectResults) {
            qCritical() << "FAIL:" << c.name << "- expected" << c.expectResults
                        << "result(s), got" << results;
            ++failures;
            continue;
        }
        if (ok != c.expectOk) {
            qCritical() << "FAIL:" << c.name << "- expected ok=" << c.expectOk
                        << ", got ok=" << ok;
            ++failures;
            continue;
        }
        if (provider.userUpdateRunning()) {
            qCritical() << "FAIL:" << c.name << "- provider still busy after finishing";
            ++failures;
            continue;
        }
        qInfo() << "PASS:" << c.name << "- one result, ok=" << ok;
    }

    if (failures > 0) {
        qCritical() << "FAILED:" << failures << "case(s)";
        return 1;
    }
    qInfo() << "ALL CHECKS PASSED";
    return 0;
}
