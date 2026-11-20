/*
 * Enthroned Settings - live journal tail (F3.6 progress source).
 * Follows journalctl for the manual update unit (-f, JSON lines). Read-only:
 * reading the system journal requires journal permissions (wheel on Aurora);
 * when unavailable, the engine falls back to unit-state polling only and the
 * UI shows an indeterminate progress indicator.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QObject>
#include <QVector>

#include "journalparser.h"

class QProcess;

namespace Enthroned {

class JournalProgressSource : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool journalAvailable READ journalAvailable NOTIFY journalAvailableChanged)

public:
    explicit JournalProgressSource(const UpdateStateMachine& spec, QObject* parent = nullptr);
    ~JournalProgressSource() override;

    bool journalAvailable() const { return m_journalAvailable; }

    // Start following the given unit. Lines are parsed with JournalParser and
    // emitted as updateEvent.
    Q_INVOKABLE void follow(const QString& unit);

    // Read recent history entries for the given units (no follow).
    Q_INVOKABLE void fetchHistory(const QStringList& units, int lines);

    // Stop any running journalctl process.
    Q_INVOKABLE void stop();

Q_SIGNALS:
    void journalAvailableChanged();
    void updateEvent(const QVariantMap& event);
    void historyFetched(const QVariantList& entries);

private:
    QProcess* startJournalctl(const QStringList& args);
    // Detach and stop the history process while this object is still intact
    // (a QProcess killed by ~QObject child deletion would emit finished into
    // a half-destroyed owner).
    void stopHistoryProcess();
    void handleLine(const QByteArray& line, bool live);

    const UpdateStateMachine& m_spec;
    JournalParser m_parser;
    QProcess* m_followProcess = nullptr;
    QProcess* m_historyProcess = nullptr;
    bool m_journalAvailable = true;
};

} // namespace Enthroned
