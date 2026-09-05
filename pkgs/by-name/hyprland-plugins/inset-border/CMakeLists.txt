cmake_minimum_required(VERSION 3.30)

project(inset-border LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland)

set(COMMON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../common")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${COMMON_DIR}/gradient.glsl")
file(READ "${COMMON_DIR}/gradient.glsl" GRADIENT_GLSL_SOURCE)
configure_file(
    "${COMMON_DIR}/gradient_shader.hpp.in"
    "${CMAKE_CURRENT_BINARY_DIR}/gradient_shader.hpp"
    @ONLY
)

add_library(inset-border SHARED main.cpp)
target_include_directories(inset-border PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(inset-border PRIVATE PkgConfig::HYPRLAND)

include(CTest)
if(BUILD_TESTING)
    set(GRADIENT_TEST_TARGET "${PROJECT_NAME}-gradient-test")
    add_executable(${GRADIENT_TEST_TARGET} "${COMMON_DIR}/gradient_progress_test.cpp")
    target_include_directories(${GRADIENT_TEST_TARGET} PRIVATE "${COMMON_DIR}")
    add_test(NAME ${GRADIENT_TEST_TARGET} COMMAND $<TARGET_FILE:${GRADIENT_TEST_TARGET}>)
    set_tests_properties(${GRADIENT_TEST_TARGET} PROPERTIES LABELS "not-gpu-validation")
endif()
