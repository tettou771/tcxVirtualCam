// =============================================================================
// PlugInMain.mm - tcxVirtualCam CoreMediaIO DAL Plug-In
// =============================================================================
//
// Phase 1B: publishes a CMIOPlugIn / CMIODevice / CMIOStream object hierarchy
// so the camera shows up in QuickTime / Photo Booth / Zoom / browser pickers.
//
// What this does NOT do yet (Phase 1C):
//   - StreamCopyBufferQueue returns no queue, so once a consumer selects the
//     camera it'll either fail to start or sit on a black/empty stream. The
//     IPC + frame plumbing comes next.
// =============================================================================

#include <CoreMediaIO/CMIOHardwarePlugIn.h>
#include <CoreMediaIO/CMIOHardwareSystem.h>
#include <CoreMedia/CMFormatDescription.h>
#include <CoreFoundation/CoreFoundation.h>
#include <os/log.h>
#include <atomic>

// -----------------------------------------------------------------------------
// Hardcoded device characteristics (Phase 1B)
// -----------------------------------------------------------------------------

namespace {
constexpr UInt32  kStreamWidth     = 1280;
constexpr UInt32  kStreamHeight    = 720;
constexpr Float64 kStreamFrameRate = 30.0;
constexpr UInt32  kPixelFormat     = kCMPixelFormat_422YpCbCr8;  // '2vuy' / UYVY

// CFSTR isn't constexpr-friendly (it casts internally), so these are plain consts.
static const CFStringRef kDeviceUID      = CFSTR("org.trussc.virtualcam.device");
static const CFStringRef kModelUID       = CFSTR("org.trussc.virtualcam.model");
static const CFStringRef kFactoryUUIDStr = CFSTR("23A6DB67-8CCA-4F60-AB4E-FEDCCE7C14B0");

// Transport-type 4cc. CoreAudio has kIOAudioDeviceTransportTypeVirtual = 'virt'
// in <IOKit/audio/IOAudioTypes.h>; pull it in directly to avoid the kernel
// dependency.
constexpr UInt32 kTransportTypeVirtual = 'virt';
}  // namespace

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

static os_log_t TCVCLog(void) {
    static os_log_t log = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("org.trussc.virtualcam", "dal");
    });
    return log;
}

#define TCVC_LOG(fmt, ...) os_log(TCVCLog(), "[tcxVirtualCam] " fmt, ##__VA_ARGS__)

// -----------------------------------------------------------------------------
// Module state
// -----------------------------------------------------------------------------
//
// One plug-in instance is loaded per consumer process. These IDs are issued
// by the DAL host via CMIOObjectCreate at initialization.

namespace {
struct Instance {
    CMIOHardwarePlugInInterface* vtable;   // MUST be first field
    CFUUIDRef                    factoryID;
    std::atomic<int32_t>         refCount;
};

CMIOObjectID            gPlugInObjectID = kCMIOObjectUnknown;
CMIOObjectID            gDeviceObjectID = kCMIOObjectUnknown;
CMIOObjectID            gStreamObjectID = kCMIOObjectUnknown;
CMVideoFormatDescriptionRef gStreamFormat = NULL;
}  // namespace

// -----------------------------------------------------------------------------
// Forward decls
// -----------------------------------------------------------------------------

