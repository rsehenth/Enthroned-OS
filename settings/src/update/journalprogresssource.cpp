/*
 * Enthroned Settings - live journal tail implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "journalprogresssource.h"

#include <QProcess>

#include <KLocalizedString>

namespace Enthroned {

JournalProgressSource::JournalProgressSource(const UpdateStateMachine& spec, QObject* parent)
    : QObject(parent)
    , m_spec(spec)
    , m_parser(spec)
{
}

JournalProgressSource::~JournalProgressSource()
{
    stop();
    stopHistoryProcess();
}

QProcess* JournalProgressSource::startJournalctl(const QStringList& args)
{
    QProcess* process = new QProcess(this);
    process->setProgram(QStringLiteral("journalctl"));
    process->setArguments(args);
    return process;
}

void JournalProgressSource::follow(const QString& unit)
{
    stop();
    // -n 0: only NEW lines; -o json: machine readable; -f: follow.
    m_followProcess = startJournalctl({ QStringLiteral("-f"), QStringLiteral("-n"),
                                        QStringLiteral("0"), QStringLiteral("-o"),
                                        QStringLiteral("json"), QStringLiteral("-u"), unit });
    connect(m_followProcess, &QProcess::readyReadStandardOutput, this, [this]() {
        while (m_followProcess->canReadLine()) {
            const QByteArray line = m_followProcess->readLine().trimmed();
            if (!line.isEmpty()) {
                handleLine(line, true);
            }
        }
    });
    connect(m_followProcess, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        if (m_journalAvailable) {
            m_journalAvailable = false;
            Q_EMIT journalAvailableChanged();
        }
        UpdateEvent event;
        event.source = QStringLiteral("journal");
        event.rawType = QStringLiteral("journal-unavailable");
        event.severity = UpdateSeverity::Debug;
        event.description = i18n("Journal unavailable; progress limited to the unit state");
        Q_EMIT updateEvent(event.toVariantMap());
    });
    m_followProcess->start(QIODevice::ReadOnly);
}

void JournalProgressSource::fetchHistory(const QStringList& units, int lines)
{
    stopHistoryProcess();
    QStringList args;
    args << QStringLiteral("-o") << QStringLiteral("json")
         << QStringLiteral("-n") << QString::number(lines);
    for (const QString& unit : units) {
        args << QStringLiteral("-u") << unit;
    }
    m_historyProcess = startJournalctl(args);
    // Identity-guarded lifecycle (same pattern as FlatpakUpdatesProvider):
    // the callback captures its own process, so a finished emitted by a
    // replaced or already-stopped journalctl can never touch the wrong (or a
    // half-destroyed) object.
    connect(m_historyProcess, &QProcess::finished, this,
            [this, process = m_historyProcess](int exitCode, QProcess::ExitStatus) {
        if (m_historyProcess != process) {
            return;
        }
        const QByteArray output = process->readAllStandardOutput();
        m_historyProcess->deleteLater();
        m_historyProcess = nullptr;

        QVariantList entries;
        if (exitCode != 0) {
            Q_EMIT historyFetched(entries);
            return;
        }
        const QList<QByteArray> lines = output.split('\n');
        for (const QByteArray& raw : lines) {
            const QByteArray trimmed = raw.trimmed();
            if (trimmed.isEmpty()) {
                continue;
            }
            const QVector<UpdateEvent> events = m_parser.parseLine(trimmed);
            for (const UpdateEvent& event : events) {
                // Keep only meaningful history: outcomes and module results.
                if (event.rawType == QLatin1String("unknown-data")
                    || event.rawType == QLatin1String("bootc-progress")) {
                    continue;
                }
                QVariantMap entry = event.toVariantMap();
                entries.append(entry);
            }
        }
        Q_EMIT historyFetched(entries);
    });
    m_historyProcess->start(QIODevice::ReadOnly);
}

void JournalProgressSource::stop()
{
    if (m_followProcess) {
        m_followProcess->disconnect(this);
        m_followProcess->terminate();
        m_followProcess->deleteLater();
        m_followProcess = nullptr;
    }
}

void JournalProgressSource::stopHistoryProcess()
{
    if (m_historyProcess) {
        m_historyProcess->disconnect(this);
        if (m_historyProcess->state() != QProcess::NotRunning) {
            m_historyProcess->kill();
            m_historyProcess->waitForFinished(500);
        }
        m_historyProcess->deleteLater();
        m_historyProcess = nullptr;
    }
}

void JournalProgressSource::handleLine(const QByteArray& line, bool live)
{
    Q_UNUSED(live);
    const QVector<UpdateEvent> events = m_parser.parseLine(line);
    for (const UpdateEvent& event : events) {
        Q_EMIT updateEvent(event.toVariantMap());
    }
}

} // namespace Enthroned
