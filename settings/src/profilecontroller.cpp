/*
 * Enthroned Settings - appearance profile controller implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "profilecontroller.h"

#include <QFileInfo>
#include <QProcess>

#include <KLocalizedString>

namespace Enthroned {

namespace {
constexpr auto kTool = "/usr/bin/enthroned-profile";
constexpr auto kClassicId = "org.enthroned.classic";
constexpr auto kModernId = "org.enthroned.modern";
} // namespace

ProfileController::ProfileController(QObject* parent)
    : QObject(parent)
{
    m_toolPresent = QFileInfo::exists(QLatin1String(kTool));
}

QString ProfileController::activeLabel() const
{
    if (m_activeProfile == QLatin1String(kClassicId)) {
        return QStringLiteral("Enthroned Classic");
    }
    if (m_activeProfile == QLatin1String(kModernId)) {
        return QStringLiteral("Enthroned Modern");
    }
    return QString();
}

void ProfileController::runTool(const QStringList& arguments, bool mutating)
{
    if (!m_toolPresent) {
        Q_EMIT applyFinished(false, i18n("The enthroned-profile tool was not found on this system."));
        return;
    }
    if (m_busy && mutating) {
        return; // one mutating operation at a time
    }
    setBusy(true);

    auto* process = new QProcess(this);
    process->setProgram(QLatin1String(kTool));
    process->setArguments(arguments);
    connect(process, &QProcess::finished, this,
            [this, process, arguments, mutating](int exitCode, QProcess::ExitStatus) {
        const QString output = QString::fromUtf8(process->readAllStandardOutput());
        const QString error = QString::fromUtf8(process->readAllStandardError());
        process->deleteLater();
        setBusy(false);

        if (!mutating) {
            if (arguments.first() == QLatin1String("status")) {
                parseStatus(output);
            }
            return;
        }

        if (exitCode == 0) {
            m_canRestore = arguments.first() == QLatin1String("apply");
            Q_EMIT applyFinished(true, output.trimmed());
        } else {
            Q_EMIT applyFinished(false, error.trimmed().left(200));
        }
        refresh();
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

void ProfileController::parseStatus(const QString& output)
{
    QString active;
    const QString activeLine = output.section(QLatin1Char('\n'), 0, 0);
    if (activeLine.contains(QLatin1String("Enthroned Classic"))) {
        active = QLatin1String(kClassicId);
    } else if (activeLine.contains(QLatin1String("Enthroned Modern"))) {
        active = QLatin1String(kModernId);
    }
    m_canRestore = output.contains(QLatin1String("Previous look-and-feel"));
    if (active != m_activeProfile) {
        m_activeProfile = active;
        Q_EMIT activeChanged();
    } else {
        Q_EMIT activeChanged();
    }
}

void ProfileController::refreshList()
{
    auto* process = new QProcess(this);
    process->setProgram(QLatin1String(kTool));
    process->setArguments({ QStringLiteral("list") });
    connect(process, &QProcess::finished, this, [this, process](int exitCode, QProcess::ExitStatus) {
        const QString output = QString::fromUtf8(process->readAllStandardOutput());
        process->deleteLater();
        if (exitCode != 0) {
            return;
        }
        QVariantList profiles;
        const QStringList lines = output.split(QLatin1Char('\n'));
        for (const QString& line : lines) {
            const QString trimmed = line.trimmed();
            if (trimmed.isEmpty()) {
                continue;
            }
            const QString id = trimmed.startsWith(QLatin1Char('*')) ? trimmed.mid(1).trimmed() : trimmed;
            QString label;
            if (id == QLatin1String(kClassicId)) {
                label = QStringLiteral("Enthroned Classic");
            } else if (id == QLatin1String(kModernId)) {
                label = QStringLiteral("Enthroned Modern");
            }
            if (label.isEmpty()) {
                continue; // only offer Enthroned profiles in this page
            }
            QVariantMap profile;
            profile.insert(QStringLiteral("id"), id);
            profile.insert(QStringLiteral("label"), label);
            profile.insert(QStringLiteral("active"), id == m_activeProfile);
            profiles.append(profile);
        }
        if (!profiles.isEmpty()) {
            m_profiles = profiles;
            Q_EMIT activeChanged();
        }
    });
    process->start();
}

void ProfileController::refresh()
{
    runTool({ QStringLiteral("status") }, false);
    refreshList();
}

void ProfileController::apply(const QString& profileId)
{
    runTool({ QStringLiteral("apply"), profileId }, true);
}

void ProfileController::restore()
{
    runTool({ QStringLiteral("restore") }, true);
}

void ProfileController::setBusy(bool busy)
{
    if (m_busy != busy) {
        m_busy = busy;
        Q_EMIT busyChanged();
    }
}

} // namespace Enthroned
