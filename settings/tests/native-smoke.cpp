// Exercises the compiled state machine, the mutation guard, the storage
// preflight decision (H4-001) and the systemd outcome classification (H4-007).
#include "update/imageorigin.h"
#include "update/storagepreflight.h"
#include "update/systemdoutcome.h"
#include "update/updatestatemachine.h"
#include <QCoreApplication>
#include <QFile>
#include <QDebug>

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    QFile file(app.arguments().value(1));
    Enthroned::UpdateStateMachine machine;
    QString error;
    if (!file.open(QIODevice::ReadOnly) || !machine.loadSpec(file.readAll(), &error)) {
        qCritical() << "Cannot load production state spec:" << error;
        return 1;
    }
    Enthroned::UpdateEvent event;
    event.rawType = QStringLiteral("engine-update-started");
    QVariantMap context{{QStringLiteral("mutationAllowed"), false}};
    if (machine.step(QStringLiteral("unknown"), event, context) != QStringLiteral("unknown")) {
        qCritical() << "Closed mutation guard allowed an update";
        return 1;
    }
    context.insert(QStringLiteral("mutationAllowed"), true);
    if (machine.step(QStringLiteral("unknown"), event, context) != QStringLiteral("updating")) {
        qCritical() << "State machine failed to evaluate an authorized transition";
        return 1;
    }
    context.insert(QStringLiteral("stagedDeployment"), true);
    // Check the actual bootc-status event with a staged deployment.
    event.rawType = QStringLiteral("bootc-status-ok");
    if (machine.step(QStringLiteral("unknown"), event, context) != QStringLiteral("restartRequired")) {
        qCritical() << "Staged deployment was not reflected in restart state";
        return 1;
    }

    // Lote 8: rollback is explicit, protected and produces a pending restart.
    event.rawType = QStringLiteral("engine-rollback-started");
    QVariantMap rollbackContext{
        { QStringLiteral("mutationAllowed"), true },
        { QStringLiteral("rollbackAvailable"), true }
    };
    if (machine.step(QStringLiteral("restartRequired"), event, rollbackContext)
        != QStringLiteral("rollingBack")) {
        qCritical() << "Authorized rollback did not enter the rollingBack state";
        return 1;
    }
    QVariantMap blockedRollbackContext{
        { QStringLiteral("mutationAllowed"), true },
        { QStringLiteral("rollbackAvailable"), false }
    };
    if (machine.step(QStringLiteral("restartRequired"), event, blockedRollbackContext)
        != QStringLiteral("restartRequired")) {
        qCritical() << "Rollback started without a previous deployment";
        return 1;
    }
    event.rawType = QStringLiteral("rollback-success");
    if (machine.step(QStringLiteral("rollingBack"), event, QVariantMap())
        != QStringLiteral("restartRequired")) {
        qCritical() << "Rollback success did not produce a pending restart";
        return 1;
    }
    // Apps-only updates finish without a reboot.
    event.rawType = QStringLiteral("flatpak-update-success");
    if (machine.step(QStringLiteral("updating"), event, QVariantMap())
        != QStringLiteral("upToDate")) {
        qCritical() << "Applications-only update did not finish without reboot";
        return 1;
    }

    // Image origin policy: never update a generic Fedora image or an unlisted one.
    using namespace Enthroned;
    const QStringList none;
    const QStringList listed{ QStringLiteral("registry.example.org/enthroned/enthroned-os") };
    struct Case { const char* image; const QStringList* expected; const char* origin; bool update; };
    const Case cases[] = {
        { "", &none, "unknown", false },
        { "quay.io/fedora/fedora-bootc:42", &none, "foreign", false },
        { "quay.io/fedora-ostree-desktops/kinoite:42", &listed, "foreign", false },
        { "ghcr.io/ublue-os/aurora:stable", &none, "unverified", true },
        { "localhost/enthroned-os:latest", &none, "unverified", true },
        { "registry.example.org/enthroned/enthroned-os:1.0", &listed, "enthroned", true },
        { "docker://Registry.Example.org/enthroned/enthroned-os@sha256:abc", &listed, "enthroned", true },
        { "ghcr.io/ublue-os/aurora:stable", &listed, "foreign", false },
    };
    for (const Case& c : cases) {
        const QString origin = ImageOrigin::classify(QString::fromUtf8(c.image), *c.expected);
        if (origin != QLatin1String(c.origin) || ImageOrigin::allowsUpdate(origin) != c.update) {
            qCritical() << "Image origin policy mismatch for" << c.image << "->" << origin;
            return 1;
        }
    }

    // Lote 9.2 (H4-001): storage preflight distinguishes valid+ready,
    // insufficient, and unreadable volumes (no QStorageInfo::exists()).
    using Enthroned::storagePreflightCheck;
    using Enthroned::StoragePreflight;
    struct StorageCase { bool valid; bool ready; qint64 bytes; qint64 min; StoragePreflight expected; };
    const StorageCase storageCases[] = {
        { true,  true,  3LL * 1024 * 1024 * 1024, 2LL * 1024 * 1024 * 1024, StoragePreflight::Ok },
        { true,  true,  1LL * 1024 * 1024 * 1024, 2LL * 1024 * 1024 * 1024, StoragePreflight::Insufficient },
        { true,  true,  2LL * 1024 * 1024 * 1024 - 1, 2LL * 1024 * 1024 * 1024, StoragePreflight::Insufficient },
        { true,  true,  -1,  2LL * 1024 * 1024 * 1024, StoragePreflight::Unreadable },
        { true,  false, 100, 2LL * 1024 * 1024 * 1024, StoragePreflight::Unreadable },
        { false, true,  100, 2LL * 1024 * 1024 * 1024, StoragePreflight::Unreadable },
        { false, false, -1,  2LL * 1024 * 1024 * 1024, StoragePreflight::Unreadable },
    };
    for (const StorageCase& c : storageCases) {
        if (storagePreflightCheck(c.valid, c.ready, c.bytes, c.min) != c.expected) {
            qCritical() << "Storage preflight mismatch for"
                        << "valid=" << c.valid << "ready=" << c.ready
                        << "bytes=" << c.bytes;
            return 1;
        }
    }

    // Lote 9.2 (H4-007): systemd outcomes. Only Completed may read as
    // success; 77 keeps its special meaning in the CHECK flow only (the
    // engine maps ExitedWithError+77 there, not here).
    using Enthroned::classifyUnitOutcome;
    using Enthroned::UnitOutcome;
    auto unitState = [](const char* active, const char* result, int code, int status,
                        bool condition) {
        QVariantMap m;
        m.insert(QStringLiteral("activeState"), QString::fromUtf8(active));
        m.insert(QStringLiteral("result"), QString::fromUtf8(result));
        m.insert(QStringLiteral("execMainCode"), code);
        m.insert(QStringLiteral("execMainStatus"), status);
        m.insert(QStringLiteral("conditionResult"), condition);
        return m;
    };
    struct OutcomeCase { QVariantMap state; UnitOutcome expected; };
    const OutcomeCase outcomeCases[] = {
        { unitState("inactive", "success", 1, 0, true), UnitOutcome::Completed },
        { unitState("inactive", "success", 1, 77, true), UnitOutcome::ExitedWithError },
        { unitState("inactive", "success", 1, 1, true), UnitOutcome::ExitedWithError },
        { unitState("failed", "exit-code", 1, 1, true), UnitOutcome::ExitedWithError },
        { unitState("failed", "signal", 2, 15, true), UnitOutcome::Killed },
        { unitState("failed", "core-dump", 3, 11, true), UnitOutcome::Killed },
        { unitState("failed", "timeout", 2, 9, true), UnitOutcome::TimedOut },
        { unitState("inactive", "success", 1, 0, false), UnitOutcome::Skipped },
        { unitState("failed", "exit-code", 1, 203, true), UnitOutcome::NotExecuted },
        { unitState("inactive", "success", 0, 0, true), UnitOutcome::NotExecuted },
        { unitState("failed", "dependency", 0, 0, true), UnitOutcome::NotExecuted },
        { unitState("failed", "start-limit", 0, 0, true), UnitOutcome::NotExecuted },
    };
    for (const OutcomeCase& c : outcomeCases) {
        if (classifyUnitOutcome(c.state) != c.expected) {
            qCritical() << "Unit outcome mismatch for"
                        << c.state.value(QStringLiteral("result")).toString()
                        << c.state.value(QStringLiteral("execMainCode")).toInt()
                        << c.state.value(QStringLiteral("execMainStatus")).toInt()
                        << c.state.value(QStringLiteral("conditionResult")).toBool();
            return 1;
        }
    }
    return 0;
}
