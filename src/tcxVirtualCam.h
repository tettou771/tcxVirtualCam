#pragma once

// =============================================================================
// tcxVirtualCam - Virtual camera output addon for TrussC
// =============================================================================
//
// Make your TrussC app appear as a webcam to other applications.
//
// Usage:
//   #include <TrussC.h>
//   #include <tcxVirtualCam.h>
//   using namespace tc;
//   using namespace tcx;
//
//   VirtualCam vcam;
//   vcam.setup("My TrussC Cam", 1280, 720);
//   vcam.send(fbo);
//
// Status:
//   - macOS: in development (DAL Plug-In backend)
//   - Windows / Linux: not yet implemented (calls become no-ops)
//
// See docs/DESIGN.md for the architecture and roadmap.
// =============================================================================

#include <TrussC.h>
#include "tcxVirtualCamSender.h"
