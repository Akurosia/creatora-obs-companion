cmake_minimum_required(VERSION 3.28)
# CI injects the version from the pushed vMAJOR.MINOR.PATCH tag.
# Branch and PR builds use the non-release version 0.0.0.
set(CREATORA_BUILD_VERSION "0.0.0" CACHE STRING "Tag-derived Creatora plugin version")
if(NOT CREATORA_BUILD_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  message(FATAL_ERROR "CREATORA_BUILD_VERSION must be MAJOR.MINOR.PATCH")
endif()
project(creatora-obs-companion VERSION ${CREATORA_BUILD_VERSION} LANGUAGES CXX)
set(CREATORA_GITHUB_REPOSITORY "Akurosia/creatora-obs-companion" CACHE STRING "owner/repo hosting public GitHub Releases")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Use an actual OBS *development* installation, not the OBS runtime directory.
# OBS_SDK_ROOT may be a prefix containing lib/cmake/libobs, or a parent
# directory containing OBS build/install exports.
set(CREATORA_OBS_MAJOR "33" CACHE STRING "Target OBS Studio major release (32 or 33)")
set_property(CACHE CREATORA_OBS_MAJOR PROPERTY STRINGS 32 33)
if(NOT CREATORA_OBS_MAJOR MATCHES "^(32|33)$")
  message(FATAL_ERROR "CREATORA_OBS_MAJOR must be 32 or 33")
endif()
set(OBS_SDK_ROOT "" CACHE PATH "OBS SDK installation/build root (containing libobsConfig.cmake)")
if(OBS_SDK_ROOT)
  file(GLOB_RECURSE _obs_configs LIST_DIRECTORIES FALSE
       "${OBS_SDK_ROOT}/*libobsConfig.cmake"
       "${OBS_SDK_ROOT}/*libobs-config.cmake")
  if(_obs_configs)
    list(GET _obs_configs 0 _obs_config)
    get_filename_component(_obs_config_dir "${_obs_config}" DIRECTORY)
    if(NOT libobs_DIR)
      set(libobs_DIR "${_obs_config_dir}" CACHE PATH "libobs CMake package directory" FORCE)
    endif()
  endif()
  file(GLOB_RECURSE _frontend_configs LIST_DIRECTORIES FALSE
       "${OBS_SDK_ROOT}/*obs-frontend-apiConfig.cmake"
       "${OBS_SDK_ROOT}/*obs-frontend-api-config.cmake")
  if(_frontend_configs)
    list(GET _frontend_configs 0 _frontend_config)
    get_filename_component(_frontend_config_dir "${_frontend_config}" DIRECTORY)
    if(NOT obs-frontend-api_DIR)
      set(obs-frontend-api_DIR "${_frontend_config_dir}" CACHE PATH "OBS frontend CMake package directory" FORCE)
    endif()
  endif()
  list(PREPEND CMAKE_PREFIX_PATH "${OBS_SDK_ROOT}")
endif()

find_package(libobs CONFIG QUIET)
if(NOT libobs_FOUND)
  message(FATAL_ERROR
    "OBS development libraries are missing. The OBS app folder is not an SDK. "
    "Build/install the OBS 32 or 33 development libraries or use the official "
    "obs-plugintemplate dependency bootstrap, then pass "
    "-DOBS_SDK_ROOT=C:/your/real/obs-sdk OR -Dlibobs_DIR=... . "
    "Do not use C:/path/to/obs-and-qt-sdk (that was only a placeholder).")
endif()
find_package(obs-frontend-api CONFIG REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Widgets Network WebSockets)

# Fail explicitly when a different major OBS SDK is supplied.
if(DEFINED libobs_VERSION AND NOT "${libobs_VERSION}" STREQUAL "")
  if(NOT libobs_VERSION VERSION_GREATER_EQUAL "${CREATORA_OBS_MAJOR}.0.0" OR
     NOT libobs_VERSION VERSION_LESS "${CREATORA_OBS_MAJOR}.999.999")
    message(FATAL_ERROR "Creatora OBS Companion targets OBS ${CREATORA_OBS_MAJOR}.x; found libobs ${libobs_VERSION}")
  endif()
  message(STATUS "Building Creatora against OBS libobs ${libobs_VERSION}")
else()
  message(WARNING "libobs package did not expose a version. Ensure this SDK is from OBS ${CREATORA_OBS_MAJOR}.x.")
endif()

add_library(creatora-obs-companion MODULE
  src/plugin.cpp
  src/companion.cpp
  src/companion.hpp
)
target_compile_definitions(creatora-obs-companion PRIVATE
  CREATORA_PLUGIN_VERSION="${PROJECT_VERSION}"
  CREATORA_RELEASE_REPOSITORY="${CREATORA_GITHUB_REPOSITORY}"
)
target_link_libraries(creatora-obs-companion PRIVATE
  OBS::libobs OBS::obs-frontend-api
  Qt6::Core Qt6::Widgets Qt6::Network Qt6::WebSockets
)
if(WIN32)
  target_link_libraries(creatora-obs-companion PRIVATE Crypt32)
endif()
set_target_properties(creatora-obs-companion PROPERTIES
  PREFIX ""
  OUTPUT_NAME "creatora-obs-companion"
)
install(TARGETS creatora-obs-companion
  LIBRARY DESTINATION "obs-plugins/64bit"
  RUNTIME DESTINATION "obs-plugins/64bit")
