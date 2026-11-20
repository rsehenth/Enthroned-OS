/*
 * Enthroned OS - supervised Settings launch for the desktop context menu.
 *
 * P1-1 (H4): the Settings app SIGSEGV'd right after being opened from the
 * context menu, leaving the user with nothing. This launcher runs the app as
 * a QProcess child of plasmashell, so a crash inside the app can never reach
 * the shell, forwards the app's output to the shell's journal for
 * diagnosis, and walks the candidate list on failure: the Settings app is
 * retried once (transient failures) and the native System Settings is the
 * last resort, mirroring the "fallback for images without the hub" intent.
 *
 * Trade-off (accepted): the child is a direct child of plasmashell, so a
 * shell restart closes the launched app; the previous detached child had the
 * same cgroup but no failure visibility. One launch chain runs at a time; a
 * re-activation while the app is already running is ignored.
 *
 * Lote 10.2 (Gate 10.1) lifecycle rules:
 *   - only FailedToStart advances the retry chain from errorOccurred(): it is
 *     the only error that is never followed by finished(). A crash is handled
 *     in finished() (Qt emits errorOccurred(Crashed) first); I/O errors are
 *     logged while the child keeps running, so a read/write failure can never
 *     spawn a second instance over a live one.
 *   - the QProcess is unparented and deletes itself on finished(); the
 *     launcher destructor therefore never runs the blocking
 *     kill()/waitForFinished() teardown on the GUI thread: it only
 *     disconnects the callbacks, asks the child to exit and lets the object
 *     clean up when the process is reaped. A child that ignores SIGTERM would
 *     linger (bounded leak, no GUI freeze) - no real candidate does.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QDebug>

class SettingsLauncher : public QObject
{
public:
    explicit SettingsLauncher(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

    ~SettingsLauncher() override
    {
        if (!m_process) {
            return;
        }
        QProcess *process = m_process;
        m_process = nullptr;
        process->disconnect(this); // no callbacks may touch the dying launcher
        process->kill();           // ask the child to exit; never wait here
    }

    // candidates: program names or absolute paths, tried in order. The first
    // entry is the product entry point; the repeat of it is the crash retry;
    // the last entry is the fallback binary.
    void launch(const QStringList &candidates)
    {
        if (m_process) {
            return; // a candidate is starting or running
        }
        m_candidates = candidates;
        m_index = -1;
        startNext();
    }

    // True while a candidate is starting or running (the launch chain is busy).
    bool isBusy() const { return m_process != nullptr; }

private:
    void startNext()
    {
        ++m_index;
        if (m_index >= m_candidates.size()) {
            qWarning() << "enthroned-contextmenu: could not launch the Settings"
                       << "app after" << m_index << "attempt(s)";
            reset();
            return;
        }
        const QString program = m_candidates.at(m_index);
        // Unparented on purpose: the process must never be destroyed from the
        // launcher's destructor (Qt would kill() and waitForFinished() on the
        // GUI thread there). It deletes itself once the child is reaped.
        auto *process = new QProcess(nullptr);
        process->setProgram(program);
        process->setProcessChannelMode(QProcess::ForwardedChannels);
        connect(process, &QProcess::finished, process, &QProcess::deleteLater);
        connect(process, &QProcess::errorOccurred, this,
                [this, process](QProcess::ProcessError error) {
            if (m_process != process) {
                return;
            }
            if (error != QProcess::FailedToStart) {
                // Crashed/I/O errors keep the child (or are immediately
                // followed by finished()): advancing here would double-step
                // the chain or spawn an instance over a live process.
                qWarning() << "enthroned-contextmenu: process error for"
                           << process->program() << "(error" << error << ")"
                           << "- keeping the child";
                return;
            }
            qWarning() << "enthroned-contextmenu: could not start" << process->program()
                       << "- trying the next candidate";
            process->deleteLater();
            m_process = nullptr;
            startNext();
        });
        connect(process, &QProcess::finished, this,
                [this, process](int exitCode, QProcess::ExitStatus exitStatus) {
            if (m_process != process) {
                return;
            }
            process->deleteLater();
            m_process = nullptr;
            if (exitStatus == QProcess::NormalExit && exitCode == 0) {
                reset();
                return;
            }
            qWarning() << "enthroned-contextmenu:" << process->program()
                       << (exitStatus == QProcess::CrashExit ? "crashed" : "failed")
                       << "with code" << exitCode << "- trying the next candidate";
            startNext();
        });
        m_process = process;
        process->start();
    }

    void reset()
    {
        m_candidates.clear();
        m_index = -1;
    }

    QProcess *m_process = nullptr;
    QStringList m_candidates;
    int m_index = -1;
};
