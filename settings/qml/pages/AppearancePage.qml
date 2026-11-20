/*
 * Enthroned Settings - Personalization page (F3.3, rebuilt in Lote 15).
 * A short front door to the preferences people actually change, grouped by what
 * they affect: general appearance, desktop, files and folders, panel and Start
 * menu. It does NOT duplicate System Settings: every control is a thin wrapper
 * over a mechanism KDE ships (plasma-apply-lookandfeel / -colorscheme /
 * -wallpaperimage, kwriteconfig6 on kdeglobals / kwinrc / Dolphin's view
 * properties, a folder's .directory file, Plasma desktop scripting). Each one
 * saves, can be restored to the default, and never claims a change it did not
 * make; the rest stays one click away under "More KDE settings".
 * Profiles are applied through /usr/bin/enthroned-profile (official look-and-feel).
 * SPDX-License-Identifier: Apache-2.0
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components"

SettingsPage {
    id: root
    title: i18n("Personalization")

    readonly property var moreModules: [
        { title: i18n("Colors and accent color"), subtitle: i18n("Color scheme and accent color."),
          icon: "preferences-desktop-color", ids: ["kcm_colors"] },
        { title: i18n("Window decorations"), subtitle: i18n("Title bar, buttons and window borders."),
          icon: "preferences-system-windows", ids: ["kcm_kwindecoration"] },
        { title: i18n("Desktop effects"), subtitle: i18n("Animations, blur and shadows."),
          icon: "preferences-desktop-effects", ids: ["kcm_kwin_effects"] },
        { title: i18n("Icons"), subtitle: i18n("Icon theme."),
          icon: "preferences-desktop-icons", ids: ["kcm_icons"] },
        { title: i18n("Mouse cursor"), subtitle: i18n("Cursor theme and size."),
          icon: "input-mouse", ids: ["kcm_cursortheme"] },
        { title: i18n("Fonts"), subtitle: i18n("Font type and size."),
          icon: "preferences-desktop-font", ids: ["kcm_fonts"] },
        { title: i18n("Global theme (Look and Feel)"), subtitle: i18n("Complete Plasma themes."),
          icon: "preferences-desktop-theme-global", ids: ["kcm_lookandfeel"], optional: true },
        { title: i18n("Splash screen"), subtitle: i18n("Screen shown when the session starts."),
          icon: "preferences-desktop-splash", ids: ["kcm_splashscreen"], optional: true }
    ]

    // Accent palette: ids and colours come from PersonalizationController (one
    // source of truth, each >= 4.5:1 with white text); only the names live here.
    // id "" is the scheme's own (violet) accent.
    readonly property var accentNames: ({
        "": i18n("Violet (Enthroned)"), "magenta": i18n("Magenta"), "red": i18n("Red"),
        "orange": i18n("Orange"), "gold": i18n("Gold"), "green": i18n("Green"),
        "teal": i18n("Teal"), "blue": i18n("Blue")
    })
    readonly property var accents: personalization.accentChoices().map(
        entry => ({ id: entry.id, color: entry.color, name: root.accentNames[entry.id] ?? entry.id }))
    // The 11 colours Dolphin's own "Set folder icon" action offers.
    readonly property var folderColours: [
        { id: "violet", name: i18n("Violet") }, { id: "magenta", name: i18n("Magenta") },
        { id: "red", name: i18n("Red") }, { id: "orange", name: i18n("Orange") },
        { id: "yellow", name: i18n("Yellow") }, { id: "green", name: i18n("Green") },
        { id: "cyan", name: i18n("Cyan") }, { id: "blue", name: i18n("Blue") },
        { id: "brown", name: i18n("Brown") }, { id: "grey", name: i18n("Grey") },
        { id: "black", name: i18n("Black") }
    ]

    property string pendingProfileId: ""
    // Accent the user is previewing; applied with the button, not on every click.
    property string pendingAccent: personalization.accent
    property url chosenFolder
    readonly property bool plasmaReachable: personalization.panelHeight >= 0
    readonly property int profilePanelHeight: profiles.activeProfile === "org.enthroned.modern" ? 48 : 44
    readonly property string chosenFolderColour: {
        personalization.revision;
        return chosenFolder.toString().length > 0 ? personalization.folderColor(chosenFolder) : "";
    }

    function requestApply(profileId) {
        pendingProfileId = profileId;
        applyDialog.open();
    }

    function accentColor(id) {
        for (let i = 0; i < accents.length; ++i) {
            if (accents[i].id === id) {
                return accents[i].color;
            }
        }
        return accents[0].color;
    }

    function folderLabel(url) {
        const text = url.toString().replace(/^file:\/\//, "");
        return decodeURIComponent(text);
    }

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: !profiles.toolPresent
            type: Kirigami.MessageType.Information
            icon.name: "dialog-information"
            text: i18n("The enthroned-profile tool is not installed on this system. The profiles remain available in System Settings → Colors & Themes → Look and Feel.")
        }

        //BEGIN General appearance
        SectionHeading {
            text: i18n("General appearance")
        }

        GridLayout {
            columns: root.width > Kirigami.Units.gridUnit * 40 ? 2 : 1
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true

            Repeater {
                model: [
                    { id: "org.enthroned.classic", title: "Enthroned Classic",
                      subtitle: i18n("Light theme, solid panel, menu on the left, clock with date (inspired by Zorin OS)."),
                      scheme: "Enthroned Light",
                      wallpaper: "file:///usr/share/wallpapers/EnthronedVigilia/contents/screenshot.png" },
                    { id: "org.enthroned.modern", title: "Enthroned Modern",
                      subtitle: i18n("Dark theme, centered floating panel, clock with time only (inspired by Windows 11)."),
                      scheme: "Enthroned Dark",
                      wallpaper: "file:///usr/share/wallpapers/EnthronedVigilia/contents/screenshot.png" }
                ]

                delegate: Kirigami.AbstractCard {
                    id: profileCard
                    required property var modelData
                    readonly property bool isActive: profiles.activeProfile === modelData.id

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        ProfilePreview {
                            Layout.maximumWidth: Kirigami.Units.gridUnit * 40
                            modern: profileCard.modelData.id === "org.enthroned.modern"
                            active: profileCard.isActive
                            wallpaper: profileCard.modelData.wallpaper
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Heading {
                                level: 3
                                text: modelData.title
                                Layout.fillWidth: true
                            }
                            Kirigami.Icon {
                                visible: profileCard.isActive
                                source: "dialog-ok-apply"
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                            }
                            QQC2.Label {
                                visible: profileCard.isActive
                                text: i18n("Active")
                                color: Kirigami.Theme.positiveTextColor
                                font.bold: true
                            }
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: modelData.subtitle
                            color: Kirigami.Theme.disabledTextColor
                        }

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            QQC2.Button {
                                text: i18n("Apply profile")
                                icon.name: "view-restore"
                                enabled: profiles.toolPresent && !profiles.busy && !profileCard.isActive
                                onClicked: root.requestApply(modelData.id)
                                Accessible.description: i18n("Applies the appearance profile after confirmation")
                            }
                            QQC2.Label {
                                visible: profiles.busy
                                text: i18n("Applying…")
                                color: Kirigami.Theme.disabledTextColor
                            }
                        }
                    }
                }
            }
        }

        QQC2.Button {
            text: i18n("Restore previous appearance")
            icon.name: "edit-undo"
            enabled: profiles.toolPresent && !profiles.busy && profiles.canRestore
            onClicked: profiles.restore()
        }

        SettingRow {
            Layout.topMargin: Kirigami.Units.largeSpacing
            title: i18n("Light or dark theme")
            subtitle: i18n("Your profile, panel and wallpaper stay as they are.")
            QQC2.Button {
                text: i18n("Light")
                icon.name: "weather-clear"
                checkable: false
                highlighted: !personalization.dark
                enabled: personalization.schemeAvailable("light") && !personalization.busy
                onClicked: personalization.applyScheme("light")
                Accessible.description: i18n("Applies the light Enthroned Light color scheme")
            }
            QQC2.Button {
                text: i18n("Dark")
                icon.name: "weather-clear-night"
                highlighted: personalization.dark
                enabled: personalization.schemeAvailable("dark") && !personalization.busy
                onClicked: personalization.applyScheme("dark")
                Accessible.description: i18n("Applies the dark Enthroned Dark color scheme")
            }
        }

        SettingRow {
            id: accentRow
            title: i18n("Accent color")
            subtitle: i18n("Used for selections, focus and the rectangle you drag to select icons. Kept when you switch between light and dark.")
            separator: false

            Flow {
                width: Kirigami.Units.gridUnit * 20
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: root.accents
                    delegate: ColorSwatch {
                        required property var modelData
                        swatchColor: modelData.color
                        colorName: modelData.name
                        checked: root.pendingAccent === modelData.id
                        enabled: personalization.schemeAvailable("light") && !personalization.busy
                        onClicked: root.pendingAccent = modelData.id
                    }
                }
            }
        }

        // Preview of the pending accent (white text on the accent, like a selected row).
        Rectangle {
            id: accentPreview
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            implicitHeight: previewColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: Kirigami.Units.smallSpacing * 1.5
            color: Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
            Accessible.role: Accessible.StaticText
            Accessible.name: i18n("Preview of the accent color")

            ColumnLayout {
                id: previewColumn
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    text: i18n("Preview")
                    color: Kirigami.Theme.disabledTextColor
                    font: Kirigami.Theme.smallFont
                    Accessible.ignored: true
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Kirigami.Units.gridUnit * 2
                    radius: Kirigami.Units.smallSpacing
                    color: root.accentColor(root.pendingAccent)
                    QQC2.Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        text: i18n("Selected item")
                        color: "white"
                        font.bold: true
                        Accessible.ignored: true
                    }
                }
                RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Rectangle {
                        implicitWidth: Kirigami.Units.gridUnit * 7
                        implicitHeight: Kirigami.Units.gridUnit * 1.6
                        radius: Kirigami.Units.smallSpacing
                        color: root.accentColor(root.pendingAccent)
                        QQC2.Label {
                            anchors.centerIn: parent
                            text: i18n("Main button")
                            color: "white"
                            Accessible.ignored: true
                        }
                    }
                    Rectangle {
                        implicitWidth: Kirigami.Units.gridUnit * 7
                        implicitHeight: Kirigami.Units.gridUnit * 1.6
                        radius: Kirigami.Units.smallSpacing
                        color: "transparent"
                        border.width: 2
                        border.color: root.accentColor(root.pendingAccent)
                        QQC2.Label {
                            anchors.centerIn: parent
                            text: i18n("Focus ring")
                            Accessible.ignored: true
                        }
                    }
                }
            }
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.Button {
                text: i18n("Apply accent color")
                icon.name: "dialog-ok-apply"
                enabled: root.pendingAccent !== personalization.accent && !personalization.busy
                    && personalization.schemeAvailable("light")
                onClicked: personalization.applyAccent(root.pendingAccent)
            }
            QQC2.Button {
                text: i18n("Restore default")
                icon.name: "edit-undo"
                enabled: (personalization.accent !== "" || root.pendingAccent !== "") && !personalization.busy
                    && personalization.schemeAvailable("light")
                onClicked: {
                    root.pendingAccent = "";
                    personalization.applyAccent("");
                }
            }
            QQC2.Label {
                visible: personalization.busy
                text: i18n("Applying…")
                color: Kirigami.Theme.disabledTextColor
            }
        }

        SettingRow {
            Layout.topMargin: Kirigami.Units.largeSpacing
            title: i18n("Window borders")
            subtitle: i18n("Thickness of the frame around windows.")
            ChoiceBox {
                settingId: "borderSize"
                choices: [
                    { value: "", text: i18n("Automatic (default)") },
                    { value: "Tiny", text: i18n("Thin") },
                    { value: "Normal", text: i18n("Normal") },
                    { value: "Large", text: i18n("Wide") }
                ]
                Accessible.name: i18n("Window borders")
            }
        }
        SettingRow {
            title: i18n("Animation speed")
            subtitle: i18n("How quickly windows and menus move.")
            separator: false
            ChoiceBox {
                settingId: "animations"
                choices: [
                    { value: "", text: i18n("Standard (default)") },
                    { value: "0.5", text: i18n("Fast") },
                    { value: "0", text: i18n("Instant") }
                ]
                Accessible.name: i18n("Animation speed")
            }
        }
        //END

        //BEGIN Desktop
        SectionHeading {
            text: i18n("Desktop")
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            text: i18n("The official wallpapers also appear in KDE's own wallpaper picker, together with any image you choose yourself. Your choice is kept when you switch profiles.")
        }
        GridLayout {
            id: wallpaperGrid
            // As many tiles per row as fit; never a fixed overall width.
            readonly property real tileMin: Kirigami.Units.gridUnit * 12
            columns: Math.max(1, Math.floor((root.width - Kirigami.Units.gridUnit * 3) / (tileMin + columnSpacing)))
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true

            Repeater {
                model: [
                    { id: "soberania", name: "Enthroned — Soberania", isDefault: false,
                      url: "file:///usr/share/wallpapers/EnthronedSoberania/contents/screenshot.png" },
                    { id: "ascensao", name: "Enthroned — Ascensão", isDefault: false,
                      url: "file:///usr/share/wallpapers/EnthronedAscensao/contents/screenshot.png" },
                    { id: "vigilia", name: "Enthroned — Vigília", isDefault: true,
                      url: "file:///usr/share/wallpapers/EnthronedVigilia/contents/screenshot.png" }
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: wallpaperGrid.tileMin
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 20
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: width * 9 / 16
                        color: Kirigami.Theme.alternateBackgroundColor
                        radius: Kirigami.Units.smallSpacing
                        clip: true
                        Accessible.ignored: true

                        Image {
                            id: wallpaperImage
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: modelData.url
                            asynchronous: true
                            sourceSize.width: Kirigami.Units.gridUnit * 26
                        }
                        QQC2.Label {
                            anchors.centerIn: parent
                            visible: wallpaperImage.status === Image.Error
                                || wallpaperImage.status === Image.Null
                            text: i18n("Wallpaper not installed")
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        QQC2.Label {
                            text: modelData.name
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        QQC2.Label {
                            visible: modelData.isDefault
                            text: i18n("Default")
                            color: Kirigami.Theme.disabledTextColor
                            font: Kirigami.Theme.smallFont
                        }
                    }
                    QQC2.Button {
                        text: i18n("Set as wallpaper")
                        icon.name: "preferences-desktop-wallpaper"
                        enabled: personalization.wallpaperAvailable(modelData.id) && !personalization.busy
                        onClicked: personalization.applyWallpaper(modelData.id)
                        Accessible.name: i18n("Set %1 as wallpaper", modelData.name)
                        Accessible.description: i18n("Sets %1 as the wallpaper using the Plasma tool", modelData.name)
                    }
                }
            }
        }
        QQC2.Button {
            text: i18n("Use your own image…")
            icon.name: "document-open"
            enabled: !personalization.busy
            onClicked: wallpaperDialog.open()
            Accessible.description: i18n("Choose a PNG, JPEG or WebP image from your files to use as the wallpaper")
        }

        SettingRow {
            Layout.topMargin: Kirigami.Units.largeSpacing
            title: i18n("Desktop icon size")
            subtitle: root.plasmaReachable
                ? i18n("Size of the icons on the desktop. Kept when you switch profiles.")
                : i18n("Available while the Plasma desktop is running.")
            separator: false
            QQC2.ComboBox {
                id: desktopIcons
                readonly property var steps: [
                    { value: 1, text: i18n("Small") },
                    { value: 2, text: i18n("Medium") },
                    { value: 3, text: i18n("Large (default)") },
                    { value: 4, text: i18n("Extra large") }
                ]
                model: steps
                textRole: "text"
                enabled: root.plasmaReachable && !personalization.busy
                Accessible.name: i18n("Desktop icon size")
                Binding {
                    target: desktopIcons
                    property: "currentIndex"
                    value: desktopIcons.steps.findIndex(s => s.value === personalization.desktopIconSize)
                    restoreMode: Binding.RestoreNone
                }
                onActivated: index => personalization.setDesktopIconSize(steps[index].value)
            }
            QQC2.Button {
                text: i18n("Restore default")
                icon.name: "edit-undo"
                enabled: root.plasmaReachable && !personalization.busy && personalization.desktopIconSize !== 3
                onClicked: personalization.setDesktopIconSize(3)
            }
        }
        //END

        //BEGIN Files and folders
        SectionHeading {
            text: i18n("Files and folders")
        }

        SettingRow {
            title: i18n("Folder color")
            subtitle: i18n("Colors one folder, the same way Dolphin's “Set folder icon” does. Pick the folder, then a color.")
            separator: false
            QQC2.Button {
                text: root.chosenFolder.toString().length > 0 ? i18n("Change folder…") : i18n("Choose folder…")
                icon.name: "folder-open"
                enabled: !personalization.busy
                onClicked: folderDialog.open()
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: root.chosenFolder.toString().length > 0
            wrapMode: Text.WrapAnywhere
            text: i18n("Folder: %1", root.folderLabel(root.chosenFolder))
            color: Kirigami.Theme.disabledTextColor
        }
        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: root.folderColours
                delegate: ColorSwatch {
                    required property var modelData
                    iconName: "folder-" + modelData.id
                    colorName: modelData.name
                    checked: root.chosenFolderColour === modelData.id
                    enabled: root.chosenFolder.toString().length > 0 && !personalization.busy
                    onClicked: personalization.setFolderColor(root.chosenFolder, modelData.id)
                }
            }
        }
        QQC2.Button {
            text: i18n("Restore default folder appearance")
            icon.name: "edit-undo"
            enabled: root.chosenFolderColour !== "" && !personalization.busy
            onClicked: personalization.setFolderColor(root.chosenFolder, "")
        }

        SettingRow {
            Layout.topMargin: Kirigami.Units.largeSpacing
            title: i18n("Dolphin: view")
            subtitle: i18n("Applies to every folder you open from now on.")
            ChoiceBox {
                settingId: "viewMode"
                choices: [
                    { value: "1", text: i18n("Details (default)") },
                    { value: "0", text: i18n("Icons") },
                    { value: "2", text: i18n("Compact") }
                ]
                Accessible.name: i18n("Dolphin view")
            }
        }
        SettingRow {
            title: i18n("Dolphin: icon size")
            ChoiceBox {
                settingId: "iconSize"
                choices: [
                    { value: "", text: i18n("Automatic (default)") },
                    { value: "22", text: i18n("Small") },
                    { value: "32", text: i18n("Medium") },
                    { value: "48", text: i18n("Large") },
                    { value: "64", text: i18n("Extra large") }
                ]
                Accessible.name: i18n("Dolphin icon size")
            }
        }
        SettingRow {
            title: i18n("Show hidden files")
            subtitle: i18n("Files and folders whose names start with a dot.")
            ToggleBox {
                settingId: "showHidden"
                defaultOn: false
                Accessible.name: i18n("Show hidden files")
            }
        }
        SettingRow {
            title: i18n("Show previews")
            subtitle: i18n("Thumbnails for images, videos and documents.")
            separator: false
            ToggleBox {
                settingId: "showPreviews"
                defaultOn: true
                Accessible.name: i18n("Show previews")
            }
        }
        QQC2.Button {
            text: i18n("Restore Dolphin defaults")
            icon.name: "edit-undo"
            enabled: !personalization.busy
            onClicked: {
                personalization.setValue("viewMode", "1"); // Enthroned default: Details
                personalization.resetValue("iconSize");
                personalization.resetValue("showHidden");
                personalization.resetValue("showPreviews");
            }
        }
        //END

        //BEGIN Panel and Start menu
        SectionHeading {
            text: i18n("Panel and Start menu")
        }
        SettingRow {
            title: i18n("Panel size")
            subtitle: root.plasmaReachable
                ? i18n("Height of the panel; icons on it scale with it. Switching profile restores that profile's own panel.")
                : i18n("Available while the Plasma desktop is running.")
            QQC2.ComboBox {
                id: panelSize
                readonly property var steps: [
                    { value: 36, text: i18n("Compact") },
                    { value: root.profilePanelHeight, text: i18n("Standard (default)") },
                    { value: 56, text: i18n("Large") }
                ]
                model: steps
                textRole: "text"
                enabled: root.plasmaReachable && !personalization.busy
                Accessible.name: i18n("Panel size")
                Binding {
                    target: panelSize
                    property: "currentIndex"
                    value: panelSize.steps.findIndex(s => s.value === personalization.panelHeight)
                    restoreMode: Binding.RestoreNone
                }
                onActivated: index => personalization.setPanelHeight(steps[index].value)
            }
            QQC2.Button {
                text: i18n("Restore default")
                icon.name: "edit-undo"
                enabled: root.plasmaReachable && !personalization.busy
                    && personalization.panelHeight !== root.profilePanelHeight
                onClicked: personalization.setPanelHeight(root.profilePanelHeight)
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            text: i18n("The Start menu has one icon scale for both profiles, tuned for readability; KDE offers no setting for it, so none is shown here.")
        }
        //END

        SectionHeading {
            text: i18n("More KDE settings")
        }
        ModuleList { modules: root.moreModules }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Individual preferences (icons, application themes, etc.) remain in the native KDE pages: Colors & Themes.")
        }
    }

    Dialogs.FileDialog {
        id: wallpaperDialog
        title: i18n("Choose a wallpaper")
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.webp *.bmp *.gif)")]
        onAccepted: personalization.applyWallpaperFile(selectedFile)
    }

    Dialogs.FolderDialog {
        id: folderDialog
        title: i18n("Choose a folder")
        onAccepted: root.chosenFolder = selectedFolder
    }

    QQC2.Dialog {
        id: applyDialog
        modal: true
        title: i18n("Apply appearance profile")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        parent: applicationWindow().overlay

        ColumnLayout {
            width: Math.min(Kirigami.Units.gridUnit * 24, applicationWindow().width - Kirigami.Units.gridUnit * 4)
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("The profile is applied through Plasma's official mechanism. The panel, Start menu and clock are rebuilt for that profile.\n\nKept: your wallpaper, accent color, desktop icon size, folder colors and Dolphin settings.\nReset: the panel size and any panel or clock change you made by hand.\n\nYou can go back with “Restore previous appearance”.")
            }
        }

        onAccepted: profiles.apply(root.pendingProfileId)
    }

    Component.onCompleted: {
        kcm.refreshAvailable();
        personalization.refresh();
    }

    Connections {
        target: personalization
        function onApplyFinished(ok, message) {
            applicationWindow().showPassiveNotification(
                ok ? i18n("Saved.") : i18n("Could not apply the change: %1", message),
                ok ? 3000 : 8000);
        }
    }

    Connections {
        target: profiles
        function onApplyFinished(ok, message) {
            applicationWindow().showPassiveNotification(
                ok ? i18n("Profile applied through the official Plasma mechanism.")
                   : i18n("Could not apply the profile: %1", message),
                ok ? 4000 : 8000);
        }
    }
}
