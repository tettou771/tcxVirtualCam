// =============================================================================
// PlugInMain.mm - tcxVirtualCam CoreMediaIO DAL Plug-In entry point
// =============================================================================
//
// Phase 1A: bundle skeleton only.
//
// What this does:
//   - Exports TrussCVirtualCamFactory (referenced by Info.plist).
//   - Returns a CMIOHardwarePlugInInterface vtable.
//   - QueryInterface / AddRef / Release implement the standard IUnknown
//     refcount pattern.
//   - Every other vtable method is a no-op stub returning success
//     (or kCMIOHardwareUnsupportedOperationError where appropriate).
//
// What this does NOT do yet (Phase 1B+):
//   - Publish a CMIO Plug-In / Device / Stream object hierarchy.
//   - Serve any video frames.
//
// So after `sudo cp`'ing the built bundle into
// /Library/CoreMediaIO/Plug-Ins/DAL/, the cmio assistant should be able to
// load it without crashing — but no virtual camera will appear in any app's
// device list yet. That comes in 1B.
// =============================================================================

#include <CoreMediaIO/CMIOHardwarePlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <os/log.h>

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------
//
// Plug-ins run inside other processes (Zoom, Photo Booth, …), so stdout/stderr
// is useless for debugging. Use os_log; view in Console.app filtered by
// subsystem "org.trussc.virtualcam".

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
// Instance struct
// -----------------------------------------------------------------------------
//
// CFPlugIn factories return a `void**` whose first dereference yields the
// vtable. To make that work, we lay the struct out with the vtable pointer
// at offset 0 and return `&instance->vtable`.

namespace {

struct Instance {
    CMIOHardwarePlugInInterface* vtable;   // MUST be first field
    CFUUIDRef                    factoryID;
    int32_t                      refCount;
};

// Forward decls so the static vtable below can reference them.
HRESULT  TCVC_QueryInterface(void* self, REFIID uuid, LPVOID* outInterface);
ULONG    TCVC_AddRef(void* self);
ULONG    TCVC_Release(void* self);

OSStatus TCVC_Initialize(CMIOHardwarePlugInRef self);
OSStatus TCVC_InitializeWithObjectID(CMIOHardwarePlugInRef self, CMIOObjectID objectID);
OSStatus TCVC_Teardown(CMIOHardwarePlugInRef self);

void     TCVC_ObjectShow(CMIOHardwarePlugInRef self, CMIOObjectID objectID);
Boolean  TCVC_ObjectHasProperty(CMIOHardwarePlugInRef self, CMIOObjectID objectID,
                                const CMIOObjectPropertyAddress* address);
OSStatus TCVC_ObjectIsPropertySettable(CMIOHardwarePlugInRef self, CMIOObjectID objectID,
                                       const CMIOObjectPropertyAddress* address,
                                       Boolean* outIsSettable);
OSStatus TCVC_ObjectGetPropertyDataSize(CMIOHardwarePlugInRef self, CMIOObjectID objectID,
                                        const CMIOObjectPropertyAddress* address,
                                        UInt32 qualifierDataSize, const void* qualifierData,
                                        UInt32* outDataSize);
OSStatus TCVC_ObjectGetPropertyData(CMIOHardwarePlugInRef self, CMIOObjectID objectID,
                                    const CMIOObjectPropertyAddress* address,
                                    UInt32 qualifierDataSize, const void* qualifierData,
                                    UInt32 dataSize, UInt32* outDataUsed, void* outData);
OSStatus TCVC_ObjectSetPropertyData(CMIOHardwarePlugInRef self, CMIOObjectID objectID,
                                    const CMIOObjectPropertyAddress* address,
                                    UInt32 qualifierDataSize, const void* qualifierData,
                                    UInt32 dataSize, const void* data);

OSStatus TCVC_DeviceSuspend(CMIOHardwarePlugInRef self, CMIODeviceID device);
OSStatus TCVC_DeviceResume(CMIOHardwarePlugInRef self, CMIODeviceID device);
OSStatus TCVC_DeviceStartStream(CMIOHardwarePlugInRef self, CMIODeviceID device, CMIOStreamID stream);
OSStatus TCVC_DeviceStopStream(CMIOHardwarePlugInRef self, CMIODeviceID device, CMIOStreamID stream);
OSStatus TCVC_DeviceProcessAVCCommand(CMIOHardwarePlugInRef self, CMIODeviceID device,
                                      CMIODeviceAVCCommand* ioAVCCommand);
OSStatus TCVC_DeviceProcessRS422Command(CMIOHardwarePlugInRef self, CMIODeviceID device,
                                        CMIODeviceRS422Command* ioRS422Command);

OSStatus TCVC_StreamCopyBufferQueue(CMIOHardwarePlugInRef self, CMIOStreamID stream,
                                    CMIODeviceStreamQueueAlteredProc queueAlteredProc,
                                    void* queueAlteredRefCon, CMSimpleQueueRef* outQueue);
OSStatus TCVC_StreamDeckPlay(CMIOHardwarePlugInRef self, CMIOStreamID stream);
OSStatus TCVC_StreamDeckStop(CMIOHardwarePlugInRef self, CMIOStreamID stream);
OSStatus TCVC_StreamDeckJog(CMIOHardwarePlugInRef self, CMIOStreamID stream, SInt32 speed);
OSStatus TCVC_StreamDeckCueTo(CMIOHardwarePlugInRef self, CMIOStreamID stream,
                              Float64 frameNumber, Boolean playOnCue);

// Static vtable wired up to the methods above.
CMIOHardwarePlugInInterface gVtable = {
    NULL,  // _reserved (IUnknown convention)

    TCVC_QueryInterface,
    TCVC_AddRef,
    TCVC_Release,

    TCVC_Initialize,
    TCVC_InitializeWithObjectID,
    TCVC_Teardown,

    TCVC_ObjectShow,
    TCVC_ObjectHasProperty,
    TCVC_ObjectIsPropertySettable,
    TCVC_ObjectGetPropertyDataSize,
    TCVC_ObjectGetPropertyData,
    TCVC_ObjectSetPropertyData,

    TCVC_DeviceSuspend,
    TCVC_DeviceResume,
    TCVC_DeviceStartStream,
    TCVC_DeviceStopStream,
    TCVC_DeviceProcessAVCCommand,
    TCVC_DeviceProcessRS422Command,

    TCVC_StreamCopyBufferQueue,
    TCVC_StreamDeckPlay,
    TCVC_StreamDeckStop,
    TCVC_StreamDeckJog,
    TCVC_StreamDeckCueTo,
};

} // anonymous namespace

