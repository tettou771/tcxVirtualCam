# macOS backend

CoreMediaIO DAL Plug-In implementation. **Not yet built** — this directory is
a placeholder for the work described in [`../../docs/DESIGN.md`](../../docs/DESIGN.md).

## Layout (intended)

```
mac/
├── plugin/        # The .plugin bundle that lives in /Library/CoreMediaIO/Plug-Ins/DAL/
│   ├── Info.plist
│   ├── TCVirtualCamDAL.mm    # CMIOHardwarePlugIn entry points
│   ├── TCDevice.{h,mm}       # Represents one virtual camera device
│   ├── TCStream.{h,mm}       # Frame-serving stream
│   └── TCIPCClient.{h,mm}    # Receives frames from the host app
├── host/          # Code linked into the host TrussC app
│   ├── tcxVirtualCamMac.mm   # Defines VirtualCam::setupBackend() etc.
│   └── TCIPCHost.{h,mm}      # Sends frames to the plug-in over Mach port
└── shared/
    └── TCIPCMessages.h       # Message format shared by both processes
```

## Build target (planned)

A separate CMake target `TrussCVirtualCamDAL` builds the `.plugin` bundle.
It is **not** linked into user apps — it's installed once per machine.

A helper script (`install_plugin.sh`) will do the `sudo cp` step.
