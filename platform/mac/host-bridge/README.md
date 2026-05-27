# Host-side bridge

ObjC++ code that gets compiled into the **TrussC user app** (not into the
extension or installer). Implements `tcx::VirtualCam::sendBackend()` etc.
by opening an XPC connection to the Camera Extension and shipping frames
over it.

This is what gets included in the CMake addon library on macOS.

## What it does

1. On `setup()`, opens an XPC connection to the Mach service published by
   the extension (see [`../shared/`](../shared) for the service name)
2. On `send(fbo|pixels|rgba)`, packages the frame:
   - Pixel format conversion (RGBA → NV12 for wire efficiency)
   - Wraps in an IOSurface for zero-copy transport
   - Sends an XPC message with the IOSurface reference
3. On `close()`, releases the IOSurface and disconnects

## Why this lives in the addon

The TrussC user app is just an XPC client — it doesn't need to be signed,
isn't a System Extension, has no Apple Developer Program entitlements.
The complicated/signed parts (`extension/`, `installer/`) are built once
and installed system-wide.

## Status

Empty. Phase 2E will fill this in (after the extension can at least
serve a static test pattern in Phase 2B / 2D).
