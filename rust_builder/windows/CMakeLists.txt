# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "rust_lib_misa_rin")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "rust_lib_misa_rin_plugin")

add_library(${PLUGIN_NAME} SHARED
  "rust_lib_misa_rin_plugin.cpp"
  "include/rust_lib_misa_rin/rust_lib_misa_rin_plugin.h"
)

apply_standard_settings(${PLUGIN_NAME})

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin dwmapi)

include("../cargokit/cmake/cargokit.cmake")

# CMake may expose CMAKE_CURRENT_SOURCE_DIR as a symlink path or a resolved
# path depending on platform/version. Probe both common layouts and pass an
# absolute manifest directory to avoid path-dependent CI failures.
set(_RUST_MANIFEST_DIR "")
set(_RUST_MANIFEST_CANDIDATES
  "${CMAKE_CURRENT_SOURCE_DIR}/../../rust"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../rust"
)
foreach(_candidate IN LISTS _RUST_MANIFEST_CANDIDATES)
  if (EXISTS "${_candidate}/Cargo.toml")
    get_filename_component(_RUST_MANIFEST_DIR "${_candidate}" ABSOLUTE)
    break()
  endif()
endforeach()
if (NOT _RUST_MANIFEST_DIR)
  message(FATAL_ERROR "Failed to locate rust/Cargo.toml from ${CMAKE_CURRENT_SOURCE_DIR}")
endif()

apply_cargokit(${PLUGIN_NAME} "${_RUST_MANIFEST_DIR}" rust_lib_misa_rin "engine_create")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(rust_lib_misa_rin_bundled_libraries
  "${${PLUGIN_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
