/*
 * Enthroned Settings - personalization controller (Lote 4, extended in Lote 15).
 * Every control goes through a mechanism KDE itself ships, user-level, no
 * privileges: plasma-apply-colorscheme (scheme + accent), plasma-apply-wallpaperimage,
 * kwriteconfig6/kreadconfig6 (kdeglobals, kwinrc, Dolphin's view properties and a
 * folder's .directory file) and Plasma's own desktop scripting over D-Bus
 * (desktop icon size, panel height). Only fixed allowlists of ids/values can be
 * applied: the UI passes an id or a value from a closed set (plus a user-chosen
 * image file or folder, validated), never a command or an arbitrary key.
 * Profiles (Classic/Modern) stay in ProfileController / enthroned-profile.
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <QList>
#include <QObject>
#include <QPair>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>

namespace Enthroned {

class PersonalizationController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString colorScheme READ colorScheme NOTIFY changed)
    Q_PROPERTY(bool dark READ dark NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // Bumped on every change so QML bindings that call value()/folderColor() re-evaluate.
    Q_PROPERTY(int revision READ revision NOTIFY changed)
    // Accent palette id chosen through this page ("" = the scheme's own accent).
    Q_PROPERTY(QString accent READ accent NOTIFY changed)
    // Read from the running plasmashell; -1 while unknown / plasmashell unreachable.
    Q_PROPERTY(int desktopIconSize READ desktopIconSize NOTIFY changed)
    Q_PROPERTY(int panelHeight READ panelHeight NOTIFY changed)

public:
    explicit PersonalizationController(QObject* parent = nullptr);

    // Active scheme name from kdeglobals ([General] ColorScheme); empty if unknown.
    QString colorScheme() const { return m_colorScheme; }
    // Live palette lightness: reflects what the user actually sees.
    bool dark() const;
    bool busy() const { return m_busy; }
    int revision() const { return m_revision; }
    QString accent() const { return m_accent; }
    int desktopIconSize() const { return m_desktopIconSize; }
    int panelHeight() const { return m_panelHeight; }

    // which: "light" | "dark". Re-applies the accent chosen on this page, if any.
    Q_INVOKABLE bool schemeAvailable(const QString& which) const;
    Q_INVOKABLE void applyScheme(const QString& which);
    // which: "soberania" | "ascensao" | "vigilia"
    Q_INVOKABLE bool wallpaperAvailable(const QString& which) const;
    Q_INVOKABLE void applyWallpaper(const QString& which);
    // A user-chosen local image (png/jpg/webp/...); validated, then handed to Plasma's tool.
    Q_INVOKABLE void applyWallpaperFile(const QUrl& file);
    // [{id, color}] of the fixed accent palette; id "" is the scheme's own accent.
    Q_INVOKABLE QVariantList accentChoices() const;
    // id from the fixed accent palette; "" restores the scheme's own accent.
    Q_INVOKABLE void applyAccent(const QString& id);

    // Allowlisted KConfig-backed settings (see kSettings in the .cpp). value() is
    // "" when the key is unset, which means "KDE/Enthroned default".
    Q_INVOKABLE QString value(const QString& id) const;
    Q_INVOKABLE bool setValue(const QString& id, const QString& value);
    Q_INVOKABLE bool resetValue(const QString& id);

    // Per-folder colour through Dolphin's own mechanism (<folder>/.directory, Icon=folder-<colour>).
    // colour: one of the 11 KDE folder colours, or "" to restore the default icon.
    Q_INVOKABLE QString folderColor(const QUrl& folder) const;
    Q_INVOKABLE bool setFolderColor(const QUrl& folder, const QString& colour);

    // Plasma desktop scripting (running session only). step 0..6, px 32..64.
    Q_INVOKABLE void setDesktopIconSize(int step);
    Q_INVOKABLE void setPanelHeight(int px);
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void changed();
    void busyChanged();
    void applyFinished(bool ok, const QString& message);

private:
    // One operation at a time; steps run in order and stop at the first failure.
    using Step = QPair<QString, QStringList>;
    void runSequence(const QList<Step>& steps, const QString& accentId = QString(), bool persistAccent = false);
    void runStep();
    void finishSequence(bool ok, const QString& error);
    void runPlasmaScript(const QString& script);
    void readPlasmaState();
    void setBusy(bool busy);
    void bump();
    QString configGet(const QString& file, const QStringList& groups, const QString& key) const;
    bool configSet(const QString& file, const QStringList& groups, const QString& key,
                   const QString& value, bool isBool = false, bool remove = false) const;

    QString m_colorScheme;
    QString m_accent;
    bool m_busy = false;
    int m_revision = 0;
    int m_desktopIconSize = -1;
    int m_panelHeight = -1;
    QList<Step> m_queue;
    QString m_pendingAccent;
    bool m_persistAccent = false;
};

} // namespace Enthroned
