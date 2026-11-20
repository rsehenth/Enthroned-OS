/*
 * Enthroned Settings - personalization controller implementation.
 * SPDX-License-Identifier: Apache-2.0
 */
#include "personalizationcontroller.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QPalette>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantMap>

#include <KLocalizedString>

namespace Enthroned {

namespace {

struct Scheme {
    const char* id;
    const char* name;      // value passed to plasma-apply-colorscheme: the FILE id, not the display name
    const char* fileName;  // color-schemes/<file> under XDG data dirs
};
// Lote 15: plasma-apply-colorscheme only accepts the colour-scheme file id
// ("EnthronedLight"); the display name with a space ("Enthroned Light") is
// rejected with 'Could not find theme' (checked against Plasma 26.08).
constexpr Scheme kSchemes[] = {
    { "light", "EnthronedLight", "color-schemes/EnthronedLight.colors" },
    { "dark", "EnthronedDark", "color-schemes/EnthronedDark.colors" },
};

struct Wallpaper {
    const char* id;
    const char* path;
};
constexpr Wallpaper kWallpapers[] = {
    // Lote 13: the three official wallpapers, shipped unmodified at the size of
    // the originals (1672x941); Plasma scales them to the screen.
    { "soberania", "/usr/share/wallpapers/EnthronedSoberania/contents/images/1672x941.png" },
    { "ascensao", "/usr/share/wallpapers/EnthronedAscensao/contents/images/1672x941.png" },
    { "vigilia", "/usr/share/wallpapers/EnthronedVigilia/contents/images/1672x941.png" },
};

// Lote 15: accent palette. Every colour keeps >= 4.5:1 against white text (the
// selection foreground), measured in docs/validation/LOTE-15-FINAL-VISUAL-POLISH.md.
struct Accent {
    const char* id;
    const char* hex;
};
constexpr Accent kAccents[] = {
    { "magenta", "#A82A8F" }, { "red", "#B8323F" },   { "orange", "#B85A1F" }, { "gold", "#8F6A12" },
    { "green", "#2A7F5A" },   { "teal", "#1B7F8C" },  { "blue", "#2F63C7" },
};

// Swatch shown for "the scheme's own accent" (EnthronedLight's selection colour).
constexpr const char* kDefaultAccentSwatch = "#6F26A8";

// The 11 colours Dolphin's "Set folder icon" action offers (Breeze folder-<colour>).
constexpr const char* kFolderColours[] = { "black", "blue", "brown", "cyan", "green", "grey",
                                           "magenta", "orange", "red", "violet", "yellow" };

// Allowlisted KConfig-backed settings. file "@dolphin" is Dolphin's global view
// properties (dolphinrc has GlobalViewProps=true). Unset key == default.
struct Setting {
    const char* id;
    const char* file;
    const char* group;      // '/' separates nested groups
    const char* key;
    const char* allowed;    // '|' separated closed set of values
    bool isBool;
    const char* companionKey;    // written next to the key (kwin: BorderSizeAuto=false)
    const char* companionValue;
    bool reloadKWin;
};
constexpr Setting kSettings[] = {
    // kdeglobals [KDE] AnimationDurationFactor: what Colors & Themes > Animation speed writes.
    { "animations", "kdeglobals", "KDE", "AnimationDurationFactor", "0|0.5", false, nullptr, nullptr, false },
    // kwinrc [org.kde.kdecoration2]: what Window Decorations > Window border size writes.
    { "borderSize", "kwinrc", "org.kde.kdecoration2", "BorderSize", "Tiny|Normal|Large", false,
      "BorderSizeAuto", "false", true },
    // Dolphin ViewProperties: group [Dolphin] (the one enthroned-files-setup seeds);
    // ViewMode 0 icons, 1 details (Enthroned default), 2 compact.
    { "viewMode", "@dolphin", "Dolphin", "ViewMode", "0|1|2", false, nullptr, nullptr, false },
    { "iconSize", "@dolphin", "Dolphin", "IconSize", "16|22|32|48|64|96|128", false, nullptr, nullptr, false },
    { "showHidden", "@dolphin", "Dolphin", "HiddenFilesShown", "true|false", true, nullptr, nullptr, false },
    { "showPreviews", "@dolphin", "Dolphin", "PreviewsShown", "true|false", true, nullptr, nullptr, false },
};

const QString kPersonalRc = QStringLiteral("enthronedpersonalizationrc");

const Scheme* findScheme(const QString& id)
{
    for (const Scheme& scheme : kSchemes) {
        if (id == QLatin1String(scheme.id)) {
            return &scheme;
        }
    }
    return nullptr;
}

const Wallpaper* findWallpaper(const QString& id)
{
    for (const Wallpaper& wallpaper : kWallpapers) {
        if (id == QLatin1String(wallpaper.id)) {
            return &wallpaper;
        }
    }
    return nullptr;
}

const Accent* findAccent(const QString& id)
{
    for (const Accent& accent : kAccents) {
        if (id == QLatin1String(accent.id)) {
            return &accent;
        }
    }
    return nullptr;
}

const Setting* findSetting(const QString& id)
{
    for (const Setting& setting : kSettings) {
        if (id == QLatin1String(setting.id)) {
            return &setting;
        }
    }
    return nullptr;
}

bool isFolderColour(const QString& colour)
{
    for (const char* known : kFolderColours) {
        if (colour == QLatin1String(known)) {
            return true;
        }
    }
    return false;
}

QString kdeglobalsScheme()
{
    const QString path = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/kdeglobals");
    if (!QFileInfo::exists(path)) {
        return QString();
    }
    QSettings settings(path, QSettings::IniFormat);
    return settings.value(QStringLiteral("General/ColorScheme")).toString();
}

QString settingFile(const Setting& setting)
{
    if (QLatin1String(setting.file) == QLatin1String("@dolphin")) {
        return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
            + QStringLiteral("/dolphin/view_properties/global/.directory");
    }
    return QLatin1String(setting.file);
}

bool allowedValue(const Setting& setting, const QString& value)
{
    return QString::fromLatin1(setting.allowed).split(QLatin1Char('|')).contains(value);
}

// Short, fixed-argument helper tools only; never a shell.
bool runTool(const QString& program, const QStringList& arguments, QString* output = nullptr)
{
    const QString exe = QStandardPaths::findExecutable(program);
    if (exe.isEmpty()) {
        return false;
    }
    QProcess process;
    process.start(exe, arguments);
    if (!process.waitForFinished(4000)) {
        process.kill();
        return false;
    }
    if (output) {
        *output = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    }
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
}

QStringList groupArguments(const QStringList& groups)
{
    QStringList arguments;
    for (const QString& group : groups) {
        arguments << QStringLiteral("--group") << group;
    }
    return arguments;
}

QString busTool()
{
    for (const char* name : { "qdbus6", "qdbus-qt6", "qdbus" }) {
        if (!QStandardPaths::findExecutable(QLatin1String(name)).isEmpty()) {
            return QLatin1String(name);
        }
    }
    return QString();
}

void reconfigureKWin()
{
    const QString bus = busTool();
    if (!bus.isEmpty()) {
        QProcess::startDetached(QStandardPaths::findExecutable(bus),
                                { QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
                                  QStringLiteral("reconfigure") });
    }
}

} // namespace

PersonalizationController::PersonalizationController(QObject* parent)
    : QObject(parent)
{
    m_colorScheme = kdeglobalsScheme();
    m_accent = configGet(kPersonalRc, { QStringLiteral("Accent") }, QStringLiteral("Id"));
    if (!findAccent(m_accent)) {
        m_accent.clear();
    }
}

bool PersonalizationController::dark() const
{
    return QGuiApplication::palette().color(QPalette::Window).lightness() < 128;
}

void PersonalizationController::refresh()
{
    m_colorScheme = kdeglobalsScheme();
    readPlasmaState();
    bump();
}

void PersonalizationController::bump()
{
    ++m_revision;
    Q_EMIT changed();
}

QString PersonalizationController::configGet(const QString& file, const QStringList& groups, const QString& key) const
{
    QString out;
    QStringList arguments = { QStringLiteral("--file"), file };
    arguments << groupArguments(groups) << QStringLiteral("--key") << key;
    return runTool(QStringLiteral("kreadconfig6"), arguments, &out) ? out : QString();
}

bool PersonalizationController::configSet(const QString& file, const QStringList& groups, const QString& key,
                                          const QString& value, bool isBool, bool remove) const
{
    QStringList arguments = { QStringLiteral("--file"), file };
    arguments << groupArguments(groups) << QStringLiteral("--key") << key;
    if (remove) {
        arguments << QStringLiteral("--delete") << QString();
    } else {
        if (isBool) {
            arguments << QStringLiteral("--type") << QStringLiteral("bool");
        }
        arguments << value;
    }
    // --notify lets running KDE applications (KWin, Dolphin, Kirigami) pick the change up.
    arguments.prepend(QStringLiteral("--notify"));
    return runTool(QStringLiteral("kwriteconfig6"), arguments);
}

QVariantList PersonalizationController::accentChoices() const
{
    // Single source of truth for the palette: the page only adds the translated names.
    QVariantList choices;
    choices << QVariantMap{ { QStringLiteral("id"), QString() }, { QStringLiteral("color"), QLatin1String(kDefaultAccentSwatch) } };
    for (const Accent& accent : kAccents) {
        choices << QVariantMap{ { QStringLiteral("id"), QLatin1String(accent.id) },
                                { QStringLiteral("color"), QLatin1String(accent.hex) } };
    }
    return choices;
}

bool PersonalizationController::schemeAvailable(const QString& which) const
{
    const Scheme* scheme = findScheme(which);
    return scheme
        && !QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                                   QLatin1String(scheme->fileName)).isEmpty()
        && !QStandardPaths::findExecutable(QStringLiteral("plasma-apply-colorscheme")).isEmpty();
}

