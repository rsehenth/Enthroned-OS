/*
 * Enthroned Settings - system identity provider implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "systemidentityprovider.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSysInfo>

namespace Enthroned {

namespace {
const QLatin1String kIdentityPath("/usr/share/enthroned-os/identity.json");
const QLatin1String kChannelPath("/usr/share/enthroned-os/release-channel.json");
const QLatin1String kOsReleasePath("/etc/os-release");
} // namespace

QString SystemIdentityProvider::readFileTrimmed(const QString& path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }
    return QString::fromUtf8(file.readAll()).trimmed();
}

QString SystemIdentityProvider::osReleaseField(const QString& key)
{
    QFile file(kOsReleasePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }
    const QStringList lines = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
    for (const QString& line : lines) {
        if (line.startsWith(key + QLatin1Char('='))) {
            QString value = line.mid(key.size() + 1).trimmed();
            value.remove(QLatin1Char('"'));
            return value;
        }
    }
    return QString();
}

SystemIdentityProvider::SystemIdentityProvider(QObject* parent)
    : QObject(parent)
{
    const QByteArray identityRaw = readFileTrimmed(kIdentityPath).toUtf8();
    if (!identityRaw.isEmpty()) {
        const QJsonDocument doc = QJsonDocument::fromJson(identityRaw);
        if (doc.isObject()) {
            const QJsonObject obj = doc.object();
            m_productName = obj.value(QStringLiteral("product_name")).toString();
            m_productVersion = obj.value(QStringLiteral("version")).toString();
            m_channel = obj.value(QStringLiteral("channel")).toString();
            m_phase = obj.value(QStringLiteral("phase")).toString();
            m_baseImage = obj.value(QStringLiteral("upstream"))
                              .toObject()
                              .value(QStringLiteral("image_reference"))
                              .toString();
            m_identityPresent = !m_productName.isEmpty();
        }
    }

    const QByteArray channelRaw = readFileTrimmed(kChannelPath).toUtf8();
    if (!channelRaw.isEmpty()) {
        const QJsonDocument doc = QJsonDocument::fromJson(channelRaw);
        if (doc.isObject()) {
            const QJsonObject obj = doc.object();
            if (m_channel.isEmpty()) {
                m_channel = obj.value(QStringLiteral("channel")).toString();
            }
            m_channelDescription = obj.value(QStringLiteral("description")).toString();
            m_channelProductionReady = obj.value(QStringLiteral("production_ready")).toBool();
            const QJsonArray expected = obj.value(QStringLiteral("expected_image_references")).toArray();
            for (const QJsonValue& value : expected) {
                if (value.isString() && !value.toString().trimmed().isEmpty()) {
                    m_expectedImages.append(value.toString().trimmed());
                }
            }
        }
    }

    m_osPrettyName = osReleaseField(QStringLiteral("PRETTY_NAME"));
}

QString SystemIdentityProvider::kernel() const
{
    return QSysInfo::kernelType() + QLatin1Char(' ') + QSysInfo::kernelVersion();
}

QString SystemIdentityProvider::architecture() const
{
    return QSysInfo::currentCpuArchitecture();
}

QString SystemIdentityProvider::hostName() const
{
    return QSysInfo::machineHostName();
}

} // namespace Enthroned