// -----------------------------------------------------------------------------
// IUnknown
// -----------------------------------------------------------------------------

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
    return (ULONG)__sync_add_and_fetch(&inst->refCount, 1);
}

ULONG TCVC_Release(void* self) {
    Instance* inst = static_cast<Instance*>(self);
    if (!inst) return 0;

    int32_t newCount = __sync_sub_and_fetch(&inst->refCount, 1);
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

} // anonymous namespace

// -----------------------------------------------------------------------------
// Plug-In lifecycle (stubs)
// -----------------------------------------------------------------------------

namespace {

OSStatus TCVC_Initialize(CMIOHardwarePlugInRef self) {
    TCVC_LOG("Initialize (legacy v2 path)");
    // v3+ hosts call InitializeWithObjectID; this path is here for completeness.
    return TCVC_InitializeWithObjectID(self, kCMIOObjectUnknown);
}

OSStatus TCVC_InitializeWithObjectID(CMIOHardwarePlugInRef self, CMIOObjectID objectID) {
    TCVC_LOG("InitializeWithObjectID: 0x%x", (unsigned)objectID);
    // Phase 1B will publish a CMIOObject hierarchy here.
    return noErr;
}

OSStatus TCVC_Teardown(CMIOHardwarePlugInRef self) {
    TCVC_LOG("Teardown");
    return noErr;
}

} // anonymous namespace

// -----------------------------------------------------------------------------
// Object property API (stubs)
// -----------------------------------------------------------------------------
//
// All return "unknown property" until Phase 1B publishes real objects.

namespace {

void TCVC_ObjectShow(CMIOHardwarePlugInRef, CMIOObjectID) {}

Boolean TCVC_ObjectHasProperty(CMIOHardwarePlugInRef, CMIOObjectID,
                               const CMIOObjectPropertyAddress*) {
    return false;
}

OSStatus TCVC_ObjectIsPropertySettable(CMIOHardwarePlugInRef, CMIOObjectID,
                                       const CMIOObjectPropertyAddress*,
                                       Boolean* outIsSettable) {
    if (outIsSettable) *outIsSettable = false;
    return kCMIOHardwareUnknownPropertyError;
}

OSStatus TCVC_ObjectGetPropertyDataSize(CMIOHardwarePlugInRef, CMIOObjectID,
                                        const CMIOObjectPropertyAddress*,
                                        UInt32, const void*,
                                        UInt32* outDataSize) {
    if (outDataSize) *outDataSize = 0;
    return kCMIOHardwareUnknownPropertyError;
}

OSStatus TCVC_ObjectGetPropertyData(CMIOHardwarePlugInRef, CMIOObjectID,
                                    const CMIOObjectPropertyAddress*,
                                    UInt32, const void*,
                                    UInt32, UInt32* outDataUsed, void*) {
    if (outDataUsed) *outDataUsed = 0;
    return kCMIOHardwareUnknownPropertyError;
}

OSStatus TCVC_ObjectSetPropertyData(CMIOHardwarePlugInRef, CMIOObjectID,
                                    const CMIOObjectPropertyAddress*,
                                    UInt32, const void*,
                                    UInt32, const void*) {
    return kCMIOHardwareUnknownPropertyError;
}

} // anonymous namespace