namespace {

// IUnknown
HRESULT TCVC_QueryInterface(void* self, REFIID uuid, LPVOID* outInterface);
ULONG   TCVC_AddRef(void* self);
ULONG   TCVC_Release(void* self);

// Lifecycle
OSStatus TCVC_Initialize(CMIOHardwarePlugInRef self);
OSStatus TCVC_InitializeWithObjectID(CMIOHardwarePlugInRef self, CMIOObjectID objectID);
OSStatus TCVC_Teardown(CMIOHardwarePlugInRef self);

// Object property API (dispatched per-object below)
void     TCVC_ObjectShow(CMIOHardwarePlugInRef, CMIOObjectID);
Boolean  TCVC_ObjectHasProperty(CMIOHardwarePlugInRef, CMIOObjectID,
                                const CMIOObjectPropertyAddress*);
OSStatus TCVC_ObjectIsPropertySettable(CMIOHardwarePlugInRef, CMIOObjectID,
                                       const CMIOObjectPropertyAddress*,
                                       Boolean*);
OSStatus TCVC_ObjectGetPropertyDataSize(CMIOHardwarePlugInRef, CMIOObjectID,
                                        const CMIOObjectPropertyAddress*,
                                        UInt32, const void*, UInt32*);
OSStatus TCVC_ObjectGetPropertyData(CMIOHardwarePlugInRef, CMIOObjectID,
                                    const CMIOObjectPropertyAddress*,
                                    UInt32, const void*,
                                    UInt32, UInt32*, void*);
OSStatus TCVC_ObjectSetPropertyData(CMIOHardwarePlugInRef, CMIOObjectID,
                                    const CMIOObjectPropertyAddress*,
                                    UInt32, const void*, UInt32, const void*);

// Device / stream
OSStatus TCVC_DeviceSuspend(CMIOHardwarePlugInRef, CMIODeviceID);
OSStatus TCVC_DeviceResume(CMIOHardwarePlugInRef, CMIODeviceID);
OSStatus TCVC_DeviceStartStream(CMIOHardwarePlugInRef, CMIODeviceID, CMIOStreamID);
OSStatus TCVC_DeviceStopStream(CMIOHardwarePlugInRef, CMIODeviceID, CMIOStreamID);
OSStatus TCVC_DeviceProcessAVCCommand(CMIOHardwarePlugInRef, CMIODeviceID, CMIODeviceAVCCommand*);
OSStatus TCVC_DeviceProcessRS422Command(CMIOHardwarePlugInRef, CMIODeviceID, CMIODeviceRS422Command*);

OSStatus TCVC_StreamCopyBufferQueue(CMIOHardwarePlugInRef, CMIOStreamID,
                                    CMIODeviceStreamQueueAlteredProc,
                                    void*, CMSimpleQueueRef*);
OSStatus TCVC_StreamDeckPlay(CMIOHardwarePlugInRef, CMIOStreamID);
OSStatus TCVC_StreamDeckStop(CMIOHardwarePlugInRef, CMIOStreamID);
OSStatus TCVC_StreamDeckJog(CMIOHardwarePlugInRef, CMIOStreamID, SInt32);
OSStatus TCVC_StreamDeckCueTo(CMIOHardwarePlugInRef, CMIOStreamID, Float64, Boolean);

CMIOHardwarePlugInInterface gVtable = {
    NULL,
    TCVC_QueryInterface, TCVC_AddRef, TCVC_Release,
    TCVC_Initialize, TCVC_InitializeWithObjectID, TCVC_Teardown,
    TCVC_ObjectShow, TCVC_ObjectHasProperty, TCVC_ObjectIsPropertySettable,
    TCVC_ObjectGetPropertyDataSize, TCVC_ObjectGetPropertyData, TCVC_ObjectSetPropertyData,
    TCVC_DeviceSuspend, TCVC_DeviceResume,
    TCVC_DeviceStartStream, TCVC_DeviceStopStream,
    TCVC_DeviceProcessAVCCommand, TCVC_DeviceProcessRS422Command,
    TCVC_StreamCopyBufferQueue,
    TCVC_StreamDeckPlay, TCVC_StreamDeckStop, TCVC_StreamDeckJog, TCVC_StreamDeckCueTo,
};

}  // anonymous namespace

// =============================================================================
// IUnknown
// =============================================================================

namespace {

HRESULT TCVC_QueryInterface(void* self, REFIID uuid, LPVOID* outInterface) {
    if (!self || !outInterface) return E_POINTER;
    *outInterface = NULL;

    CFUUIDRef requestedID = CFUUIDCreateFromUUIDBytes(NULL, uuid);
    if (!requestedID) return E_INVALIDARG;

    HRESULT result = E_NOINTERFACE;
    if (CFEqual(requestedID, IUnknownUUID) ||
        CFEqual(requestedID, kCMIOHardwarePlugInInterfaceID)) {
        TCVC_AddRef(self);
        *outInterface = self;
        result = S_OK;
    }
    CFRelease(requestedID);
    return result;
}

ULONG TCVC_AddRef(void* self) {
    Instance* inst = static_cast<Instance*>(self);
    if (!inst) return 0;
    return (ULONG)(inst->refCount.fetch_add(1) + 1);
}

ULONG TCVC_Release(void* self) {
    Instance* inst = static_cast<Instance*>(self);
    if (!inst) return 0;
    int32_t newCount = inst->refCount.fetch_sub(1) - 1;
    if (newCount == 0) {
        if (inst->factoryID) {
            CFPlugInRemoveInstanceForFactory(inst->factoryID);
            CFRelease(inst->factoryID);
        }
        TCVC_LOG("instance released");
        free(inst);
        return 0;
    }
    return (ULONG)newCount;
}

}  // anonymous namespace

