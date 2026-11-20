# Enthroned Settings - central de configuracoes e atualizacoes do Enthroned OS.
# F3 - aplicacao Qt Quick/Kirigami nativa (C++ backend + QML).
# SPDX-License-Identifier: Apache-2.0
cmake_minimum_required(VERSION 3.24)

project(enthroned-settings
    VERSION 0.1.0
    DESCRIPTION "Enthroned Settings - central de configuracoes e atualizacoes"
    LANGUAGES CXX)

set(QT_MIN_VERSION "6.6.0")
set(KF6_MIN_VERSION "6.5.0")

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Quick QuickControls2 Widgets DBus)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS Kirigami I18n Notifications)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

qt_standard_project_setup(REQUIRES 6.6)

set(ENTHRONED_SETTINGS_SOURCES
    src/main.cpp
    src/systemidentityprovider.cpp
    src/deviceinfoprovider.cpp
    src/personalizationcontroller.cpp
    src/preferencemanager.cpp
    src/bootcstatusprovider.cpp
    src/flatpakupdatesprovider.cpp
    src/profilecontroller.cpp
    src/kcmlauncher.cpp
    src/update/updateevent.cpp
    src/update/updatestatemachine.cpp
    src/update/journalparser.cpp
    src/update/systemdcalls.cpp
    src/update/journalprogresssource.cpp
    src/update/connectivitymonitor.cpp
    src/update/updateengine.cpp
    src/update/historylog.cpp
    src/update/notificationpresenter.cpp
)

qt_add_executable(enthroned-settings ${ENTHRONED_SETTINGS_SOURCES})

target_include_directories(enthroned-settings PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

target_link_libraries(enthroned-settings PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    Qt6::DBus
    KF6::Kirigami
    KF6::I18n
    KF6::Notifications
)

qt_add_qml_module(enthroned-settings
    URI org.enthroned.settings
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/SearchIndex.qml
        qml/search.js
        qml/components/InfoRow.qml
        qml/components/EmptyState.qml
        qml/components/StatusIcon.qml
        qml/components/ProfilePreview.qml
        qml/components/BrandWordmark.qml
        qml/components/SectionHeading.qml
        qml/components/SettingRow.qml
        qml/components/ColorSwatch.qml
        qml/components/ChoiceBox.qml
        qml/components/ToggleBox.qml
        qml/components/ModuleCard.qml
        qml/components/ModuleList.qml
        qml/components/ShortcutTile.qml
        qml/components/SettingsPage.qml
        qml/pages/HomePage.qml
        qml/pages/FocusPage.qml
        qml/pages/SystemPage.qml
        qml/pages/DevicesPage.qml
        qml/pages/NetworkPage.qml
        qml/pages/AppearancePage.qml
        qml/pages/AppsPage.qml
        qml/pages/AccountsPage.qml
        qml/pages/TimeLanguagePage.qml
        qml/pages/AccessibilityPage.qml
        qml/pages/PrivacyPage.qml
        qml/pages/UpdatesPage.qml
        qml/pages/AboutPage.qml
)

# Shared machine-state contract + demo scenarios embedded in the binary.
# The same spec is consumed by settings/tests/run-tests.mjs (logic tests).
qt_add_resources(enthroned-settings "enthroned-settings-data"
    PREFIX "/"
    FILES
        src/update/update-state-spec.json
        src/update/demo/scenarios/up-to-date.json
        src/update/demo/scenarios/update-available.json
        src/update/demo/scenarios/downloading.json
        src/update/demo/scenarios/preparing.json
        src/update/demo/scenarios/failure.json
        src/update/demo/scenarios/restart-pending.json
        src/update/demo/scenarios/service-unavailable.json
        src/update/demo/scenarios/progress-without-percent.json
        src/update/demo/scenarios/two-providers.json
        src/update/demo/scenarios/unexpected-data.json
        src/update/demo/scenarios/cancel.json
        src/update/demo/scenarios/concurrent.json
        src/update/demo/scenarios/system-update.json
        src/update/demo/scenarios/apps-update.json
        src/update/demo/scenarios/rollback-success.json
        src/update/demo/scenarios/rollback-failed.json
        src/update/demo/scenarios/preflight-blocked.json
        src/update/demo/scenarios/download-interrupted.json
        src/update/demo/scenarios/origin-unauthorized.json
        src/update/demo/scenarios/staged-recovery.json
)

install(TARGETS enthroned-settings ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES data/org.enthroned.settings.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES data/org.enthroned.settings.appdata.xml DESTINATION ${KDE_INSTALL_METAINFODIR})
install(FILES data/enthronedsettings.notifyrc DESTINATION ${KDE_INSTALL_KNOTIFYRCDIR})
# Gate 13.1: official raster icon set (scripts/gen-brand-assets.py), hicolor PNGs 16-512.
install(DIRECTORY data/icons/hicolor DESTINATION ${KDE_INSTALL_FULL_ICONDIR})

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)

