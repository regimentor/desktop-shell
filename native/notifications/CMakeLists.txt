cmake_minimum_required(VERSION 3.20)
project(daevox_notifications LANGUAGES C CXX)
set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
find_package(Qt6 REQUIRED COMPONENTS Quick Qml DBus)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
add_custom_command(OUTPUT lock-client.h lock-protocol.c
    COMMAND ${WAYLAND_SCANNER} client-header ${CMAKE_CURRENT_SOURCE_DIR}/lock.xml lock-client.h
    COMMAND ${WAYLAND_SCANNER} private-code ${CMAKE_CURRENT_SOURCE_DIR}/lock.xml lock-protocol.c
    DEPENDS lock.xml)
add_library(daevoxnotifications MODULE plugin.cpp lock-protocol.c lock-client.h)
target_include_directories(daevoxnotifications PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(daevoxnotifications PRIVATE Qt6::Quick Qt6::Qml Qt6::DBus PkgConfig::WAYLAND)
target_compile_options(daevoxnotifications PRIVATE -Wall -Wextra -Werror)
