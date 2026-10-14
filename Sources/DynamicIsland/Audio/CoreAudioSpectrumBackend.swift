import CoreAudio
import Foundation

protocol AudioSpectrumCaptureBackend: Sendable {
    func start(generation: UInt64) async throws -> AudioSpectrumMailbox
    func stop(generation: UInt64) async throws
}

/// Only this actor owns HAL resources. Permission-sensitive operations never run on MainActor.
actor CoreAudioSpectrumBackend: AudioSpectrumCaptureBackend {
    private let hardware: any AudioTapHardware
    private var session: AudioTapSession?
    private var generation: UInt64?

    init(hardware: any AudioTapHardware = CoreAudioTapHardware()) { self.hardware = hardware }

    func start(generation: UInt64) throws -> AudioSpectrumMailbox {
        if self.generation == generation, let session { return session.mailbox }
        try session?.close()
        session = nil
        let created = AudioTapSession(hardware: hardware)
        session = created
        self.generation = generation
        do {
            try created.start()
            return created.mailbox
        } catch {
            try? created.close()
            if created.isClosed { session = nil; self.generation = nil }
            throw error
        }
    }

    func stop(generation: UInt64) throws {
        guard self.generation == generation else { return }
        try session?.close()
        session = nil
        self.generation = nil
    }
}

protocol AudioTapHardware: Sendable {
    func createTap() throws -> AudioObjectID
    func format(tap: AudioObjectID) throws -> AudioStreamBasicDescription
    func createAggregate(tap: AudioObjectID) throws -> AudioObjectID
    func createIOProc(device: AudioObjectID, processor: RealtimeSpectrumProcessor) throws -> AudioDeviceIOProcID
    func observeChanges(tap: AudioObjectID, mailbox: AudioSpectrumMailbox) throws
    func removeObservers()
    func start(device: AudioObjectID, io: AudioDeviceIOProcID) throws
    func stop(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus
    func destroyIOProc(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus
    func destroyAggregate(_ id: AudioObjectID) -> OSStatus
    func destroyTap(_ id: AudioObjectID) -> OSStatus
}

private final class AudioTapSession {
    let mailbox = AudioSpectrumMailbox()
    private let hardware: any AudioTapHardware
    private var tap: AudioObjectID?
    private var device: AudioObjectID?
    private var io: AudioDeviceIOProcID?
    private var started = false
    private var processor: RealtimeSpectrumProcessor?
    var isClosed: Bool { tap == nil && device == nil && io == nil }
    init(hardware: any AudioTapHardware) { self.hardware = hardware }
    deinit { try? close() }

    func start() throws {
        tap = try hardware.createTap()
        let format = try hardware.format(tap: tap!)
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mBitsPerChannel == 32, (1...2).contains(format.mChannelsPerFrame),
              format.mFramesPerPacket == 1,
              format.mBytesPerFrame == 4 * (planar ? 1 : format.mChannelsPerFrame) else {
            throw NativeAudioError.unsupportedFormat
        }
        let processor = try RealtimeSpectrumProcessor(sampleRate: format.mSampleRate, mailbox: mailbox)
        self.processor = processor
        device = try hardware.createAggregate(tap: tap!)
        io = try hardware.createIOProc(device: device!, processor: processor)
        try hardware.observeChanges(tap: tap!, mailbox: mailbox)
        try hardware.start(device: device!, io: io!)
        started = true
    }

    func close() throws {
        mailbox.invalidate()
        hardware.removeObservers()
        var firstError: NativeAudioError?
        if let device, let io {
            if started {
                let status = hardware.stop(device: device, io: io)
                if status == noErr { started = false }
                else { firstError = .operationFailed(.stopDevice, status) }
            }
            let status = hardware.destroyIOProc(device: device, io: io)
            if status == noErr { self.io = nil; started = false }
            else { firstError = firstError ?? .operationFailed(.destroyIOProc, status) }
        }
        // Keep failed resources for a later explicit teardown; never create another tap over them.
        if io == nil, let device {
            let status = hardware.destroyAggregate(device)
            if status == noErr { self.device = nil }
            else { firstError = firstError ?? .operationFailed(.destroyAggregate, status) }
        }
        if io == nil, device == nil, let tap {
            let status = hardware.destroyTap(tap)
            if status == noErr { self.tap = nil }
            else { firstError = firstError ?? .operationFailed(.destroyTap, status) }
        }
        if isClosed { processor = nil }
        if let firstError { throw firstError }
    }
}

/// All mutable ownership is confined to CoreAudioSpectrumBackend; the IOProc owns only processor scratch.
final class CoreAudioTapHardware: AudioTapHardware, @unchecked Sendable {
    private let events = DispatchQueue(label: "DynamicIsland.audio.configuration")
    private var observers: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func createTap() throws -> AudioObjectID {
        guard #available(macOS 14.2, *) else { throw NativeAudioError.unsupportedPlatform }
        let description = Self.makeTapDescription()
        var id = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &id), .createTap)
        guard id != kAudioObjectUnknown else { throw NativeAudioError.operationFailed(.createTap, kAudioHardwareBadObjectError) }
        return id
    }

