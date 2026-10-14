cmake_minimum_required(VERSION 3.30)

project(custom-layout-resize LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland)

add_library(custom-layout-resize SHARED main.cpp)
target_link_libraries(custom-layout-resize PRIVATE PkgConfig::HYPRLAND)

include(CTest)
if(BUILD_TESTING)
    add_executable(custom-layout-resize-timing-test resize_delivery_timing_test.cpp)
    add_test(NAME custom-layout-resize-timing-test COMMAND custom-layout-resize-timing-test)
endif()
