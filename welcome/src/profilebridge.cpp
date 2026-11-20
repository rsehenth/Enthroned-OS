/*
 * Enthroned Welcome - appearance profile bridge implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "profilebridge.h"

#include <QProcess>
#include <QStandardPaths>

#include <KLocalizedString>

namespace Enthroned {

ProfileBridge::ProfileBridge(QObject* parent)
    : QObject(parent)
{
    m_toolPresent = !QStandardPaths::findExecutable(QStringLiteral("enthroned-profile")).isEmpty();
}

ProfileBridge::~ProfileBridge()
{
    // Quitting right after "Aplicar perfil" must not kill plasma-apply-lookandfeel
    // half-way (a QProcess child kills its process on destruction): give it time to finish.
    if (m_process && m_process->state() != QProcess::NotRunning) {
        m_process->disconnect(this);
        m_process->waitForFinished(15000);
    }
}

QString ProfileBridge::activeLabel() const
{
    if (m_activeProfile == QLatin1String("org.enthroned.classic")) {
        return QStringLiteral("Enthroned Classic");
    }
    if (m_activeProfile == QLatin1String("org.enthroned.modern")) {
        return QStringLiteral("Enthroned Modern");
    }
    return QString();
}

void ProfileBridge::runTool(const QStringList& arguments, bool mutating)
{
    if (m_busy) {
        return;
    }
    const QString tool = QStandardPaths::findExecutable(QStringLiteral("enthroned-profile"));
    if (tool.isEmpty()) {
        Q_EMIT applyFinished(false, QStringLiteral("enthroned-profile"));
        return;
    }
    setBusy(true);
    auto* process = new QProcess(this);
    m_process = process;
    process->setProgram(tool);
    process->setArguments(arguments);
    connect(process, &QProcess::finished, this,
            [this, process, mutating](int exitCode, QProcess::ExitStatus) {
                const QString output = QString::fromUtf8(process->readAllStandardOutput());
                const QString errors = QString::fromUtf8(process->readAllStandardError());
                process->deleteLater();
                setBusy(false);
                if (mutating) {
                    if (exitCode == 0) {
                        parseStatus(output);
                        Q_EMIT applyFinished(true, QString());
                    } else {
                        Q_EMIT applyFinished(false, errors.trimmed());
                    }
                } else if (exitCode == 0) {
                    parseStatus(output);
                }
            });
    // FailedToStart never emits finished(); without this m_busy would stay true forever.
    connect(process, &QProcess::errorOccurred, this,
            [this, process, mutating](QProcess::ProcessError error) {
                if (error != QProcess::FailedToStart) {
                    return;
                }
                process->deleteLater();
                setBusy(false);
                if (mutating) {
                    Q_EMIT applyFinished(false, process->errorString());
                }
            });
    process->start();
}

void ProfileBridge::parseStatus(const QString& output)
{
    // enthroned-profile status prints "Active profile: <label> (<id>)" or
    // "Active profile: none set (Plasma default)" / "(not an Enthroned profile)".
    QString profile;
    const QStringList lines = output.split(QLatin1Char('\n'));
    for (const QString& line : lines) {
        if (!line.startsWith(QLatin1String("Active profile:"))) {
            continue;
        }
        const int open = line.lastIndexOf(QLatin1Char('('));
        const int close = line.lastIndexOf(QLatin1Char(')'));
        if (open > 0 && close > open) {
            profile = line.mid(open + 1, close - open - 1).trimmed();
        }
        if (!profile.contains(QLatin1String("org.enthroned."))) {
            profile = QString();
        }
        break;
    }
    if (m_activeProfile != profile) {
        m_activeProfile = profile;
        Q_EMIT activeChanged();
    }
}

void ProfileBridge::refresh()
{
    if (!m_toolPresent || m_busy) {
        return;
    }
    runTool({ QStringLiteral("status") }, false);
}

void ProfileBridge::apply(const QString& profileId)
{
    if (!m_toolPresent || m_busy) {
        return;
    }
    QString target;
    if (profileId == QLatin1String("org.enthroned.classic")) {
        target = QStringLiteral("classic");
    } else if (profileId == QLatin1String("org.enthroned.modern")) {
        target = QStringLiteral("modern");
    } else {
        Q_EMIT applyFinished(false, i18n("Unknown profile"));
        return;
    }
    runTool({ QStringLiteral("apply"), target }, true);
}

void ProfileBridge::setBusy(bool busy)
{
    if (m_busy != busy) {
        m_busy = busy;
        Q_EMIT busyChanged();
    }
}

} // namespace Enthroned
