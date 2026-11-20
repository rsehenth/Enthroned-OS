/*
 * Enthroned Welcome - optional ArtCraft Launcher installer implementation.
 * See the security contract in artcraftinstaller.h before touching anything.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "artcraftinstaller.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrl>

#include <KLocalizedString>

namespace Enthroned {
namespace {

constexpr auto kApiReleasesUrl =
    "https://api.github.com/repos/storytold/craft-launcher/releases/latest";
constexpr auto kAppId = "ai.storyteller.artcraft-launcher";
constexpr auto kGateEnv = "ENTHRONED_WELCOME_ALLOW_INSTALL";
constexpr auto kPolicyFile = "/usr/share/enthroned-os/install-policy.json";
constexpr auto kUserAgent = "enthroned-welcome/0.1 (Enthroned OS)";

QByteArray fetchResource(const QString& path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return file.readAll();
}

} // namespace

ArtcraftInstaller::ArtcraftInstaller(bool demoMode, const QString& demoScenario, QObject* parent)
    : QObject(parent)
    , m_demoMode(demoMode)
    , m_demoScenario(demoScenario)
{
    m_flatpakPresent = !QStandardPaths::findExecutable(QStringLiteral("flatpak")).isEmpty();
}

bool ArtcraftInstaller::policyAllows()
{
    // Shipped policy file: the Lote 6 contract (official GitHub source, SHA-256
    // verified bundle, user-level Flatpak, explicit consent, progress, failure
    // and cancellation) is validated, so the image opens the gate. Removing or
    // flipping the file locks the optional install again without code changes.
    const QByteArray raw = fetchResource(QString::fromUtf8(kPolicyFile));
    if (raw.isEmpty()) {
        return false;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(raw);
    return doc.object().value(QLatin1String("allowArtcraftInstall")).toBool(false);
}

bool ArtcraftInstaller::gateOpen() const
{
    return qEnvironmentVariableIntValue(kGateEnv) == 1 || policyAllows();
}

bool ArtcraftInstaller::launcherInstalled() const
{
    return !QStandardPaths::locate(QStandardPaths::ApplicationsLocation,
                                   QStringLiteral("%1.desktop").arg(QLatin1String(kAppId)))
                .isEmpty();
}

QString ArtcraftInstaller::assetArch()
{
    // Release asset names use x86_64 / aarch64 (project README, verified).
    const QString arch = QSysInfo::currentCpuArchitecture();
    if (arch == QLatin1String("x86_64")) {
        return QStringLiteral("x86_64");
    }
    if (arch == QLatin1String("arm64") || arch == QLatin1String("aarch64")) {
        return QStringLiteral("aarch64");
    }
    return arch;
}

void ArtcraftInstaller::setState(const QString& state, const QString& message, int progress)
{
    if (!state.isNull()) {
        m_state = state;
    }
    if (!message.isNull()) {
        m_message = message;
    }
    m_progress = progress;
    Q_EMIT stateChanged();
    if (state == QLatin1String("done") || state == QLatin1String("failed")
        || state == QLatin1String("blocked") || state == QLatin1String("cancelled")) {
        m_running = false;
        m_currentReply.clear();
        m_currentProcess = nullptr;
        Q_EMIT finished(state == QLatin1String("done"), m_message);
        Q_EMIT availabilityChanged();
    }
}

void ArtcraftInstaller::cancel()
{
    if (!m_running) {
        return;
    }
    m_cancelRequested = true;
    if (m_currentReply) {
        m_currentReply->abort();
    }
    if (m_currentProcess) {
        m_currentProcess->terminate();
        if (!m_currentProcess->waitForFinished(2000)) {
            m_currentProcess->kill();
        }
    }
    setState(QStringLiteral("cancelled"),
             i18n("The installation was canceled. Nothing on the system was changed."));
}

void ArtcraftInstaller::install()
{
    if (m_running) {
        return;
    }
    if (!m_flatpakPresent) {
        setState(QStringLiteral("failed"),
                 i18n("Flatpak is not available on this system."));
        return;
    }
    if (launcherInstalled()) {
        setState(QStringLiteral("done"),
                 i18n("ArtCraft Launcher is already installed on this system."));
        return;
    }
    if (!gateOpen()) {
        // Honest blocked state: no consent bypass, no network access.
        setState(QStringLiteral("blocked"),
                 i18n("The ArtCraft Launcher installation is disabled at this stage of "
                      "Enthroned OS (under security review). You can install it later "
                      "from Settings or directly from the project's official page."));
        return;
    }
    m_running = true;
    m_cancelRequested = false;
    if (m_demoMode) {
        runDemoScenario();
        return;
    }
    startReal();
}

void ArtcraftInstaller::reset()
{
    if (m_running) {
        return;
    }
    setState(QStringLiteral("idle"), QString(), -1);
}

void ArtcraftInstaller::maybeCreateDesktopShortcut()
{
    if (m_demoMode) {
        return;
    }
    const QSettings prefs(
        QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
            + QStringLiteral("/enthroned-os/preferences.conf"),
        QSettings::IniFormat);
    if (!prefs.value(QStringLiteral("General/CreateDesktopShortcuts"), true).toBool()) {
        return;
    }
    const QString helper =
        QStandardPaths::findExecutable(QStringLiteral("enthroned-desktop-shortcut"));
    if (helper.isEmpty()) {
        return;
    }
    QProcess::startDetached(helper, { QStringLiteral("--if-enabled"),
                                      QStringLiteral("%1.desktop").arg(QLatin1String(kAppId)) });
}

void ArtcraftInstaller::startReal()
{
    setState(QStringLiteral("checking"),
             i18n("Querying the official ArtCraft Launcher release…"));

    QNetworkRequest request{ QUrl(QString::fromUtf8(kApiReleasesUrl)) };
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/vnd.github+json"));
    request.setRawHeader(QByteArrayLiteral("User-Agent"), QByteArray(kUserAgent));

    QNetworkReply* reply = m_nam.get(request);
    m_currentReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        m_currentReply.clear();
        if (m_cancelRequested) {
            return; // cancel() already reported the final state.
        }
        if (reply->error() != QNetworkReply::NoError) {
            setState(QStringLiteral("failed"),
                     i18n("Could not query the official release (no internet or "
                          "service unavailable): %1")
                         .arg(reply->errorString()));
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        const QJsonObject release = doc.object();
        const QString tag = release.value(QLatin1String("tag_name")).toString();
        const QJsonArray assets = release.value(QLatin1String("assets")).toArray();
        QString bundleUrl;
        QString sumsUrl;
        const QString arch = assetArch();
        const QRegularExpression bundlePattern(
            QStringLiteral("^artcraft-launcher-.*-linux-%1\\.flatpak$").arg(arch));
        for (const auto& assetValue : assets) {
            const QJsonObject asset = assetValue.toObject();
            const QString name = asset.value(QLatin1String("name")).toString();
            if (bundlePattern.match(name).hasMatch()) {
                bundleUrl = asset.value(QLatin1String("browser_download_url")).toString();
            } else if (name == QLatin1String("SHA256SUMS.txt")) {
                sumsUrl = asset.value(QLatin1String("browser_download_url")).toString();
            }
        }
        if (bundleUrl.isEmpty() || sumsUrl.isEmpty()) {
            setState(QStringLiteral("failed"),
                     i18n("No Flatpak %1 package in release %2.")
                         .arg(assetArch(), tag.isEmpty() ? i18n("(unknown)") : tag));
            return;
        }

        QTemporaryDir* temp = new QTemporaryDir;
        if (!temp->isValid()) {
            delete temp;
            setState(QStringLiteral("failed"), i18n("No usable temporary folder."));
            return;
        }
        const QString bundlePath = temp->filePath(QStringLiteral("artcraft-launcher.flatpak"));
        const QString sumsPath = temp->filePath(QStringLiteral("SHA256SUMS.txt"));

        // SHA256SUMS first (small), then the bundle with progress.
        setState(QStringLiteral("downloading"), i18n("Downloading ArtCraft Launcher…"), 0);
        QNetworkReply* sumsReply = m_nam.get(QNetworkRequest(QUrl(sumsUrl)));
        m_currentReply = sumsReply;
        connect(sumsReply, &QNetworkReply::finished, this, [this, sumsReply, sumsPath, bundleUrl, bundlePath, temp]() {
            sumsReply->deleteLater();
            m_currentReply.clear();
            if (m_cancelRequested) {
                delete temp;
                return; // cancel() already reported the final state.
            }
            if (sumsReply->error() != QNetworkReply::NoError) {
                delete temp;
                setState(QStringLiteral("failed"),
                         i18n("Failed to download the official checksums: %1")
                             .arg(sumsReply->errorString()));
                return;
            }
            {
                QFile sumsFile(sumsPath);
                if (!sumsFile.open(QIODevice::WriteOnly | QIODevice::Truncate)
                    || sumsFile.write(sumsReply->readAll()) < 0) {
                    delete temp;
                    setState(QStringLiteral("failed"), i18n("Failed to save the checksums."));
                    return;
                }
            }
            QNetworkReply* bundleReply = m_nam.get(QNetworkRequest(QUrl(bundleUrl)));
            m_currentReply = bundleReply;
            connect(bundleReply, &QNetworkReply::downloadProgress, this,
                    [this](qint64 received, qint64 total) {
                        if (total > 0) {
                            setState(QString(), QString(),
                                     static_cast<int>(received * 100 / total));
                        }
                    });
            connect(bundleReply, &QNetworkReply::finished, this,
                    [this, bundleReply, bundlePath, sumsPath, bundleUrl, temp]() {
                        bundleReply->deleteLater();
                        m_currentReply.clear();
                        if (m_cancelRequested) {
                            delete temp;
                            return; // cancel() already reported the final state.
                        }
                        if (bundleReply->error() != QNetworkReply::NoError) {
                            delete temp;
                            setState(QStringLiteral("failed"),
                                     i18n("Download failed: %1").arg(bundleReply->errorString()));
                            return;
                        }
                        {
                            QSaveFile bundleFile(bundlePath);
                            if (!bundleFile.open(QIODevice::WriteOnly | QIODevice::Truncate)
                                || bundleFile.write(bundleReply->readAll()) < 0 || !bundleFile.commit()) {
                                delete temp;
                                setState(QStringLiteral("failed"), i18n("Failed to save the downloaded package."));
                                return;
                            }
                        }
                        // Verify the SHA-256 of the exact downloaded asset against
                        // the official SHA256SUMS (releases ship one bundle per arch).
                        setState(QStringLiteral("verifying"),
                                 i18n("Verifying the package (SHA-256)…"));
                        QCryptographicHash hash(QCryptographicHash::Sha256);
                        {
                            QFile bundleFile(bundlePath);
                            if (!bundleFile.open(QIODevice::ReadOnly)) {
                                delete temp;
                                setState(QStringLiteral("failed"), i18n("The downloaded package is unreadable."));
                                return;
                            }
                            hash.addData(&bundleFile);
                        }
                        const QString digest =
                            QString::fromLatin1(hash.result().toHex()).toLower();
                        const QString bundleName = QUrl(bundleUrl).fileName();
                        QString expected;
                        const QRegularExpression linePattern(QStringLiteral("^(%1)\\s+\\*?%2$")
                                                                 .arg(QStringLiteral("[0-9a-fA-F]{64}"),
                                                                      QRegularExpression::escape(bundleName)));
                        const QStringList lines =
                            QString::fromUtf8(fetchResource(sumsPath)).split(QLatin1Char('\n'));
                        for (const QString& line : lines) {
                            const auto match = linePattern.match(line.trimmed());
                            if (match.hasMatch()) {
                                expected = match.captured(1).toLower();
                                break;
                            }
                        }
                        if (expected.isEmpty() || digest != expected) {
                            delete temp;
                            setState(QStringLiteral("failed"),
                                     i18n("The SHA-256 verification failed. The download was "
                                          "discarded for safety."));
                            return;
                        }

                        setState(QStringLiteral("installing"),
                                 i18n("Installing into the user profile (Flatpak)…"));
                        auto* process = new QProcess(this);
                        m_currentProcess = process;
                        process->setProgram(QStandardPaths::findExecutable(QStringLiteral("flatpak")));
                        process->setArguments({ QStringLiteral("install"), QStringLiteral("--user"),
                                                QStringLiteral("--noninteractive"), bundlePath });
                        connect(process, &QProcess::finished, this,
                                [this, process, temp](int exitCode, QProcess::ExitStatus) {
                                    const QString errors =
                                        QString::fromUtf8(process->readAllStandardError());
                                    process->deleteLater();
                                    m_currentProcess = nullptr;
                                    delete temp;
                                    if (m_cancelRequested) {
                                        return; // cancel() already reported the final state.
                                    }
                                    if (exitCode != 0) {
                                        setState(QStringLiteral("failed"),
                                                 i18n("The Flatpak installation failed: %1")
                                                     .arg(errors.trimmed()));
                                        return;
                                    }
                                    if (!launcherInstalled()) {
                                        setState(QStringLiteral("failed"),
                                                 i18n("The installation finished, but the "
                                                      "application was not found."));
                                        return;
                                    }
                                    setState(QStringLiteral("done"),
                                             i18n("ArtCraft Launcher installed."));
                                    maybeCreateDesktopShortcut();
                                });
                        // FailedToStart never emits finished(); without this the UI stays in "installing".
                        connect(process, &QProcess::errorOccurred, this,
                                [this, process, temp](QProcess::ProcessError error) {
                                    if (error != QProcess::FailedToStart) {
                                        return;
                                    }
                                    process->deleteLater();
                                    m_currentProcess = nullptr;
                                    delete temp;
                                    setState(QStringLiteral("failed"),
                                             i18n("Could not start flatpak."));
                                });
                        process->start();
                    });
        });
    });
}

void ArtcraftInstaller::runDemoScenario()
{
    // Demo: replay the fixture scenario against the same contract states, with
    // no network access and no real installation.
    const QByteArray raw =
        fetchResource(QStringLiteral(":/src/demo/scenarios/%1.json").arg(m_demoScenario));
    const QJsonDocument doc = QJsonDocument::fromJson(raw);
    const QJsonArray steps = doc.object().value(QLatin1String("steps")).toArray();
    const QString name = doc.object().value(QLatin1String("name")).toString();
    setState(QStringLiteral("idle"), i18n("Demo mode: %1").arg(name));
    m_running = true;
    int delay = 0;
    for (const auto& stepValue : steps) {
        const QJsonObject step = stepValue.toObject();
        delay += 400;
        QTimer::singleShot(delay, this, [this, step]() {
            setState(step.value(QLatin1String("state")).toString(),
                     step.value(QLatin1String("message")).toString(),
                     step.value(QLatin1String("progress")).toInt(-1));
        });
    }
    QTimer::singleShot(delay + 400, this, [this]() { m_running = false; });
}

} // namespace Enthroned
