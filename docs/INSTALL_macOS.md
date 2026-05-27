# Installing the macOS virtual camera plug-in

> 🚧 The plug-in itself isn't built yet — this document describes the intended
> install flow so the user-facing UX is clear before we start writing code.

## Overview

On macOS, a virtual camera is a **CoreMediaIO DAL Plug-In**: a `.plugin` bundle
that the OS loads into every process that opens a camera. It must live in:

```
/Library/CoreMediaIO/Plug-Ins/DAL/TrussCVirtualCam.plugin
```

This is a system path, so installing it requires `sudo`.

## Install

```bash
# From the TrussC addon directory:
sudo cp -R build/TrussCVirtualCam.plugin /Library/CoreMediaIO/Plug-Ins/DAL/
```

There's no daemon to start — every camera-consuming app that launches *after*
the copy will see "TrussC Virtual Camera" in its device list.

## Uninstall

```bash
sudo rm -rf /Library/CoreMediaIO/Plug-Ins/DAL/TrussCVirtualCam.plugin
```

## Known compatibility caveats

Some applications run with **Hardened Runtime + Library Validation**, which
refuses to load DAL plug-ins not signed by the same Team ID as the host app.
Apps known to be affected:

- Safari (sometimes — depends on macOS version)
- FaceTime, QuickTime Player (Apple's own apps, signed by Apple)
- Some Electron apps with explicit hardening

Apps that typically **work** with unsigned DAL plug-ins:

- Zoom, Google Meet (in Chrome/Firefox), Discord
- OBS Studio
- Photo Booth (varies by macOS version)
- Chromium-based browsers

If a target app doesn't see the camera, that's usually the cause — it's not a
TrussC bug, it's macOS's signing policy. The fix is either to sign the plug-in
with a Developer ID, or to use a different consumer app.

## Permissions

After install, the **first** app you point at the virtual camera may trigger
the standard macOS camera permission prompt (TCC). That's normal — grant it
once per consumer app, as usual.

## Removing the OS cache

If you reinstall the plug-in and an app keeps showing the old version, the
DAL daemon may be caching:

```bash
# Restart the CoreMediaIO assistant
sudo killall -9 'cmio*' 2>/dev/null || true
```

…and relaunch the consumer app.
