# Camera Extension

A `.systemextension` bundle that registers a CMIOExtensionProvider with macOS
and serves frames to any consumer app (Zoom, Photo Booth, browsers, …).

**Implementation language: Swift.** Source is in [`Sources/`](Sources/).
Info.plist + entitlements are in [`Resources/`](Resources/).

## Status: Phase 2B

Static SMPTE-style color bars at 1280×720 NV12 / 30 fps. No XPC channel
yet — host TrussC apps can't push frames into this extension; that's
Phase 2E.

The goal of this phase is: **"TrussC Virtual Cam" appears in Photo Booth's
camera picker, and when selected, shows colored bars.**

## Source layout

| File | Role |
|---|---|
| [`Sources/main.swift`](Sources/main.swift) | Entry point — constructs the provider, hands off to `CMIOExtensionProvider.startService` |
| [`Sources/Branding.swift`](Sources/Branding.swift) | All naming / UUIDs — the one place to edit when forking |
| [`Sources/TCVProviderSource.swift`](Sources/TCVProviderSource.swift) | `CMIOExtensionProviderSource` — owns one device, exposes manufacturer/name |
| [`Sources/TCVDeviceSource.swift`](Sources/TCVDeviceSource.swift) | `CMIOExtensionDeviceSource` — owns one stream, exposes transport type / model |
| [`Sources/TCVStreamSource.swift`](Sources/TCVStreamSource.swift) | `CMIOExtensionStreamSource` — generates color-bar frames and pushes via `stream.send(...)` |
| [`Resources/Info.plist`](Resources/Info.plist) | `NSExtension` dictionary tells launchd this is a `CMIOExtensionProvider` |
| [`Resources/Extension.entitlements`](Resources/Extension.entitlements) | App sandbox entitlement (required for system extensions) |

## Building (manual Xcode setup for now)

There's no committed `.xcodeproj` yet — Phase 2C will add one alongside
the installer app. Until then, the build flow is:

### One-time setup

1. **Enable developer mode for System Extensions** (loosens signature
   checks so a Personal Team is enough):
   ```bash
   sudo systemextensionsctl developer on
   ```
   Reboot.

2. **Open Xcode → File → New → Project**
   - macOS → Generic → **Camera Extension**
   - Product Name: `TrussCVirtualCamExtension`
   - Team: your Apple ID (Personal Team is fine for local dev)
   - Organization Identifier: `org.trussc`
     - → resulting Bundle Identifier: `org.trussc.TrussCVirtualCamExtension`
   - Language: Swift
   - Save anywhere outside this repo (e.g. `~/dev/tcxvc-xcode/`)

3. **Replace the template's generated files** with ours:
   - In Finder, delete the Swift files Xcode auto-generated inside
     `TrussCVirtualCamExtension/` (the target folder, not the project)
   - Drag in everything from `platform/mac/extension/Sources/`
     (Copy items: NO, Create groups, target: the extension target)
   - In `TrussCVirtualCamExtension/Info.plist`, copy the contents of
     [`Resources/Info.plist`](Resources/Info.plist) over the template's
   - In `TrussCVirtualCamExtension.entitlements`, copy the contents of
     [`Resources/Extension.entitlements`](Resources/Extension.entitlements)

4. **Build & run** the extension target (⌘R). On first run Xcode installs
   the extension; macOS prompts you to allow it via System Settings →
   Privacy & Security.

5. Verify in **Photo Booth**:
   - Open Photo Booth
   - Camera menu → "TrussC Virtual Cam"
   - You should see animated-feel SMPTE color bars

### Iterating

After the initial setup, edits to the Swift files only require pressing
⌘R in Xcode. macOS detects the version bump and reinstalls. If a
reinstall gets confused:
```bash
systemextensionsctl list                                            # see installed
systemextensionsctl uninstall <team-id> org.trussc.TrussCVirtualCamExtension
```
…then ⌘R again.

## Fork workflow (preview)

To ship your own "MyApp Virtual Cam":

1. Fork the repo, then in
   [`Sources/Branding.swift`](Sources/Branding.swift):
   - `deviceDisplayName` → "MyApp Virtual Cam"
   - `manufacturer` → "MyApp"
   - `deviceUUID` and `streamUUID` → run `uuidgen` twice, paste
   - `machServiceName` → your reverse-DNS
2. In Xcode: change bundle identifier to `com.yourorg.yourcam.extension`
3. Build, sign with your team
4. Ship via your own GitHub Releases page

Phase 2D will pull these out of Swift into a top-level `branding.toml`
so step 1 becomes editing a single config file.

## Why no committed Xcode project yet

Hand-authoring `project.pbxproj` is fiddly and would distract from
getting the actual Swift right. The Apple "Camera Extension" template
takes ~5 min to bootstrap and produces a known-good signed build. Once
the design is settled (Phase 2C), we'll commit either a hand-written
`.xcodeproj` or an `xcodegen` config so cloning the repo is one step.
