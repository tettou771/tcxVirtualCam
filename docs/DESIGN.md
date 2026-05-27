# tcxVirtualCam — Design

## Goal

Let a TrussC app appear as a webcam to other applications on the same machine,
so any effect/sketch built with TrussC can be used as a video source in Zoom,
Discord, OBS, browsers, etc. — the SnapCamera / Snap Lens Studio use case,
but driven by TrussC code.

## Non-goals

- **Network streaming** — that's what [tcxNDI](../tcxNDI) is for.
- **Receiving from a virtual camera** — the host OS's standard camera APIs
  (`AVCaptureDevice`, Media Foundation, V4L2) already cover that.
- **Audio routing** — use BlackHole / VB-Cable / pipewire.

## Why a separate "extension" process

Every OS requires the virtual camera to be a special binary loaded by the
OS itself, never directly by our user app:

- **macOS:** A `.systemextension` bundle living in `/Library/SystemExtensions/`,
  activated by `OSSystemExtensionRequest`. Loaded by `cameracaptured` and
  served to consumer processes via the CMIOExtension framework.
- **Windows:** A COM-registered DirectShow / MediaFoundation VirtualCamera DLL,
  loaded by consumer processes via COM activation.
- **Linux:** `v4l2loopback` is a kernel module that exposes a `/dev/videoN`
  device — the "extension" is the kernel module + our app writing frames.

So the TrussC host app and the virtual camera live in different processes
(except Linux, where the kernel mediates). IPC is the central design question.

## Pivot from DAL → CMIOExtension (macOS)

> If you're reading this for the first time, ignore this section. It's here
> for posterity / fork authors who might want to support older macOS too.

This repo originally targeted the legacy `CMIOHardwarePlugIn` DAL API. On
macOS 26 the DAL assistant process is gone and DAL plug-ins are silently
ignored. Even on macOS 14+ most apps don't load DAL plug-ins. The current
approach is therefore Camera Extensions (`CMIOExtensionProvider`, …),
which has been the official path since macOS 12.3.

Cost of the pivot:
- Code signing is now required (Personal Team works for local dev; Developer
  ID needed for distribution).
- User has to install a small `.app` once per machine that activates the
  extension via `OSSystemExtensionRequest`.

Benefits gained:
- Actually works on current macOS.
- API is class-based (Swift), much less hand-rolled vtable code.
- IOSurface-based frame transport is a first-class concept in this API.

The old DAL implementation is preserved in git history; jump to the commit
before this section was written if you ever need it for macOS 12 or earlier.

## Architecture

Three moving parts, regardless of platform:

```
┌──────────────────────┐    IPC    ┌──────────────────────┐    Native    ┌────────────┐
│  TrussC user app     │ ────────▶ │  Virtual cam process │  ─────────▶  │ Other app  │
│  (host process)      │  frames   │  (OS-loaded daemon)  │   API        │ (Zoom, …)  │
└──────────────────────┘           └──────────────────────┘              └────────────┘
        │                                    ▲
        │                                    │
   tcxVirtualCam.h              ┌────────────┴────────────┐
   (public API)                 │ macOS  : Camera Extension│
                                │ Windows: DirectShow DLL  │
                                │ Linux  : (kernel-mediated) │
                                └─────────────────────────┘
```

## macOS: process map

```
┌─────────────────────────────────────┐
│  Camera Extension (.systemextension)│   ← installed once, system-wide
│  → cmio framework loads it          │     team.tettou771.tcxVirtualCam.extension
│  → publishes "TrussC Virtual Cam"   │     /Library/SystemExtensions/…
└─────────────────────────────────────┘
              ▲                ▲
              │ XPC            │ CMIOExtension API
              │ (frames)       │
┌─────────────┴────────┐  ┌────┴───────────────────┐
│ TrussC user app      │  │ Consumer app (Zoom, …)  │
│ (any process, any    │  │ Uses AVCaptureSession;  │
│  signing or none)    │  │ sees us as a normal cam │
└──────────────────────┘  └─────────────────────────┘
              ▲
              │ (one-time install)
┌─────────────┴────────┐
│ Installer.app        │   ← shipped via GitHub Releases
│ embeds the extension │     calls OSSystemExtensionRequest
│ shows install UI     │     to register the extension
└──────────────────────┘
```

## IPC (macOS first cut)

| Concern         | Choice                                                 |
|-----------------|--------------------------------------------------------|
| Discovery       | Mach service `org.trussc.virtualcam.frames`            |
| Frame transport | `IOSurface` referenced by Mach port, double-buffered   |
| Synchronization | XPC message round-trip (1 message per frame)           |
| Metadata        | XPC dict: width, height, fourcc, ts, protocol version  |

`IOSurface` is the zero-copy primitive used by macOS itself for video frames
(CoreVideo, AVFoundation all use it under the hood). Avoiding GPU↔CPU
round-trips is essential for keeping 1080p60 viable.

