cmake_minimum_required(VERSION 3.30)

project(cursor-outline LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland)
pkg_check_modules(GLESV2 REQUIRED IMPORTED_TARGET glesv2)

add_library(cursor-outline SHARED main.cpp)
target_link_libraries(cursor-outline PRIVATE PkgConfig::HYPRLAND PkgConfig::GLESV2)
