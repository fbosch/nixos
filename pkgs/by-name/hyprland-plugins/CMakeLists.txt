cmake_minimum_required(VERSION 3.30)

project(hyprland-plugins LANGUAGES CXX)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
# clangd does not inherit the Nix compiler wrapper's implicit include paths.
set(CMAKE_CXX_STANDARD_INCLUDE_DIRECTORIES ${CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES})
include(CTest)

add_subdirectory(adaptive-soft-shadow)
add_subdirectory(anr-tag-ignore)
add_subdirectory(cursor-outline)
add_subdirectory(custom-layout-resize)
add_subdirectory(focus-animation)
add_subdirectory(inset-border)
add_subdirectory(pointer-edge-hooks)
add_subdirectory(window-interaction-hooks)
