/*
 * Enthroned Settings - device information provider (Lote 4).
 * Real, local, read-only hardware facts: CPU and memory from /proc, GPU from
 * lspci (fallback: /sys/class/drm), mounted block-device volumes from
 * QStorageInfo, SELinux mode from /sys/fs/selinux. Everything is collected on
 * a worker thread and delivered by a queued call, so the UI thread never waits
 * on files or processes. Missing data stays empty ("Indisponível" in the UI);
 * nothing is invented.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

class QThread;

namespace Enthroned {

class DeviceInfoProvider : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(QString deviceName READ deviceName CONSTANT)
    Q_PROPERTY(QString userName READ userName CONSTANT)
    Q_PROPERTY(QString timeZone READ timeZone CONSTANT)
    Q_PROPERTY(QString localeName READ localeName CONSTANT)
    Q_PROPERTY(QString deviceModel READ deviceModel NOTIFY changed)
    Q_PROPERTY(QString cpu READ cpu NOTIFY changed)
    Q_PROPERTY(QString memory READ memory NOTIFY changed)
    Q_PROPERTY(QStringList gpus READ gpus NOTIFY changed)
    // [{ mount, total, free, usedPercent }]
    Q_PROPERTY(QVariantList storage READ storage NOTIFY changed)
    // enforcing | permissive | unavailable
    Q_PROPERTY(QString selinux READ selinux NOTIFY changed)
    Q_PROPERTY(bool usrReadOnly READ usrReadOnly NOTIFY changed)

public:
    explicit DeviceInfoProvider(QObject* parent = nullptr);
    ~DeviceInfoProvider() override;

    bool ready() const { return m_ready; }
    QString deviceName() const;
    QString userName() const;
    QString timeZone() const;
    QString localeName() const;
    QString deviceModel() const { return m_model; }
    QString cpu() const { return m_cpu; }
    QString memory() const { return m_memory; }
    QStringList gpus() const { return m_gpus; }
    QVariantList storage() const { return m_storage; }
    QString selinux() const { return m_selinux; }
    bool usrReadOnly() const { return m_usrReadOnly; }

    // Starts one background collection (no-op while one is running).
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void copyToClipboard(const QString& text) const;

Q_SIGNALS:
    void changed();

private:
    QThread* m_worker = nullptr;
    bool m_ready = false;
    QString m_model;
    QString m_cpu;
    QString m_memory;
    QStringList m_gpus;
    QVariantList m_storage;
    QString m_selinux = QStringLiteral("unavailable");
    bool m_usrReadOnly = false;
};

} // namespace Enthroned
