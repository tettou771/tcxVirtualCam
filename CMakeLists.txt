# =============================================================================
# tcxVirtualCam - Virtual camera output addon for TrussC
# =============================================================================
#
# Header-only stub for now. Platform backends (macOS DAL plug-in,
# Windows DirectShow filter, Linux v4l2loopback) will be linked in here
# as they're implemented.
# =============================================================================

cmake_minimum_required(VERSION 3.16)
set(ADDON_NAME tcxVirtualCam)

# -----------------------------------------------------------------------------
# Per-platform backend selection
# -----------------------------------------------------------------------------

set(_BACKEND_AVAILABLE FALSE)
set(_BACKEND_SOURCES)
set(_BACKEND_LIBS)
set(_BACKEND_INCLUDES)

if(APPLE)
    # macOS DAL Plug-In backend — not yet implemented.
    # When it lands:
    #   list(APPEND _BACKEND_SOURCES
    #       platform/mac/host/tcxVirtualCamMac.mm
    #       platform/mac/host/TCIPCHost.mm)
    #   list(APPEND _BACKEND_LIBS "-framework CoreMediaIO"
    #                            "-framework IOSurface"
    #                            "-framework CoreVideo"
    #                            "-framework Foundation")
    #   set(_BACKEND_AVAILABLE TRUE)
    message(STATUS "tcxVirtualCam: macOS backend in development — running in stub mode")
elseif(WIN32)
    message(STATUS "tcxVirtualCam: Windows backend not yet implemented — stub mode")
else()
    message(STATUS "tcxVirtualCam: Linux backend not yet implemented — stub mode")
endif()

# -----------------------------------------------------------------------------
# Addon library
# -----------------------------------------------------------------------------

if(_BACKEND_AVAILABLE)
    add_library(${ADDON_NAME} STATIC ${_BACKEND_SOURCES})
    target_include_directories(${ADDON_NAME} PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${_BACKEND_INCLUDES}
    )
    target_link_libraries(${ADDON_NAME} PUBLIC TrussC ${_BACKEND_LIBS})
    target_compile_definitions(${ADDON_NAME} PUBLIC TCX_VIRTUALCAM_HAS_BACKEND)
else()
    add_library(${ADDON_NAME} INTERFACE)
    target_include_directories(${ADDON_NAME} INTERFACE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    target_link_libraries(${ADDON_NAME} INTERFACE TrussC)
endif()

add_library(tc::${ADDON_NAME} ALIAS ${ADDON_NAME})
