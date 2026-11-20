# Enthroned Welcome - assistente de primeira experiencia do Enthroned OS.
# F4 - aplicacao Qt Quick/Kirigami nativa (C++ backend + QML).
# SPDX-License-Identifier: Apache-2.0
cmake_minimum_required(VERSION 3.24)

project(enthroned-welcome
    VERSION 0.1.0
    DESCRIPTION "Enthroned Welcome - assistente de primeira experiencia"
    LANGUAGES CXX)

# GenericStateLocation, used by the persisted first-login contract, needs 6.7.
set(QT_MIN_VERSION "6.7.0")
set(KF6_MIN_VERSION "6.5.0")

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Quick QuickControls2 Widgets Network)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS Kirigami I18n)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

qt_standard_project_setup(REQUIRES 6.7)

set(ENTHRONED_WELCOME_SOURCES
    src/main.cpp
    src/welcomecontroller.cpp
    src/appavailability.cpp
    src/profilebridge.cpp
    src/artcraftinstaller.cpp
)

qt_add_executable(enthroned-welcome ${ENTHRONED_WELCOME_SOURCES})

target_include_directories(enthroned-welcome PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

target_link_libraries(enthroned-welcome PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    Qt6::Network
    KF6::Kirigami
    KF6::I18n
)

qt_add_qml_module(enthroned-welcome
    URI org.enthroned.welcome
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/StepDots.qml
        qml/components/ProfilePreview.qml
        qml/pages/WelcomePage.qml
        qml/pages/StylePage.qml
        qml/pages/AppsPage.qml
        qml/pages/ArtcraftPage.qml
        qml/pages/FinishPage.qml
        qml/pages/RoadmapPage.qml
)

# Shared first-run contract + installer demo scenarios embedded in the binary.
# The same spec is consumed by welcome/tests/run-tests.mjs (logic tests).
qt_add_resources(enthroned-welcome "enthroned-welcome-data"
    PREFIX "/"
    FILES
        src/welcome-state-spec.json
        src/demo/scenarios/install-complete.json
        src/demo/scenarios/install-failed.json
        src/demo/scenarios/download-unavailable.json
        src/demo/scenarios/offline.json
)

install(TARGETS enthroned-welcome ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES data/org.enthroned.welcome.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES data/org.enthroned.welcome.appdata.xml DESTINATION ${KDE_INSTALL_METAINFODIR})
install(FILES data/org.enthroned.welcome.autostart.desktop
        DESTINATION ${KDE_INSTALL_SYSCONFDIR}/xdg/autostart)
# Gate 13.1: official raster icon set (scripts/gen-brand-assets.py), hicolor PNGs 16-512.
install(DIRECTORY data/icons/hicolor DESTINATION ${KDE_INSTALL_FULL_ICONDIR})

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)

include(CTest)
if(BUILD_TESTING)
    qt_add_executable(welcome-native-smoke tests/native-smoke.cpp src/welcomecontroller.cpp)
    target_include_directories(welcome-native-smoke PRIVATE src)
    target_link_libraries(welcome-native-smoke PRIVATE Qt6::Core)
    qt_add_resources(welcome-native-smoke "welcome-test-data"
        PREFIX "/" FILES src/welcome-state-spec.json)
    add_test(NAME welcome-native-smoke COMMAND welcome-native-smoke)
endif()
