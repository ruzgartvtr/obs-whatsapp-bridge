cmake_minimum_required(VERSION 3.28)

project(obs-whatsapp-bridge VERSION 1.0.0 LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS version")

option(BUILD_AUDIO_DRIVER "Build OBS Bridge Mic Audio Server Plugin" ON)

# --- OBS plugin ---
find_package(libobs REQUIRED)
find_package(obs-frontend-api REQUIRED)

add_library(obs-whatsapp-bridge MODULE
  src/plugin-main.cpp
  src/audio-bridge.cpp
  src/audio-bridge.hpp
  src/whatsapp-compat.mm
  src/whatsapp-compat.hpp
  src/bridge-ui.mm
  src/bridge-ui.hpp
)

target_link_libraries(obs-whatsapp-bridge PRIVATE
  OBS::libobs
  OBS::obs-frontend-api
  "-framework Cocoa"
  "-framework CoreAudio"
  "-framework AudioToolbox"
  "-framework AppKit"
  "-framework ApplicationServices"
)

target_compile_definitions(obs-whatsapp-bridge PRIVATE
  PLUGIN_NAME="obs-whatsapp-bridge"
  PLUGIN_VERSION="${PROJECT_VERSION}"
  OBS_BRIDGE_MIC_NAME="OBS Bridge Mic"
)

set_target_properties(obs-whatsapp-bridge PROPERTIES
  PREFIX ""
  OUTPUT_NAME "obs-whatsapp-bridge"
  BUNDLE TRUE
  BUNDLE_EXTENSION "plugin"
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/data/Info.plist.in"
  MACOSX_BUNDLE_BUNDLE_NAME "OBS WhatsApp Bridge"
  MACOSX_BUNDLE_GUI_IDENTIFIER "com.obsproject.whatsapp-bridge"
  MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
)

install(TARGETS obs-whatsapp-bridge
  LIBRARY DESTINATION "obs-plugins"
  BUNDLE DESTINATION "obs-plugins"
)

install(DIRECTORY data/locale DESTINATION data/obs-plugins/obs-whatsapp-bridge)
install(PROGRAMS data/enable-whatsapp.sh DESTINATION data/obs-plugins/obs-whatsapp-bridge)

# --- Virtual microphone (Audio Server Plugin) ---
if(BUILD_AUDIO_DRIVER)
  add_library(OBSBridgeMic MODULE
    mac/OBSBridgeMic/OBSBridgeMic.c
    mac/OBSBridgeMic/OBSBridgeMic.h
  )

  target_include_directories(OBSBridgeMic PRIVATE mac/OBSBridgeMic)
  target_link_libraries(OBSBridgeMic PRIVATE
    "-framework CoreAudio"
    "-framework CoreFoundation"
  )

  set_target_properties(OBSBridgeMic PROPERTIES
    PREFIX ""
    BUNDLE TRUE
    BUNDLE_EXTENSION "driver"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/mac/OBSBridgeMic/Info.plist.in"
    OUTPUT_NAME "OBSBridgeMic"
  )

  install(TARGETS OBSBridgeMic
    BUNDLE DESTINATION "Library/Audio/Plug-Ins/HAL"
  )
endif()