// =============================================================================
// Property routing helpers
// =============================================================================
//
// The DAL hands us an objectID and we dispatch by which of {plug-in, device,
// stream} it points at. With only one of each, equality on a module-global
// ID is sufficient.

namespace {

enum class ObjectKind { Unknown, PlugIn, Device, Stream };

ObjectKind kindOf(CMIOObjectID id) {
    if (id != kCMIOObjectUnknown && id == gPlugInObjectID) return ObjectKind::PlugIn;
    if (id != kCMIOObjectUnknown && id == gDeviceObjectID) return ObjectKind::Device;
    if (id != kCMIOObjectUnknown && id == gStreamObjectID) return ObjectKind::Stream;
    return ObjectKind::Unknown;
}

// Helper: emit a 4-byte CFString into a UInt32 codec.
inline UInt32 fourcc(const char (&s)[5]) {
    return ((UInt32)s[0] << 24) | ((UInt32)s[1] << 16) | ((UInt32)s[2] << 8) | (UInt32)s[3];
}

// Helper: copy a CFStringRef out, retaining (CMIO Get is "give us a retained ref").
OSStatus copyString(CFStringRef src, UInt32 dataSize, UInt32* dataUsed, void* outData) {
    if (dataSize < sizeof(CFStringRef)) return kCMIOHardwareBadPropertySizeError;
    *(CFStringRef*)outData = (CFStringRef)CFRetain(src);
    if (dataUsed) *dataUsed = sizeof(CFStringRef);
    return noErr;
}

OSStatus copyU32(UInt32 v, UInt32 dataSize, UInt32* dataUsed, void* outData) {
    if (dataSize < sizeof(UInt32)) return kCMIOHardwareBadPropertySizeError;
    *(UInt32*)outData = v;
    if (dataUsed) *dataUsed = sizeof(UInt32);
    return noErr;
}

OSStatus copyF64(Float64 v, UInt32 dataSize, UInt32* dataUsed, void* outData) {
    if (dataSize < sizeof(Float64)) return kCMIOHardwareBadPropertySizeError;
    *(Float64*)outData = v;
    if (dataUsed) *dataUsed = sizeof(Float64);
    return noErr;
}

OSStatus copyPID(pid_t v, UInt32 dataSize, UInt32* dataUsed, void* outData) {
    if (dataSize < sizeof(pid_t)) return kCMIOHardwareBadPropertySizeError;
    *(pid_t*)outData = v;
    if (dataUsed) *dataUsed = sizeof(pid_t);
    return noErr;
}

// Format description used by the stream's "what formats do you support" answer.
CMVideoFormatDescriptionRef ensureStreamFormat() {
    if (gStreamFormat) return gStreamFormat;
    OSStatus s = CMVideoFormatDescriptionCreate(
        kCFAllocatorDefault, kPixelFormat, kStreamWidth, kStreamHeight,
        NULL, &gStreamFormat);
    if (s != noErr) {
        TCVC_LOG("CMVideoFormatDescriptionCreate failed: %d", (int)s);
        gStreamFormat = NULL;
    }
    return gStreamFormat;
}

}  // anonymous namespace

// =============================================================================
// Per-object property tables
// =============================================================================
//
// Each per-object section answers the four queries (has / settable / size /
// data). Property selectors are 4-char codes; we switch on them.

