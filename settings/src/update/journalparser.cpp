/*
 * Enthroned Settings - journal parser implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "journalparser.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <KLocalizedString>

namespace Enthroned {

JournalParser::JournalParser(const UpdateStateMachine& spec)
    : m_spec(spec)
{
}

namespace {

UpdateSeverity severityFromSlogLevel(const QString& level)
{
    if (level == QLatin1String("ERROR")) return UpdateSeverity::Error;
    if (level == QLatin1String("WARN"))  return UpdateSeverity::Warning;
    if (level == QLatin1String("DEBUG")) return UpdateSeverity::Debug;
    return UpdateSeverity::Info;
}

} // namespace

QVector<UpdateEvent> JournalParser::parseLine(const QByteArray& line) const
{
    const QJsonDocument document = QJsonDocument::fromJson(line);
    if (!document.isObject()) {
        UpdateEvent unknown;
        unknown.source = QStringLiteral("journal");
        unknown.rawType = QStringLiteral("unknown-data");
        unknown.severity = UpdateSeverity::Debug;
        unknown.description = i18n("Unrecognized journal line");
        return { unknown };
    }

    const QJsonObject entry = document.object();
    const QString message = entry.value(QStringLiteral("MESSAGE")).toString();

    const QVector<UpdateEvent> events = parseSlogMessage(message);
    if (!events.isEmpty()) {
        return events;
    }

    UpdateEvent unknown;
    unknown.source = QStringLiteral("journal");
    unknown.rawType = QStringLiteral("unknown-data");
    unknown.severity = UpdateSeverity::Debug;
    unknown.description = message.left(200);
    return { unknown };
}

QVector<UpdateEvent> JournalParser::parseSlogMessage(const QString& message) const
{
    QVector<UpdateEvent> events;
    if (message.isEmpty() || !message.startsWith(QLatin1Char('{'))) {
        return events;
    }

    const QJsonDocument slogDoc = QJsonDocument::fromJson(message.toUtf8());
    if (!slogDoc.isObject()) {
        return events;
    }
    const QJsonObject slog = slogDoc.object();
    const QString msg = slog.value(QStringLiteral("msg")).toString();
    const QString level = slog.value(QStringLiteral("level")).toString();

    const QJsonArray rules = m_spec.journalMapping();
    for (const QJsonValue& ruleValue : rules) {
        const QJsonObject rule = ruleValue.toObject();
        const QJsonObject match = rule.value(QStringLiteral("match")).toObject();
        const QString event = rule.value(QStringLiteral("event")).toString();
        if (event == QLatin1String("ignore")) {
            if (match.contains(QStringLiteral("msg"))
                && match.value(QStringLiteral("msg")).toString() == msg) {
                return events;
            }
            continue;
        }

        // Match on exact msg
        if (match.contains(QStringLiteral("msg"))) {
            if (match.value(QStringLiteral("msg")).toString() != msg) {
                continue;
            }
        }
        // Match on msg suffix
        if (match.contains(QStringLiteral("msgSuffix"))) {
            if (!msg.endsWith(match.value(QStringLiteral("msgSuffix")).toString())) {
                continue;
            }
        }
        // Match on level
        if (match.contains(QStringLiteral("level"))) {
            if (match.value(QStringLiteral("level")).toString() != level) {
                continue;
            }
        }
        // Match on an extra field value (e.g. status == "running")
        if (match.contains(QStringLiteral("field"))) {
            const QString field = match.value(QStringLiteral("field")).toString();
            const QString equals = match.value(QStringLiteral("equals")).toString();
            if (slog.value(field).toString() != equals) {
                continue;
            }
        }

        // Rule matched; build the event.
        UpdateEvent eventObj;
        eventObj.rawType = event;
        eventObj.severity = severityFromSlogLevel(level);
        eventObj.description = msg;
        const QString sourceField = rule.value(QStringLiteral("sourceFromField")).toString();
        if (!sourceField.isEmpty()) {
            eventObj.source = slog.value(sourceField).toString().toLower();
        }
        eventObj.source = rule.value(QStringLiteral("source")).toString(
            eventObj.source.isEmpty() ? QStringLiteral("system") : eventObj.source);

        const QString payloadField = rule.value(QStringLiteral("payloadFromField")).toString();
        const bool payloadFromMessage = rule.value(QStringLiteral("payloadFromMessage")).toBool();
        if (!payloadField.isEmpty() || payloadFromMessage) {
            // payloadFromField: a slog field carries the bootc progress JSON
            // (uupd path). payloadFromMessage: MESSAGE itself is the raw
            // bootc --progress-fd JSON line (enthroned-system-update path).
            const QString payload = payloadFromMessage ? message : slog.value(payloadField).toString();
            if (event == QLatin1String("bootc-progress")) {
                return parseBootcProgress(payload, eventObj.source);
            }
        }

        // Boolean field forwarding (e.g. update_available from "Update Check")
        const QJsonObject slogAll = slog;
        if (msg == QLatin1String("Update Check")) {
            eventObj.description = slogAll.value(QStringLiteral("update_available")).toBool()
                ? i18n("Update available")
                : i18n("No updates available");
        }
        events.append(eventObj);
        return events;
    }

    return events;
}

QVector<UpdateEvent> JournalParser::parseBootcProgress(const QString& payload,
                                                       const QString& source) const
{
    QVector<UpdateEvent> events;
    const QJsonDocument progressDoc = QJsonDocument::fromJson(payload.toUtf8());
    if (!progressDoc.isObject()) {
        UpdateEvent unknown;
        unknown.source = source;
        unknown.rawType = QStringLiteral("unknown-data");
        unknown.severity = UpdateSeverity::Debug;
        unknown.description = payload.left(200);
        events.append(unknown);
        return events;
    }

    const QJsonObject progress = progressDoc.object();
    const QString type = progress.value(QStringLiteral("type")).toString();
    const QString task = progress.value(QStringLiteral("task")).toString();

    if (type != QLatin1String("ProgressSteps") && type != QLatin1String("ProgressBytes")) {
        return events;
    }

    const QJsonObject phases = m_spec.bootcProgressMapping().value(QStringLiteral("phases")).toObject();
    const QJsonObject window = phases.contains(task)
        ? phases.value(task).toObject()
        : phases.value(QStringLiteral("unknown")).toObject();

    UpdateEvent event;
    event.source = source;
    event.rawType = QStringLiteral("bootc-progress");
    event.description = window.value(QStringLiteral("phase")).toString();
    event.phase = updatePhaseFromString(event.description);
    event.severity = UpdateSeverity::Info;

    const double start = window.value(QStringLiteral("start")).toDouble();
    const double length = window.value(QStringLiteral("length")).toDouble();
    if (type == QLatin1String("ProgressBytes")) {
        const double bytes = progress.value(QStringLiteral("bytes")).toDouble();
        const double bytesTotal = progress.value(QStringLiteral("bytesTotal")).toDouble();
        event.bytesTransferred = static_cast<qint64>(bytes);
        event.bytesTotal = static_cast<qint64>(bytesTotal);
        if (bytesTotal > 0) {
            event.progressPercent = start + qMin(length, (bytes / bytesTotal) * length);
        }
    } else {
        const double steps = progress.value(QStringLiteral("steps")).toDouble();
        const double stepsTotal = progress.value(QStringLiteral("stepsTotal")).toDouble();
        if (stepsTotal >= 0) {
            event.progressPercent = start + qMin(length, (steps / (stepsTotal + 1.0)) * length);
        }
    }

    // downloadFinished: transition FROM 'pulling' (pull phase ended).
    const QString previousTask = m_lastTask;
    m_lastTask = task;
    if (previousTask == QLatin1String("pulling") && task != QLatin1String("pulling")) {
        UpdateEvent finished = event;
        finished.rawType = QStringLiteral("bootc-download-finished");
        finished.phase = UpdatePhase::Preparing;
        finished.description = i18n("Download finished");
        finished.progressPercent = -1.0;
        events.append(finished);
    }

    events.append(event);
    return events;
}

} // namespace Enthroned