// -----------------------------------------------------------------------------
// Device / Stream methods (stubs)
// -----------------------------------------------------------------------------

namespace {

OSStatus TCVC_DeviceSuspend(CMIOHardwarePlugInRef, CMIODeviceID)  { return noErr; }
OSStatus TCVC_DeviceResume (CMIOHardwarePlugInRef, CMIODeviceID)  { return noErr; }

OSStatus TCVC_DeviceStartStream(CMIOHardwarePlugInRef, CMIODeviceID, CMIOStreamID) {
    TCVC_LOG("DeviceStartStream (stub)");
    return noErr;
}

OSStatus TCVC_DeviceStopStream(CMIOHardwarePlugInRef, CMIODeviceID, CMIOStreamID) {
    TCVC_LOG("DeviceStopStream (stub)");
    return noErr;
}

OSStatus TCVC_DeviceProcessAVCCommand(CMIOHardwarePlugInRef, CMIODeviceID,
                                      CMIODeviceAVCCommand*) {
    return kCMIOHardwareUnsupportedOperationError;
}

OSStatus TCVC_DeviceProcessRS422Command(CMIOHardwarePlugInRef, CMIODeviceID,
                                        CMIODeviceRS422Command*) {
    return kCMIOHardwareUnsupportedOperationError;
}

OSStatus TCVC_StreamCopyBufferQueue(CMIOHardwarePlugInRef, CMIOStreamID,
                                    CMIODeviceStreamQueueAlteredProc,
                                    void*, CMSimpleQueueRef* outQueue) {
    if (outQueue) *outQueue = NULL;
    // No stream objects yet — Phase 1C will return a real queue here.
    return kCMIOHardwareIllegalOperationError;
}

OSStatus TCVC_StreamDeckPlay (CMIOHardwarePlugInRef, CMIOStreamID) { return kCMIOHardwareUnsupportedOperationError; }
OSStatus TCVC_StreamDeckStop (CMIOHardwarePlugInRef, CMIOStreamID) { return kCMIOHardwareUnsupportedOperationError; }
OSStatus TCVC_StreamDeckJog  (CMIOHardwarePlugInRef, CMIOStreamID, SInt32)
    { return kCMIOHardwareUnsupportedOperationError; }
OSStatus TCVC_StreamDeckCueTo(CMIOHardwarePlugInRef, CMIOStreamID, Float64, Boolean)
    { return kCMIOHardwareUnsupportedOperationError; }

} // anonymous namespace

// -----------------------------------------------------------------------------
// Factory
// -----------------------------------------------------------------------------
//
// Symbol name MUST match the CFPlugInFactories entry in Info.plist.
// CFPlugIn calls this with the requested type UUID (we only handle
// kCMIOHardwarePlugInTypeID).

extern "C" void* TrussCVirtualCamFactory(CFAllocatorRef allocator, CFUUIDRef requestedTypeID) {
    if (!CFEqual(requestedTypeID, kCMIOHardwarePlugInTypeID)) {
        TCVC_LOG("factory rejected: not a CMIO plug-in type request");
        return NULL;
    }

    // UUID must match CFPlugInFactories key in Info.plist.
    static const CFStringRef kFactoryUUIDStr =
        CFSTR("23A6DB67-8CCA-4F60-AB4E-FEDCCE7C14B0");

    Instance* inst = (Instance*)calloc(1, sizeof(Instance));
    if (!inst) return NULL;

    inst->vtable    = &gVtable;
    inst->factoryID = CFUUIDCreateFromString(allocator, kFactoryUUIDStr);
    inst->refCount  = 1;

    if (inst->factoryID) {
        CFPlugInAddInstanceForFactory(inst->factoryID);
    }

    TCVC_LOG("factory created instance %p", inst);
    return inst;   // first field is the vtable pointer, so this == CMIOHardwarePlugInRef
}
