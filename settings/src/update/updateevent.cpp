/*
 * Enthroned Settings - update event model implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "updateevent.h"

#include <QDateTime>

namespace Enthroned {

QString updatePhaseToString(UpdatePhase phase)
{
    switch (phase) {
    case UpdatePhase::Initializing:  return QStringLiteral("Initializing");
    case UpdatePhase::Checking:      return QStringLiteral("Checking");
    case UpdatePhase::FetchingInfo:  return QStringLiteral("FetchingInfo");
    case UpdatePhase::Downloading:   return QStringLiteral("Downloading");
    case UpdatePhase::Preparing:     return QStringLiteral("Preparing");
    case UpdatePhase::Applying:      return QStringLiteral("Applying");
    case UpdatePhase::Validating:    return QStringLiteral("Validating");
    case UpdatePhase::WaitingRestart: return QStringLiteral("WaitingRestart");
    case UpdatePhase::Completed:     return QStringLiteral("Completed");
    case UpdatePhase::Failed:        return QStringLiteral("Failed");
    }
    return QStringLiteral("Initializing");
}

UpdatePhase updatePhaseFromString(const QString& value)
{
    if (value == QLatin1String("Checking"))       return UpdatePhase::Checking;
    if (value == QLatin1String("FetchingInfo"))   return UpdatePhase::FetchingInfo;
    if (value == QLatin1String("Downloading"))    return UpdatePhase::Downloading;
    if (value == QLatin1String("Preparing"))      return UpdatePhase::Preparing;
    if (value == QLatin1String("Applying"))       return UpdatePhase::Applying;
    if (value == QLatin1String("Validating"))     return UpdatePhase::Validating;
    if (value == QLatin1String("WaitingRestart")) return UpdatePhase::WaitingRestart;
    if (value == QLatin1String("Completed"))      return UpdatePhase::Completed;
    if (value == QLatin1String("Failed"))         return UpdatePhase::Failed;
    return UpdatePhase::Initializing;
}

QString updateSeverityToString(UpdateSeverity severity)
{
    switch (severity) {
    case UpdateSeverity::Debug:   return QStringLiteral("Debug");
    case UpdateSeverity::Info:    return QStringLiteral("Info");
    case UpdateSeverity::Warning: return QStringLiteral("Warning");
    case UpdateSeverity::Error:   return QStringLiteral("Error");
    }
    return QStringLiteral("Info");
}

UpdateSeverity updateSeverityFromString(const QString& value)
{
    if (value == QLatin1String("Debug"))   return UpdateSeverity::Debug;
    if (value == QLatin1String("Warning")) return UpdateSeverity::Warning;
    if (value == QLatin1String("Error"))   return UpdateSeverity::Error;
    return UpdateSeverity::Info;
}

QString updateResultToString(UpdateResult result)
{
    switch (result) {
    case UpdateResult::None:      return QStringLiteral("None");
    case UpdateResult::Success:   return QStringLiteral("Success");
    case UpdateResult::Failure:   return QStringLiteral("Failure");
    case UpdateResult::Cancelled: return QStringLiteral("Cancelled");
    }
    return QStringLiteral("None");
}

UpdateResult updateResultFromString(const QString& value)
{
    if (value == QLatin1String("Success"))   return UpdateResult::Success;
    if (value == QLatin1String("Failure"))   return UpdateResult::Failure;
    if (value == QLatin1String("Cancelled")) return UpdateResult::Cancelled;
    return UpdateResult::None;
}

QVariantMap UpdateEvent::toVariantMap() const
{
    QVariantMap map;
    map.insert(QStringLiteral("source"), source);
    map.insert(QStringLiteral("operationId"), operationId);
    map.insert(QStringLiteral("rawType"), rawType);
    map.insert(QStringLiteral("phase"), updatePhaseToString(phase));
    map.insert(QStringLiteral("description"), description);
    map.insert(QStringLiteral("timestamp"), timestampMs);
    map.insert(QStringLiteral("severity"), updateSeverityToString(severity));
    if (progressPercent >= 0.0) {
        map.insert(QStringLiteral("progressPercent"), progressPercent);
    }
    if (bytesTransferred >= 0) {
        map.insert(QStringLiteral("bytesTransferred"), bytesTransferred);
        if (bytesTotal > 0) {
            map.insert(QStringLiteral("bytesTotal"), bytesTotal);
        }
    }
    if (!currentItem.isEmpty()) {
        map.insert(QStringLiteral("currentItem"), currentItem);
    }
    if (result != UpdateResult::None) {
        map.insert(QStringLiteral("result"), updateResultToString(result));
    }
    return map;
}

UpdateEvent UpdateEvent::fromVariantMap(const QVariantMap& map)
{
    UpdateEvent event;
    event.source = map.value(QStringLiteral("source")).toString();
    event.operationId = map.value(QStringLiteral("operationId")).toString();
    event.rawType = map.value(QStringLiteral("rawType")).toString();
    event.phase = updatePhaseFromString(map.value(QStringLiteral("phase")).toString());
    event.description = map.value(QStringLiteral("description")).toString();
    event.timestampMs = static_cast<qint64>(map.value(QStringLiteral("timestamp")).toLongLong());
    if (event.timestampMs == 0) {
        event.timestampMs = QDateTime::currentMSecsSinceEpoch();
    }
    event.severity = updateSeverityFromString(map.value(QStringLiteral("severity")).toString());
    event.progressPercent = map.value(QStringLiteral("progressPercent"), -1.0).toDouble();
    event.bytesTransferred = map.value(QStringLiteral("bytesTransferred"), qint64(-1)).toLongLong();
    event.bytesTotal = map.value(QStringLiteral("bytesTotal"), qint64(-1)).toLongLong();
    event.currentItem = map.value(QStringLiteral("currentItem")).toString();
    event.result = updateResultFromString(map.value(QStringLiteral("result")).toString());
    return event;
}

} // namespace Enthroned
