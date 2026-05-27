// =============================================================================
// Branding.swift - Single source of truth for product naming
// =============================================================================
//
// Forking this addon to publish your own virtual camera? Change values here
// (and the matching entries in `Resources/Info.plist` + the Xcode target's
// bundle identifiers + signing team). Phase 2D will move this to a shared
// config file so the Info.plist substitutions are automatic.
//
// `deviceUUID` MUST be stable across launches — consumer apps key off it to
// remember "your" camera in their picker. Generate a fresh one with
// `uuidgen` when you fork; never reuse the TrussC one.

import Foundation

enum Branding {
    /// What end users see in Photo Booth / Zoom / etc.
    static let deviceDisplayName  = "TrussC Virtual Cam"
    static let streamDisplayName  = "TrussC Virtual Cam Stream"
    static let manufacturer       = "TrussC"
    static let deviceModelName    = "TrussC Virtual Cam"

    /// Stable identity. Generate once per fork; never change.
    static let deviceUUID = UUID(uuidString: "98F47AB1-2C39-4E5C-A5B1-7B6A0E9D2F4E")!
    static let streamUUID = UUID(uuidString: "D6C8E0B1-1F2A-4C7D-8E0F-3A5B6C8D9E0F")!

    /// Mach service the host TrussC app's XPC bridge will connect to.
    /// Used in Phase 2E; declared here so naming stays in one place.
    static let machServiceName    = "org.trussc.virtualcam.frames"

    /// Stream geometry. NV12 video range, 30 fps. Phase 2F may add more
    /// formats; for now the extension publishes exactly one.
    static let streamWidth: Int32  = 1280
    static let streamHeight: Int32 = 720
    static let streamFps: Int32    = 30
}
