# tcxVirtualCam

Virtual camera output for [TrussC](https://github.com/TrussC-org/TrussC).

Make your TrussC app appear as a webcam to other applications (Zoom, Discord,
OBS, browsers, …) — useful for building **SnapCamera-style effect apps**,
live VJ feeds, presentation overlays, and the like.

> **Status: 🚧 Early development.** macOS only at this stage, and not yet
> functional end-to-end. The API is unstable. See [`docs/DESIGN.md`](docs/DESIGN.md)
> for the roadmap.

## Status by platform

| Platform | Mechanism | Status |
|---|---|---|
| macOS | Camera Extension (CMIOExtension) | 🚧 In development (Phase 2A) |
| Windows | DirectShow Source Filter | ⏳ Not started |
| Linux | v4l2loopback | ⏳ Not started |

## Sketch of the API

```cpp
#include <TrussC.h>
#include <tcxVirtualCam.h>
using namespace tc;
using namespace tcx;

VirtualCam vcam;

tcApp::setup() {
    vcam.setup("My TrussC Cam", 1280, 720);
    vcam.setFrameRate(30);
}

tcApp::draw() {
    fbo.begin();
        // ... draw stuff ...
    fbo.end();
    vcam.send(fbo);            // ships the FBO out as a webcam feed
}
```

In stub mode (current state, until the macOS backend lands), `vcam.send(...)`
is a no-op — your app compiles and runs unchanged.

## Install (end-user, planned)

A signed installer `.app` will be published on
[Releases](https://github.com/tettou771/tcxVirtualCam/releases) once Phase 2C
is done. The user flow is:

1. Download `TrussC VirtualCam.app.zip` from Releases.
2. Unzip, drag into `/Applications`.
3. Run it once — System Settings prompts to approve the system extension.
4. From now on, any TrussC app that uses `tcxVirtualCam` can output to the
   shared "TrussC Virtual Cam" device. No per-app signing required.

## Use as a TrussC addon

```bash
trusscli addon clone tcxVirtualCam
trusscli addon add tcxVirtualCam
```

The addon library is header-only on the public API side and only adds a
small ObjC++ bridge on macOS (which talks XPC to the Camera Extension).

## Forking (planned)

Want your own differently-named virtual camera (e.g., "MyApp Cam")?
That's the intended use case for forking this repo. A single config file
at the repo root will hold all the product naming / bundle IDs / Mach
service names, and the build system will substitute them everywhere.
Phase 2D introduces that config; until then, naming is hardcoded.

## Caveats

- **Code signing on macOS.** The Camera Extension and its installer `.app`
  must be signed for distribution. tettou771's Developer ID is used for
  the official builds; forks need their own. Local development works with
  a free Apple ID (Personal Team) + `systemextensionsctl developer on`.
- **One device per machine, currently.** Multiple TrussC apps share the
  same "TrussC Virtual Cam" channel. Multi-device support is not on the
  near-term roadmap.

## License

MIT. See [LICENSE](LICENSE).