include(CTest)
if(BUILD_TESTING)
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        add_library(settings-close-fixture MODULE tests/close-window.cpp)
        target_link_libraries(settings-close-fixture PRIVATE Qt6::Quick)
        file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/close-test-home")
        add_test(NAME settings-close-smoke COMMAND enthroned-settings --demo)
        set_property(TEST settings-close-smoke PROPERTY ENVIRONMENT
            "LD_PRELOAD=$<TARGET_FILE:settings-close-fixture>"
            "QT_QPA_PLATFORM=offscreen"
            "QT_QUICK_BACKEND=software"
            "QT_QUICK_CONTROLS_STYLE=org.kde.desktop"
            "HOME=${CMAKE_CURRENT_BINARY_DIR}/close-test-home"
            "XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/close-test-home/config"
            "XDG_STATE_HOME=${CMAKE_CURRENT_BINARY_DIR}/close-test-home/state")
        set_tests_properties(settings-close-smoke PROPERTIES TIMEOUT 20)
    endif()

    qt_add_executable(settings-native-smoke tests/native-smoke.cpp
        src/update/updatestatemachine.cpp src/update/updateevent.cpp)
    target_include_directories(settings-native-smoke PRIVATE src)
    target_link_libraries(settings-native-smoke PRIVATE Qt6::Core)
    add_test(NAME settings-native-smoke COMMAND settings-native-smoke
        "${CMAKE_CURRENT_SOURCE_DIR}/src/update/update-state-spec.json")

    # Lote 9.2 (H4-005): user Flatpak update process lifecycle against a
    # fake flatpak program (crash, exit 1, exit 0, failed to start).
    qt_add_executable(flatpak-lifecycle-smoke tests/flatpak-lifecycle-smoke.cpp
        src/flatpakupdatesprovider.cpp)
    target_include_directories(flatpak-lifecycle-smoke PRIVATE src)
    target_link_libraries(flatpak-lifecycle-smoke PRIVATE Qt6::Core KF6::I18n)
    add_test(NAME flatpak-lifecycle-smoke COMMAND flatpak-lifecycle-smoke)

    # Lote 10 (P1-2): bootc status read from the root-owned per-boot cache
    # (enthroned-bootc-status.service); the direct bootc execution stays a
    # test-only seam. No real bootc is ever executed.
    qt_add_executable(bootc-status-smoke tests/bootc-status-smoke.cpp
        src/bootcstatusprovider.cpp)
    target_include_directories(bootc-status-smoke PRIVATE src)
    target_link_libraries(bootc-status-smoke PRIVATE Qt6::Core KF6::I18n)
    add_test(NAME bootc-status-smoke COMMAND bootc-status-smoke)

    # Lote 9.4 (R93-01/R93-02): UpdateEngine integration test with a scripted
    # SystemdCalls double, a fake bootc on PATH and a fake flatpak program.
    # Covers job correlation, stale-state protection, the Flatpak operation
    # identity regression (timeout -> retry -> late result) and the refusal
    # guards. No systemd unit and no real flatpak is ever started.
    qt_add_executable(update-engine-integration-smoke
        tests/update-engine-integration-smoke.cpp
        src/bootcstatusprovider.cpp
        src/flatpakupdatesprovider.cpp
        src/systemidentityprovider.cpp
        src/update/connectivitymonitor.cpp
        src/update/historylog.cpp
        src/update/journalparser.cpp
        src/update/journalprogresssource.cpp
        src/update/notificationpresenter.cpp
        src/update/systemdcalls.cpp
        src/update/updateengine.cpp
        src/update/updateevent.cpp
        src/update/updatestatemachine.cpp)
    target_include_directories(update-engine-integration-smoke PRIVATE src)
    target_link_libraries(update-engine-integration-smoke PRIVATE
        Qt6::Core Qt6::DBus KF6::I18n KF6::Notifications)
    qt_add_resources(update-engine-integration-smoke "update-engine-integration-smoke-data"
        PREFIX "/"
        FILES src/update/update-state-spec.json)
    add_test(NAME update-engine-integration-smoke COMMAND update-engine-integration-smoke)

    # Lote 15: PersonalizationController against the real kwriteconfig6/
    # kreadconfig6 in an isolated HOME and a fake plasma-apply-colorscheme.
    qt_add_executable(personalization-smoke tests/personalization-smoke.cpp
        src/personalizationcontroller.cpp)
    target_include_directories(personalization-smoke PRIVATE src)
    target_link_libraries(personalization-smoke PRIVATE Qt6::Gui Qt6::DBus KF6::I18n)
    add_test(NAME personalization-smoke COMMAND personalization-smoke)
    set_tests_properties(personalization-smoke PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 60)
endif()
