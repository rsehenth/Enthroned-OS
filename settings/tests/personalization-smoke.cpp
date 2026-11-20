/*
 * Lote 15: PersonalizationController against the real kwriteconfig6 /
 * kreadconfig6 (isolated HOME/XDG dirs) and a fake plasma-apply-colorscheme.
 * Covers: allowlist rejection, set/read/restore of kdeglobals, kwinrc and
 * Dolphin view properties (incl. the BorderSizeAuto companion key), folder
 * colours through .directory (restore only removes what this feature wrote),
 * accent persistence and re-application after a scheme change, and the accent
 * reset sequence. Plasma itself is NOT started: the Plasma-scripting setters are
 * not exercised here. Skips (exit 77) when the KDE config tools are missing.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "personalizationcontroller.h"

#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileDevice>
#include <QGuiApplication>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTextStream>
#include <QTimer>

#include <functional>
#include <iostream>

using Enthroned::PersonalizationController;

static int g_failures = 0;
static void check(const char* name, bool ok)
{
    std::cout << (ok ? "PASS: " : "FAIL: ") << name << std::endl;
    if (!ok) {
        ++g_failures;
    }
}

static QString readKey(const QString& file, const QString& group, const QString& key)
{
    QProcess process;
    process.start(QStringLiteral("kreadconfig6"),
                  { QStringLiteral("--file"), file, QStringLiteral("--group"), group, QStringLiteral("--key"), key });
    process.waitForFinished(4000);
    return QString::fromUtf8(process.readAllStandardOutput()).trimmed();
}

// Runs a controller operation and waits for its applyFinished (also when it is
// emitted synchronously, e.g. a rejected argument); returns that ok flag.
static bool runOp(PersonalizationController& controller, const std::function<void()>& action)
{
    QEventLoop loop;
    bool ok = false;
    bool gotSignal = false;
    QObject::connect(&controller, &PersonalizationController::applyFinished, &loop, [&](bool result, const QString&) {
        ok = result;
        gotSignal = true;
        loop.quit();
    });
    action();
    if (!gotSignal) {
        QTimer::singleShot(8000, &loop, &QEventLoop::quit);
        loop.exec();
    }
    return ok && gotSignal;
}

int main(int argc, char** argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QTemporaryDir home;
    QTemporaryDir bin;
    QTemporaryDir data;
    if (!home.isValid() || !bin.isValid() || !data.isValid()) {
        return 2;
    }
    const QString homePath = home.path();
    qputenv("HOME", homePath.toUtf8());
    qputenv("XDG_CONFIG_HOME", (homePath + QStringLiteral("/config")).toUtf8());
    qputenv("XDG_DATA_HOME", (homePath + QStringLiteral("/share")).toUtf8());
    qputenv("XDG_DATA_DIRS", data.path().toUtf8());
    QDir().mkpath(homePath + QStringLiteral("/config"));
    QDir().mkpath(data.path() + QStringLiteral("/color-schemes"));
    for (const char* scheme : { "EnthronedLight", "EnthronedDark" }) {
        QFile file(data.path() + QStringLiteral("/color-schemes/") + QLatin1String(scheme) + QStringLiteral(".colors"));
        file.open(QIODevice::WriteOnly);
        file.write("[General]\n");
    }
    // Fake plasma-apply-colorscheme: logs its arguments, always succeeds.
    const QString log = bin.path() + QStringLiteral("/apply.log");
    {
        QFile tool(bin.path() + QStringLiteral("/plasma-apply-colorscheme"));
        tool.open(QIODevice::WriteOnly);
        tool.write(QStringLiteral("#!/bin/sh\necho \"$*\" >> \"%1\"\n").arg(log).toUtf8());
        tool.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    }
    qputenv("PATH", (bin.path() + QLatin1Char(':') + QString::fromUtf8(qgetenv("PATH"))).toUtf8());

    if (QStandardPaths::findExecutable(QStringLiteral("kwriteconfig6")).isEmpty()
        || QStandardPaths::findExecutable(QStringLiteral("kreadconfig6")).isEmpty()) {
        std::cout << "SKIP: kwriteconfig6/kreadconfig6 not installed" << std::endl;
        return 77;
    }

    QGuiApplication app(argc, argv);
    PersonalizationController controller;
    const QString dolphinFile = homePath + QStringLiteral("/share/dolphin/view_properties/global/.directory");
    auto logLines = [&]() {
        QFile file(log);
        if (!file.open(QIODevice::ReadOnly)) {
            return QStringList();
        }
        return QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    };

    const QVariantList choices = controller.accentChoices();
    check("accent palette: default + 7 colours, default first", choices.size() == 8
          && choices.first().toMap().value(QStringLiteral("id")).toString().isEmpty());

    // --- allowlist ---------------------------------------------------------
    check("unknown setting id rejected", !controller.setValue(QStringLiteral("nope"), QStringLiteral("1")));
    check("value outside the allowed set rejected", !controller.setValue(QStringLiteral("animations"), QStringLiteral("7")));
    check("rejected value wrote nothing", controller.value(QStringLiteral("animations")).isEmpty());

    // --- kdeglobals / kwinrc ----------------------------------------------
    check("animations 0.5 saved", controller.setValue(QStringLiteral("animations"), QStringLiteral("0.5"))
          && readKey(QStringLiteral("kdeglobals"), QStringLiteral("KDE"), QStringLiteral("AnimationDurationFactor")) == QLatin1String("0.5")
          && controller.value(QStringLiteral("animations")) == QLatin1String("0.5"));
    check("animations restored to default (key deleted)", controller.resetValue(QStringLiteral("animations"))
          && controller.value(QStringLiteral("animations")).isEmpty());
    check("border size writes the key and BorderSizeAuto=false",
          controller.setValue(QStringLiteral("borderSize"), QStringLiteral("Tiny"))
          && readKey(QStringLiteral("kwinrc"), QStringLiteral("org.kde.kdecoration2"), QStringLiteral("BorderSize")) == QLatin1String("Tiny")
          && readKey(QStringLiteral("kwinrc"), QStringLiteral("org.kde.kdecoration2"), QStringLiteral("BorderSizeAuto")) == QLatin1String("false"));
    check("border size restore removes both keys", controller.resetValue(QStringLiteral("borderSize"))
          && readKey(QStringLiteral("kwinrc"), QStringLiteral("org.kde.kdecoration2"), QStringLiteral("BorderSize")).isEmpty()
          && readKey(QStringLiteral("kwinrc"), QStringLiteral("org.kde.kdecoration2"), QStringLiteral("BorderSizeAuto")).isEmpty());

    // --- Dolphin view properties ------------------------------------------
    check("view mode saved in [Dolphin] of the global view properties",
          controller.setValue(QStringLiteral("viewMode"), QStringLiteral("2"))
          && readKey(dolphinFile, QStringLiteral("Dolphin"), QStringLiteral("ViewMode")) == QLatin1String("2"));
    check("hidden files saved as a real boolean", controller.setValue(QStringLiteral("showHidden"), QStringLiteral("true"))
          && readKey(dolphinFile, QStringLiteral("Dolphin"), QStringLiteral("HiddenFilesShown")) == QLatin1String("true"));
    check("icon size outside the allowed set rejected", !controller.setValue(QStringLiteral("iconSize"), QStringLiteral("33")));
    check("Dolphin keys restored", controller.resetValue(QStringLiteral("viewMode"))
          && controller.resetValue(QStringLiteral("showHidden"))
          && readKey(dolphinFile, QStringLiteral("Dolphin"), QStringLiteral("ViewMode")).isEmpty());

    // --- folder colour -----------------------------------------------------
    QTemporaryDir folder;
    const QUrl folderUrl = QUrl::fromLocalFile(folder.path());
    check("invalid folder colour rejected", !controller.setFolderColor(folderUrl, QStringLiteral("pink")));
    check("folder colour writes Icon=folder-red", controller.setFolderColor(folderUrl, QStringLiteral("red"))
          && readKey(folder.path() + QStringLiteral("/.directory"), QStringLiteral("Desktop Entry"), QStringLiteral("Icon")) == QLatin1String("folder-red")
          && controller.folderColor(folderUrl) == QLatin1String("red"));
    check("folder colour restore removes the key and the empty file", controller.setFolderColor(folderUrl, QString())
          && !QFile::exists(folder.path() + QStringLiteral("/.directory")) && controller.folderColor(folderUrl).isEmpty());
    {
        QFile custom(folder.path() + QStringLiteral("/.directory"));
        custom.open(QIODevice::WriteOnly);
        custom.write("[Desktop Entry]\nIcon=my-own-icon\n");
    }
    check("restore never removes a custom (non-colour) icon", controller.setFolderColor(folderUrl, QString())
          && readKey(folder.path() + QStringLiteral("/.directory"), QStringLiteral("Desktop Entry"), QStringLiteral("Icon")) == QLatin1String("my-own-icon"));
    check("non-folder rejected", !controller.setFolderColor(QUrl::fromLocalFile(folder.path() + QStringLiteral("/.directory")), QStringLiteral("red")));

    // --- accent + scheme ---------------------------------------------------
    check("accent applied through --accent-color with the palette hex",
          runOp(controller, [&] { controller.applyAccent(QStringLiteral("red")); })
          && logLines().contains(QStringLiteral("--accent-color #B8323F")) && controller.accent() == QLatin1String("red"));
    check("accent persisted with id and hex (read by enthroned-profile)",
          readKey(QStringLiteral("enthronedpersonalizationrc"), QStringLiteral("Accent"), QStringLiteral("Id")) == QLatin1String("red")
          && readKey(QStringLiteral("enthronedpersonalizationrc"), QStringLiteral("Accent"), QStringLiteral("Hex")) == QLatin1String("#B8323F"));
    check("unknown accent rejected without running a tool",
          !runOp(controller, [&] { controller.applyAccent(QStringLiteral("not-a-colour")); }) && logLines().size() == 1);
    {
        QFile(log).remove();
        const bool ok = runOp(controller, [&] { controller.applyScheme(QStringLiteral("dark")); });
        const QStringList lines = logLines();
        check("scheme change passes the file id, then re-applies the accent",
              ok && lines == QStringList({ QStringLiteral("EnthronedDark"), QStringLiteral("--accent-color #B8323F") }));
    }
    {
        QFile(log).remove();
        const bool ok = runOp(controller, [&] { controller.applyAccent(QString()); });
        // offscreen palette is light: reset = other scheme (dark) then back to the current (light)
        check("accent reset switches scheme away and back", ok
              && logLines() == QStringList({ QStringLiteral("EnthronedDark"), QStringLiteral("EnthronedLight") }));
        check("accent reset clears the stored choice", controller.accent().isEmpty()
              && readKey(QStringLiteral("enthronedpersonalizationrc"), QStringLiteral("Accent"), QStringLiteral("Hex")).isEmpty());
    }
    check("the display name with a space is never passed to the tool",
          !logLines().join(QLatin1Char('\n')).contains(QStringLiteral("Enthroned Light")));

    return g_failures == 0 ? 0 : 1;
}
