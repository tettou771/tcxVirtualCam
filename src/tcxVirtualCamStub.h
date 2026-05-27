#pragma once

// =============================================================================
// tcxVirtualCamStub.h - Inline no-op backend
// =============================================================================
//
// Used until a real platform backend (DAL plug-in / DirectShow filter /
// v4l2loopback writer) is wired in. Keeps the addon header-only and lets
// user code compile and run on every platform.
//
// When a real backend lands, it should:
//   1. Define TCX_VIRTUALCAM_HAS_BACKEND before this header is included, OR
//   2. Replace this file with platform-specific .cpp/.mm definitions.
// =============================================================================

#include "tcxVirtualCamSender.h"

namespace tcx {

#ifndef TCX_VIRTUALCAM_HAS_BACKEND

inline bool VirtualCam::setupBackend() {
    // Backend not yet available on this platform.
    return false;
}

inline void VirtualCam::closeBackend() {
    // No-op.
}

inline bool VirtualCam::sendBackend(const unsigned char* /*rgba*/,
                                    int /*w*/, int /*h*/) {
    // No-op: nothing to send to yet.
    return false;
}

#endif // TCX_VIRTUALCAM_HAS_BACKEND

} // namespace tcx