bool PersonalizationController::wallpaperAvailable(const QString& which) const
{
    const Wallpaper* wallpaper = findWallpaper(which);
    return wallpaper && QFileInfo::exists(QLatin1String(wallpaper->path))
        && !QStandardPaths::findExecutable(QStringLiteral("plasma-apply-wallpaperimage")).isEmpty();
}

void PersonalizationController::applyScheme(const QString& which)
{
    const Scheme* scheme = findScheme(which);
    if (!scheme || !schemeAvailable(which)) {
        Q_EMIT applyFinished(false, i18n("Color scheme unavailable on this system."));
        return;
    }
    QList<Step> steps = { { QStringLiteral("plasma-apply-colorscheme"), { QLatin1String(scheme->name) } } };
    // Applying a scheme resets the accent to that scheme's own; keep the user's choice.
    if (const Accent* accent = findAccent(m_accent)) {
        steps << Step{ QStringLiteral("plasma-apply-colorscheme"),
                       { QStringLiteral("--accent-color"), QLatin1String(accent->hex) } };
    }
    runSequence(steps);
}

void PersonalizationController::applyAccent(const QString& id)
{
    if (QStandardPaths::findExecutable(QStringLiteral("plasma-apply-colorscheme")).isEmpty()) {
        Q_EMIT applyFinished(false, i18n("Accent color unavailable on this system."));
        return;
    }
    if (id.isEmpty()) {
        // plasma-apply-colorscheme ignores a scheme that is already current, so the
        // scheme's own accent comes back by switching to the other Enthroned scheme and back.
        const bool isDark = dark();
        const Scheme* current = findScheme(isDark ? QStringLiteral("dark") : QStringLiteral("light"));
        const Scheme* other = findScheme(isDark ? QStringLiteral("light") : QStringLiteral("dark"));
        if (!schemeAvailable(QLatin1String(current->id)) || !schemeAvailable(QLatin1String(other->id))) {
            Q_EMIT applyFinished(false, i18n("Color scheme unavailable on this system."));
            return;
        }
        runSequence({ { QStringLiteral("plasma-apply-colorscheme"), { QLatin1String(other->name) } },
                      { QStringLiteral("plasma-apply-colorscheme"), { QLatin1String(current->name) } } },
                    QString(), true);
        return;
    }
    const Accent* accent = findAccent(id);
    if (!accent) {
        Q_EMIT applyFinished(false, i18n("Unknown accent color."));
        return;
    }
    runSequence({ { QStringLiteral("plasma-apply-colorscheme"),
                    { QStringLiteral("--accent-color"), QLatin1String(accent->hex) } } },
                id, true);
}

