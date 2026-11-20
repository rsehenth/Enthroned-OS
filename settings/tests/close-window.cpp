// Close the real Settings window without adding a test entry point to the app.
// SPDX-License-Identifier: Apache-2.0
#include <QCoreApplication>
#include <QGuiApplication>
#include <QPointer>
#include <QQuickWindow>
#include <QTimer>

#include <cstdio>
#include <cstdlib>

static QPointer<QQuickWindow> settingsWindow;

static void checkWindowDestroyed()
{
    if (settingsWindow) {
        std::fputs("Settings window survived until QApplication teardown\n", stderr);
        std::_Exit(EXIT_FAILURE);
    }
}

static void closeSettingsWindow()
{
    QTimer::singleShot(0, [] {
        const auto windows = QGuiApplication::topLevelWindows();
        for (QWindow *window : windows) {
            auto *quickWindow = qobject_cast<QQuickWindow *>(window);
            if (quickWindow && quickWindow->isVisible()) {
                settingsWindow = quickWindow;
                qAddPostRoutine(checkWindowDestroyed);
                if (!window->close()) {
                    QCoreApplication::exit(2);
                }
                return;
            }
        }
        QCoreApplication::exit(3);
    });
}

Q_COREAPP_STARTUP_FUNCTION(closeSettingsWindow)
