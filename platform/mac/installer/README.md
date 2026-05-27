# Installer app

A regular macOS `.app` that:

1. Embeds the Camera Extension at
   `Contents/Library/SystemExtensions/<extension>.systemextension`
2. On first launch, calls `OSSystemExtensionRequest.activationRequest(...)`
   to ask macOS to install it
3. Shows simple "install / uninstall / status" UI in AppKit (or SwiftUI)

This is the user-facing artifact published on GitHub Releases — the only
thing end users have to download and double-click.

## Why an `.app` and not a `.pkg`

`.app` is the **standard pattern for Camera Extensions** on modern macOS.
OBS does this; Immersed does this; Apple's sample code does this. The
extension is delivered via the host app's bundle and activated through
`OSSystemExtensionRequest`. macOS handles the elevation prompt; no admin
shell required for the user.

## Lifetime

Once the user has activated the extension, the `.app` can be deleted —
the extension remains installed in `/Library/SystemExtensions/`. The
`.app` is really just an installer + uninstaller wrapper.

(We may add a small status / about UI later, but the MVP can be
"activate-on-first-launch and quit".)

## Status

Empty. Phase 2C will fill this in.
