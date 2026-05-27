# Camera Extension

A `.systemextension` bundle that registers a CMIOExtensionProvider with macOS
and serves frames to any consumer app (Zoom, Photo Booth, browsers, …).

**Implementation language: Swift.** All current Apple sample code for
CMIOExtension is Swift; using it keeps this directory close to upstream
examples that the user/fork-author can copy patterns from.

## What it does

1. Registers a `CMIOExtensionProviderSource` so `cameracaptured` discovers it
2. Vends one `CMIOExtensionDeviceSource` named (by default) "TrussC Virtual Cam"
3. Each device owns one `CMIOExtensionStreamSource` advertising NV12 (or
   UYVY fallback) at 30 fps
4. Listens on a Mach service for frame submissions from the host TrussC app
   (see [`../shared/`](../shared) for the wire protocol)
5. When no host is connected, emits an idle "no signal" pattern so consumer
   apps don't see a black frame

## Why a separate process

System Extensions run as their own daemon under the `nobody`-ish user
`_cmiodalassistants`. They live in `/Library/SystemExtensions/<uuid>/` after
activation. They cannot share memory directly with the host TrussC app —
hence the XPC + IOSurface IPC.

## Status

Empty. Phase 2B will fill this in.

## Fork-friendly knobs

Identifiers come from a single source of truth (see `../../../branding.*` —
created in Phase 2A) so a fork can rename the camera with one config edit.
