/*
 * Enthroned Welcome - first-run state controller (F4.7).
 * Owns the per-user walkthrough state: the declarative contract in
 * welcome-state-spec.json (shared with welcome/tests/run-tests.mjs), the
 * atomic persistence in $XDG_STATE_HOME/enthroned-os/welcome-state.json and
 * the launch decision (autostart/manual, single instance). Consent for the
 * optional ArtCraft installation is part of the persisted state and is never
 * implied by absence of a choice.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>

namespace Enthroned {

class WelcomeController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString phase READ phase NOTIFY stateChanged)
    Q_PROPERTY(int currentPage READ currentPage NOTIFY stateChanged)
    Q_PROPERTY(int pageCount READ pageCount CONSTANT)
    Q_PROPERTY(bool artcraftConsented READ artcraftConsented NOTIFY stateChanged)
    Q_PROPERTY(QString artcraftInstallState READ artcraftInstallState NOTIFY stateChanged)
    Q_PROPERTY(bool demoMode READ demoMode CONSTANT)

public:
    static constexpr int kPageCount = 5;

    explicit WelcomeController(bool demoMode, QObject* parent = nullptr);

    QString phase() const { return m_phase; }
    int currentPage() const { return m_currentPage; }
    int pageCount() const { return kPageCount; }
    bool artcraftConsented() const { return m_artcraftConsented; }
    QString artcraftInstallState() const { return m_artcraftInstallState; }
    bool demoMode() const { return m_demoMode; }

    // Pure launch policy, mirrored 1:1 by welcome/tests/run-tests.mjs.
    // Terminal phases suppress autostart. Manual launches remain available.
    static bool shouldShowOnLaunch(const QString& phase, const QString& source,
                                   bool alreadyRunning);

    // Pure persistence validation, mirrored by the tests: anything invalid
    // resets to the initial state instead of crashing or blocking the user.
    static QJsonObject sanitize(const QJsonObject& raw);

    void notifyLaunched();
    Q_INVOKABLE void goTo(int page);
    Q_INVOKABLE void next();
    Q_INVOKABLE void back();
    Q_INVOKABLE void finish();
    Q_INVOKABLE void dismiss();
    Q_INVOKABLE void markClosed();
    Q_INVOKABLE void consentArtcraft();
    Q_INVOKABLE void declineArtcraft();
    Q_INVOKABLE void retryArtcraft();

    // Wired from ArtcraftInstaller::finished(ok, message).
    Q_INVOKABLE void artcraftFinished(bool ok);

Q_SIGNALS:
    void stateChanged();
    void requestQuit();

private:
    bool applyEvent(const QString& event);
    void load();
    void save() const;
    void touch();

    bool m_demoMode = false;
    QString m_phase = QStringLiteral("never-started");
    int m_currentPage = 0;
    bool m_artcraftConsented = false;
    QString m_artcraftInstallState = QStringLiteral("idle");
};

} // namespace Enthroned
