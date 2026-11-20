/*
 * Enthroned Settings - application entry point (F3.1).
 * Qt Quick/Kirigami application; backend objects are exposed as context
 * properties. Demo mode and the mutation gate come from CLI/env (never from
 * the UI itself) - see docs/architecture/ENTHRONED-UPDATE-ARCHITECTURE.md.
 * SPDX-License-Identifier: Apache-2.0
 */
#include <QCommandLineParser>
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>

#include <KLocalizedContext>
#include <KLocalizedString>

#include "bootcstatusprovider.h"
#include "deviceinfoprovider.h"
#include "flatpakupdatesprovider.h"
#include "kcmlauncher.h"
#include "personalizationcontroller.h"
#include "preferencemanager.h"
#include "profilecontroller.h"
#include "systemidentityprovider.h"
#include "update/updateengine.h"

int main(int argc, char* argv[])
{
    QApplication app(argc, argv);
    QGuiApplication::setOrganizationName(QStringLiteral("Enthroned OS"));
    QGuiApplication::setApplicationName(QStringLiteral("enthroned-settings"));
    QGuiApplication::setApplicationVersion(QStringLiteral("0.1.0"));
    QGuiApplication::setDesktopFileName(QStringLiteral("org.enthroned.settings"));

    QCommandLineParser cli;
    cli.setApplicationDescription(
        QStringLiteral("Enthroned Settings - central de configuracoes e atualizacoes do Enthroned OS"));
    cli.addHelpOption();
    cli.addVersionOption();
    QCommandLineOption demoOption(QStringList{ QStringLiteral("d"), QStringLiteral("demo") },
        QStringLiteral("Modo de demonstracao: dados ficticios, nenhuma acao real e executada."));
    QCommandLineOption demoScenarioOption(QStringLiteral("demo-scenario"),
        QStringLiteral("Cenario do modo demo (padrao: update-available)."), QStringLiteral("name"));
    cli.addOption(demoOption);
    cli.addOption(demoScenarioOption);
    cli.process(app);

    // C++ i18n() calls resolve the enthroned-settings catalog through the
    // application domain; the QML engine gets the same domain via KLocalizedContext.
    KLocalizedString::setApplicationDomain("enthroned-settings");

    // QML windows still need QApplication's widget style during teardown.
    QQmlApplicationEngine engine;
    auto* localized = new KLocalizedContext(&engine);
    localized->setTranslationDomain(QStringLiteral("enthroned-settings"));
    auto* context = engine.rootContext();
    context->setContextObject(localized);

    using namespace Enthroned;

    auto* identity = new SystemIdentityProvider(&engine);
    auto* flatpak = new FlatpakUpdatesProvider(QString(), &engine);
    auto* profiles = new ProfileController(&engine);
    auto* kcm = new KcmLauncher(&engine);
    auto* deviceInfo = new DeviceInfoProvider(&engine);
    auto* personalization = new PersonalizationController(&engine);
    auto* preferences = new PreferenceManager(&engine);
    auto* updates = new UpdateEngine(app.arguments(), nullptr, QString(), QString(),
                                     UpdateEngine::kDefaultWatchTimeoutMs,
                                     UpdateEngine::kDefaultPollIntervalMs, &engine);

    context->setContextProperty(QStringLiteral("identity"), identity);
    // One bootc status instance: the engine's, refreshed by updates->refreshAll().
    context->setContextProperty(QStringLiteral("bootc"), updates->bootc());
    context->setContextProperty(QStringLiteral("flatpakUpdates"), flatpak);
    context->setContextProperty(QStringLiteral("profiles"), profiles);
    context->setContextProperty(QStringLiteral("kcm"), kcm);
    context->setContextProperty(QStringLiteral("deviceInfo"), deviceInfo);
    context->setContextProperty(QStringLiteral("personalization"), personalization);
    context->setContextProperty(QStringLiteral("preferences"), preferences);
    context->setContextProperty(QStringLiteral("updates"), updates);

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     []() { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule(QStringLiteral("org.enthroned.settings"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

    // Initial read-only refreshes (nothing mutating happens at startup).
    kcm->refreshAvailable();
    profiles->refresh();
    deviceInfo->refresh(); // worker thread; the UI shows "Coletando…" until ready
    updates->refreshAll(); // includes the bootc status (no-op in demo mode)

    return app.exec();
}
