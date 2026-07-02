#pragma once

// =============================================================================
// tcxVirtualCamSender.h - Send frames to the platform virtual camera
// =============================================================================
//
// API mirrors tcxNDISender for familiarity. See tcxVirtualCam.h for usage.
//
// Implementation status:
//   - macOS:   stub (no-op, logs warning once on setup)
//   - Windows: stub
//   - Linux:   stub
//
// The stub lets user apps compile and run unchanged once the platform backend
// lands; calls just don't produce visible output yet.
// =============================================================================

#include <TrussC.h>
#include <string>
#include <vector>
#include <cstdint>

namespace tcx::virtualcam {

class VirtualCam {
public:
    VirtualCam() = default;
    ~VirtualCam() { close(); }

    // Non-copyable: owns IPC channel / platform sender state
    VirtualCam(const VirtualCam&) = delete;
    VirtualCam& operator=(const VirtualCam&) = delete;

    // -------------------------------------------------------------------------
    // Setup / Cleanup
    // -------------------------------------------------------------------------

    bool setup(const std::string& name, int width, int height) {
        close();
        name_ = name;
        width_ = width;
        height_ = height;
        setup_ = setupBackend();
        if (!setup_) {
            tc::logWarning() << "[VirtualCam] Backend not available on this platform — "
                                "calls will be no-ops. See tcxVirtualCam/docs/DESIGN.md.";
        } else {
            tc::logNotice() << "[VirtualCam] Started: " << name_
                            << " (" << width_ << "x" << height_ << ")";
        }
        return setup_;
    }

    void close() {
        if (setup_) {
            closeBackend();
            tc::logNotice() << "[VirtualCam] Stopped: " << name_;
        }
        setup_ = false;
        pixelBuffer_.clear();
    }

    bool isSetup() const { return setup_; }

    // -------------------------------------------------------------------------
    // Send video
    // -------------------------------------------------------------------------

    // Raw RGBA pixels. Caller owns the buffer.
    bool send(const unsigned char* pixels, int width, int height) {
        if (!setup_ || !pixels) return false;
        return sendBackend(pixels, width, height);
    }

    bool send(const tc::Pixels& pixels) {
        if (!pixels.isAllocated()) return false;
        return send(pixels.getData(), pixels.getWidth(), pixels.getHeight());
    }

    // GPU readback path. Allocates / reuses internal CPU buffer.
    bool send(tc::Fbo& fbo) {
        if (!setup_ || !fbo.isAllocated()) return false;
        int w = fbo.getWidth();
        int h = fbo.getHeight();
        size_t required = (size_t)w * h * 4;
        if (pixelBuffer_.size() != required) pixelBuffer_.resize(required);
        if (!fbo.readPixels(pixelBuffer_.data())) return false;
        return send(pixelBuffer_.data(), w, h);
    }

    // -------------------------------------------------------------------------
    // Settings
    // -------------------------------------------------------------------------

    void setFrameRate(float fps) {
        if (fps <= 0) return;
        fps_ = fps;
    }
    float getFrameRate() const { return fps_; }

    int getWidth() const  { return width_; }
    int getHeight() const { return height_; }
    const std::string& getName() const { return name_; }

private:
    // Per-platform implementations — defined in tcxVirtualCam_<plat>.{mm,cpp}
    // when a backend exists; default stub is in tcxVirtualCamStub.h.
    bool setupBackend();
    void closeBackend();
    bool sendBackend(const unsigned char* rgba, int w, int h);

    std::string name_;
    int   width_  = 0;
    int   height_ = 0;
    float fps_    = 30.0f;
    bool  setup_  = false;

    std::vector<unsigned char> pixelBuffer_;
};

} // namespace tcx::virtualcam

// Pull in the stub definitions while the platform backends are still TBD.
// Once a backend exists, the platform .mm/.cpp will define these instead.
#include "tcxVirtualCamStub.h"

// -----------------------------------------------------------------------------
// Backward compatibility. The canonical namespace is now `tcx::virtualcam`.
// These silent aliases keep older code compiling: flat `tcx::VirtualCam` and
// legacy `trussc::VirtualCam`. DEPRECATED — removed in v1.0.0.
// (No [[deprecated]] attribute: under the usual `using namespace tc;` it would
//  warn on idiomatic unqualified use too. See tcxVirtualCam README for migration.)
// -----------------------------------------------------------------------------
namespace tcx    { using virtualcam::VirtualCam; } // deprecated: remove at v1.0.0
namespace trussc { using tcx::virtualcam::VirtualCam; } // deprecated: remove at v1.0.0
