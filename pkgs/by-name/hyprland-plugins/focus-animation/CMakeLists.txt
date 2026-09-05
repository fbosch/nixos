cmake_minimum_required(VERSION 3.30)

project(focus-animation LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland)

add_library(focus-animation SHARED main.cpp)
target_link_libraries(focus-animation PRIVATE PkgConfig::HYPRLAND)

include(CTest)
if(BUILD_TESTING)
    add_executable(focus-animation-geometry-test focus_animation_geometry_test.cpp)
    add_test(NAME focus-animation-geometry-test COMMAND focus-animation-geometry-test)
endif()
