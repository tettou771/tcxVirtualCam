// =============================================================================
// TCVProviderSource.swift - CMIOExtensionProviderSource implementation
// =============================================================================
//
// One ProviderSource per extension process. Owns a single device.
//
// Lifecycle on macOS:
//   1. cameracaptured launches the extension binary
//   2. We instantiate this class
//   3. CMIOExtensionProvider.startService(...) hands the OS our provider
//   4. The OS calls connect(to:) / disconnect(from:) as consumer apps attach
//   5. Properties (manufacturer / name) are queried via providerProperties(...)

import Foundation
import CoreMediaIO

final class TCVProviderSource: NSObject, CMIOExtensionProviderSource {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: TCVDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()

        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)

        deviceSource = TCVDeviceSource(localizedName: Branding.deviceDisplayName)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("[tcxVirtualCam] failed to add device: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // Client connection — accept everyone, no auth in Phase 2B
    // -------------------------------------------------------------------------

    func connect(to client: CMIOExtensionClient) throws {
        // Phase 2E will validate the client's team ID here if we want
        // a "TrussC apps only" policy. For now, all comers welcome.
    }

    func disconnect(from client: CMIOExtensionClient) {
        // Stream cleanup is handled per-stream in TCVStreamSource.
    }

    // -------------------------------------------------------------------------
    // Provider-level properties
    // -------------------------------------------------------------------------

    var availableProperties: Set<CMIOExtensionProperty> {
        return [.providerManufacturer, .providerName]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionProviderProperties
    {
        let p = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            p.manufacturer = Branding.manufacturer
        }
        if properties.contains(.providerName) {
            p.name = Branding.deviceDisplayName
        }
        return p
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
        // Nothing settable in Phase 2B.
    }
}
