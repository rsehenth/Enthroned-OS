/*
 * Enthroned Welcome - first-run state controller implementation (F4.7).
 * SPDX-License-Identifier: Apache-2.0
 */
#include "welcomecontroller.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonParseError>
#include <QSaveFile>
#include <QStandardPaths>
#include <QDateTime>

namespace Enthroned {
namespace {

constexpr int kPersistenceVersion = 1;

QString specPath()
{
    return QStringLiteral(":/src/welcome-state-spec.json");
}

QString stateFilePath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
        + QStringLiteral("/enthroned-os/welcome-state.json");
}

QJsonObject loadSpec()
{
    QFile file(specPath());
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QJsonDocument::fromJson(file.readAll()).object();
}

} // namespace

WelcomeController::WelcomeController(bool demoMode, QObject* parent)
    : QObject(parent)
    , m_demoMode(demoMode)
{
    load();
}

bool WelcomeController::shouldShowOnLaunch(const QString& phase, const QString& source,
                                           bool alreadyRunning)
{
    if (alreadyRunning) {
        return false;
    }
    if (source == QLatin1String("manual")) {
        return true;
    }
    return phase != QLatin1String("completed") && phase != QLatin1String("dismissed");
}

QJsonObject WelcomeController::sanitize(const QJsonObject& raw)
{
    const QJsonObject spec = loadSpec();
    const QStringList states = [&spec]() {
        QStringList list;
        for (const auto& value : spec.value(QLatin1String("states")).toArray()) {
            list.append(value.toString());
        }
        return list;
    }();

    // The persisted record is trusted only as a whole: an unknown phase or a
    // wrong schema version resets everything to the initial state, so a
    // partially corrupted file can never mix fields from two lives.
    const QString rawPhase = raw.value(QLatin1String("phase")).toString();
    const bool coherent = raw.value(QLatin1String("version")).toInt(-1) == kPersistenceVersion
        && states.contains(rawPhase);

    QJsonObject clean;
    clean.insert(QStringLiteral("version"), kPersistenceVersion);
    clean.insert(QStringLiteral("phase"),
                 coherent ? rawPhase : spec.value(QLatin1String("initial")).toString());
    const int page = raw.value(QLatin1String("currentPage")).toInt(-1);
    clean.insert(QStringLiteral("currentPage"),
                 coherent && page >= 0 && page < WelcomeController::kPageCount ? page : 0);
    clean.insert(QStringLiteral("artcraftConsented"),
                 coherent ? raw.value(QLatin1String("artcraftConsented")).toBool(false) : false);
    const QString installState = raw.value(QLatin1String("artcraftInstallState")).toString();
    clean.insert(QStringLiteral("artcraftInstallState"),
                 coherent && QStringList{QStringLiteral("idle"), QStringLiteral("pending"),
                                         QStringLiteral("done"), QStringLiteral("failed")}
                             .contains(installState)
                     ? installState
                     : QStringLiteral("idle"));
    return clean;
}

void WelcomeController::load()
{
    if (m_demoMode) {
        m_phase = QStringLiteral("never-started");
        return;
    }
    QFile file(stateFilePath());
    QJsonObject raw;
    if (file.open(QIODevice::ReadOnly)) {
        QJsonParseError error;
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
        if (error.error == QJsonParseError::NoError && doc.isObject()) {
            raw = doc.object();
        }
        // Parse failures and wrong versions fall through to the initial state.
        if (raw.value(QLatin1String("version")).toInt(-1) != kPersistenceVersion) {
            raw = {};
        }
    }
    const QJsonObject clean = sanitize(raw);
    m_phase = clean.value(QLatin1String("phase")).toString();
    m_currentPage = clean.value(QLatin1String("currentPage")).toInt();
    m_artcraftConsented = clean.value(QLatin1String("artcraftConsented")).toBool();
    m_artcraftInstallState = clean.value(QLatin1String("artcraftInstallState")).toString();
}

