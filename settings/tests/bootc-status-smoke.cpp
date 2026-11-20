// Lote 10 (P1-2): the Update Center must learn the REAL version/origin from
// the root-owned bootc status cache (enthroned-bootc-status.service ->
// /run/enthroned/bootc-status.json) instead of executing `bootc status`
// unprivileged (H4: the CLI demands root and the answer was always
// "bootc indisponível"). Scenarios: valid cache, missing cache, invalid JSON,
// JSON without deployments, empty cache, malformed value types (Lote 10.2:
// booted null/boolean/empty/incomplete, staged with wrong types), oversized
// cache, symlinked cache, writable-by-others cache, stale-state clearing
// after a valid staged read, the late-publication watcher, binary-override
// precedence (the Lote 9.5.1 test seam keeps working) and cache re-read.
// No real bootc is ever executed.
#include "../src/bootcstatusprovider.h"

#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QIODevice>
#include <QTemporaryDir>
#include <QTimer>
#include <cstdio>
#include <cstdlib>
#include <functional>
#ifdef Q_OS_UNIX
#include <sys/stat.h>
#endif

int g_passed = 0;
int g_failed = 0;

// fprintf, not qDebug: the Release build may silence Qt logging categories
// depending on the environment; the harness output must always be visible.
void check(bool condition, const char* name, const char* detail = "")
{
    if (condition) {
        ++g_passed;
        fprintf(stderr, "PASS: %s\n", name);
    } else {
        ++g_failed;
        fprintf(stderr, "FAIL: %s%s%s\n", name, *detail ? " — " : "", detail);
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

// Mirrors the REAL bootc 1.x status schema (Gate A G-A-09): booted.image =
// { image: ImageReference { image, transport }, version, timestamp };
// staged/rollback may be empty objects or deployments.
QString captureStatus(bool withStaged, bool withRollback)
{
    QString json = QStringLiteral(
        "{\"status\":{"
        "\"booted\":{\"image\":{\"image\":{\"image\":\"registry.example.org/enthroned/enthroned-os:1.0\","
        "\"transport\":\"registry\"},\"version\":\"1.0\",\"timestamp\":\"2026-11-18T12:00:00Z\"}}");
    if (withStaged) {
        json += QStringLiteral(
            ",\"staged\":{\"image\":{\"image\":{\"image\":\"registry.example.org/enthroned/enthroned-os:2.0\","
            "\"transport\":\"registry\"},\"version\":\"2.0\",\"timestamp\":\"2026-11-18T13:00:00Z\"}}");
    } else {
        json += QStringLiteral(",\"staged\":{}");
    }
    if (withRollback) {
        json += QStringLiteral(
            ",\"rollback\":{\"image\":{\"image\":{\"image\":\"registry.example.org/enthroned/enthroned-os:0.9\","
            "\"transport\":\"registry\"},\"version\":\"0.9\",\"timestamp\":\"2026-11-17T12:00:00Z\"}}");
    } else {
        json += QStringLiteral(",\"rollback\":{}");
    }
    json += QStringLiteral("}}");
    return json;
}

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir work;
    if (!work.isValid()) failFast("temporary work dir unavailable");

    const QString cachePath = work.filePath(QStringLiteral("bootc-status.json"));
    auto writeCache = [&cachePath](const QString& content) {
        // Remove first: a previous case may have left a symlink at the path
        // (QFile would otherwise follow it and keep the link in place).
        QFile::remove(cachePath);
        QFile file(cachePath);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            fprintf(stderr, "FATAL: cannot write the fake cache at %s\n", qPrintable(cachePath));
            exit(2);
        }
        file.write(content.toUtf8());
        file.close();
        if (!file.setPermissions(QFile::ReadOwner | QFile::ReadGroup | QFile::ReadOther)) {
            failFast("cache must be world-readable like the real /run file");
        }
    };

    // 1. Valid cache: the real version/origin become visible unprivileged.
    writeCache(captureStatus(false, false));
    Enthroned::BootcStatusProvider valid(QString(), nullptr, cachePath);
    int resultCalls = 0;
    bool lastOk = true;
    bool lastStaged = true;
    QObject::connect(&valid, &Enthroned::BootcStatusProvider::statusResult,
        [&](bool ok, bool staged) { ++resultCalls; lastOk = ok; lastStaged = staged; });
    valid.refresh();
    check(valid.available(), "valid cache: available");
    check(valid.bootedVersion() == QStringLiteral("1.0"), "valid cache: booted version read");
    check(valid.bootedImage() == QStringLiteral("registry.example.org/enthroned/enthroned-os:1.0"),
          "valid cache: booted image (origin) read");
    check(valid.bootedTimestamp() == QStringLiteral("2026-11-18T12:00:00Z"),
          "valid cache: booted timestamp read");
    // Lote 11B (H5 P2-4b): the transport travels with the reference (H5 asked
    // for image/transport on the origin row).
    check(valid.bootedTransport() == QStringLiteral("registry"),
          "valid cache: booted transport read");
    check(!valid.stagedPresent() && !valid.restartRequired(), "valid cache: no staged deployment");
    check(!valid.rollbackPresent(), "valid cache: no rollback deployment");
    check(resultCalls == 1 && lastOk && !lastStaged, "valid cache: statusResult(true,false) emitted");

    // 1b. Lote 11B: a capture WITHOUT a transport field stays valid (the
    // transport is purely presentational and must never invalidate a capture).
    writeCache(QStringLiteral(
        "{\"status\":{\"booted\":{\"image\":{\"image\":{\"image\":\"localhost/enthroned-os:h5\"},"
        "\"version\":\"0.1.0-dev\",\"timestamp\":\"2026-11-19T00:20:45Z\"}},\"staged\":{},\"rollback\":{}}}"));
    Enthroned::BootcStatusProvider noTransport(QString(), nullptr, cachePath);
    noTransport.refresh();
    check(noTransport.available(), "no transport: capture still valid");
    check(noTransport.bootedTransport().isEmpty(), "no transport: field is empty");
    check(noTransport.bootedImage() == QStringLiteral("localhost/enthroned-os:h5"),
          "no transport: image reference still read");

    // 2. Staged + rollback deployments are exposed for restart/rollback states.
    writeCache(captureStatus(true, true));
    Enthroned::BootcStatusProvider withDeployments(QString(), nullptr, cachePath);
    withDeployments.refresh();
    check(withDeployments.available(), "staged cache: available");
    check(withDeployments.stagedPresent() && withDeployments.restartRequired(),
          "staged cache: restart required");
    check(withDeployments.stagedVersion() == QStringLiteral("2.0"), "staged cache: staged version read");
    check(withDeployments.stagedImageRef() == QStringLiteral("registry.example.org/enthroned/enthroned-os:2.0"),
          "staged cache: staged image ref read (origin gate)");
    check(withDeployments.rollbackPresent() && withDeployments.rollbackVersion() == QStringLiteral("0.9"),
          "staged cache: rollback version read");

    // 2b. Lote 10.2: after a valid staged read, a vanished cache must clear
    // every derived field and report (false,false) - no stale staged/rollback
    // signal may reach the UpdateEngine.
    QFile::remove(cachePath);
    int staleCalls = 0;
    bool staleOk = true;
    bool staleStaged = true;
    QObject::connect(&withDeployments, &Enthroned::BootcStatusProvider::statusResult,
        [&](bool ok, bool staged) { ++staleCalls; staleOk = ok; staleStaged = staged; });
    withDeployments.refresh();
    check(!withDeployments.available(), "stale clearing: unavailable after the cache vanished");
    check(!withDeployments.stagedPresent() && !withDeployments.restartRequired(),
          "stale clearing: staged state cleared");
    check(withDeployments.stagedVersion().isEmpty() && withDeployments.stagedImageRef().isEmpty(),
          "stale clearing: staged fields cleared");
    check(!withDeployments.rollbackPresent() && withDeployments.rollbackVersion().isEmpty(),
          "stale clearing: rollback state cleared");
    check(staleCalls == 1 && !staleOk && !staleStaged,
          "stale clearing: statusResult(false,false) emitted");

    // 3. Missing cache: honest unavailability, no crash, no bootc execution.
    Enthroned::BootcStatusProvider missing(QString(), nullptr, cachePath);
    missing.refresh();
    check(!missing.available(), "missing cache: unavailable");
    check(missing.errorHint() == QStringLiteral("The bootc status cache is not available in this boot."),
          "missing cache: cache-specific hint (not a bootc exec error)");

    // 4. Invalid JSON: unavailable without crash.
    writeCache(QStringLiteral("this is not json {{{"));
    Enthroned::BootcStatusProvider invalid(QString(), nullptr, cachePath);
    invalid.refresh();
    check(!invalid.available()
              && invalid.errorHint() == QStringLiteral("bootc status returned invalid data"),
          "invalid JSON: unavailable with invalid-data hint");

    // 5. JSON without deployments: unavailable without crash.
    writeCache(QStringLiteral("{\"status\":{}}"));
    Enthroned::BootcStatusProvider noDeployments(QString(), nullptr, cachePath);
    noDeployments.refresh();
    check(!noDeployments.available()
              && noDeployments.errorHint() == QStringLiteral("bootc status has no deployment data"),
          "no-deployment JSON: unavailable with no-data hint");

    // 6. Empty cache file: unavailable without crash.
    writeCache(QString());
    Enthroned::BootcStatusProvider empty(QString(), nullptr, cachePath);
    empty.refresh();
    check(!empty.available(), "empty cache: unavailable");

    // 6b. Lote 10.2: malformed value types must never read as a valid status.
    struct MalformedCase { const char* name; const char* json; };
    const MalformedCase malformed[] = {
        {"booted null", "{\"status\":{\"booted\":null,\"staged\":{},\"rollback\":{}}}"},
        {"booted boolean", "{\"status\":{\"booted\":true,\"staged\":{},\"rollback\":{}}}"},
        {"booted empty object", "{\"status\":{\"booted\":{},\"staged\":{},\"rollback\":{}}}"},
        {"booted without image", "{\"status\":{\"booted\":{\"version\":\"1.0\"},\"staged\":{},\"rollback\":{}}}"},
        {"booted image ref not a string",
         "{\"status\":{\"booted\":{\"image\":{\"image\":{\"image\":7},\"version\":\"1.0\"}},\"staged\":{},\"rollback\":{}}}"},
        {"booted version not a string",
         "{\"status\":{\"booted\":{\"image\":{\"image\":{\"image\":\"registry.example.org/enthroned/enthroned-os:1.0\"},\"version\":10}},\"staged\":{},\"rollback\":{}}}"},
        {"status not an object", "{\"status\":\"ok\"}"},
        {"staged boolean",
         "{\"status\":{\"booted\":{\"image\":{\"image\":{\"image\":\"registry.example.org/enthroned/enthroned-os:1.0\"}}},\"staged\":true,\"rollback\":{}}}"},
        {"staged version not a string",
         "{\"status\":{\"booted\":{\"image\":{\"image\":{\"image\":\"registry.example.org/enthroned/enthroned-os:1.0\"}}},"
         "\"staged\":{\"image\":{\"image\":{\"image\":\"registry.example.org/enthroned/enthroned-os:2.0\"},\"version\":2}},\"rollback\":{}}}"},
        {"rollback array",
         "{\"status\":{\"booted\":{\"image\":{\"image\":{\"image\":\"registry.example.org/enthroned/enthroned-os:1.0\"}}},\"staged\":{},\"rollback\":[]}}"},
    };
    for (const MalformedCase& testCase : malformed) {
        writeCache(QString::fromUtf8(testCase.json));
        Enthroned::BootcStatusProvider provider(QString(), nullptr, cachePath);
        provider.refresh();
        check(!provider.available(), QStringLiteral("malformed: %1 rejected").arg(testCase.name).toUtf8().constData());
        check(!provider.stagedPresent() && !provider.restartRequired() && !provider.rollbackPresent(),
              QStringLiteral("malformed: %1 leaves no deployment flags").arg(testCase.name).toUtf8().constData());
    }

    // 6c. Lote 10.2: an oversized cache is rejected, never read.
    writeCache(QStringLiteral("{\"status\":{\"booted\":{}}},\"pad\":\"")
               + QString(static_cast<int>(1024 * 1024), QLatin1Char('x')));
    Enthroned::BootcStatusProvider oversized(QString(), nullptr, cachePath);
    oversized.refresh();
    check(!oversized.available()
              && oversized.errorHint() == QStringLiteral("bootc status returned invalid data"),
          "oversized cache: rejected with invalid-data hint");

    // 6d. Lote 10.2: a symlink at the cache path is never followed.
    const QString linkTarget = work.filePath(QStringLiteral("link-target.json"));
    QFile target(linkTarget);
    if (!target.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        failFast("cannot write the symlink target");
    }
    target.write(captureStatus(false, false).toUtf8());
    target.close();
    target.setPermissions(QFile::ReadOwner | QFile::ReadGroup | QFile::ReadOther);
    QFile::remove(cachePath);
    if (!QFile::link(linkTarget, cachePath)) {
        failFast("cannot create the symlink case");
    }
    Enthroned::BootcStatusProvider symlinked(QString(), nullptr, cachePath);
    symlinked.refresh();
    check(!symlinked.available()
              && symlinked.errorHint() == QStringLiteral("bootc status returned invalid data"),
          "symlinked cache: rejected (never followed)");

#ifdef Q_OS_UNIX
    QFile::remove(cachePath);
    if (::mkfifo(QFile::encodeName(cachePath).constData(), 0600) != 0) {
        failFast("cannot create the FIFO case");
    }
    Enthroned::BootcStatusProvider fifo(QString(), nullptr, cachePath);
    fifo.refresh();
    check(!fifo.available(), "FIFO cache: rejected without waiting for a writer");
    QFile::remove(cachePath);
#endif

    // 6e. Lote 10.2: a cache writable by group/other is a provenance violation.
    writeCache(captureStatus(false, false));
    QFile(cachePath).setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup
                                    | QFile::WriteGroup | QFile::ReadOther);
    Enthroned::BootcStatusProvider writable(QString(), nullptr, cachePath);
    writable.refresh();
    check(!writable.available()
              && writable.errorHint() == QStringLiteral("bootc status returned invalid data"),
          "group-writable cache: rejected");

    // 7. Binary override keeps precedence over the cache (Lote 9.5.1 seam):
    // a failing fake bootc must be used INSTEAD of the valid cache file.
    writeCache(captureStatus(false, false));
    const QString fakeBin = work.filePath(QStringLiteral("fakes"));
    QDir().mkpath(fakeBin);
    const QString fakeBootc = fakeBin + QStringLiteral("/bootc");
    const QString bootcMarker = work.filePath(QStringLiteral("bootc-ran"));
    QFile fake(fakeBootc);
    if (!fake.open(QIODevice::WriteOnly | QIODevice::Text)) {
        fprintf(stderr, "FATAL: cannot write the fake bootc at %s\n", qPrintable(fakeBootc));
        exit(2);
    }
    fake.write(QStringLiteral("#!/bin/sh\ntouch \"%1\"\necho 'must not be parsed' >&2\nexit 1\n")
                   .arg(bootcMarker).toUtf8());
    fake.close();
    if (!fake.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner)
        || !QFileInfo(fakeBootc).isExecutable()) {
        failFast("fake bootc is not executable");
    }
    Enthroned::BootcStatusProvider overridden(fakeBootc, nullptr, cachePath);
    overridden.refresh();
    check(waitFor([&]() { return QFile::exists(bootcMarker); }, 5000),
          "binary override: fake bootc executed");
    check(waitFor([&]() { return !overridden.available(); }, 5000),
          "binary override: fake bootc used instead of the cache");

    // 8. Cache re-read: a rewritten cache updates the exposed state.
    Enthroned::BootcStatusProvider reread(QString(), nullptr, cachePath);
    writeCache(captureStatus(false, false));
    reread.refresh();
    check(reread.available() && reread.bootedVersion() == QStringLiteral("1.0"),
          "re-read: first version");
    writeCache(QString(captureStatus(false, false)).replace(QStringLiteral("\"1.0\""),
                                                            QStringLiteral("\"1.5\"")));
    reread.refresh();
    check(reread.available() && reread.bootedVersion() == QStringLiteral("1.5"),
          "re-read: updated version picked up");

    // 9. Lote 10.2: the status published AFTER the first (failed) read is
    // picked up by the watcher without a manual refresh - the UI updates when
    // the cache appears.
    QFile::remove(cachePath);
    Enthroned::BootcStatusProvider late(QString(), nullptr, cachePath);
    late.refresh();
    check(!late.available(), "watcher: unavailable before publication");
    writeCache(captureStatus(false, false));
    check(waitFor([&]() { return late.available(); }, 5000),
          "watcher: cache publication is picked up automatically");
    check(late.bootedVersion() == QStringLiteral("1.0"), "watcher: published version read");

    const QString newDirectory = work.filePath(QStringLiteral("created-later"));
    const QString newCache = newDirectory + QStringLiteral("/bootc-status.json");
    Enthroned::BootcStatusProvider lateDirectory(QString(), nullptr, newCache);
    lateDirectory.refresh();
    check(!lateDirectory.available(), "watcher: unavailable before the directory exists");
    QFile published(newCache);
    if (!QDir().mkpath(newDirectory) || !published.open(QIODevice::WriteOnly)) {
        failFast("cannot write cache under the later directory");
    }
    published.write(captureStatus(false, false).toUtf8());
    published.close();
    check(waitFor([&]() { return lateDirectory.available(); }, 5000),
          "watcher: publication in a newly created directory is picked up");

    // 10. Gate 12.1: the capture clock is trusted only as a well-formed decimal string; every
    // other shape reads as 0 ("older than any unit exit"), so it can never confirm an operation.
    {
        const struct { const char* raw; quint64 expected; const char* label; } cases[] = {
            { "\"200\"", 200, "decimal string" },
            { "\"18446744073709551615\"", 18446744073709551615ULL, "largest valid value" },
            { "200", 0, "JSON number" },
            { "\"-5\"", 0, "negative" },
            { "\"18446744073709551616\"", 0, "overflow" },
            { "\"200abc\"", 0, "trailing garbage" },
            { "\"0x10\"", 0, "hexadecimal" },
            { "\"1e3\"", 0, "exponent" },
            { "\"\"", 0, "empty string" },
            { "null", 0, "null" },
            { "[\"200\"]", 0, "array" },
            { "true", 0, "boolean" },
        };
        for (const auto& c : cases) {
            writeCache(QString(captureStatus(false, false))
                           .replace(0, 1, QStringLiteral("{\"enthronedCaptureUsec\":%1,")
                                              .arg(QLatin1String(c.raw))));
            Enthroned::BootcStatusProvider provider(QString(), nullptr, cachePath);
            provider.refresh();
            const QByteArray label = QStringLiteral("capture clock %1 reads as %2")
                                         .arg(QLatin1String(c.label)).arg(c.expected).toUtf8();
            check(provider.available() && provider.captureUsec() == c.expected, label.constData());
        }
        writeCache(captureStatus(false, false));
        Enthroned::BootcStatusProvider missing(QString(), nullptr, cachePath);
        missing.refresh();
        check(missing.available() && missing.captureUsec() == 0, "capture clock missing reads as 0");
        QFile::remove(cachePath);
        missing.refresh();
        check(!missing.available() && missing.captureUsec() == 0,
              "capture clock cleared when the cache disappears");
    }

    fprintf(stderr, "----------------------------------------\n");
    fprintf(stderr, "bootc-status-smoke: %d passed, %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
