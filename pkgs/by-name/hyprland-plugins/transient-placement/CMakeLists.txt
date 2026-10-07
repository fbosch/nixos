cmake_minimum_required(VERSION 3.30)
project(transient-placement LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland)

add_library(transient-placement SHARED main.cpp)
target_link_libraries(transient-placement PRIVATE PkgConfig::HYPRLAND)

include(CTest)
if(BUILD_TESTING)
    add_executable(transient-placement-policy-test policy_test.cpp)
    add_test(NAME transient-placement-policy-test COMMAND transient-placement-policy-test)
endif()
