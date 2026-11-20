/*
 * Enthroned Settings - native KCM launcher implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "kcmlauncher.h"

#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>

namespace Enthroned {

KcmLauncher::KcmLauncher(QObject* parent)
    : QObject(parent)
{
    m_toolPresent = !QStandardPaths::findExecutable(QStringLiteral("kcmshell6")).isEmpty();
}

void KcmLauncher::refreshAvailable()
{
    if (!m_toolPresent || m_busy) {
        Q_EMIT availableChanged();
        return;
    }
    setBusy(true);
    auto* process = new QProcess(this);
    process->setProgram(QStandardPaths::findExecutable(QStringLiteral("kcmshell6")));
    process->setArguments({ QStringLiteral("--list") });
    connect(process, &QProcess::finished, this, [this, process](int exitCode, QProcess::ExitStatus) {
        const QString output = QString::fromUtf8(process->readAllStandardOutput());
        process->deleteLater();
        setBusy(false);

        QStringList available;
        if (exitCode == 0) {
            const QStringList lines = output.split(QLatin1Char('\n'));
            for (const QString& line : lines) {
                // Format: "<module> <space or dash> description..." -> id is the
                // first token; tolerate both "id - desc" and "id: desc".
                const QString trimmed = line.trimmed();
                if (trimmed.isEmpty()) {
                    continue;
                }
                QString id = trimmed.section(QLatin1Char(' '), 0, 0);
                id.remove(QLatin1Char(':'));
                if (!id.isEmpty()) {
                    available.append(id);
                }
            }
        }
        m_available = available;
        Q_EMIT availableChanged();
    });
    // FailedToStart never emits finished(); without this m_busy would stay true forever.
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
            setBusy(false);
            Q_EMIT availableChanged();
        }
    });
    process->start();
}

bool KcmLauncher::isAvailable(const QString& module) const
{
    return m_available.contains(module);
}

void KcmLauncher::launch(const QString& module)
{
    // Only modules that kcmshell6 itself listed can be opened (no arbitrary arguments).
    if (!m_toolPresent || !m_available.contains(module)) {
        Q_EMIT launched(false, module);
        return;
    }
    const bool ok = QProcess::startDetached(
        QStandardPaths::findExecutable(QStringLiteral("kcmshell6")), { module });
    Q_EMIT launched(ok, module);
}

bool KcmLauncher::hasExecutable(const QString& program) const
{
    return !QStandardPaths::findExecutable(program).isEmpty();
}

bool KcmLauncher::hasFlatpakApp(const QString& appId) const
{
    // Flatpak installs export their .desktop files through XDG_DATA_DIRS
    // (system: /var/lib/flatpak/exports/share, user: ~/.local/share/flatpak/
    // exports/share), so ApplicationsLocation covers both.
    return !QStandardPaths::locate(QStandardPaths::ApplicationsLocation,
                                   appId + QStringLiteral(".desktop"))
                .isEmpty();
}

void KcmLauncher::launchApp(const QString& program)
{
    const QString path = QStandardPaths::findExecutable(program);
    if (path.isEmpty()) {
        Q_EMIT launched(false, program);
        return;
    }
    const bool ok = QProcess::startDetached(path, {});
    Q_EMIT launched(ok, program);
}

void KcmLauncher::setBusy(bool busy)
{
    if (m_busy != busy) {
        m_busy = busy;
        Q_EMIT busyChanged();
    }
}

} // namespace Enthroned
