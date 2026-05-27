# Shared protocol

Headers (and potentially a tiny static lib) shared by both the Camera
Extension and the host-side bridge. Anything that has to agree across
the IPC boundary lives here:

- Mach service name (e.g., `org.trussc.virtualcam.frames`)
- XPC message keys / payload schema
- Pixel format enums + width/height/timestamp struct
- Protocol version number (incremented when the schema changes)

## Why factored out

If the extension and host bridge each define these constants
independently, every protocol tweak risks drift. One header, included by
both, prevents that.

## Status

Empty. Phase 2A defines the initial protocol surface.
