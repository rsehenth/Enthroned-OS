/*
 * Enthroned Settings - system identity provider (F3.2).
 * Reads the Enthroned identity files shipped by F1 and basic host facts.
 * Read-only: never writes anywhere. Missing data is reported as
 * "Indisponivel" by the UI (empty QString), never invented.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

namespace Enthroned {

class SystemIdentityProvider : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString productName READ productName CONSTANT)
    Q_PROPERTY(QString productVersion READ productVersion CONSTANT)
    Q_PROPERTY(QString channel READ channel CONSTANT)
    Q_PROPERTY(QString channelDescription READ channelDescription CONSTANT)
    Q_PROPERTY(bool channelProductionReady READ channelProductionReady CONSTANT)
    Q_PROPERTY(QString phase READ phase CONSTANT)
    Q_PROPERTY(QString baseImage READ baseImage CONSTANT)
    Q_PROPERTY(QString osPrettyName READ osPrettyName CONSTANT)
    Q_PROPERTY(QString kernel READ kernel CONSTANT)
    Q_PROPERTY(QString architecture READ architecture CONSTANT)
    Q_PROPERTY(QString hostName READ hostName CONSTANT)
    Q_PROPERTY(bool identityPresent READ identityPresent CONSTANT)
    Q_PROPERTY(QStringList expectedImageReferences READ expectedImageReferences CONSTANT)

public:
    explicit SystemIdentityProvider(QObject* parent = nullptr);

    QString productName() const { return m_productName; }
    QString productVersion() const { return m_productVersion; }
    QString channel() const { return m_channel; }
    QString channelDescription() const { return m_channelDescription; }
    bool channelProductionReady() const { return m_channelProductionReady; }
    QString phase() const { return m_phase; }
    QString baseImage() const { return m_baseImage; }
    QString osPrettyName() const { return m_osPrettyName; }
    QString kernel() const;
    QString architecture() const;
    QString hostName() const;
    bool identityPresent() const { return m_identityPresent; }
    // Image repositories that identify the Enthroned channel (release-channel.json).
    QStringList expectedImageReferences() const { return m_expectedImages; }

private:
    static QString readFileTrimmed(const QString& path);
    static QString osReleaseField(const QString& key);

    QString m_productName;
    QString m_productVersion;
    QString m_channel;
    QString m_channelDescription;
    bool m_channelProductionReady = false;
    QString m_phase;
    QString m_baseImage;
    QString m_osPrettyName;
    bool m_identityPresent = false;
    QStringList m_expectedImages;
};

} // namespace Enthroned
