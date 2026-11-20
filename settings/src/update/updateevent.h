/*
 * Enthroned Settings - update event model (F3.6 contract).
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QMetaType>
#include <QString>
#include <QVariantMap>

namespace Enthroned {

// Fases previstas para operacoes de atualizacao (prompt F3.6).
// Nenhuma fase e avancada por cronometro: so por eventos/estados reais.
enum class UpdatePhase {
    Initializing,
    Checking,
    FetchingInfo,
    Downloading,
    Preparing,
    Applying,
    Validating,
    WaitingRestart,
    Completed,
    Failed
};

enum class UpdateSeverity {
    Debug,
    Info,
    Warning,
    Error
};

enum class UpdateResult {
    None,
    Success,
    Failure,
    Cancelled
};

QString updatePhaseToString(UpdatePhase phase);
UpdatePhase updatePhaseFromString(const QString& value);
QString updateSeverityToString(UpdateSeverity severity);
UpdateSeverity updateSeverityFromString(const QString& value);
QString updateResultToString(UpdateResult result);
UpdateResult updateResultFromString(const QString& value);

// Evento normalizado. "rawType" guarda o tipo normalizado (contrato
// update-state-spec.json -> event_types) que alimenta a maquina de estados.
struct UpdateEvent {
    QString source;             // "engine" | "check" | "system" | "flatpak" | <modulo>
    QString operationId;
    QString rawType;
    UpdatePhase phase = UpdatePhase::Initializing;
    QString description;
    qint64 timestampMs = 0;
    UpdateSeverity severity = UpdateSeverity::Info;
    double progressPercent = -1.0;   // < 0 = nao confiavel/ausente (UI: indeterminado)
    qint64 bytesTransferred = -1;
    qint64 bytesTotal = -1;
    QString currentItem;
    UpdateResult result = UpdateResult::None;

    QVariantMap toVariantMap() const;
    static UpdateEvent fromVariantMap(const QVariantMap& map);
};

} // namespace Enthroned

Q_DECLARE_METATYPE(Enthroned::UpdateEvent)
