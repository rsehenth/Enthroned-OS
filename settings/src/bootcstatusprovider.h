/*
 * Enthroned Settings - bootc status provider (read-only, F3.5).
 * Lote 10 (P1-2): `bootc status` demands root (H4), so production reads the
 * root-owned cache published by enthroned-bootc-status.service at
 * /run/enthroned/bootc-status.json (written by a fixed, read-only root
 * helper; no upgrade/switch/rollback path exists). The direct
 * `bootc status --format=json` execution remains ONLY as the testability
 * seam used by the existing fake-binary tests.
 *
 * The boot capture is taken shortly after graphical.target. Update units
 * publish another capture after successful system updates. The capture's
 * monotonic start time is separate from deployment version metadata.
 * The provider validates the opened file (regular file,
 * never a symlink, size capped, no group/other write bit, and - on the
 * production path only - owned by root) before trusting it, validates the
 * JSON structure and value types consumed (booted must be a complete
 * deployment; staged/rollback must be absent/null or well-typed objects),
 * and clears every derived field before reporting unavailability so stale
 * staged/rollback data can never reach the UpdateEngine. When the cache is
 * not there yet, or is replaced, a QFileSystemWatcher on the cache directory
 * re-reads it - event driven, no polling loop.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QString>

class QFileSystemWatcher;
class QProcess;

namespace Enthroned {

class BootcStatusProvider : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool bootcPresent READ bootcPresent CONSTANT)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QString errorHint READ errorHint NOTIFY availableChanged)
    Q_PROPERTY(QString bootedImage READ bootedImage NOTIFY availableChanged)
    // Lote 11B (H5 P2-4b): transport of the booted image reference as captured
    // by the bootc-status cache (e.g. "registry", "container-storage"). Empty
    // when the capture carries no transport; purely presentational and never
    // used for trust decisions.
    Q_PROPERTY(QString bootedTransport READ bootedTransport NOTIFY availableChanged)
    Q_PROPERTY(QString bootedVersion READ bootedVersion NOTIFY availableChanged)
    Q_PROPERTY(QString bootedTimestamp READ bootedTimestamp NOTIFY availableChanged)
    Q_PROPERTY(bool stagedPresent READ stagedPresent NOTIFY availableChanged)
    Q_PROPERTY(QString stagedVersion READ stagedVersion NOTIFY availableChanged)
    Q_PROPERTY(QString stagedTimestamp READ stagedTimestamp NOTIFY availableChanged)
    // Lote 8: image reference of the staged deployment, used to verify that
    // the pending update still comes from the Enthroned channel origin.
    Q_PROPERTY(QString stagedImageRef READ stagedImageRef NOTIFY availableChanged)
    Q_PROPERTY(bool rollbackPresent READ rollbackPresent NOTIFY availableChanged)
    Q_PROPERTY(QString rollbackVersion READ rollbackVersion NOTIFY availableChanged)
    Q_PROPERTY(bool restartRequired READ restartRequired NOTIFY availableChanged)

public:
    // binaryOverride is a TESTABILITY seam (Lote 9.5.1): production code never
    // sets it and bootcBinary() resolves the real binary; tests inject the
    // absolute fake path so /usr/bin/bootc and PATH are never consulted and no
    // real bootc invocation can ever happen. When set, it also bypasses the
    // status cache (the direct-exec path is test-only).
    // statusFileOverride is the Lote 10 seam for the cache file (tests inject
    // a temporary file; production always reads /run/enthroned/bootc-status.json).
    // The seam bypasses the root-ownership check (tests run unprivileged) but
    // not the structural ones: symlink rejection, size cap and write-bit
    // checks apply to both paths.
    explicit BootcStatusProvider(const QString& binaryOverride = QString(),
                                 QObject* parent = nullptr,
                                 const QString& statusFileOverride = QString());

    bool bootcPresent() const { return m_bootcPresent; }
    bool available() const { return m_available; }
    QString errorHint() const { return m_errorHint; }
    QString bootedImage() const { return m_bootedImage; }
    QString bootedTransport() const { return m_bootedTransport; }
    QString bootedVersion() const { return m_bootedVersion; }
    QString bootedTimestamp() const { return m_bootedTimestamp; }
    bool stagedPresent() const { return m_stagedPresent; }
    QString stagedVersion() const { return m_stagedVersion; }
    QString stagedTimestamp() const { return m_stagedTimestamp; }
    QString stagedImageRef() const { return m_stagedImageRef; }
    bool rollbackPresent() const { return m_rollbackPresent; }
    QString rollbackVersion() const { return m_rollbackVersion; }
    bool restartRequired() const { return m_stagedPresent; }
    quint64 captureUsec() const { return m_captureUsec; }

    void refresh();

Q_SIGNALS:
    void availableChanged();
    // ok=false -> status unavailable (emit bootc-status-unavailable upstream)
    void statusResult(bool ok, bool staged);

private:
    void refreshFromBinary(const QString& binary);
    void applyJson(const QByteArray& output);
    void markUnavailable(const QString& hint);
    // Reads and validates the cache file; returns an empty QString on
    // success or the failure hint. strictOwnership enforces the root-owned
    // provenance check (production path only; the test seam skips it).
    QString readValidatedCache(QByteArray* output);
    // Watch the directory because publication atomically replaces the file.
    QString cacheFilePath() const;
    void ensureCacheWatch();

    bool m_bootcPresent = false;
    bool m_available = false;
    QString m_errorHint;
    QString m_bootedImage;
    QString m_bootedTransport;
    QString m_bootedVersion;
    QString m_bootedTimestamp;
    bool m_stagedPresent = false;
    QString m_stagedVersion;
    QString m_stagedTimestamp;
    QString m_stagedImageRef;
    bool m_rollbackPresent = false;
    QString m_rollbackVersion;
    quint64 m_captureUsec = 0;
    QProcess* m_process = nullptr;
    QString m_binaryOverride;
    QString m_statusFileOverride;
    QFileSystemWatcher* m_cacheWatcher = nullptr;
};

} // namespace Enthroned
