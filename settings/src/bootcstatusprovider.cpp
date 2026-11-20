/*
 * Enthroned Settings - bootc status provider implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "bootcstatusprovider.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QProcess>
#include <QStandardPaths>

#include <KLocalizedString>

#ifdef Q_OS_UNIX
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace Enthroned {

namespace {
// Lote 9.5.1: when the test override is set it is returned verbatim (absolute
// fake path) with NO fallback to /usr/bin/bootc or PATH; production keeps the
// original safe resolution.
QString findBootc(const QString& binaryOverride)
{
    if (!binaryOverride.isEmpty()) {
        return binaryOverride;
    }
    if (QFileInfo::exists(QStringLiteral("/usr/bin/bootc"))) {
        return QStringLiteral("/usr/bin/bootc");
    }
    return QStandardPaths::findExecutable(QStringLiteral("bootc"));
}

// The cache holds one bootc status capture (a few KiB); anything larger is
// not a legitimate capture (Lote 10.2 reader-side size cap).
constexpr qint64 kMaxCacheBytes = 1024 * 1024;

struct DeploymentData
{
    bool present = false;
    QString imageRef;
    QString version;
    QString timestamp;
};

// Validates one bootc deployment entry (staged/rollback/booted): absent or
// null means "no deployment"; an object must carry well-typed optional fields
// ({image: {image: {image}}, version, timestamp} - all strings or absent);
// any other type, or a wrongly-typed field, is a malformed response. An entry
// may legitimately exist without image metadata (empty imageRef).
bool readDeployment(const QJsonObject& status, const QString& key, DeploymentData* out)
{
    const QJsonValue value = status.value(key);
    if (value.isUndefined() || value.isNull()) {
        return true; // legitimate absence
    }
    if (!value.isObject()) {
        return false; // boolean/number/string/array where a deployment belongs
    }
    const QJsonObject entry = value.toObject();
    if (entry.isEmpty()) {
        return true; // explicit empty entry carries no deployment
    }
    const QJsonValue imageValue = entry.value(QStringLiteral("image"));
    if (imageValue.isObject()) {
        const QJsonObject image = imageValue.toObject();
        const QJsonValue refValue = image.value(QStringLiteral("image"));
        if (refValue.isObject()) {
            const QJsonValue ref = refValue.toObject().value(QStringLiteral("image"));
            if (ref.isString()) {
                out->imageRef = ref.toString();
            } else if (!ref.isUndefined() && !ref.isNull()) {
                return false;
            }
        } else if (!refValue.isUndefined() && !refValue.isNull()) {
            return false;
        }
        const QJsonValue version = image.value(QStringLiteral("version"));
        if (version.isString()) {
            out->version = version.toString();
        } else if (!version.isUndefined() && !version.isNull()) {
            return false;
        }
        const QJsonValue timestamp = image.value(QStringLiteral("timestamp"));
        if (timestamp.isString()) {
            out->timestamp = timestamp.toString();
        } else if (!timestamp.isUndefined() && !timestamp.isNull()) {
            return false;
        }
    } else if (!imageValue.isUndefined() && !imageValue.isNull()) {
        return false;
    }
    out->present = true;
    return true;
}
} // namespace

BootcStatusProvider::BootcStatusProvider(const QString& binaryOverride,
                                         QObject* parent,
                                         const QString& statusFileOverride)
    : QObject(parent)
    , m_binaryOverride(binaryOverride)
    , m_statusFileOverride(statusFileOverride)
{
    m_bootcPresent = !findBootc(m_binaryOverride).isEmpty();
}

QString BootcStatusProvider::cacheFilePath() const
{
    return m_statusFileOverride.isEmpty()
        ? QStringLiteral("/run/enthroned/bootc-status.json")
        : m_statusFileOverride;
}

void BootcStatusProvider::refresh()
{
    // Test seam (Lote 9.5.1): an explicit binary override keeps the legacy
    // direct-exec path (a fake binary; never /usr/bin/bootc or PATH).
    if (!m_binaryOverride.isEmpty()) {
        refreshFromBinary(findBootc(m_binaryOverride));
        return;
    }
    // Production (Lote 10, P1-2): `bootc status` demands root (H4 evidence),
    // so the status comes from the root-owned cache of
    // enthroned-bootc-status.service (fixed read-only helper, 0644 root:root).
    // bootc is never executed unprivileged, which could only produce the
    // misleading "must be executed as root" hint.
    ensureCacheWatch();
    QByteArray output;
    const QString hint = readValidatedCache(&output);
    if (!hint.isEmpty()) {
        markUnavailable(hint);
        Q_EMIT statusResult(false, m_stagedPresent);
        return;
    }
    applyJson(output);
}

QString BootcStatusProvider::readValidatedCache(QByteArray* output)
{
    const QString path = cacheFilePath();
#ifdef Q_OS_UNIX
    // O_NOFOLLOW: never read through a symlink planted at the cache path.
    // A FIFO must not block open() before fstat() can reject it.
    const int fd = ::open(QFile::encodeName(path).constData(),
                          O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) {
        return errno == ELOOP
            ? i18n("bootc status returned invalid data")
            : i18n("The bootc status cache is not available in this boot.");
    }
    struct stat st;
    if (::fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)
        || (st.st_mode & (S_IWGRP | S_IWOTH)) != 0
        || static_cast<qint64>(st.st_size) > kMaxCacheBytes
        // Provenance (production path only): the cache must be root-owned,
        // like everything the helper publishes. The test seam runs
        // unprivileged and skips exactly this check.
        || (m_statusFileOverride.isEmpty() && st.st_uid != 0)) {
        ::close(fd);
        return i18n("bootc status returned invalid data");
    }
    const qint64 toRead = qMin<qint64>(static_cast<qint64>(st.st_size), kMaxCacheBytes) + 1;
    output->resize(static_cast<int>(toRead));
    const ssize_t n = ::read(fd, output->data(), static_cast<size_t>(toRead));
    ::close(fd);
    if (n < 0 || static_cast<qint64>(n) > kMaxCacheBytes) {
        return i18n("bootc status returned invalid data");
    }
    output->truncate(static_cast<int>(n));
    return QString();
#else
    const QFileInfo info(path);
    if (!info.exists()) {
        return i18n("The bootc status cache is not available in this boot.");
    }
    if (info.isSymLink() || !info.isFile() || info.permission(QFile::WriteGroup)
        || info.permission(QFile::WriteOther) || info.size() > kMaxCacheBytes) {
        return i18n("bootc status returned invalid data");
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return i18n("The bootc status cache is not available in this boot.");
    }
    *output = file.read(kMaxCacheBytes + 1);
    if (output->size() > kMaxCacheBytes) {
        return i18n("bootc status returned invalid data");
    }
    return QString();
#endif
}

void BootcStatusProvider::ensureCacheWatch()
{
    if (!m_cacheWatcher) {
        m_cacheWatcher = new QFileSystemWatcher(this);
        connect(m_cacheWatcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString&) {
            refresh();
        });
    }
    QDir cacheDir = QFileInfo(cacheFilePath()).dir();
    if (!cacheDir.exists()) {
        cacheDir.cdUp(); // watch the parent until the managed directory appears
    }
    const QString path = cacheDir.absolutePath();
    const QStringList previous = m_cacheWatcher->directories();
    if (!previous.contains(path) && !m_cacheWatcher->addPath(path)) {
        return;
    }
    for (const QString& watched : previous) {
        if (watched != path) {
            m_cacheWatcher->removePath(watched);
        }
    }
}

void BootcStatusProvider::refreshFromBinary(const QString& binary)
{
    if (m_process) {
        return; // one query at a time
    }
    if (binary.isEmpty()) {
        markUnavailable(i18n("bootc not found on this system"));
        Q_EMIT statusResult(false, m_stagedPresent);
        return;
    }

    m_process = new QProcess(this);
    m_process->setProgram(binary);
    m_process->setArguments({ QStringLiteral("status"), QStringLiteral("--format=json") });

    connect(m_process, &QProcess::finished, this, [this, process = m_process](int exitCode, QProcess::ExitStatus exitStatus) {
        if (m_process != process) return;
        const QByteArray output = m_process->readAllStandardOutput();
        const QByteArray error = m_process->readAllStandardError();
        m_process->deleteLater();
        m_process = nullptr;

        if (exitCode != 0 || exitStatus != QProcess::NormalExit) {
            markUnavailable(QString::fromUtf8(error).trimmed().left(160));
            Q_EMIT statusResult(false, m_stagedPresent);
            return;
        }
        applyJson(output);
    });
    connect(m_process, &QProcess::errorOccurred, this, [this, process = m_process](QProcess::ProcessError) {
        if (m_process != process) return;
        markUnavailable(i18n("Failed to run bootc"));
        m_process->deleteLater();
        m_process = nullptr;
        Q_EMIT statusResult(false, m_stagedPresent);
    });

    m_process->start();
}

void BootcStatusProvider::applyJson(const QByteArray& output)
{
    const QString invalidHint = i18n("bootc status returned invalid data");
    const QJsonDocument doc = QJsonDocument::fromJson(output);
    if (!doc.isObject()) {
        markUnavailable(invalidHint);
        Q_EMIT statusResult(false, m_stagedPresent);
        return;
    }

    const QJsonValue statusValue = doc.object().value(QStringLiteral("status"));
    if (!statusValue.isObject()) {
        markUnavailable(invalidHint);
        Q_EMIT statusResult(false, m_stagedPresent);
        return;
    }
    const QJsonObject status = statusValue.toObject();

    DeploymentData booted;
    if (!readDeployment(status, QStringLiteral("booted"), &booted)) {
        markUnavailable(invalidHint);
        Q_EMIT statusResult(false, m_stagedPresent);
        return;
    }
    if (!booted.present) {
        // Legitimate absence of a booted deployment (distinct from malformed
        // data, which gets the invalid-data hint above).
        markUnavailable(i18n("bootc status has no deployment data"));
        Q_EMIT statusResult(false, m_stagedPresent);
        return;
    }
    if (booted.imageRef.isEmpty()) {
        // An incomplete booted entry is not a valid status (Lote 10.2):
        // the Update Center cannot display it and must not treat it as fresh.
        markUnavailable(invalidHint);
        Q_EMIT statusResult(false, m_stagedPresent);
        return;
    }

    DeploymentData staged;
    DeploymentData rollback;
    if (!readDeployment(status, QStringLiteral("staged"), &staged)
        || !readDeployment(status, QStringLiteral("rollback"), &rollback)) {
        markUnavailable(invalidHint);
        Q_EMIT statusResult(false, m_stagedPresent);
        return;
    }

    m_bootedImage = booted.imageRef;
    // Lote 11B (H5 P2-4b): optional transport of the booted image reference.
    // Lenient by design: a purely presentational field must never invalidate
    // an otherwise well-formed capture, so only a well-typed string is kept.
    const QJsonValue transportValue = status.value(QStringLiteral("booted"))
                                          .toObject().value(QStringLiteral("image"))
                                          .toObject().value(QStringLiteral("image"))
                                          .toObject().value(QStringLiteral("transport"));
    m_bootedTransport = transportValue.isString() ? transportValue.toString() : QString();
    m_bootedVersion = booted.version;
    m_bootedTimestamp = booted.timestamp;
    m_stagedPresent = staged.present;
    m_stagedImageRef = staged.imageRef;
    m_stagedVersion = staged.version;
    m_stagedTimestamp = staged.timestamp;
    m_rollbackPresent = rollback.present;
    m_rollbackVersion = rollback.version;
    // Older captures still describe the booted image but cannot confirm an update.
    m_captureUsec = doc.object().value(QStringLiteral("enthronedCaptureUsec"))
                        .toString().toULongLong();

    m_available = true;
    m_errorHint.clear();
    Q_EMIT availableChanged();
    Q_EMIT statusResult(true, m_stagedPresent);
}

void BootcStatusProvider::markUnavailable(const QString& hint)
{
    // Lote 10.2: clear every derived field so a previously read staged or
    // rollback deployment can never survive into an unavailability report
    // (and from there into the UpdateEngine context). availableChanged is
    // only emitted on a real transition: while the cache is still missing
    // (e.g. the watcher re-checks it) repeated failures stay silent.
    const bool wasAvailable = m_available;
    m_available = false;
    m_errorHint = hint;
    m_bootedImage.clear();
    m_bootedTransport.clear();
    m_bootedVersion.clear();
    m_bootedTimestamp.clear();
    m_stagedPresent = false;
    m_stagedImageRef.clear();
    m_stagedVersion.clear();
    m_stagedTimestamp.clear();
    m_rollbackPresent = false;
    m_rollbackVersion.clear();
    m_captureUsec = 0;
    if (wasAvailable) {
        Q_EMIT availableChanged();
    }
}

} // namespace Enthroned