namespace {

// ---- Plug-In object --------------------------------------------------------

Boolean PlugIn_HasProperty(const CMIOObjectPropertyAddress* a) {
    switch (a->mSelector) {
        case kCMIOObjectPropertyClass:
        case kCMIOObjectPropertyOwner:
        case kCMIOObjectPropertyName:
        case kCMIOObjectPropertyManufacturer:
        case kCMIOObjectPropertyOwnedObjects:
            return true;
        default: return false;
    }
}

OSStatus PlugIn_GetPropertyDataSize(const CMIOObjectPropertyAddress* a,
                                    UInt32* outSize) {
    switch (a->mSelector) {
        case kCMIOObjectPropertyClass:
        case kCMIOObjectPropertyOwner:
            *outSize = sizeof(UInt32); return noErr;
        case kCMIOObjectPropertyName:
        case kCMIOObjectPropertyManufacturer:
            *outSize = sizeof(CFStringRef); return noErr;
        case kCMIOObjectPropertyOwnedObjects:
            *outSize = (gDeviceObjectID != kCMIOObjectUnknown) ? sizeof(CMIOObjectID) : 0;
            return noErr;
        default: return kCMIOHardwareUnknownPropertyError;
    }
}

OSStatus PlugIn_GetPropertyData(const CMIOObjectPropertyAddress* a,
                                UInt32 dataSize, UInt32* dataUsed, void* outData) {
    switch (a->mSelector) {
        case kCMIOObjectPropertyClass:
            return copyU32(kCMIOPlugInClassID, dataSize, dataUsed, outData);
        case kCMIOObjectPropertyOwner:
            return copyU32(kCMIOObjectUnknown, dataSize, dataUsed, outData);
        case kCMIOObjectPropertyName:
            return copyString(CFSTR("TrussC Virtual Cam"), dataSize, dataUsed, outData);
        case kCMIOObjectPropertyManufacturer:
            return copyString(CFSTR("TrussC"), dataSize, dataUsed, outData);
        case kCMIOObjectPropertyOwnedObjects: {
            if (gDeviceObjectID == kCMIOObjectUnknown) {
                if (dataUsed) *dataUsed = 0;
                return noErr;
            }
            if (dataSize < sizeof(CMIOObjectID)) return kCMIOHardwareBadPropertySizeError;
            *(CMIOObjectID*)outData = gDeviceObjectID;
            if (dataUsed) *dataUsed = sizeof(CMIOObjectID);
            return noErr;
        }
        default: return kCMIOHardwareUnknownPropertyError;
    }
}

// ---- Device object ---------------------------------------------------------

Boolean Device_HasProperty(const CMIOObjectPropertyAddress* a) {
    switch (a->mSelector) {
        case kCMIOObjectPropertyClass:
        case kCMIOObjectPropertyOwner:
        case kCMIOObjectPropertyName:
        case kCMIOObjectPropertyManufacturer:
        case kCMIOObjectPropertyElementName:
        case kCMIODevicePropertyPlugIn:
        case kCMIODevicePropertyDeviceUID:
        case kCMIODevicePropertyModelUID:
        case kCMIODevicePropertyTransportType:
        case kCMIODevicePropertyDeviceIsAlive:
        case kCMIODevicePropertyDeviceIsRunning:
        case kCMIODevicePropertyDeviceIsRunningSomewhere:
        case kCMIODevicePropertyDeviceCanBeDefaultDevice:
        case kCMIODevicePropertyHogMode:
        case kCMIODevicePropertyLatency:
        case kCMIODevicePropertyStreams:
        case kCMIODevicePropertyExcludeNonDALAccess:
        case kCMIODevicePropertyDeviceHasChanged:
        case kCMIOObjectPropertyOwnedObjects:
            return true;
        default: return false;
    }
}

OSStatus Device_GetPropertyDataSize(const CMIOObjectPropertyAddress* a,
                                    UInt32* outSize) {
    switch (a->mSelector) {
        case kCMIOObjectPropertyClass:
        case kCMIOObjectPropertyOwner:
        case kCMIODevicePropertyPlugIn:
        case kCMIODevicePropertyTransportType:
        case kCMIODevicePropertyDeviceIsAlive:
        case kCMIODevicePropertyDeviceIsRunning:
        case kCMIODevicePropertyDeviceIsRunningSomewhere:
        case kCMIODevicePropertyDeviceCanBeDefaultDevice:
        case kCMIODevicePropertyLatency:
        case kCMIODevicePropertyExcludeNonDALAccess:
        case kCMIODevicePropertyDeviceHasChanged:
            *outSize = sizeof(UInt32); return noErr;
        case kCMIODevicePropertyHogMode:
            *outSize = sizeof(pid_t); return noErr;
        case kCMIOObjectPropertyName:
        case kCMIOObjectPropertyManufacturer:
        case kCMIOObjectPropertyElementName:
        case kCMIODevicePropertyDeviceUID:
        case kCMIODevicePropertyModelUID:
            *outSize = sizeof(CFStringRef); return noErr;
        case kCMIODevicePropertyStreams:
        case kCMIOObjectPropertyOwnedObjects:
            *outSize = (gStreamObjectID != kCMIOObjectUnknown) ? sizeof(CMIOObjectID) : 0;
            return noErr;
        default: return kCMIOHardwareUnknownPropertyError;
    }
}

OSStatus Device_GetPropertyData(const CMIOObjectPropertyAddress* a,
                                UInt32 dataSize, UInt32* dataUsed, void* outData) {
    switch (a->mSelector) {
        case kCMIOObjectPropertyClass:
            return copyU32(kCMIODeviceClassID, dataSize, dataUsed, outData);
        case kCMIOObjectPropertyOwner:
        case kCMIODevicePropertyPlugIn:
            return copyU32(gPlugInObjectID, dataSize, dataUsed, outData);
        case kCMIOObjectPropertyName:
        case kCMIOObjectPropertyElementName:
            return copyString(CFSTR("TrussC Virtual Cam"), dataSize, dataUsed, outData);
        case kCMIOObjectPropertyManufacturer:
            return copyString(CFSTR("TrussC"), dataSize, dataUsed, outData);
        case kCMIODevicePropertyDeviceUID:
            return copyString(kDeviceUID, dataSize, dataUsed, outData);
        case kCMIODevicePropertyModelUID:
            return copyString(kModelUID, dataSize, dataUsed, outData);
        case kCMIODevicePropertyTransportType:
            return copyU32(kTransportTypeVirtual, dataSize, dataUsed, outData);
        case kCMIODevicePropertyDeviceIsAlive:
            return copyU32(1, dataSize, dataUsed, outData);
        case kCMIODevicePropertyDeviceIsRunning:
        case kCMIODevicePropertyDeviceIsRunningSomewhere:
            return copyU32(0, dataSize, dataUsed, outData);
        case kCMIODevicePropertyDeviceCanBeDefaultDevice:
            return copyU32(1, dataSize, dataUsed, outData);
        case kCMIODevicePropertyHogMode:
            return copyPID(-1, dataSize, dataUsed, outData);  // no exclusive owner
        case kCMIODevicePropertyLatency:
            return copyU32(0, dataSize, dataUsed, outData);
        case kCMIODevicePropertyExcludeNonDALAccess:
            return copyU32(0, dataSize, dataUsed, outData);
        case kCMIODevicePropertyDeviceHasChanged:
            return copyU32(0, dataSize, dataUsed, outData);
        case kCMIODevicePropertyStreams:
        case kCMIOObjectPropertyOwnedObjects: {
            if (gStreamObjectID == kCMIOObjectUnknown) {
                if (dataUsed) *dataUsed = 0;
                return noErr;
            }
            if (dataSize < sizeof(CMIOObjectID)) return kCMIOHardwareBadPropertySizeError;
            *(CMIOObjectID*)outData = gStreamObjectID;
            if (dataUsed) *dataUsed = sizeof(CMIOObjectID);
            return noErr;
        }
        default: return kCMIOHardwareUnknownPropertyError;
    }
}

// ---- Stream object ---------------------------------------------------------

Boolean Stream_HasProperty(const CMIOObjectPropertyAddress* a) {
    switch (a->mSelector) {
        case kCMIOObjectPropertyClass:
        case kCMIOObjectPropertyOwner:
        case kCMIOObjectPropertyName:
        case kCMIOObjectPropertyElementName:
        case kCMIOStreamPropertyDirection:
        case kCMIOStreamPropertyTerminalType:
        case kCMIOStreamPropertyStartingChannel:
        case kCMIOStreamPropertyLatency:
        case kCMIOStreamPropertyFormatDescription:
        case kCMIOStreamPropertyFormatDescriptions:
        case kCMIOStreamPropertyFrameRate:
        case kCMIOStreamPropertyMinimumFrameRate:
        case kCMIOStreamPropertyFrameRates:
            return true;
        default: return false;
    }
}

OSStatus Stream_GetPropertyDataSize(const CMIOObjectPropertyAddress* a,
                                    UInt32* outSize) {
    switch (a->mSelector) {
        case kCMIOObjectPropertyClass:
        case kCMIOObjectPropertyOwner:
        case kCMIOStreamPropertyDirection:
        case kCMIOStreamPropertyTerminalType:
        case kCMIOStreamPropertyStartingChannel:
        case kCMIOStreamPropertyLatency:
            *outSize = sizeof(UInt32); return noErr;
        case kCMIOStreamPropertyFrameRate:
        case kCMIOStreamPropertyMinimumFrameRate:
            *outSize = sizeof(Float64); return noErr;
        case kCMIOStreamPropertyFrameRates:
            *outSize = sizeof(Float64); return noErr;  // 1 entry
        case kCMIOObjectPropertyName:
        case kCMIOObjectPropertyElementName:
            *outSize = sizeof(CFStringRef); return noErr;
        case kCMIOStreamPropertyFormatDescription:
            *outSize = sizeof(CMFormatDescriptionRef); return noErr;
        case kCMIOStreamPropertyFormatDescriptions:
            *outSize = sizeof(CFArrayRef); return noErr;
        default: return kCMIOHardwareUnknownPropertyError;
    }
}

OSStatus Stream_GetPropertyData(const CMIOObjectPropertyAddress* a,
                                UInt32 dataSize, UInt32* dataUsed, void* outData) {
    switch (a->mSelector) {
        case kCMIOObjectPropertyClass:
            return copyU32(kCMIOStreamClassID, dataSize, dataUsed, outData);
        case kCMIOObjectPropertyOwner:
            return copyU32(gDeviceObjectID, dataSize, dataUsed, outData);
        case kCMIOObjectPropertyName:
        case kCMIOObjectPropertyElementName:
            return copyString(CFSTR("TrussC Virtual Cam Stream"), dataSize, dataUsed, outData);
        case kCMIOStreamPropertyDirection:
            // 0 = input (the OS sees us as feeding video INTO the consumer).
            return copyU32(0, dataSize, dataUsed, outData);
        case kCMIOStreamPropertyTerminalType:
            return copyU32(0x101 /* USB Camera Input */, dataSize, dataUsed, outData);
        case kCMIOStreamPropertyStartingChannel:
            return copyU32(1, dataSize, dataUsed, outData);
        case kCMIOStreamPropertyLatency:
            return copyU32(0, dataSize, dataUsed, outData);
        case kCMIOStreamPropertyFrameRate:
        case kCMIOStreamPropertyMinimumFrameRate:
            return copyF64(kStreamFrameRate, dataSize, dataUsed, outData);
        case kCMIOStreamPropertyFrameRates: {
            // Array of supported rates — we have one.
            if (dataSize < sizeof(Float64)) return kCMIOHardwareBadPropertySizeError;
            *(Float64*)outData = kStreamFrameRate;
            if (dataUsed) *dataUsed = sizeof(Float64);
            return noErr;
        }
        case kCMIOStreamPropertyFormatDescription: {
            CMVideoFormatDescriptionRef fmt = ensureStreamFormat();
            if (!fmt) return kCMIOHardwareIllegalOperationError;
            if (dataSize < sizeof(CMFormatDescriptionRef)) return kCMIOHardwareBadPropertySizeError;
            *(CMFormatDescriptionRef*)outData = (CMFormatDescriptionRef)CFRetain(fmt);
            if (dataUsed) *dataUsed = sizeof(CMFormatDescriptionRef);
            return noErr;
        }
        case kCMIOStreamPropertyFormatDescriptions: {
            CMVideoFormatDescriptionRef fmt = ensureStreamFormat();
            if (!fmt) return kCMIOHardwareIllegalOperationError;
            if (dataSize < sizeof(CFArrayRef)) return kCMIOHardwareBadPropertySizeError;
            const void* values[1] = { fmt };
            *(CFArrayRef*)outData = CFArrayCreate(NULL, values, 1, &kCFTypeArrayCallBacks);
            if (dataUsed) *dataUsed = sizeof(CFArrayRef);
            return noErr;
        }
        default: return kCMIOHardwareUnknownPropertyError;
    }
}

}  // anonymous namespace