void PersonalizationController::applyWallpaper(const QString& which)
{
    const Wallpaper* wallpaper = findWallpaper(which);
    if (!wallpaper || !wallpaperAvailable(which)) {
        Q_EMIT applyFinished(false, i18n("Wallpaper unavailable on this system."));
        return;
    }
    runSequence({ { QStringLiteral("plasma-apply-wallpaperimage"), { QLatin1String(wallpaper->path) } } });
}

void PersonalizationController::applyWallpaperFile(const QUrl& file)
{
    const QFileInfo info(file.toLocalFile());
    static const QStringList kImageSuffixes = { QStringLiteral("png"), QStringLiteral("jpg"),
                                                QStringLiteral("jpeg"), QStringLiteral("webp"),
                                                QStringLiteral("bmp"), QStringLiteral("gif") };
    if (!file.isLocalFile() || !info.isFile() || !info.isReadable()
        || !kImageSuffixes.contains(info.suffix().toLower())
        || QStandardPaths::findExecutable(QStringLiteral("plasma-apply-wallpaperimage")).isEmpty()) {
        Q_EMIT applyFinished(false, i18n("Choose an image file (PNG, JPEG, WebP, BMP or GIF)."));
        return;
    }
    runSequence({ { QStringLiteral("plasma-apply-wallpaperimage"), { info.canonicalFilePath() } } });
}

