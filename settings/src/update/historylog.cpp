/*
 * Enthroned Settings - local history log implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "historylog.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

namespace Enthroned {

HistoryLog::HistoryLog(QObject* parent)
    : QObject(parent)
{
}

QString HistoryLog::logPath() const
{
    QString stateHome = qEnvironmentVariable("XDG_STATE_HOME");
    if (stateHome.isEmpty()) {
        stateHome = QDir::homePath() + QStringLiteral("/.local/state");
    }
    return stateHome + QStringLiteral("/enthroned-os/settings-history.jsonl");
}

void HistoryLog::append(const QString& source, const QString& kind,
                        const QString& title, const QString& detail)
{
    const QString path = logPath();
    QDir().mkpath(QFileInfo(path).absolutePath());

    QJsonObject entry;
    entry.insert(QStringLiteral("ts"), QDateTime::currentMSecsSinceEpoch());
    entry.insert(QStringLiteral("source"), source);
    entry.insert(QStringLiteral("kind"), kind);
    entry.insert(QStringLiteral("title"), title);
    if (!detail.isEmpty()) {
        entry.insert(QStringLiteral("detail"), detail);
    }
    const QByteArray line = QJsonDocument(entry).toJson(QJsonDocument::Compact);

    QFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        file.write(line);
        file.write("\n");
    }
}

QVariantList HistoryLog::readRecent(int maxEntries) const
{
    QVariantList entries;
    QFile file(logPath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return entries;
    }
    const QStringList lines = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
    for (const QString& line : lines) {
        const QString trimmed = line.trimmed();
        if (trimmed.isEmpty()) {
            continue;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(trimmed.toUtf8());
        if (doc.isObject()) {
            entries.append(doc.object().toVariantMap());
        }
    }
    while (entries.size() > maxEntries) {
        entries.removeFirst();
    }
    return entries;
}

} // namespace Enthroned
