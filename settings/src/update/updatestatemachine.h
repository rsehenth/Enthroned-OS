/*
 * Enthroned Settings - declarative update state machine (F3.6).
 * The transition table lives in update-state-spec.json and is shared with the
 * logic test runner (settings/tests/run-tests.mjs). Semantics: first matching
 * rule wins; "requires" lists context keys that must be true; unknown events
 * and unmatched transitions keep the current state.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QJsonArray>
#include <QVector>
#include <QString>
#include <QStringList>

#include "updateevent.h"

namespace Enthroned {

struct UpdateTransition {
    QString from;
    QString event;
    QStringList requiredContext;
    QString to;
};

class UpdateStateMachine
{
public:
    // Load the declarative spec (JSON bytes). Returns false and fills error.
    bool loadSpec(const QByteArray& json, QString* error);

    QString initialState() const { return m_initial; }
    QStringList states() const { return m_states; }
    bool hasState(const QString& state) const { return m_states.contains(state); }
    QVector<UpdateTransition> transitions() const { return m_transitions; }

    // Evaluate one event against the machine. Returns the new state; when no
    // rule matches, the current state is returned unchanged.
    QString step(const QString& state, const UpdateEvent& event, const QVariantMap& context) const;

    // Journal mapping (uupd slog JSON lines -> normalized events), shared with
    // the test runner. See journal_mapping in the spec.
    QJsonArray journalMapping() const { return m_journalMapping; }

    // bootc progress mapping (task -> phase/percent window).
    QJsonObject bootcProgressMapping() const { return m_bootcProgress; }

private:
    QString m_initial;
    QStringList m_states;
    QVector<UpdateTransition> m_transitions;
    QJsonArray m_journalMapping;
    QJsonObject m_bootcProgress;
};

} // namespace Enthroned
