# Enthroned OS - ContainmentActions plugin for the desktop context menu.
# Wraps the stock Plasma menu (org.kde.contextmenu) and prepends the
# "Configurações do Enthroned" entry. Built in the image apps-builder stage
# (see Containerfile); only public Plasma/KF6 API is used.
# SPDX-License-Identifier: Apache-2.0
cmake_minimum_required(VERSION 3.24)

project(enthroned-desktop-actions
    VERSION 0.1.0
    DESCRIPTION "Enthroned OS desktop context menu plugin"
    LANGUAGES CXX)

# KDECMakeSettings only sets CMAKE_LIBRARY_OUTPUT_DIRECTORY when
# ECM_GLOBAL_FIND_VERSION >= 5.38.0; keep the version aligned with the
# sibling projects (settings/, welcome/).
set(KF6_MIN_VERSION "6.5.0")
find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 REQUIRED COMPONENTS Core Gui)
find_package(KF6 REQUIRED COMPONENTS Config CoreAddons)
find_package(Plasma REQUIRED)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

kcoreaddons_add_plugin(enthroned_contextmenu
    SOURCES src/enthronedcontextmenu.cpp
    INSTALL_NAMESPACE "plasma/containmentactions")

set_target_properties(enthroned_contextmenu PROPERTIES
    OUTPUT_NAME org.enthroned.contextmenu)

target_link_libraries(enthroned_contextmenu
    Qt6::Core
    Qt6::Gui
    KF6::ConfigCore
    KF6::CoreAddons
    Plasma::Plasma)

# Lote 10 (P1-1): supervised Settings launch (crash-safe, with retry).
include(CTest)
if(BUILD_TESTING)
    add_executable(settingslauncher-smoke tests/settingslauncher-smoke.cpp)
    target_include_directories(settingslauncher-smoke PRIVATE src)
    target_link_libraries(settingslauncher-smoke PRIVATE Qt6::Core)
    add_test(NAME settingslauncher-smoke COMMAND settingslauncher-smoke)
endif()
