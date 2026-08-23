cmake_minimum_required(VERSION 3.30)

project(custom-layout-pointer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland)

add_library(custom-layout-pointer SHARED main.cpp)
target_link_libraries(custom-layout-pointer PRIVATE PkgConfig::HYPRLAND)