// =============================================================================
// Vtable: top-level property dispatch
// =============================================================================

namespace {

Boolean TCVC_ObjectHasProperty(CMIOHardwarePlugInRef, CMIOObjectID id,
                               const CMIOObjectPropertyAddress* address) {
    if (!address) return false;
    switch (kindOf(id)) {
        case ObjectKind::PlugIn: return PlugIn_HasProperty(address);
        case ObjectKind::Device: return Device_HasProperty(address);
        case ObjectKind::Stream: return Stream_HasProperty(address);
        default: return false;
    }
}

OSStatus TCVC_ObjectIsPropertySettable(CMIOHardwarePlugInRef, CMIOObjectID,
                                       const CMIOObjectPropertyAddress*,
                                       Boolean* outIsSettable) {
    // Nothing is settable in Phase 1B.
    if (outIsSettable) *outIsSettable = false;
    return noErr;
}

OSStatus TCVC_ObjectGetPropertyDataSize(CMIOHardwarePlugInRef, CMIOObjectID id,
                                        const CMIOObjectPropertyAddress* address,
                                        UInt32, const void*,
                                        UInt32* outSize) {
    if (!address || !outSize) return kCMIOHardwareIllegalOperationError;
    switch (kindOf(id)) {
        case ObjectKind::PlugIn: return PlugIn_GetPropertyDataSize(address, outSize);
        case ObjectKind::Device: return Device_GetPropertyDataSize(address, outSize);
        case ObjectKind::Stream: return Stream_GetPropertyDataSize(address, outSize);
        default: return kCMIOHardwareBadObjectError;
    }
}

OSStatus TCVC_ObjectGetPropertyData(CMIOHardwarePlugInRef, CMIOObjectID id,
                                    const CMIOObjectPropertyAddress* address,
                                    UInt32, const void*,
                                    UInt32 dataSize, UInt32* dataUsed,
                                    void* outData) {
    if (!address || !outData) return kCMIOHardwareIllegalOperationError;
    switch (kindOf(id)) {
        case ObjectKind::PlugIn:
            return PlugIn_GetPropertyData(address, dataSize, dataUsed, outData);
        case ObjectKind::Device:
            return Device_GetPropertyData(address, dataSize, dataUsed, outData);
        case ObjectKind::Stream:
            return Stream_GetPropertyData(address, dataSize, dataUsed, outData);
        default:
            return kCMIOHardwareBadObjectError;
    }
}

OSStatus TCVC_ObjectSetPropertyData(CMIOHardwarePlugInRef, CMIOObjectID,
                                    const CMIOObjectPropertyAddress*,
                                    UInt32, const void*,
                                    UInt32, const void*) {
    return kCMIOHardwareIllegalOperationError;
}

void TCVC_ObjectShow(CMIOHardwarePlugInRef, CMIOObjectID) {}

}  // anonymous namespace