    @available(macOS 14.2, *)
    static func makeTapDescription() -> CATapDescription {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "DynamicIsland Live Spectrum"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        return description
    }

    func format(tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var value = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = property(kAudioTapPropertyFormat)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &value), .readFormat)
        guard size == MemoryLayout<AudioStreamBasicDescription>.size else { throw NativeAudioError.unsupportedFormat }
        return value
    }

    func createAggregate(tap: AudioObjectID) throws -> AudioObjectID {
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = property(kAudioTapPropertyUID)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &uid), .createAggregate)
        guard let uid else { throw NativeAudioError.operationFailed(.createAggregate, kAudioHardwareBadObjectError) }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "DynamicIsland Spectrum Input",
            kAudioAggregateDeviceUIDKey: "com.local.dynamicisland.spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: uid.takeRetainedValue() as String, kAudioSubTapDriftCompensationKey: true]]
        ]
        var id = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &id), .createAggregate)
        guard id != kAudioObjectUnknown else { throw NativeAudioError.operationFailed(.createAggregate, kAudioHardwareBadObjectError) }
        return id
    }

    func createIOProc(device: AudioObjectID, processor: RealtimeSpectrumProcessor) throws -> AudioDeviceIOProcID {
        var io: AudioDeviceIOProcID?
        // nil queue: HAL invokes directly; no synchronous dispatch to a main/UI queue.
        try check(AudioDeviceCreateIOProcIDWithBlock(&io, device, nil) { now, input, _, _, _ in
            processor.consume(input, hostTime: now.pointee.mHostTime)
        }, .createIOProc)
        guard let io else { throw NativeAudioError.operationFailed(.createIOProc, kAudioHardwareBadObjectError) }
        return io
    }

    func observeChanges(tap: AudioObjectID, mailbox: AudioSpectrumMailbox) throws {
        for (id, selector) in [(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice),
                               (tap, kAudioTapPropertyFormat)] {
            var address = property(selector)
            let block: AudioObjectPropertyListenerBlock = { _, _ in mailbox.invalidate() }
            try check(AudioObjectAddPropertyListenerBlock(id, &address, events, block), .readFormat)
            observers.append((id, address, block))
        }
    }

    func removeObservers() {
        for (id, saved, block) in observers {
            var address = saved
            AudioObjectRemovePropertyListenerBlock(id, &address, events, block)
        }
        observers.removeAll()
    }
    func start(device: AudioObjectID, io: AudioDeviceIOProcID) throws { try check(AudioDeviceStart(device, io), .startDevice) }
    func stop(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { AudioDeviceStop(device, io) }
    func destroyIOProc(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { AudioDeviceDestroyIOProcID(device, io) }
    func destroyAggregate(_ id: AudioObjectID) -> OSStatus { AudioHardwareDestroyAggregateDevice(id) }
    func destroyTap(_ id: AudioObjectID) -> OSStatus {
        guard #available(macOS 14.2, *) else { return kAudioHardwareUnsupportedOperationError }
        return AudioHardwareDestroyProcessTap(id)
    }
    private func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private func check(_ status: OSStatus, _ operation: NativeAudioOperation) throws {
        if status == kAudioDevicePermissionsError { throw NativeAudioError.permissionDenied }
        if status != noErr { throw NativeAudioError.operationFailed(operation, status) }
    }
}
