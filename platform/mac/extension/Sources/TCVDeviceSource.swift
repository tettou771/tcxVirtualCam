// =============================================================================
// TCVDeviceSource.swift - CMIOExtensionDeviceSource implementation
// =============================================================================
//
// One device per provider. Owns a single stream.

import Foundation
import CoreMediaIO
import IOKit.audio

final class TCVDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!
    private var streamSource: TCVStreamSource!

    init(localizedName: String) {
        super.init()

        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: Branding.deviceUUID,
            legacyDeviceID: nil,
            source: self
        )

        streamSource = TCVStreamSource(parentDevice: device)
        do {
            try device.addStream(streamSource.stream)
        } catch {
            fatalError("[tcxVirtualCam] failed to add stream: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // Device-level properties
    // -------------------------------------------------------------------------

    var availableProperties: Set<CMIOExtensionProperty> {
        return [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionDeviceProperties
    {
        let p = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            // kIOAudioDeviceTransportTypeVirtual = 'virt' (0x76697274).
            // The IOKit constant covers both audio and video DAL transports.
            p.transportType = NSNumber(value: kIOAudioDeviceTransportTypeVirtual)
        }
        if properties.contains(.deviceModel) {
            p.model = Branding.deviceModelName
        }
        return p
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        // Nothing settable in Phase 2B.
    }
}