// =============================================================================
// Lifecycle
// =============================================================================

namespace {

OSStatus TCVC_Initialize(CMIOHardwarePlugInRef self) {
    return TCVC_InitializeWithObjectID(self, kCMIOObjectUnknown);
}

OSStatus TCVC_InitializeWithObjectID(CMIOHardwarePlugInRef self, CMIOObjectID plugInID) {
    TCVC_LOG("Initialize plugInID=0x%x", (unsigned)plugInID);
    gPlugInObjectID = plugInID;

    // Eagerly build the format descriptor — Streams answer queries about it.
    ensureStreamFormat();

    // Device owned by the plug-in.
    OSStatus s = CMIOObjectCreate(self, plugInID, kCMIODeviceClassID, &gDeviceObjectID);
    if (s != noErr) {
        TCVC_LOG("CMIOObjectCreate(Device) failed: %d", (int)s);
        return s;
    }

    // Stream owned by the device.
    s = CMIOObjectCreate(self, gDeviceObjectID, kCMIOStreamClassID, &gStreamObjectID);
    if (s != noErr) {
        TCVC_LOG("CMIOObjectCreate(Stream) failed: %d", (int)s);
        return s;
    }

    // Publish device under the plug-in, then stream under the device.
    CMIOObjectID devs[1] = { gDeviceObjectID };
    s = CMIOObjectsPublishedAndDied(self, plugInID, 1, devs, 0, NULL);
    if (s != noErr) {
        TCVC_LOG("Publish(Device) failed: %d", (int)s);
        return s;
    }

    CMIOObjectID streams[1] = { gStreamObjectID };
    s = CMIOObjectsPublishedAndDied(self, gDeviceObjectID, 1, streams, 0, NULL);
    if (s != noErr) {
        TCVC_LOG("Publish(Stream) failed: %d", (int)s);
        return s;
    }

    TCVC_LOG("published device=0x%x stream=0x%x",
             (unsigned)gDeviceObjectID, (unsigned)gStreamObjectID);
    return noErr;
}

OSStatus TCVC_Teardown(CMIOHardwarePlugInRef) {
    TCVC_LOG("Teardown");
    if (gStreamFormat) { CFRelease(gStreamFormat); gStreamFormat = NULL; }
    gPlugInObjectID = gDeviceObjectID = gStreamObjectID = kCMIOObjectUnknown;
    return noErr;
}

// ---- Device / stream stubs (Phase 1C will fill these in) -------------------

OSStatus TCVC_DeviceSuspend(CMIOHardwarePlugInRef, CMIODeviceID) { return noErr; }
OSStatus TCVC_DeviceResume (CMIOHardwarePlugInRef, CMIODeviceID) { return noErr; }

OSStatus TCVC_DeviceStartStream(CMIOHardwarePlugInRef, CMIODeviceID, CMIOStreamID) {
    TCVC_LOG("DeviceStartStream — no frames will arrive yet (Phase 1C)");
    return noErr;
}

OSStatus TCVC_DeviceStopStream(CMIOHardwarePlugInRef, CMIODeviceID, CMIOStreamID) {
    TCVC_LOG("DeviceStopStream");
    return noErr;
}

OSStatus TCVC_DeviceProcessAVCCommand   (CMIOHardwarePlugInRef, CMIODeviceID, CMIODeviceAVCCommand*)   { return kCMIOHardwareUnsupportedOperationError; }
OSStatus TCVC_DeviceProcessRS422Command (CMIOHardwarePlugInRef, CMIODeviceID, CMIODeviceRS422Command*) { return kCMIOHardwareUnsupportedOperationError; }

OSStatus TCVC_StreamCopyBufferQueue(CMIOHardwarePlugInRef, CMIOStreamID,
                                    CMIODeviceStreamQueueAlteredProc,
                                    void*, CMSimpleQueueRef* outQueue) {
    if (outQueue) *outQueue = NULL;
    TCVC_LOG("StreamCopyBufferQueue — Phase 1B has no queue yet");
    return kCMIOHardwareIllegalOperationError;
}

OSStatus TCVC_StreamDeckPlay (CMIOHardwarePlugInRef, CMIOStreamID) { return kCMIOHardwareUnsupportedOperationError; }
OSStatus TCVC_StreamDeckStop (CMIOHardwarePlugInRef, CMIOStreamID) { return kCMIOHardwareUnsupportedOperationError; }
OSStatus TCVC_StreamDeckJog  (CMIOHardwarePlugInRef, CMIOStreamID, SInt32)
    { return kCMIOHardwareUnsupportedOperationError; }
OSStatus TCVC_StreamDeckCueTo(CMIOHardwarePlugInRef, CMIOStreamID, Float64, Boolean)
    { return kCMIOHardwareUnsupportedOperationError; }

}  // anonymous namespace

// =============================================================================
// Factory
// =============================================================================

extern "C" void* TrussCVirtualCamFactory(CFAllocatorRef allocator, CFUUIDRef requestedTypeID) {
    if (!CFEqual(requestedTypeID, kCMIOHardwarePlugInTypeID)) {
        TCVC_LOG("factory rejected: not a CMIO plug-in type request");
        return NULL;
    }

    Instance* inst = (Instance*)calloc(1, sizeof(Instance));
    if (!inst) return NULL;

    inst->vtable    = &gVtable;
    inst->factoryID = CFUUIDCreateFromString(allocator, kFactoryUUIDStr);
    inst->refCount.store(1);

    if (inst->factoryID) CFPlugInAddInstanceForFactory(inst->factoryID);

    TCVC_LOG("factory created instance %p", inst);
    return inst;
}
