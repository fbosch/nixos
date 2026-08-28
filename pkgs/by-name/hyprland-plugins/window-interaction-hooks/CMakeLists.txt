cmake_minimum_required(VERSION 3.30)

project(window-interaction-hooks LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland)

add_library(window-interaction-hooks SHARED main.cpp)
target_link_libraries(window-interaction-hooks PRIVATE PkgConfig::HYPRLAND)
