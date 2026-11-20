/*
 * Enthroned Settings - Flatpak updates provider implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "flatpakupdatesprovider.h"

#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

#include <KLocalizedString>

namespace Enthroned {

namespace {
// One user-installation update at a time; flatpak has its own lock, this
// keeps the GUI from stacking sessions on top of each other.
constexpr int kPercentCap = 100;
} // namespace

QString FlatpakUpdatesProvider::flatpakBinary() const
{
    if (!m_binaryOverride.isEmpty()) {
        return m_binaryOverride;
    }
    if (QFileInfo::exists(QStringLiteral("/usr/bin/flatpak"))) {
        return QStringLiteral("/usr/bin/flatpak");
    }
    return QStandardPaths::findExecutable(QStringLiteral("flatpak"));
}

FlatpakUpdatesProvider::FlatpakUpdatesProvider(const QString& binaryOverride,
                                               QObject* parent)
    : QObject(parent)
    , m_binaryOverride(binaryOverride)
{
    m_flatpakPresent = !flatpakBinary().isEmpty();
}

void FlatpakUpdatesProvider::refreshUpdates()
{
    if (!m_flatpakPresent) {
        if (m_available) {
            m_available = false;
            Q_EMIT availableChanged();
        }
        return;
    }
    // Fresh generation: answers from an older listing never merge in.
    ++m_generation;
    m_updates.clear();
    // Two cached, read-only listings: the user installation and the system
    // installation. Rows carry the installation so the UI can tell them apart.
    runRemoteList(QStringLiteral("--user"), QStringLiteral("user"));
    runRemoteList(QStringLiteral("--system"), QStringLiteral("system"));
}

void FlatpakUpdatesProvider::runRemoteList(const QString& installationFlag,
                                           const QString& installationLabel)
{
    const quint64 generation = m_generation;
    auto* process = new QProcess(this);
    process->setProgram(flatpakBinary());
    // Read-only listing of cached update metadata. No --install/--update.
    // --cached: never hit the network at startup.
    process->setArguments({ QStringLiteral("remote-ls"), QStringLiteral("--updates"),
                            QStringLiteral("--cached"), installationFlag,
                            QStringLiteral("--columns=application,version,origin") });
    connect(process, &QProcess::finished, this,
            [this, process, installationLabel, generation](int exitCode, QProcess::ExitStatus) {
        const QByteArray output = process->readAllStandardOutput();
        process->deleteLater();

        if (generation != m_generation) {
            return; // a newer refresh already owns the result set
        }
        if (exitCode == 0) {
            applyListOutput(output, installationLabel, generation);
            m_available = true;
        } else if (installationLabel == QLatin1String("system")) {
            // The user listing already ran; a missing system installation
            // (no system remotes) is not an error for the whole provider.
            m_available = true;
        } else {
            m_available = false;
        }
        Q_EMIT availableChanged();
    });
    process->start();
}

void FlatpakUpdatesProvider::applyListOutput(const QByteArray& output,
                                             const QString& installationLabel,
                                             quint64 generation)
{
    QVariantList updates;
    const QStringList rows = QString::fromUtf8(output).split(QLatin1Char('\n'));
    for (const QString& row : rows) {
        const QString trimmed = row.trimmed();
        if (trimmed.isEmpty()) {
            continue;
        }
        // Columns are tab-separated when non-interactive.
        const QStringList columns = trimmed.split(QLatin1Char('\t'));
        if (columns.size() < 3) {
            continue;
        }
        if (columns.at(0) == QLatin1String("Application")) {
            continue; // header row
        }
        QVariantMap app;
        app.insert(QStringLiteral("id"), columns.at(0).trimmed());
        app.insert(QStringLiteral("version"), columns.at(1).trimmed());
        app.insert(QStringLiteral("origin"), columns.at(2).trimmed());
        app.insert(QStringLiteral("installation"), installationLabel);
        app.insert(QStringLiteral("source"), QStringLiteral("flatpak"));
        updates.append(app);
    }
    m_updates.append(updates);
}

bool FlatpakUpdatesProvider::updateUserInstallations()
{
    if (!m_flatpakPresent || m_userUpdateProcess) {
        return false;
    }
    auto* process = new QProcess(this);
    m_userUpdateProcess = process;
    process->setProgram(flatpakBinary());
    // Fixed, non-configurable argv: never builds a command from UI strings.
    process->setArguments({ QStringLiteral("update"),
                            QStringLiteral("--user"),
                            QStringLiteral("--noninteractive") });
    // H4-005: identity-guarded lifecycle. A crashed process emits
    // errorOccurred(Crashed) BEFORE finished(); only FailedToStart never
    // reaches finished(). Callbacks capture their own process, so a late
    // signal from an already-finalized operation can never dereference a
    // cleared member and every operation finishes exactly once.
    connect(process, &QProcess::finished, this,
            [this, process](int exitCode, QProcess::ExitStatus exitStatus) {
        if (m_userUpdateProcess != process) {
            return; // stale callback from an operation that already ended
        }
        const QByteArray error = process->readAllStandardError();
        finishUserUpdate(process,
                         exitCode == 0 && exitStatus == QProcess::NormalExit,
                         QString::fromUtf8(error).trimmed().left(200));
    });
    connect(process, &QProcess::errorOccurred, this,
            [this, process](QProcess::ProcessError error) {
        if (m_userUpdateProcess != process) {
            return;
        }
        if (error == QProcess::FailedToStart) {
            // The only error that never emits finished().
            finishUserUpdate(process, false, i18n("Failed to run flatpak"));
        }
        // Crashed and every other error still emit finished(); wait for it so
        // the process output is read and the result is emitted exactly once.
    });
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process]() {
        const QStringList lines =
            QString::fromUtf8(process->readAllStandardOutput())
                .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString& line : lines) {
            // flatpak prints its own progress ("... 45% (12/27)") plus app
            // names; parse what is real, never invent a percentage.
            static const QRegularExpression percentRegex(
                QStringLiteral("\\b(\\d{1,3})\\s*%"));
            const QRegularExpressionMatch match = percentRegex.match(line);
            int percent = -1;
            if (match.hasMatch()) {
                percent = qMin(kPercentCap, match.captured(1).toInt());
            }
            QString item;
            static const QRegularExpression appRegex(
                QStringLiteral("\\b([\\w.]+/[\\w-]+/[\\w-]+)\\b"));
            const QRegularExpressionMatch appMatch = appRegex.match(line);
            if (appMatch.hasMatch()) {
                item = appMatch.captured(1);
            } else if (line.startsWith(QLatin1String("Updating"))
                || line.startsWith(QLatin1String("Installing"))) {
                item = line.trimmed().left(80);
            }
            if (percent >= 0 || !item.isEmpty()) {
                Q_EMIT userUpdateProgress(percent, item);
            }
        }
    });
    process->start();
    return true;
}

void FlatpakUpdatesProvider::finishUserUpdate(QProcess* process, bool ok,
                                              const QString& errorHint)
{
    m_userUpdateProcess = nullptr;
    process->deleteLater();
    Q_EMIT userUpdateFinished(ok, ok ? QString() : errorHint);
}

void FlatpakUpdatesProvider::fetchHistory()
{
    if (!m_flatpakPresent) {
        Q_EMIT historyFetched(QVariantList());
        return;
    }
    auto* process = new QProcess(this);
    process->setProgram(flatpakBinary());
    process->setArguments({ QStringLiteral("history"),
                            QStringLiteral("--columns=time,change,application,version"),
                            QStringLiteral("--since=30days") });
    connect(process, &QProcess::finished, this, [this, process](int exitCode, QProcess::ExitStatus) {
        const QByteArray output = process->readAllStandardOutput();
        process->deleteLater();

        QVariantList entries;
        if (exitCode == 0) {
            const QStringList rows = QString::fromUtf8(output).split(QLatin1Char('\n'));
            for (const QString& row : rows) {
                const QString trimmed = row.trimmed();
                if (trimmed.isEmpty()) {
                    continue;
                }
                const QStringList columns = trimmed.split(QLatin1Char('\t'));
                if (columns.size() < 4) {
                    continue;
                }
                QVariantMap entry;
                entry.insert(QStringLiteral("timestamp"), columns.at(0).trimmed());
                entry.insert(QStringLiteral("kind"), columns.at(1).trimmed());
                entry.insert(QStringLiteral("title"), columns.at(2).trimmed());
                entry.insert(QStringLiteral("detail"), columns.at(3).trimmed());
                entry.insert(QStringLiteral("source"), QStringLiteral("flatpak"));
                entries.append(entry);
            }
        }
        Q_EMIT historyFetched(entries);
    });
    process->start();
}

} // namespace Enthroned
