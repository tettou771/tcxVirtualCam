# =============================================================================
# TrussCVirtualCamDAL - CoreMediaIO DAL Plug-In bundle
# =============================================================================
#
# Builds a .plugin bundle that lives in /Library/CoreMediaIO/Plug-Ins/DAL/.
# This target is NOT linked into user apps; it's a one-time install per machine.
#
# Phase 1A: bundle skeleton + factory entry point only — no Device / Stream
# objects yet. Goal is just for cmio to be able to load the bundle without
# crashing.
# =============================================================================

cmake_minimum_required(VERSION 3.16)
project(TrussCVirtualCamDAL LANGUAGES C CXX OBJC OBJCXX)

set(PLUGIN_NAME       "TrussCVirtualCamDAL")
set(PLUGIN_BUNDLE_ID  "org.trussc.virtualcam.dal")
set(PLUGIN_FACTORY_UUID "23A6DB67-8CCA-4F60-AB4E-FEDCCE7C14B0")

# -----------------------------------------------------------------------------
# Info.plist (UUIDs substituted via configure_file)
# -----------------------------------------------------------------------------

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in
    ${CMAKE_CURRENT_BINARY_DIR}/Info.plist
    @ONLY
)

# -----------------------------------------------------------------------------
# Sources
# -----------------------------------------------------------------------------

set(_PLUGIN_SOURCES
    PlugInMain.mm
)

# -----------------------------------------------------------------------------
# Bundle target
# -----------------------------------------------------------------------------

add_library(${PLUGIN_NAME} MODULE ${_PLUGIN_SOURCES})

set_target_properties(${PLUGIN_NAME} PROPERTIES
    BUNDLE                            TRUE
    BUNDLE_EXTENSION                  "plugin"
    MACOSX_BUNDLE_INFO_PLIST          ${CMAKE_CURRENT_BINARY_DIR}/Info.plist
    MACOSX_BUNDLE_BUNDLE_NAME         ${PLUGIN_NAME}
    MACOSX_BUNDLE_GUI_IDENTIFIER      ${PLUGIN_BUNDLE_ID}
    MACOSX_BUNDLE_BUNDLE_VERSION      "0.1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
    OUTPUT_NAME                       ${PLUGIN_NAME}
    XCODE_ATTRIBUTE_WRAPPER_EXTENSION "plugin"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
    "-framework CoreFoundation"
    "-framework CoreMediaIO"
    "-framework CoreMedia"
    "-framework CoreVideo"
    "-framework Foundation"
    "-framework IOSurface"
)

target_compile_options(${PLUGIN_NAME} PRIVATE
    -Wno-deprecated-declarations  # CMIOHardwarePlugIn API is deprecated but still functional
    -fobjc-arc
)

# Suppress dynamic-loader missing-symbol checks since the plug-in is loaded
# via dlopen from the cmio assistant.
set_target_properties(${PLUGIN_NAME} PROPERTIES
    LINK_FLAGS "-undefined dynamic_lookup"
)

message(STATUS "tcxVirtualCam plug-in: ${PLUGIN_NAME}.plugin")
message(STATUS "  Factory UUID:  ${PLUGIN_FACTORY_UUID}")
message(STATUS "  Bundle ID:     ${PLUGIN_BUNDLE_ID}")
message(STATUS "  Install path:  /Library/CoreMediaIO/Plug-Ins/DAL/${PLUGIN_NAME}.plugin")
