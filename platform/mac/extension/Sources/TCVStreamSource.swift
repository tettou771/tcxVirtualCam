// =============================================================================
// TCVStreamSource.swift - CMIOExtensionStreamSource implementation
// =============================================================================
//
// Owns one output stream. While no consumer is reading, it idles. When the
// first consumer calls startStream, we kick a 30 fps timer that renders an
// SMPTE-style color bar pattern into an NV12 CVPixelBuffer and ships it via
// stream.send(...).
//
// Phase 2B: hardcoded color bars. Phase 2E swaps the color-bar source for
// frames received over XPC from a TrussC host app, falling back to the bars
// when no host is connected.

import Foundation
import CoreMediaIO
import CoreVideo
import CoreMedia

final class TCVStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    private weak var parentDevice: CMIOExtensionDevice?

    private let streamFormat: CMIOExtensionStreamFormat
    private let formatDescription: CMFormatDescription

    private let frameQueue = DispatchQueue(
        label: "org.trussc.virtualcam.frame", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var pixelBuffer: CVPixelBuffer?
    private var frameNumber: UInt64 = 0
    private var timebase = mach_timebase_info_data_t(numer: 0, denom: 0)

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init(parentDevice: CMIOExtensionDevice) {
        self.parentDevice = parentDevice

        var fd: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            width: Branding.streamWidth,
            height: Branding.streamHeight,
            extensions: nil,
            formatDescriptionOut: &fd)
        precondition(status == noErr && fd != nil,
                     "[tcxVirtualCam] CMVideoFormatDescriptionCreate failed")
        self.formatDescription = fd!

        let frameDur = CMTime(value: 1, timescale: Branding.streamFps)
        self.streamFormat = CMIOExtensionStreamFormat(
            formatDescription: formatDescription,
            maxFrameDuration:  frameDur,
            minFrameDuration:  frameDur,
            validFrameDurations: nil)

        super.init()

        mach_timebase_info(&timebase)

        stream = CMIOExtensionStream(
            localizedName: Branding.streamDisplayName,
            streamID:      Branding.streamUUID,
            direction:     .source,
            clockType:     .hostTime,
            source:        self)
    }

    // -------------------------------------------------------------------------
    // CMIOExtensionStreamSource — formats + properties
    // -------------------------------------------------------------------------

    var formats: [CMIOExtensionStreamFormat] { [streamFormat] }

    var availableProperties: Set<CMIOExtensionProperty> {
        return [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionStreamProperties
    {
        let p = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            p.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            p.frameDuration = CMTime(value: 1, timescale: Branding.streamFps)
        }
        return p
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        // Format/rate are fixed in Phase 2B.
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    // -------------------------------------------------------------------------
    // Start / stop
    // -------------------------------------------------------------------------

    func startStream() throws {
        // Allocate the CVPixelBuffer once and reuse it every frame.
        let attrs: CFDictionary = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ] as CFDictionary

        var pb: CVPixelBuffer?
        let s = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(Branding.streamWidth), Int(Branding.streamHeight),
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attrs, &pb)
        guard s == kCVReturnSuccess, let pb else {
            throw NSError(domain: "org.trussc.virtualcam", code: Int(s))
        }
        pixelBuffer = pb
        frameNumber = 0

        let t = DispatchSource.makeTimerSource(queue: frameQueue)
        let interval = DispatchTimeInterval.nanoseconds(
            Int(1_000_000_000 / UInt64(Branding.streamFps)))
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.emitFrame() }
        timer = t
        t.resume()
    }

    func stopStream() throws {
        timer?.cancel()
        timer = nil
        pixelBuffer = nil
    }

    // -------------------------------------------------------------------------
    // Frame generation
    // -------------------------------------------------------------------------

    private func emitFrame() {
        guard let pb = pixelBuffer else { return }

        renderColorBars(into: pb)

        var timing = CMSampleTimingInfo(
            duration:             CMTime(value: 1, timescale: Branding.streamFps),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp:       .invalid)

        var sb: CMSampleBuffer?
        let s = CMSampleBufferCreateReadyWithImageBuffer(
            allocator:         kCFAllocatorDefault,
            imageBuffer:       pb,
            formatDescription: formatDescription,
            sampleTiming:      &timing,
            sampleBufferOut:   &sb)
        guard s == noErr, let sb else { return }

        let now = mach_absolute_time()
        let hostNs = now * UInt64(timebase.numer) / UInt64(timebase.denom)
        stream.send(sb, discontinuity: [], hostTimeInNanoseconds: hostNs)

        frameNumber &+= 1
    }

    // -------------------------------------------------------------------------
    // SMPTE-ish 75% color bars in NV12 video range
    // -------------------------------------------------------------------------
    //
    // Pre-computed Y / U / V values for 7 vertical bars, BT.601 limited range:
    //   bar         Y    U    V
    //   White 75%  180  128  128
    //   Yellow     162   44  142
    //   Cyan       131  156   44
    //   Green      112   72   58
    //   Magenta     84  184  198
    //   Red         65  100  212
    //   Blue        35  212  114
    //
    // NV12 layout:
    //   Y plane:  width * height bytes, one byte per luma sample
    //   UV plane: (width/2) * (height/2) * 2 bytes, interleaved U,V
    //             (each chroma sample serves a 2x2 luma block)

    private static let barY: [UInt8] = [180, 162, 131, 112,  84,  65,  35]
    private static let barU: [UInt8] = [128,  44, 156,  72, 184, 100, 212]
    private static let barV: [UInt8] = [128, 142,  44,  58, 198, 212, 114]

    private func renderColorBars(into pb: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        let width  = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        let cw     = width  / 2
        let ch     = height / 2

        // ---- Y plane (per pixel) ----
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let yPtr    = yBase.assumingMemoryBound(to: UInt8.self)

        // Build one row of Y values, then memcpy it to every row.
        var yRow = [UInt8](repeating: 0, count: yStride)
        for x in 0..<width {
            let bar = (x * 7) / width
            yRow[x] = TCVStreamSource.barY[bar]
        }
        yRow.withUnsafeBufferPointer { src in
            for y in 0..<height {
                memcpy(yPtr.advanced(by: y * yStride), src.baseAddress!, width)
            }
        }

        // ---- UV plane (one chroma sample per 2x2 luma block) ----
        guard let uvBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else { return }
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        let uvPtr    = uvBase.assumingMemoryBound(to: UInt8.self)

        var uvRow = [UInt8](repeating: 0, count: uvStride)
        for x in 0..<cw {
            // Map chroma-x back to full-width-x for bar lookup
            let bar = (x * 2 * 7) / width
            uvRow[2 * x    ] = TCVStreamSource.barU[bar]
            uvRow[2 * x + 1] = TCVStreamSource.barV[bar]
        }
        uvRow.withUnsafeBufferPointer { src in
            for y in 0..<ch {
                memcpy(uvPtr.advanced(by: y * uvStride), src.baseAddress!, cw * 2)
            }
        }
    }
}
