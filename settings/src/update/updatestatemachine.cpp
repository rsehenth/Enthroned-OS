/*
 * Enthroned Settings - declarative update state machine implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "updatestatemachine.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace Enthroned {

bool UpdateStateMachine::loadSpec(const QByteArray& json, QString* error)
{
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        if (error) {
            *error = QStringLiteral("update-state-spec.json: %1 (offset %2)")
                         .arg(parseError.errorString()).arg(parseError.offset);
        }
        return false;
    }

    const QJsonObject root = doc.object();
    m_initial = root.value(QStringLiteral("initial")).toString();
    m_states.clear();
    m_transitions.clear();

    const QJsonArray states = root.value(QStringLiteral("states")).toArray();
    for (const QJsonValue& value : states) {
        m_states.append(value.toString());
    }

    const QJsonArray transitions = root.value(QStringLiteral("transitions")).toArray();
    for (const QJsonValue& value : transitions) {
        const QJsonObject obj = value.toObject();
        UpdateTransition transition;
        transition.from = obj.value(QStringLiteral("from")).toString();
        transition.event = obj.value(QStringLiteral("event")).toString();
        transition.to = obj.value(QStringLiteral("to")).toString();
        const QJsonArray requiredContext = obj.value(QStringLiteral("requires")).toArray();
        for (const QJsonValue& requirement : requiredContext) {
            transition.requiredContext.append(requirement.toString());
        }
        m_transitions.append(transition);
    }

    m_journalMapping = root.value(QStringLiteral("journal_mapping")).toArray();
    m_bootcProgress = root.value(QStringLiteral("bootc_progress")).toObject();

    if (m_initial.isEmpty() || m_states.isEmpty() || !hasState(m_initial)) {
        if (error) {
            *error = QStringLiteral("update-state-spec.json: initial state invalid or empty");
        }
        return false;
    }
    for (const UpdateTransition& transition : m_transitions) {
        if (!hasState(transition.from) || !hasState(transition.to)) {
            if (error) {
                *error = QStringLiteral("update-state-spec.json: unknown state in transition %1 --%2--> %3")
                             .arg(transition.from, transition.event, transition.to);
            }
            return false;
        }
    }
    return true;
}

QString UpdateStateMachine::step(const QString& state, const UpdateEvent& event,
                                 const QVariantMap& context) const
{
    for (const UpdateTransition& transition : m_transitions) {
        if (transition.from != state || transition.event != event.rawType) {
            continue;
        }
        bool satisfied = true;
        for (const QString& requirement : transition.requiredContext) {
            if (!context.value(requirement, false).toBool()) {
                satisfied = false;
                break;
            }
        }
        if (satisfied) {
            return transition.to;
        }
    }
    return state;
}

} // namespace Enthroned