QString PersonalizationController::value(const QString& id) const
{
    const Setting* setting = findSetting(id);
    if (!setting) {
        return QString();
    }
    const QString file = settingFile(*setting);
    if (file.startsWith(QLatin1Char('/')) && !QFileInfo::exists(file)) {
        return QString();
    }
    const QString current = configGet(file, QString::fromLatin1(setting->group).split(QLatin1Char('/')),
                                      QLatin1String(setting->key));
    return allowedValue(*setting, current) ? current : QString();
}

bool PersonalizationController::setValue(const QString& id, const QString& value)
{
    const Setting* setting = findSetting(id);
    if (!setting || !allowedValue(*setting, value)) {
        Q_EMIT applyFinished(false, i18n("Invalid value for this setting."));
        return false;
    }
    const QString file = settingFile(*setting);
    if (file.startsWith(QLatin1Char('/'))) {
        QDir().mkpath(QFileInfo(file).absolutePath());
    }
    const QStringList groups = QString::fromLatin1(setting->group).split(QLatin1Char('/'));
    bool ok = configSet(file, groups, QLatin1String(setting->key), value, setting->isBool);
    if (ok && setting->companionKey) {
        ok = configSet(file, groups, QLatin1String(setting->companionKey),
                       QLatin1String(setting->companionValue), true);
    }
    if (ok && setting->reloadKWin) {
        reconfigureKWin();
    }
    Q_EMIT applyFinished(ok, ok ? QString() : i18n("Could not save the setting."));
    bump();
    return ok;
}

