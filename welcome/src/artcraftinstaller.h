/*
 * Enthroned Welcome - optional ArtCraft Launcher installer (F4.6/F4.8).
 *
 * HARD SECURITY CONTRACT (docs/architecture/ENTHRONED-FIRST-RUN-ARCHITECTURE.md):
 *   - nothing runs without the UI consent flow (checkbox + explicit dialog);
 *   - the real download/install path is gated by the environment variable
 *     ENTHRONED_WELCOME_ALLOW_INSTALL=1; without it the action reports the
 *     honest "blocked" state and performs NO network access;
 *   - the only source is the official project releases on GitHub
 *     (storytold/craft-launcher); the .flatpak bundle is installed with
 *     `flatpak install --user` (no root, no system mutation, no rpm-ostree
 *     layering, no script execution, no curl | bash);
 *   - every download is verified against the release SHA256SUMS.txt before
 *     installation; a checksum failure aborts with a clear message;
 *   - offline runs fail cleanly and the assistant stays usable.
 *
 * Demo mode (--demo) replays fixture scenarios from :/src/demo/scenarios/
 * without any network access, mirroring the F3 demo contract.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QString>

namespace Enthroned {

class ArtcraftInstaller : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool gateOpen READ gateOpen CONSTANT)
    Q_PROPERTY(bool flatpakPresent READ flatpakPresent CONSTANT)
    Q_PROPERTY(bool launcherInstalled READ launcherInstalled NOTIFY availabilityChanged)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString message READ message NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY stateChanged)
    Q_PROPERTY(bool demoMode READ demoMode CONSTANT)

public:
    explicit ArtcraftInstaller(bool demoMode, const QString& demoScenario, QObject* parent = nullptr);

    bool gateOpen() const;
    bool flatpakPresent() const { return m_flatpakPresent; }
    bool launcherInstalled() const;
    QString state() const { return m_state; }
    QString message() const { return m_message; }
    int progress() const { return m_progress; }
    bool demoMode() const { return m_demoMode; }

    // Static asset arch (x86_64/aarch64) used in the release asset name.
    static QString assetArch();

    Q_INVOKABLE void install();
    Q_INVOKABLE void reset();
    // Lote 6: honest cancellation of an in-flight download/install. Aborts
    // the current network reply or terminates the flatpak process; the UI
    // returns to a usable state and nothing partial is kept.
    Q_INVOKABLE void cancel();

Q_SIGNALS:
    void stateChanged();
    void availabilityChanged();
    // ok=false carries a human-readable message for the UI.
    void finished(bool ok, const QString& message);

private:
    void setState(const QString& state, const QString& message = QString(), int progress = -1);
    void startReal();
    void runDemoScenario();
    // Lote 6: the shipped install policy (/usr/share/enthroned-os/install-policy.json)
    // opens the gate once the source and package contract are validated; the
    // environment variable remains a testing override.
    static bool policyAllows();
    // Lote 6: after a real install, create the desktop shortcut when the
    // user preference (CreateDesktopShortcuts, default true) allows it.
    void maybeCreateDesktopShortcut();

    bool m_demoMode = false;
    QString m_demoScenario;
    bool m_flatpakPresent = false;
    QString m_state = QStringLiteral("idle");
    QString m_message;
    int m_progress = -1;
    bool m_running = false;
    bool m_cancelRequested = false;
    QPointer<QNetworkReply> m_currentReply;
    QProcess* m_currentProcess = nullptr;
    QNetworkAccessManager m_nam;
};

} // namespace Enthroned
