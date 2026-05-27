// =============================================================================
// main.swift - Camera Extension entry point
// =============================================================================
//
// macOS launches us as a normal-ish daemon process under cameracaptured.
// Our job is to construct the CMIOExtensionProvider, register a single
// device + stream, and then hand control to CoreMediaIO via
// CMIOExtensionProvider.startService(...).
//
// startService blocks until the system tears the extension down (sleep,
// reload, uninstall). We never return from main under normal operation.

import Foundation
import CoreMediaIO

let providerSource = TCVProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

// Keep the process alive. startService's blocking guarantees vary across
// macOS versions; the explicit run loop is belt-and-suspenders.
CFRunLoopRun()
