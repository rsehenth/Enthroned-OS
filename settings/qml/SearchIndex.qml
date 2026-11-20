/*
 * Enthroned Settings - in-memory search index (Lote 4).
 * Pages plus the individual settings that really exist in this application or
 * in a native KDE module it can open. Every entry points at something that is
 * actually reachable; "keywords" carry the common synonyms (PT/EN). Built once,
 * in memory: no indexer, no background service, no external dependency.
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick

QtObject {
    id: root

    // [{ id, title, icon, keywords }] from Main.qml
    property var pages: []

    function pageTitle(pageId) {
        for (let i = 0; i < pages.length; i++) {
            if (pages[i].id === pageId) {
                return pages[i].title;
            }
        }
        return "";
    }

    // Lote 6: whether an entry belongs to the advanced areas. Derived from
    // the TARGET page, so every item that opens an advanced area inherits the
    // badge in Modo Simples without duplicating flags per item.
    function pageIsAdvanced(pageId) {
        for (let i = 0; i < pages.length; i++) {
            if (pages[i].id === pageId) {
                return pages[i].advanced === true;
            }
        }
        return false;
    }

    // Entries with `ids` open the native KDE module directly when it exists;
    // otherwise they fall back to the page that explains the situation.
    readonly property var items: [
        // Rede e Internet
        { page: "network", title: i18n("Wi-Fi and network connections"), icon: "network-wireless", ids: ["kcm_networkmanagement"],
          keywords: i18n("wifi wi-fi internet wireless ethernet cable vpn network network password connect") },
        // Bluetooth e dispositivos
        { page: "devices", title: i18n("Bluetooth"), icon: "preferences-system-bluetooth", ids: ["kcm_bluetooth"],
          keywords: i18n("bluetooth headphones pairing pair wireless devices") },
        { page: "devices", title: i18n("Mouse"), icon: "input-mouse", ids: ["kcm_mouse"],
          keywords: i18n("pointer cursor speed click scrolling") },
        { page: "devices", title: i18n("Touchpad"), icon: "input-touchpad", ids: ["kcm_touchpad"],
          keywords: i18n("tap natural scrolling gestures") },
        { page: "devices", title: i18n("Keyboard"), icon: "input-keyboard", ids: ["kcm_keyboard"],
          keywords: i18n("layout abnt2 shortcuts repeat keys") },
        { page: "devices", title: i18n("Printers"), icon: "printer", ids: ["kcm_printer_manager", "printers"],
          keywords: i18n("print printing scanner") },
        { page: "devices", title: i18n("Game controllers"), icon: "input-gaming", ids: ["kcm_gamecontroller"],
          keywords: i18n("gamepad joystick controller") },
        { page: "devices", title: i18n("Removable media"), icon: "drive-removable-media", ids: ["kcm_device_automounter"],
          keywords: i18n("usb drive disk automount") },
        // Sistema
        { page: "display", title: i18n("Display"), icon: "preferences-desktop-display", ids: ["kcm_kscreen", "kcm_displayconfiguration"],
          keywords: i18n("monitor resolution scale brightness orientation refresh rate night light display") },
        { page: "sound", title: i18n("Sound"), icon: "audio-card", ids: ["kcm_pulseaudio"],
          keywords: i18n("audio volume speaker microphone headset output input sound") },
        { page: "notifications", title: i18n("Notifications"), icon: "preferences-desktop-notification", ids: ["kcm_notifications"],
          keywords: i18n("alerts do not disturb notifications") },
        { page: "system", title: i18n("Power and battery"), icon: "battery", ids: ["kcm_powerdevilprofilesconfig"],
          keywords: i18n("battery suspend screen off power saving") },
        { page: "system", title: i18n("Virtual desktops"), icon: "preferences-desktop-virtual", ids: ["kcm_kwin_virtualdesktops"],
          keywords: i18n("desktops workspaces multitasking") },
        { page: "system", title: i18n("Automatic updates (policy)"), icon: "view-refresh",
          keywords: i18n("uupd schedule timer automatic update itself") },
        // Personalização
        { page: "appearance", title: i18n("Classic and Modern profiles"), icon: "preferences-desktop-theme",
          keywords: i18n("classic modern profile layout panel start menu zorin windows 11") },
        { page: "appearance", title: i18n("Light and dark theme"), icon: "preferences-desktop-color",
          keywords: i18n("dark mode light color scheme theme night") },
        { page: "appearance", title: i18n("Wallpaper"), icon: "preferences-desktop-wallpaper",
          keywords: i18n("wallpaper background image desktop") },
        { page: "appearance", title: i18n("Accent color (quick choice)"), icon: "preferences-desktop-color",
          keywords: i18n("accent highlight selection color rectangle drag personalize") },
        { page: "appearance", title: i18n("Folder color"), icon: "folder-open",
          keywords: i18n("folder color icon colorful dolphin directory") },
        { page: "appearance", title: i18n("Desktop icon size"), icon: "preferences-desktop-icons",
          keywords: i18n("desktop icons size bigger smaller") },
        { page: "appearance", title: i18n("Dolphin view and icon size"), icon: "system-file-manager",
          keywords: i18n("dolphin files view details icons compact hidden files previews thumbnails") },
        { page: "appearance", title: i18n("Panel size"), icon: "configure-toolbars",
          keywords: i18n("panel taskbar height size bigger smaller") },
        { page: "appearance", title: i18n("Colors and accent color"), icon: "preferences-desktop-color", ids: ["kcm_colors"],
          keywords: i18n("accent highlight scheme palette") },
        { page: "appearance", title: i18n("Window decorations"), icon: "preferences-system-windows", ids: ["kcm_kwindecoration"],
          keywords: i18n("title bar buttons borders window appearance") },
        { page: "appearance", title: i18n("Desktop effects"), icon: "preferences-desktop-effects", ids: ["kcm_kwin_effects"],
          keywords: i18n("animations blur transparency shadows performance") },
        { page: "appearance", title: i18n("Icons"), icon: "preferences-desktop-icons", ids: ["kcm_icons"],
          keywords: i18n("icon theme") },
        { page: "appearance", title: i18n("Mouse cursor (theme)"), icon: "input-mouse", ids: ["kcm_cursortheme"],
          keywords: i18n("pointer cursor theme size") },
        { page: "appearance", title: i18n("Fonts and text size"), icon: "preferences-desktop-font", ids: ["kcm_fonts"],
          keywords: i18n("letter typography text size font") },
        // Aplicativos
        { page: "apps", title: i18n("Default applications"), icon: "preferences-desktop-default-applications", ids: ["kcm_componentchooser"],
          keywords: i18n("default browser email file manager terminal open with") },
        { page: "apps", title: i18n("Flatpak application permissions"), icon: "applications-internet", ids: ["kcm_flatpak"],
          keywords: i18n("flatpak sandbox permissions access") },
        { page: "apps", title: i18n("Startup applications"), icon: "system-run", ids: ["kcm_autostart"],
          keywords: i18n("start with system autostart programs at login") },
        { page: "apps", title: i18n("App store (Discover)"), icon: "system-software-install",
          keywords: i18n("install store discover flathub programs uninstall") },
        { page: "apps", title: i18n("Reopen Enthroned Welcome"), icon: "org.enthroned.enthroned-os",
          keywords: i18n("welcome assistant first experience") },
        // Contas
        { page: "accounts", title: i18n("User accounts"), icon: "system-users", ids: ["kcm_users"],
          keywords: i18n("user password account profile picture login name") },
        // Hora e idioma
        { page: "time", title: i18n("Date and time"), icon: "preferences-system-time", ids: ["kcm_clock"],
          keywords: i18n("clock time zone automatic time ntp calendar") },
        { page: "time", title: i18n("Language and region"), icon: "preferences-desktop-locale", ids: ["kcm_regionandlang"],
          keywords: i18n("language formats currency number region") },
        // Acessibilidade
        { page: "accessibility", title: i18n("Accessibility"), icon: "preferences-desktop-accessibility", ids: ["kcm_access"],
          keywords: i18n("screen reader orca sticky keys sound alert disability") },
        { page: "accessibility", title: i18n("Magnifier and zoom"), icon: "zoom-in", ids: ["kcm_kwin_effects"],
          keywords: i18n("magnify magnifier zoom enlarge screen") },
        // Privacidade e segurança
        { page: "privacy", title: i18n("Screen locking"), icon: "system-lock-screen", ids: ["kcm_kscreenlocker"],
          keywords: i18n("lock password screen protection idle") },
        { page: "privacy", title: i18n("Password wallet (KWallet)"), icon: "kwalletmanager", ids: ["kcm_kwallet", "kcm_kwallet5"],
          keywords: i18n("passwords keys secrets kwallet") },
        { page: "privacy", title: i18n("Recent files history"), icon: "document-open-recent", ids: ["kcm_recentFiles"],
          keywords: i18n("privacy recent history") },
        { page: "privacy", title: i18n("File search (Baloo)"), icon: "system-search", ids: ["kcm_baloofile"],
          keywords: i18n("baloo indexing file search") },
        { page: "privacy", title: i18n("Firewall"), icon: "security-high", ids: ["kcm_firewall"],
          keywords: i18n("ports network security block connections") },
        { page: "privacy", title: i18n("System security (SELinux and immutable model)"), icon: "security-high",
          keywords: i18n("selinux immutable read-only protection integrity") },
        // Atualizações do sistema
        { page: "updates", title: i18n("Check for updates"), icon: "view-refresh",
          keywords: i18n("update system bootc uupd new version") },
        { page: "updates", title: i18n("Update history"), icon: "view-history",
          keywords: i18n("record log updated when") },
        { page: "updates", title: i18n("Recovery (rollback)"), icon: "edit-undo",
          keywords: i18n("back previous version deployment restore system") },
        { page: "updates", title: i18n("Application updates (Flatpak)"), icon: "applications-internet",
          keywords: i18n("flatpak apps update applications") },
        // Sobre o dispositivo
        { page: "about", title: i18n("Device name"), icon: "computer",
          keywords: i18n("hostname computer name pc machine") },
        { page: "about", title: i18n("Device specifications"), icon: "computer",
          keywords: i18n("processor cpu memory ram gpu graphics card storage disk kernel architecture hardware") },
        { page: "about", title: i18n("Enthroned OS version"), icon: "help-about",
          keywords: i18n("version channel build edition technical base fedora aurora") }
    ]

    readonly property var entries: {
        const list = [];
        for (let i = 0; i < pages.length; i++) {
            list.push({ page: pages[i].id, title: pages[i].title, icon: pages[i].icon,
                        keywords: pages[i].keywords, pageTitle: "", ids: undefined, isPage: true,
                        advanced: pages[i].advanced === true });
        }
        for (let j = 0; j < items.length; j++) {
            const item = items[j];
            list.push({ page: item.page, title: item.title, icon: item.icon, keywords: item.keywords,
                        pageTitle: pageTitle(item.page), ids: item.ids, isPage: false,
                        advanced: pageIsAdvanced(item.page) });
        }
        return list;
    }
}
