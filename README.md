# tcxVirtualCam

Virtual camera output for [TrussC](https://github.com/TrussC-org/TrussC).

Make your TrussC app appear as a webcam to other applications (Zoom, Discord, OBS, browsers, etc.) — useful for building **SnapCamera-style effect apps**, live VJ feeds, presentation overlays, and the like.

> **Status: 🚧 Work in progress** — early prototype, macOS only at this stage. API and IPC format are unstable.

## Features (planned)

- **Send-only** (output) for now. Reception is left to the host OS's standard camera APIs.
- Cross-platform virtual camera backends:
  - **macOS** — CoreMediaIO DAL Plug-In
  - **Windows** — DirectShow Source Filter *(planned)*
  - **Linux** — `v4l2loopback` *(planned)*
- Sender API mirroring `tcxNDI` for familiarity:
  ```cpp
  tcx::VirtualCam vcam;
  vcam.setup("My TrussC Cam", 1280, 720);
  vcam.setFrameRate(30);
  // in draw():
  vcam.send(fbo);
  ```
- GPU-side RGBA → NV12 / YUYV conversion (planned, to keep 60fps at 1080p).

## Status by platform

| Platform | Backend | Status |
|---|---|---|
| macOS | CoreMediaIO DAL Plug-In | 🚧 In development |
| Windows | DirectShow Source Filter | ⏳ Not started |
| Linux | v4l2loopback | ⏳ Not started |

See [docs/DESIGN.md](docs/DESIGN.md) for the architecture and roadmap.

## Caveats

- **No code signing assumed.** This is a personal/野良 addon — each user is responsible for any signing requirements their OS or app stack imposes.
- macOS DAL Plug-Ins are **deprecated in favor of CoreMediaIO Camera Extensions**. We start with DAL because it requires no Developer ID and no notarization; a Camera Extension backend may be added later.
- Some applications (notably Apple's own apps using `AVCaptureDevice` with hardened runtime) may refuse to load unsigned DAL plug-ins. See [docs/INSTALL_macOS.md](docs/INSTALL_macOS.md).

## Install

This addon is consumed via [trusscli](https://github.com/TrussC-org/TrussC):

```bash
trusscli addon clone tcxVirtualCam
trusscli addon add tcxVirtualCam
```

For the macOS plug-in installation steps (one-time `sudo cp` into `/Library/CoreMediaIO/Plug-Ins/DAL/`), see [docs/INSTALL_macOS.md](docs/INSTALL_macOS.md).

## License

MIT. See [LICENSE](LICENSE).
