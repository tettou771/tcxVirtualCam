# macOS backend (CMIOExtension)

The macOS virtual camera is implemented as a **System Extension** using the
modern `CMIOExtension` API. The legacy `CMIOHardwarePlugIn` (DAL) approach
was abandoned because on macOS 14+ (and definitively on macOS 26) the cmio
DAL assistant no longer loads third-party DAL bundles — so a DAL plug-in
silently never appears in any consumer app's device list.

See [`../../docs/DESIGN.md`](../../docs/DESIGN.md) for the full architecture.
For why we made the pivot, see the git history of that file
(or check the parent commit of this one for the old DAL implementation).

## Layout

```
mac/
├── extension/         # The Camera Extension (.systemextension). Swift.
├── installer/         # Container .app the user double-clicks to install.
├── host-bridge/       # ObjC++ XPC client linked into TrussC user apps.
└── shared/            # XPC protocol & Mach service name, common to both sides.
```

Each subdirectory has its own README with the role and current status.

## Build flow (planned)

```
host-bridge/    →  built by the addon's CMakeLists, links into user TrussC apps
extension/      →  built by xcodebuild as part of the installer .app
installer/      →  built by xcodebuild, embeds the extension, this is the
                   shippable artifact for GitHub Releases
shared/         →  headers only; included by host-bridge AND extension
```

A top-level `scripts/build_release_mac.sh` will (later) produce
`TrussC VirtualCam.app.zip` ready to upload as a release asset.

## Fork-friendliness

All product naming (display name, bundle IDs, Mach service name, factory
UUID) flow from a single config file (created alongside Phase 2A) so a
fork can rename the virtual camera with one edit instead of a sweep.