bool PersonalizationController::resetValue(const QString& id)
{
    const Setting* setting = findSetting(id);
    if (!setting) {
        return false;
    }
    const QString file = settingFile(*setting);
    if (file.startsWith(QLatin1Char('/')) && !QFileInfo::exists(file)) {
        bump();
        return true; // nothing stored: already the default
    }
    const QStringList groups = QString::fromLatin1(setting->group).split(QLatin1Char('/'));
    bool ok = configSet(file, groups, QLatin1String(setting->key), QString(), false, true);
    if (ok && setting->companionKey) {
        ok = configSet(file, groups, QLatin1String(setting->companionKey), QString(), false, true);
    }
    if (ok && setting->reloadKWin) {
        reconfigureKWin();
    }
    Q_EMIT applyFinished(ok, ok ? QString() : i18n("Could not restore the default."));
    bump();
    return ok;
}

QString PersonalizationController::folderColor(const QUrl& folder) const
{
    const QString directory = folder.toLocalFile() + QStringLiteral("/.directory");
    if (!folder.isLocalFile() || !QFileInfo::exists(directory)) {
        return QString();
    }
    const QString icon = configGet(directory, { QStringLiteral("Desktop Entry") }, QStringLiteral("Icon"));
    return icon.startsWith(QStringLiteral("folder-")) && isFolderColour(icon.mid(7)) ? icon.mid(7) : QString();
}

bool PersonalizationController::setFolderColor(const QUrl& folder, const QString& colour)
{
    const QFileInfo info(folder.toLocalFile());
    if (!folder.isLocalFile() || !info.isDir() || !info.isWritable() || info.isSymLink()
        || (!colour.isEmpty() && !isFolderColour(colour))) {
        Q_EMIT applyFinished(false, i18n("Choose a folder you can modify."));
        return false;
    }
    const QString directory = info.canonicalFilePath() + QStringLiteral("/.directory");
    const QStringList group = { QStringLiteral("Desktop Entry") };
    bool ok = true;
    if (colour.isEmpty()) {
        // Only an Icon this feature wrote (folder-<colour>) is removed; a custom icon stays.
        if (!QFileInfo::exists(directory) || folderColor(QUrl::fromLocalFile(info.canonicalFilePath())).isEmpty()) {
            Q_EMIT applyFinished(true, QString());
            return true;
        }
        ok = configSet(directory, group, QStringLiteral("Icon"), QString(), false, true);
        if (ok && QFileInfo(directory).size() == 0) {
            QFile::remove(directory);
        }
    } else {
        ok = configSet(directory, group, QStringLiteral("Icon"), QStringLiteral("folder-") + colour);
    }
    Q_EMIT applyFinished(ok, ok ? QString() : i18n("Could not change the folder color."));
    bump();
    return ok;
}

void PersonalizationController::runPlasmaScript(const QString& script)
{
    // Only a plasmashell that is already running: a plain call could D-Bus-activate a new one.
    auto* bus = QDBusConnection::sessionBus().interface();
    if (!bus || !bus->isServiceRegistered(QStringLiteral("org.kde.plasmashell"))) {
        Q_EMIT applyFinished(false, i18n("The Plasma desktop is not running."));
        return;
    }
    QDBusInterface shell(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"),
                         QStringLiteral("org.kde.PlasmaShell"));
    auto* watcher = new QDBusPendingCallWatcher(shell.asyncCall(QStringLiteral("evaluateScript"), script), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* done) {
        QDBusPendingReply<QString> reply = *done;
        done->deleteLater();
        if (reply.isError()) {
            Q_EMIT applyFinished(false, reply.error().message().left(200));
            return;
        }
        Q_EMIT applyFinished(true, QString());
        readPlasmaState();
    });
}

