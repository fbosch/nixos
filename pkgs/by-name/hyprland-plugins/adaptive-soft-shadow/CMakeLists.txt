cmake_minimum_required(VERSION 3.30)

project(adaptive-soft-shadow LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland)

add_library(adaptive-soft-shadow SHARED main.cpp)
target_link_libraries(adaptive-soft-shadow PRIVATE PkgConfig::HYPRLAND)
