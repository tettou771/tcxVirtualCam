# macOS backend

CoreMediaIO DAL Plug-In implementation.

## Current status: Phase 1A complete

The bundle builds and exposes the required `TrussCVirtualCamFactory` entry
symbol, but does **not** publish any CMIO Device/Stream objects yet. So
installing it lets the cmio assistant load it without crashing, but no
"TrussC Virtual Camera" device appears in any consumer app yet. That's
Phase 1B.

See [`../../docs/DESIGN.md`](../../docs/DESIGN.md) for the full roadmap.

## Layout

```
mac/
├── plugin/        # The .plugin bundle (installs to /Library/CoreMediaIO/Plug-Ins/DAL/)
│   ├── CMakeLists.txt
│   ├── Info.plist.in
│   ├── PlugInMain.mm          # Factory + IUnknown + CMIO vtable stubs
│   └── build/                 # CMake output, ignored
├── host/          # (Phase 2) Code linked into the host TrussC app
└── shared/        # (Phase 2) Message format shared by both processes
```

## Build & install

```bash
# From the addon root:
./scripts/build_plugin_mac.sh
./scripts/install_plugin_mac.sh        # sudo cp into /Library/CoreMediaIO/Plug-Ins/DAL/
./scripts/uninstall_plugin_mac.sh      # remove
```

## Watching plug-in logs

The plug-in runs inside other processes (Zoom, Photo Booth, browsers, …) so
stdout/stderr is useless. Logging goes to `os_log` under the subsystem
`org.trussc.virtualcam`. To stream:

```bash
log stream --predicate 'subsystem == "org.trussc.virtualcam"'
```
