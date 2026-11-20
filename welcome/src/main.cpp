/*
 * Enthroned Welcome - application entry point (F4.4/F4.7).
 * Launched by XDG autostart with --autostart on every graphical login; the
 * per-user persisted state decides whether the window shows (first login,
 * interrupted walkthrough, pending optional install) or the process exits
 * silently (completed or dismissed walkthrough). Manual launches always show. A lock file
 * guarantees a single instance. No network access happens on startup.
 * SPDX-License-Identifier: Apache-2.0
 */
#include <QCommandLineParser>
#include <QApplication>
#include <QLockFile>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStandardPaths>

#include <KLocalizedContext>
#include <KLocalizedString>

#include "appavailability.h"
#include "artcraftinstaller.h"
#include "profilebridge.h"
#include "welcomecontroller.h"

int main(int argc, char* argv[])
{
    QApplication app(argc, argv);
    QGuiApplication::setOrganizationName(QStringLiteral("Enthroned OS"));
    QGuiApplication::setApplicationName(QStringLiteral("enthroned-welcome"));
    QGuiApplication::setApplicationVersion(QStringLiteral("0.1.0"));
    QGuiApplication::setDesktopFileName(QStringLiteral("org.enthroned.welcome"));

    QCommandLineParser cli;
    cli.setApplicationDescription(
        QStringLiteral("Enthroned Welcome - assistente de primeira experiencia do Enthroned OS"));
    cli.addHelpOption();
    cli.addVersionOption();
    QCommandLineOption autostartOption(QStringLiteral("autostart"),
        QStringLiteral("Executado pelo XDG autostart; so abre conforme o estado por usuario."));
    QCommandLineOption reopenOption(QStringList{ QStringLiteral("reopen"), QStringLiteral("manual") },
        QStringLiteral("Abertura manual: sempre abre, mesmo apos concluido (revisita)."));
    QCommandLineOption demoOption(QStringList{ QStringLiteral("d"), QStringLiteral("demo") },
        QStringLiteral("Modo demonstracao: nenhuma instalacao real e executada."));
    QCommandLineOption demoScenarioOption(QStringLiteral("demo-scenario"),
        QStringLiteral("Cenario do modo demo (padrao: install-complete)."), QStringLiteral("name"),
        QStringLiteral("install-complete"));
    cli.addOption(autostartOption);
    cli.addOption(reopenOption);
    cli.addOption(demoOption);
    cli.addOption(demoScenarioOption);
    cli.process(app);

    const bool autostart = cli.isSet(autostartOption);
    const bool manual = cli.isSet(reopenOption);

    // Single instance: a second process exits without showing anything.
    QLockFile lock(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
                   + QStringLiteral("/enthroned-welcome.lock"));
    if (!lock.tryLock(0)) {
        if (autostart) {
            return 0;
        }
        fprintf(stderr, "enthroned-welcome: já está em execução.\n");
        return 0;
    }

    using namespace Enthroned;

    // C++ i18n() calls resolve the enthroned-welcome catalog through the
    // application domain; the QML engine gets the same domain via KLocalizedContext.
    KLocalizedString::setApplicationDomain("enthroned-welcome");

    WelcomeController controller(cli.isSet(demoOption));
    const QString source = autostart && !manual ? QStringLiteral("autostart") : QStringLiteral("manual");
    if (!WelcomeController::shouldShowOnLaunch(controller.phase(), source, false)) {
        return 0;
    }
    controller.notifyLaunched();

    auto* engine = new QQmlApplicationEngine(&app);
    auto* localized = new KLocalizedContext(engine);
    localized->setTranslationDomain(QStringLiteral("enthroned-welcome"));
    engine->rootContext()->setContextObject(localized);

    auto* profiles = new ProfileBridge(engine);
    auto* apps = new AppAvailability(engine);
    auto* artcraft = new ArtcraftInstaller(cli.isSet(demoOption), cli.value(demoScenarioOption), engine);
    QObject::connect(artcraft, &ArtcraftInstaller::finished, &controller,
                     &WelcomeController::artcraftFinished);
    QObject::connect(&controller, &WelcomeController::requestQuit, &app, &QGuiApplication::quit);

    engine->rootContext()->setContextProperty(QStringLiteral("welcome"), &controller);
    engine->rootContext()->setContextProperty(QStringLiteral("profiles"), profiles);
    engine->rootContext()->setContextProperty(QStringLiteral("apps"), apps);
    engine->rootContext()->setContextProperty(QStringLiteral("artcraft"), artcraft);

    QObject::connect(engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     []() { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine->loadFromModule(QStringLiteral("org.enthroned.welcome"), QStringLiteral("Main"));
    if (engine->rootObjects().isEmpty()) {
        return 1;
    }

    // Read-only initial refreshes; nothing mutating happens at startup.
    profiles->refresh();

    const int code = app.exec();
    // The engine is parented to app, which outlives `controller`; destroy it first so
    // QML bindings on `welcome` never re-evaluate against a destroyed controller (TypeError on exit).
    delete engine;
    return code;
}
