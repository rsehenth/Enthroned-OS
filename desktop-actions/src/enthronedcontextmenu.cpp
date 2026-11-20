/*
 * Enthroned OS - desktop context menu (Plasma ContainmentActions plugin).
 *
 * The stock desktop menu plugin (org.kde.contextmenu) builds its item list
 * from a fixed C++ set, so a custom entry cannot be added through
 * configuration alone (plasma-workspace containmentactions/contextmenu,
 * ContextMenu::restore). This plugin binds to the desktop right button in
 * its place and delegates the whole stock menu — restore(), save(),
 * contextualActions() and the wheel actions — to the upstream plugin,
 * only PREPENDING one action: "Configurações do Enthroned". Every stock
 * entry and its per-entry configuration toggles keep working unchanged
 * because the upstream plugin still reads and owns them.
 *
 * Only public, stable API is used: Plasma/ContainmentActions,
 * KPluginFactory/KPluginMetaData. If the stock plugin is missing (e.g. after
 * a bootc rollback to an older image) the menu degrades to the Enthroned
 * entry alone; the per-login user script
 * (/usr/libexec/enthroned-desktop-actions) heals the user binding back to
 * org.kde.contextmenu in that case.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <Plasma/ContainmentActions>

#include <KConfigGroup>
#include <KPluginFactory>
#include <KPluginMetaData>

#include <QAction>
#include <QDebug>
#include <QIcon>
#include <QVariantList>

#include "settingslauncher.h"

using namespace Qt::StringLiterals;

namespace
{

class EnthronedContextMenu : public Plasma::ContainmentActions
{
public:
    EnthronedContextMenu(QObject *parent, const QVariantList &args)
        : Plasma::ContainmentActions(parent, args)
    {
        m_settingsAction = new QAction(
            QIcon::fromTheme(u"org.enthroned.settings"_s, QIcon::fromTheme(u"preferences-system"_s)),
            QStringLiteral("Configurações do Enthroned"), this);
        connect(m_settingsAction, &QAction::triggered, this, &EnthronedContextMenu::openSettings);
        m_launcher = new SettingsLauncher(this);
    }

    ~EnthronedContextMenu() override
    {
        delete m_stock;
    }

    void restore(const KConfigGroup &config) override
    {
        loadStockPlugin();
        if (m_stock) {
            m_stock->setContainment(containment());
            m_stock->restore(config);
        }
    }

    void save(KConfigGroup &config) override
    {
        if (m_stock) {
            m_stock->save(config);
        }
    }

    QList<QAction *> contextualActions() override
    {
        QList<QAction *> actions;
        if (m_settingsAction) {
            actions << m_settingsAction;
        }
        if (m_stock) {
            const QList<QAction *> stockActions = m_stock->contextualActions();
            for (QAction *action : stockActions) {
                if (action) {
                    actions << action;
                }
            }
        }
        return actions;
    }

    void performNextAction() override
    {
        if (m_stock) {
            m_stock->performNextAction();
        }
    }

    void performPreviousAction() override
    {
        if (m_stock) {
            m_stock->performPreviousAction();
        }
    }

private:
    // Same lookup Plasma::PluginLoader uses for the stock menu plugin: the
    // upstream binary embeds no KPlugin Id, the id is the library file name.
    void loadStockPlugin()
    {
        if (m_stock || m_stockLookupDone) {
            return;
        }
        m_stockLookupDone = true;
        const KPluginMetaData meta(u"plasma/containmentactions/org.kde.contextmenu"_s,
                                   KPluginMetaData::AllowEmptyMetaData);
        if (meta.isValid()) {
            const auto result = KPluginFactory::instantiatePlugin<Plasma::ContainmentActions>(
                meta, nullptr, {QVariant::fromValue(meta)});
            if (result) {
                m_stock = result.plugin;
            } else {
                qWarning() << "enthroned-contextmenu: failed to load the stock Plasma menu plugin:"
                           << result.errorString;
            }
        } else {
            qWarning() << "enthroned-contextmenu: stock Plasma menu plugin (org.kde.contextmenu) not found";
        }
    }

    void openSettings()
    {
        // The hub is the product entry point; the repeat covers a transient
        // failure (P1-1: a SIGSEGV used to leave the user with nothing) and
        // the native System Settings is the last-resort fallback for images
        // without the hub. The supervised launch keeps a crashing app away
        // from the Plasma Shell. Absolute installed paths (Lote 10.2) pin the
        // trusted origin of the executables instead of trusting the session
        // PATH.
        m_launcher->launch({ u"/usr/bin/enthroned-settings"_s,
                             u"/usr/bin/enthroned-settings"_s,
                             u"/usr/bin/systemsettings"_s });
    }

    QAction *m_settingsAction = nullptr;
    SettingsLauncher *m_launcher = nullptr;
    Plasma::ContainmentActions *m_stock = nullptr;
    bool m_stockLookupDone = false;
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(EnthronedContextMenu, "org.enthroned.contextmenu.json")

#include "enthronedcontextmenu.moc"