void PersonalizationController::readPlasmaState()
{
    auto* bus = QDBusConnection::sessionBus().interface();
    if (!bus || !bus->isServiceRegistered(QStringLiteral("org.kde.plasmashell"))) {
        return;
    }
    QDBusInterface shell(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"),
                         QStringLiteral("org.kde.PlasmaShell"));
    const QString script = QStringLiteral(
        "var ic = -1; var ds = desktops();"
        "if (ds.length) { var d = ds[0]; d.currentConfigGroup = [\"General\"]; ic = d.readConfig(\"iconSize\", 3); }"
        "var h = -1; var ps = panels(); if (ps.length) { h = ps[0].height; }"
        "print(ic + \"|\" + h);");
    auto* watcher = new QDBusPendingCallWatcher(shell.asyncCall(QStringLiteral("evaluateScript"), script), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* done) {
        QDBusPendingReply<QString> reply = *done;
        done->deleteLater();
        if (reply.isError()) {
            return;
        }
        const QStringList parts = reply.value().trimmed().split(QLatin1Char('|'));
        if (parts.size() == 2) {
            m_desktopIconSize = parts[0].toInt();
            m_panelHeight = parts[1].toInt();
            bump();
        }
    });
}

void PersonalizationController::setDesktopIconSize(int step)
{
    if (step < 0 || step > 6) {
        return;
    }
    // Same scripting API the profiles' layout scripts use (folder containment [General] iconSize).
    runPlasmaScript(QStringLiteral(
        "var ds = desktops(); for (var i = 0; i < ds.length; i++) { var d = ds[i];"
        "d.currentConfigGroup = [\"General\"]; d.writeConfig(\"iconSize\", %1);"
        "if (d.reloadConfig) { d.reloadConfig(); } }").arg(step));
}

void PersonalizationController::setPanelHeight(int px)
{
    if (px < 32 || px > 64) {
        return;
    }
    runPlasmaScript(QStringLiteral("var ps = panels(); for (var i = 0; i < ps.length; i++) { ps[i].height = %1; }").arg(px));
}

void PersonalizationController::runSequence(const QList<Step>& steps, const QString& accentId, bool persistAccent)
{
    if (m_busy || steps.isEmpty()) {
        return; // one operation at a time
    }
    setBusy(true);
    m_queue = steps;
    m_pendingAccent = accentId;
    m_persistAccent = persistAccent;
    runStep();
}

void PersonalizationController::runStep()
{
    if (m_queue.isEmpty()) {
        finishSequence(true, QString());
        return;
    }
    const Step step = m_queue.takeFirst();
    auto* process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process](int exitCode, QProcess::ExitStatus status) {
        const QString error = QString::fromUtf8(process->readAllStandardError()).trimmed().left(200);
        process->deleteLater();
        if (exitCode == 0 && status == QProcess::NormalExit) {
            runStep();
        } else {
            finishSequence(false, error);
        }
    });
    // FailedToStart never emits finished(); without this m_busy would stay true forever.
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) {
            return;
        }
        const QString message = process->errorString();
        process->deleteLater();
        finishSequence(false, message);
    });
    process->start(QStandardPaths::findExecutable(step.first), step.second);
}

void PersonalizationController::finishSequence(bool ok, const QString& error)
{
    m_queue.clear();
    setBusy(false);
    if (ok && m_persistAccent) {
        m_accent = m_pendingAccent;
        const QStringList group = { QStringLiteral("Accent") };
        // Id for this page, Hex for enthroned-profile (re-applies it after a profile switch).
        if (const Accent* accent = findAccent(m_accent)) {
            configSet(kPersonalRc, group, QStringLiteral("Id"), m_accent);
            configSet(kPersonalRc, group, QStringLiteral("Hex"), QLatin1String(accent->hex));
        } else {
            configSet(kPersonalRc, group, QStringLiteral("Id"), QString(), false, true);
            configSet(kPersonalRc, group, QStringLiteral("Hex"), QString(), false, true);
        }
    }
    m_persistAccent = false;
    refresh();
    // The application palette follows kdeglobals asynchronously; re-read once it settled.
    QTimer::singleShot(800, this, &PersonalizationController::refresh);
    Q_EMIT applyFinished(ok, ok ? QString() : error);
}

void PersonalizationController::setBusy(bool busy)
{
    if (m_busy != busy) {
        m_busy = busy;
        Q_EMIT busyChanged();
    }
}

} // namespace Enthroned
