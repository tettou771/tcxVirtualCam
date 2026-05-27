# Installing on macOS

> **Status: planned.** The installer `.app` referenced in this document
> doesn't exist yet (Phase 2C). For now this file describes the *intended*
> install flow so the UX is clear ahead of time.

## End-user install

1. Download `TrussC VirtualCam.app.zip` from the
   [Releases](https://github.com/tettou771/tcxVirtualCam/releases) page.
2. Unzip; drag `TrussC VirtualCam.app` into `/Applications`.
3. Open the app. It triggers an `OSSystemExtensionRequest` and macOS shows:
   - A standard System Settings prompt asking you to approve the system
     extension (Privacy & Security pane).
   - After approving, the extension activates and the virtual camera
     becomes visible to other apps.
4. Re-open Zoom / Photo Booth / your browser; "TrussC Virtual Cam" now
   shows up in the camera picker.

The `.app` itself can stay in `/Applications` (it doubles as an
uninstaller and status panel) or be deleted — the extension keeps running
either way.

## Uninstalling

Run `TrussC VirtualCam.app` and click "Uninstall", **or** from a terminal:

```bash
systemextensionsctl list                                # see installed extensions
systemextensionsctl uninstall <team-id> <bundle-id>     # remove ours
```

## Developer (running unsigned local builds)

If you're modifying this addon and want to install your own local build of
the extension without paying for a Developer ID, you can use **System
Extension developer mode**:

```bash
# Once per machine, requires reboot:
sudo systemextensionsctl developer on

# Build + run the installer .app:
./scripts/build_extension_mac.sh
open ./platform/mac/installer/build/Debug/TrussC\ VirtualCam.app
```

Developer mode loosens the signature requirements so an Apple ID Personal
Team signature is enough. **Don't leave it on for production machines** —
it weakens the System Extension security posture.

## Why this is so much more involved than the old DAL approach

macOS has retired the old DAL plug-in path. Pre-macOS-14 you could `sudo cp`
an unsigned `.plugin` into `/Library/CoreMediaIO/Plug-Ins/DAL/` and be
done. From macOS 14 onward (and definitively on macOS 26) the DAL
assistant doesn't even load third-party DAL plug-ins, so the modern
Camera Extension path is the only one that works. That path is
signed-by-design.
