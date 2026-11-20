/*
 * Enthroned Settings - device information provider implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "deviceinfoprovider.h"

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QHash>
#include <QLocale>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSysInfo>
#include <QThread>
#include <QTimeZone>
#include <QVariantMap>

#include <algorithm>
#include <utility>

namespace Enthroned {

namespace {

constexpr int kToolTimeoutMs = 3000;

QString readSmall(const QString& path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }
    return QString::fromUtf8(file.read(64 * 1024)).trimmed();
}

// Value of the first "<key> : <value>" line (cpuinfo/meminfo format).
QString firstField(const QString& text, const QString& key)
{
    for (const QString& line : text.split(QLatin1Char('\n'))) {
        if (line.startsWith(key)) {
            const qsizetype colon = line.indexOf(QLatin1Char(':'));
            if (colon >= 0) {
                return line.mid(colon + 1).trimmed();
            }
        }
    }
    return QString();
}

QString cpuName()
{
    const QString info = readSmall(QStringLiteral("/proc/cpuinfo"));
    QString name = firstField(info, QStringLiteral("model name"));
    if (name.isEmpty()) {
        name = firstField(info, QStringLiteral("Model")); // arm64 boards
    }
    if (name.isEmpty()) {
        name = firstField(info, QStringLiteral("Hardware"));
    }
    if (name.isEmpty()) {
        return QString();
    }
    name.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral(" "));
    int threads = 0;
    for (const QString& line : info.split(QLatin1Char('\n'))) {
        if (line.startsWith(QLatin1String("processor"))) {
            ++threads;
        }
    }
    return threads > 0 ? QStringLiteral("%1 (%2 threads)").arg(name).arg(threads) : name;
}

QString memoryTotal()
{
    // "MemTotal:       16314940 kB" -> usable RAM as seen by the kernel.
    const QString value = firstField(readSmall(QStringLiteral("/proc/meminfo")), QStringLiteral("MemTotal"));
    bool ok = false;
    const qint64 kib = value.section(QLatin1Char(' '), 0, 0).toLongLong(&ok);
    if (!ok || kib <= 0) {
        return QString();
    }
    return QLocale().formattedDataSize(kib * 1024, 1, QLocale::DataSizeIecFormat);
}

QStringList gpuFromLspci()
{
    const QString lspci = QStandardPaths::findExecutable(QStringLiteral("lspci"));
    if (lspci.isEmpty()) {
        return {};
    }
    QProcess process;
    process.start(lspci, { QStringLiteral("-mm") });
    if (!process.waitForFinished(kToolTimeoutMs) || process.exitCode() != 0) {
        process.kill();
        return {};
    }
    // 00:02.0 "VGA compatible controller" "Intel Corporation" "UHD Graphics" ...
    static const QRegularExpression field(QStringLiteral("\"([^\"]*)\""));
    QStringList gpus;
    const QStringList lines = QString::fromUtf8(process.readAllStandardOutput()).split(QLatin1Char('\n'));
    for (const QString& line : lines) {
        QStringList parts;
        auto it = field.globalMatch(line);
        while (it.hasNext()) {
            parts.append(it.next().captured(1));
        }
        if (parts.size() < 3) {
            continue;
        }
        const QString cls = parts.at(0);
        if (cls.contains(QLatin1String("VGA")) || cls.contains(QLatin1String("3D controller"))
            || cls.contains(QLatin1String("Display controller"))) {
            gpus.append(parts.at(1) + QLatin1Char(' ') + parts.at(2));
        }
    }
    return gpus;
}

QStringList gpuFromSysfs()
{
    static const QHash<QString, QString> vendors = {
        { QStringLiteral("0x10de"), QStringLiteral("NVIDIA") },
        { QStringLiteral("0x1002"), QStringLiteral("AMD/ATI") },
        { QStringLiteral("0x8086"), QStringLiteral("Intel") },
        { QStringLiteral("0x1af4"), QStringLiteral("Red Hat (virtio)") },
        { QStringLiteral("0x15ad"), QStringLiteral("VMware") },
        { QStringLiteral("0x1234"), QStringLiteral("QEMU/Bochs") },
        { QStringLiteral("0x80ee"), QStringLiteral("VirtualBox") },
        { QStringLiteral("0x1414"), QStringLiteral("Microsoft Hyper-V") },
    };
    QStringList gpus;
    const QStringList cards = QDir(QStringLiteral("/sys/class/drm"))
        .entryList({ QStringLiteral("card[0-9]") }, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString& card : cards) {
        const QString base = QStringLiteral("/sys/class/drm/%1/device/").arg(card);
        const QString vendor = readSmall(base + QStringLiteral("vendor")).toLower();
        const QString device = readSmall(base + QStringLiteral("device")).toLower();
        if (vendor.isEmpty()) {
            continue;
        }
        gpus.append(QStringLiteral("%1 (ID %2)").arg(vendors.value(vendor, vendor), device));
    }
    return gpus;
}

QString dmiModel()
{
    const QString vendor = readSmall(QStringLiteral("/sys/class/dmi/id/sys_vendor"));
    const QString product = readSmall(QStringLiteral("/sys/class/dmi/id/product_name"));
    if (product.isEmpty()) {
        return vendor;
    }
    return vendor.isEmpty() || product.startsWith(vendor) ? product : vendor + QLatin1Char(' ') + product;
}

QVariantList storageVolumes()
{
    // Only real block devices; tmpfs/overlay/composefs and the boot partitions are noise.
    // Bind mounts of one device (/var, /sysroot, /var/home on ostree) collapse to the
    // shortest mount path.
    QSet<QByteArray> seen;
    QVariantList volumes;
    QList<QStorageInfo> candidates = QStorageInfo::mountedVolumes();
    std::sort(candidates.begin(), candidates.end(), [](const QStorageInfo& a, const QStorageInfo& b) {
        return a.rootPath().size() < b.rootPath().size();
    });
    for (const QStorageInfo& info : std::as_const(candidates)) {
        if (!info.isValid() || !info.isReady() || !info.device().startsWith("/dev/")
            || info.rootPath().startsWith(QLatin1String("/boot"))) {
            continue;
        }
        if (seen.contains(info.device())) {
            continue;
        }
        seen.insert(info.device());
        const qint64 total = info.bytesTotal();
        const qint64 free = info.bytesAvailable();
        QVariantMap row;
        row.insert(QStringLiteral("mount"), info.rootPath());
        row.insert(QStringLiteral("total"), QLocale().formattedDataSize(total, 1, QLocale::DataSizeIecFormat));
        row.insert(QStringLiteral("free"), QLocale().formattedDataSize(free, 1, QLocale::DataSizeIecFormat));
        row.insert(QStringLiteral("usedPercent"), total > 0 ? int(100 * (total - free) / total) : 0);
        volumes.append(row);
    }
    return volumes;
}

QString selinuxMode()
{
    const QString enforce = readSmall(QStringLiteral("/sys/fs/selinux/enforce"));
    if (enforce == QLatin1String("1")) {
        return QStringLiteral("enforcing");
    }
    if (enforce == QLatin1String("0")) {
        return QStringLiteral("permissive");
    }
    return QStringLiteral("unavailable");
}

struct Snapshot {
    QString model;
    QString cpu;
    QString memory;
    QStringList gpus;
    QVariantList storage;
    QString selinux;
    bool usrReadOnly = false;
};

Snapshot collect()
{
    Snapshot snap;
    snap.model = dmiModel();
    snap.cpu = cpuName();
    snap.memory = memoryTotal();
    snap.gpus = gpuFromLspci();
    if (snap.gpus.isEmpty()) {
        snap.gpus = gpuFromSysfs();
    }
    snap.storage = storageVolumes();
    snap.selinux = selinuxMode();
    snap.usrReadOnly = QStorageInfo(QStringLiteral("/usr")).isReadOnly();
    return snap;
}

} // namespace

DeviceInfoProvider::DeviceInfoProvider(QObject* parent)
    : QObject(parent)
{
}

DeviceInfoProvider::~DeviceInfoProvider()
{
    if (m_worker) {
        m_worker->wait(kToolTimeoutMs * 2);
    }
}

QString DeviceInfoProvider::deviceName() const
{
    return QSysInfo::machineHostName();
}

QString DeviceInfoProvider::userName() const
{
    const QString user = qEnvironmentVariable("USER");
    return user.isEmpty() ? qEnvironmentVariable("LOGNAME") : user;
}

QString DeviceInfoProvider::timeZone() const
{
    return QString::fromUtf8(QTimeZone::systemTimeZoneId());
}

QString DeviceInfoProvider::localeName() const
{
    return QLocale().name(); // application default = the session locale
}

void DeviceInfoProvider::refresh()
{
    if (m_worker) {
        return;
    }
    m_worker = QThread::create([this]() {
        const Snapshot snap = collect();
        QMetaObject::invokeMethod(this, [this, snap]() {
            m_model = snap.model;
            m_cpu = snap.cpu;
            m_memory = snap.memory;
            m_gpus = snap.gpus;
            m_storage = snap.storage;
            m_selinux = snap.selinux;
            m_usrReadOnly = snap.usrReadOnly;
            m_ready = true;
            Q_EMIT changed();
        }, Qt::QueuedConnection);
    });
    connect(m_worker, &QThread::finished, this, [this]() {
        m_worker->deleteLater();
        m_worker = nullptr;
    });
    m_worker->start();
}

void DeviceInfoProvider::copyToClipboard(const QString& text) const
{
    if (QClipboard* clipboard = QGuiApplication::clipboard()) {
        clipboard->setText(text);
    }
}

} // namespace Enthroned
