/*
 * Enthroned Settings - journal -> normalized update events (F3.6/F3.9).
 * Parses journalctl -o json lines containing uupd slog JSON output. The
 * mapping rules and bootc progress windows live in update-state-spec.json so
 * the C++ backend and the node test runner share one executable contract.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QByteArray>
#include <QVector>

#include "updatestatemachine.h"

namespace Enthroned {

class JournalParser
{
public:
    explicit JournalParser(const UpdateStateMachine& spec);

    // Parse a single journalctl JSON line. Returns a list of events (may be
    // empty when the line is ignored). Malformed input yields one
    // 'unknown-data' event (severity Debug) so callers can count it, but it
    // never drives state changes.
    QVector<UpdateEvent> parseLine(const QByteArray& line) const;

private:
    QVector<UpdateEvent> parseSlogMessage(const QString& message) const;
    QVector<UpdateEvent> parseBootcProgress(const QString& payload,
                                            const QString& source) const;

    const UpdateStateMachine& m_spec;
    mutable QString m_lastTask;
};

} // namespace Enthroned