Single-writer policy: only one TrussC app at a time can send frames. Second
connections get rejected by the extension. This avoids racing frame writers.

## API surface (planned)

```cpp
#include <TrussC.h>
#include <tcxVirtualCam.h>
using namespace tc;
using namespace tcx;

tcApp::setup() {
    fbo.allocate(1280, 720);
    vcam.setup("My TrussC Cam", 1280, 720);
    vcam.setFrameRate(30);
}

tcApp::draw() {
    fbo.begin();
        // ... draw stuff ...
    fbo.end();

    vcam.send(fbo);            // GPU readback path
    // vcam.send(pixels);      // CPU path
    // vcam.send(rgba, w, h);  // raw path
}
```

`VirtualCam` is non-copyable, owns the XPC connection and any IOSurface
buffers it has registered with the extension.

The "name" argument is currently advisory — at the macOS layer the OS sees
a single fixed device name baked into the extension. Multiple TrussC apps
share the one virtual camera channel.

## Pixel format

Camera Extensions (and DirectShow / V4L2 on the other platforms) all prefer
**YUV** formats over RGBA. Consumer apps will accept RGB but at the cost of
an extra conversion on their side.

Wire format target: **NV12** because:
- All three target backends accept it natively.
- Half the bandwidth of RGBA (12 bpp vs. 32 bpp).
- GPU shaders can emit NV12 (luma plane + interleaved chroma) in one pass.

Host-side path:

```
sg_image (RGBA8) ──► YUV pack shader ──► sg_image (R8 luma + RG8 chroma)
                                                 │
                                                 ▼
                                       sg_query_image_pixels
                                                 │
                                                 ▼
                                            IOSurface
                                                 │
                                                 ▼
                                          XPC → extension
```

Slow path: CPU readback then convert. Fine for prototyping; replace with
the GPU shader path once 1080p60 is the target.

## Fork-friendliness

A fork should be able to ship their own virtual camera ("MyCoolApp Cam")
by editing one config file. To make that work, **all** of these have to
flow from a single source of truth:

- Product display name (`TrussC Virtual Cam`)
- Bundle ID prefix (`org.trussc.virtualcam`)
- Mach service name (`org.trussc.virtualcam.frames`)
- Manufacturer string (`TrussC`)
- Extension binary bundle ID
- Installer app bundle ID
- Code-signing team / Developer ID

→ See `branding.toml` (or similar) at the repo root once Phase 2A lands. The
build system substitutes these into Info.plist files at build time.

## Roadmap

### Phase 1 (done, then redone via DAL) — abandoned
Original DAL plug-in approach. Worked in concept on macOS 12 and earlier,
but dead on macOS 14+. Source preserved in git history before the pivot
commit.

### Phase 2A — Repo restructure & design *(this commit)*
- Drop DAL code and scripts
- New `platform/mac/{extension,installer,host-bridge,shared}/` skeleton
- Updated DESIGN.md, README, INSTALL_macOS.md

### Phase 2B — Camera Extension shows up as a device
- Xcode project under `platform/mac/extension/`
- Minimal `CMIOExtensionProviderSource` + `DeviceSource` + `StreamSource`
- Static color-bar test pattern, no IPC yet
- Verifiable: "TrussC Virtual Cam" appears in Photo Booth's camera picker

### Phase 2C — Installer .app
- Container `.app` under `platform/mac/installer/`
- Embeds the extension; calls `OSSystemExtensionRequest`
- Minimal UI: "Install" button, status, "Uninstall" button
- Verifiable: user double-clicks, approves prompt, virtual cam visible

### Phase 2D — Branding extraction
- `branding.toml` or `branding.xcconfig` at repo root
- All product names / bundle IDs / UUIDs derived from it
- README documents the fork workflow

### Phase 2E — XPC channel
- `shared/` defines the protocol (Mach service name, message keys)
- `host-bridge/` opens the connection from the TrussC app side
- Extension accepts connection, no frames yet

### Phase 2F — Frame transport (CPU path)
- IOSurface allocation + XPC handoff
- RGBA → NV12 conversion on CPU
- 720p30 verified end-to-end (TrussC app → extension → Zoom)

### Phase 2G — GPU pack + perf
- GPU NV12 pack shader in TrussC
- 1080p60 target

### Phase 2H — Release packaging
- `scripts/build_release_mac.sh` produces `.app.zip` ready for GitHub Releases
- README points users at Releases

### Phase 3+ — Windows, then Linux
- DirectShow source filter
- v4l2loopback wrapper
- API stays identical to macOS so user code is portable

## References

- Apple "Creating a camera extension with Core Media I/O" sample
- [`CMIOExtensionProvider` headers](file:///Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreMediaIO.framework/Headers/)
- OBS `mac-camera-extension` — GPL, reference only