void WelcomeController::save() const
{
    if (m_demoMode) {
        return;
    }
    const QString directory = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
        + QStringLiteral("/enthroned-os");
    QDir().mkpath(directory);

    QJsonObject clean;
    clean.insert(QStringLiteral("version"), kPersistenceVersion);
    clean.insert(QStringLiteral("phase"), m_phase);
    clean.insert(QStringLiteral("currentPage"), m_currentPage);
    clean.insert(QStringLiteral("artcraftConsented"), m_artcraftConsented);
    clean.insert(QStringLiteral("artcraftInstallState"), m_artcraftInstallState);
    clean.insert(QStringLiteral("updatedAt"),
                 QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    // Atomic write: QSaveFile writes a temporary file and renames it, so a
    // crash or power loss cannot corrupt the persisted state.
    QSaveFile file(stateFilePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    file.write(QJsonDocument(clean).toJson(QJsonDocument::Indented));
    file.commit();
}

void WelcomeController::touch()
{
    save();
    Q_EMIT stateChanged();
}

bool WelcomeController::applyEvent(const QString& event)
{
    const QJsonObject spec = loadSpec();
    const QJsonArray transitions = spec.value(QLatin1String("transitions")).toArray();
    for (const auto& value : transitions) {
        const QJsonObject transition = value.toObject();
        if (transition.value(QLatin1String("from")).toString() == m_phase
            && transition.value(QLatin1String("event")).toString() == event) {
            m_phase = transition.value(QLatin1String("to")).toString();
            return true;
        }
    }
    // Unmatched events keep the current state (same semantics as F3).
    return false;
}

void WelcomeController::notifyLaunched()
{
    const QString event = m_phase == QLatin1String("never-started")
        ? QStringLiteral("first-launch")
        : (m_phase == QLatin1String("interrupted") ? QStringLiteral("resume") : QString());
    if (!event.isEmpty()) {
        applyEvent(event);
    }
    touch();
}

void WelcomeController::goTo(int page)
{
    if (page < 0 || page >= pageCount() || page == m_currentPage) {
        return;
    }
    m_currentPage = page;
    touch();
}

void WelcomeController::next()
{
    goTo(m_currentPage + 1);
}

void WelcomeController::back()
{
    goTo(m_currentPage - 1);
}

void WelcomeController::finish()
{
    if (m_currentPage != pageCount() - 1) {
        return;
    }
    applyEvent(QStringLiteral("finish"));
    touch();
    Q_EMIT requestQuit();
}

void WelcomeController::dismiss()
{
    applyEvent(QStringLiteral("dismiss"));
    touch();
    Q_EMIT requestQuit();
}

void WelcomeController::markClosed()
{
    applyEvent(QStringLiteral("close"));
    touch();
    Q_EMIT requestQuit();
}

void WelcomeController::consentArtcraft()
{
    m_artcraftConsented = true;
    if (m_artcraftInstallState == QLatin1String("idle")) {
        m_artcraftInstallState = QStringLiteral("pending");
    }
    applyEvent(QStringLiteral("artcraft-consent"));
    touch();
}

void WelcomeController::declineArtcraft()
{
    m_artcraftConsented = false;
    m_artcraftInstallState = QStringLiteral("idle");
    applyEvent(QStringLiteral("artcraft-decline"));
    touch();
}

void WelcomeController::retryArtcraft()
{
    if (!m_artcraftConsented) {
        return;
    }
    m_artcraftInstallState = QStringLiteral("pending");
    applyEvent(QStringLiteral("artcraft-retry"));
    touch();
}

void WelcomeController::artcraftFinished(bool ok)
{
    if (!m_artcraftConsented) {
        return;
    }
    applyEvent(ok ? QStringLiteral("artcraft-success") : QStringLiteral("artcraft-failure"));
    m_artcraftInstallState = ok ? QStringLiteral("done") : QStringLiteral("failed");
    touch();
}

} // namespace Enthroned
