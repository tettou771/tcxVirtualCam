# tcxVirtualCam — Design

## Goal

Let a TrussC app appear as a webcam to other applications on the same machine,
so any effect/sketch built with TrussC can be used as a video source in Zoom,
Discord, OBS, browsers, etc.

This is the SnapCamera / Snap Lens Studio use case, but driven by TrussC code.

## Non-goals (for now)

- **Network streaming** — that's what [tcxNDI](../tcxNDI) is for.
- **Receiving from a virtual camera** — the host OS's standard camera APIs
  (`AVCaptureDevice`, Media Foundation, V4L2) work just fine for that.
- **Audio routing** — out of scope. Use BlackHole / VB-Cable / pipewire.

## Architecture

Three moving parts, regardless of platform:

```
┌──────────────────────┐    IPC    ┌──────────────────────┐    Native    ┌────────────┐
│  TrussC user app     │ ────────▶ │  Virtual cam plugin  │  ─────────▶  │ Other app  │
│  (host process)      │  frames   │  (OS-loaded process) │   API        │ (Zoom, …)  │
└──────────────────────┘           └──────────────────────┘              └────────────┘
        ▲                                    ▲
        │                                    │
   tcxVirtualCam.h                      Platform-specific plugin
   (public API)                         binary (built once,
                                         installed once per machine)
```

### Why two processes?

Each OS requires the virtual camera to be a special binary loaded by the OS
itself — not by our app:

- **macOS:** `.plugin` bundle in `/Library/CoreMediaIO/Plug-Ins/DAL/`, loaded
  by every consumer process that opens a `CoreMediaIO` device.
- **Windows:** COM-registered DLL (DirectShow) or MF VirtualCamera, loaded by
  consumer processes via COM activation.
- **Linux:** `v4l2loopback` is a kernel module that exposes a `/dev/videoN`
  device; the "plugin" is just the kernel module + our app writing frames.

So the TrussC host app and the camera plugin live in different processes
(except Linux, where the kernel mediates). IPC is the key design question.

## IPC design (macOS first cut)

| Concern         | Choice                                                 |
|-----------------|--------------------------------------------------------|
| Discovery       | Mach service name `org.trussc.virtualcam.host.<pid>`   |
| Frame transport | `IOSurface` referenced by Mach port, double-buffered   |
| Synchronization | `mach_semaphore` or POSIX `sem_open` named semaphore   |
| Metadata        | Shared memory header (width, height, fps, format, seq) |

Rationale:

- `IOSurface` is the zero-copy primitive used by macOS itself for video frames
  (CoreVideo, AVFoundation all use it under the hood). Avoids GPU→CPU→GPU
  round-trips when possible.
- Mach ports are the standard way to pass `IOSurface` between processes on
  macOS.
- Double-buffering lets the host write frame N+1 while the plugin reads N.

On Windows we'll use named shared memory + an event handle. On Linux there's
no IPC — we write directly to the V4L2 fd.

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

    vcam.send(fbo);           // GPU readback path
    // vcam.send(pixels);     // CPU path
    // vcam.send(rgba, w, h); // raw path
}
```

`VirtualCam` is non-copyable, owns the IPC channel and the per-platform sender
state.

## Pixel format

DAL plug-ins, DirectShow filters, and V4L2 devices all prefer **YUV** formats
(NV12, YUYV/YUY2, UYVY) over RGBA. Consumer apps will accept RGB but at the
cost of an extra conversion on their side.

We aim for **NV12** as the wire format because:
- All three target backends accept it natively.
- It halves the bandwidth vs. RGBA (12 bpp vs. 32 bpp).
- GPU shaders can emit NV12 (luma plane + interleaved chroma) in a single pass.

Therefore the host-side path is:

```
sg_image (RGBA8) ──► YUV pack shader ──► sg_image (R8 luma + RG8 chroma)
                                                 │
                                                 ▼
                                       sg_query_image_pixels
                                                 │
                                                 ▼
                                            IOSurface
```

When that's too expensive, fallback to readback-then-convert on CPU.

## Roadmap

### Phase 0 — Scaffold *(in progress)*
- [x] Repo layout, README, license, addon.json
- [ ] Header-only stub API (compiles, methods log warnings)
- [ ] Example sketch that calls `vcam.send(fbo)` (no-ops until backend exists)

### Phase 1 — macOS DAL test pattern
- [ ] Build a `.plugin` bundle that registers as `TrussC Virtual Camera`
- [ ] Serves a hardcoded color-bar pattern
- [ ] Appears in QuickTime, Photo Booth, Zoom, browser `getUserMedia`
- [ ] Install/uninstall script

### Phase 2 — macOS IPC
- [ ] Host app posts frames to plugin via IOSurface + Mach port
- [ ] Plugin serves the most recent frame to the consumer
- [ ] Latency target: <33 ms end-to-end at 30 fps

### Phase 3 — Format & performance
- [ ] GPU-side RGBA→NV12 shader
- [ ] Drop frame strategy (consumers run at variable fps)
- [ ] 1080p60 verified

### Phase 4 — Windows
- [ ] DirectShow source filter (regsvr32 install)
- [ ] Shared memory IPC

### Phase 5 — Linux
- [ ] v4l2loopback wrapper

### Phase 6 — Camera Extension (macOS modern path, optional)
- [ ] Investigate whether unsigned Camera Extensions are practical for end users

## References

- OBS [`mac-virtualcam`](https://github.com/obsproject/obs-studio/tree/master/plugins/mac-virtualcam) — GPL, reference only
- Apple [`CMIOMinimalSample`](https://developer.apple.com/library/archive/samplecode/CMIOMinimalSample/) — Apple Sample License
- [`obs-mac-virtualcam`](https://github.com/johnboiles/obs-mac-virtualcam) — original implementation, GPL
- Microsoft `vcam` DirectShow sample — MS-PL
- [`v4l2loopback`](https://github.com/v4l2loopback/v4l2loopback) — GPL kernel module, MIT userspace samples
