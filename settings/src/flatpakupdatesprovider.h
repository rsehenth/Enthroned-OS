/*
 * Enthroned Settings - Flatpak updates provider (F3.5 / Lote 8).
 * Lists available app updates for the user and system installations with
 * `flatpak remote-ls --updates` (cached metadata listing; read-only) and the
 * update history with `flatpak history --columns=...` (read-only).
 *
 * Mutating paths (Lote 8), kept separate and never mixed:
 *   - system installation: enthroned-flatpak-update.service (systemd D-Bus,
 *     fixed command, polkit-authorized) - owned by the update engine;
 *   - user installation: updateUserInstallations() below runs the FIXED
 *     command `flatpak update --user --noninteractive` with fixed arguments
 *     (no user-provided strings) in the user session; no privilege needed.
 * No app or app data is ever removed.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>

class QProcess;

namespace Enthroned {

class FlatpakUpdatesProvider : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool flatpakPresent READ flatpakPresent CONSTANT)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool updatesPresent READ updatesPresent NOTIFY availableChanged)
    Q_PROPERTY(QVariantList updates READ updates NOTIFY availableChanged)

public:
    // binaryOverride is a TESTABILITY seam (Lote 9.2): production code never
    // sets it and flatpakBinary() resolves the real binary; tests inject a
    // fake program path so no real flatpak invocation can ever happen.
    explicit FlatpakUpdatesProvider(const QString& binaryOverride = QString(),
                                    QObject* parent = nullptr);

    bool flatpakPresent() const { return m_flatpakPresent; }
    bool available() const { return m_available; }
    bool updatesPresent() const { return !m_updates.isEmpty(); }
    QVariantList updates() const { return m_updates; }

    void refreshUpdates();
    void fetchHistory();

    // Update the USER installation with the fixed, non-configurable command
    // `flatpak update --user --noninteractive`. Emits userUpdateProgress and
    // userUpdateFinished. Refuses to start twice (concurrent guard).
    Q_INVOKABLE bool updateUserInstallations();
    bool userUpdateRunning() const { return m_userUpdateProcess != nullptr; }

Q_SIGNALS:
    void availableChanged();
    void historyFetched(const QVariantList& entries);
    // percent < 0 means the source did not provide a trustworthy percentage.
    void userUpdateProgress(int percent, const QString& currentItem);
    void userUpdateFinished(bool ok, const QString& errorHint);

private:
    void runRemoteList(const QString& installationFlag, const QString& installationLabel);
    void applyListOutput(const QByteArray& output, const QString& installationLabel,
                         quint64 generation);
    void finishUserUpdate(QProcess* process, bool ok, const QString& errorHint);
    QString flatpakBinary() const;

    bool m_flatpakPresent = false;
    bool m_available = false;
    QVariantList m_updates;
    quint64 m_generation = 0;
    QString m_binaryOverride;
    QProcess* m_userUpdateProcess = nullptr;
};

} // namespace Enthroned
