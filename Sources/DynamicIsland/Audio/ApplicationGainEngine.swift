import CoreAudio
import Foundation
import os

/// The output route a gain session replays into.
struct ApplicationGainRoute: Sendable, Equatable {
    let uid: String
    /// A route that also captures (headset, AirPods) would put its microphone
    /// into the aggregate; v1 declines it instead of touching an input.
    let hasInputStreams: Bool
}

/// Real-time half of one gain session. The IOProc only reads this object:
/// no allocation, logging or blocking. The target is exchanged through a
/// try-lock that the audio thread never waits on (the house mailbox pattern).
final class ApplicationGainRenderer: @unchecked Sendable {
    private struct Shared { var target: Float; var cycles: UInt64 = 0 }
    private let shared: OSAllocatedUnfairLock<Shared>
    private var current: Float
    private var target: Float
    let tapChannels: Int
    let tapInterleaved: Bool

    init(gain: Float, tapChannels: Int, tapInterleaved: Bool) {
        let gain = Self.clamp(gain)
        shared = OSAllocatedUnfairLock(initialState: Shared(target: gain))
        current = gain; target = gain
        self.tapChannels = tapChannels; self.tapInterleaved = tapInterleaved
    }

    func setTarget(_ gain: Float) { shared.withLock { $0.target = Self.clamp(gain) } }
    /// Completed render cycles; the engine's watchdog compares successive reads.
    var cycles: UInt64 { shared.withLock { $0.cycles } }

    /// Tap samples × gain into every output channel. The gain ramps linearly
    /// across the buffer so slider moves never click.
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        if let next = shared.withLockIfAvailable({ state -> Float in state.cycles &+= 1; return state.target }) { target = next }
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let outputChannelCount = outputs.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard outputChannelCount > 0 else { return }
        let frames = outputs.first.map { Int($0.mDataByteSize) / (4 * max(1, Int($0.mNumberChannels))) } ?? 0
        let available = availableTapFrames(inputs)
        let start = current, step = frames > 0 ? (target - current) / Float(frames) : 0
        var channelBase = 0
        for buffer in outputs {
            let channels = Int(buffer.mNumberChannels)
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self), channels > 0 else { channelBase += channels; continue }
            let bufferFrames = min(frames, Int(buffer.mDataByteSize) / (4 * channels))
            for frame in 0..<bufferFrames {
                let gain = start + step * Float(frame + 1)
                for channel in 0..<channels {
                    let sample = frame < available
                        ? tapSample(inputs, frame: frame, outputChannel: channelBase + channel, outputChannels: outputChannelCount)
                        : 0
                    data[frame * channels + channel] = sample * gain
                }
            }
            channelBase += channels
        }
        current = target
    }

    private func availableTapFrames(_ inputs: UnsafeMutableAudioBufferListPointer) -> Int {
        guard let first = inputs.first, first.mData != nil else { return 0 }
        let perFrame = tapInterleaved ? tapChannels : 1
        return Int(first.mDataByteSize) / (4 * max(1, perFrame))
    }

    /// Stereo tap → device channels: L→1, R→2, silence above; a mono device
    /// receives the average.
    private func tapSample(_ inputs: UnsafeMutableAudioBufferListPointer, frame: Int, outputChannel: Int, outputChannels: Int) -> Float {
        if outputChannels == 1 && tapChannels > 1 {
            var sum: Float = 0
            for channel in 0..<tapChannels { sum += tapChannelSample(inputs, frame: frame, channel: channel) }
            return sum / Float(tapChannels)
        }
        guard outputChannel < tapChannels else { return 0 }
        return tapChannelSample(inputs, frame: frame, channel: outputChannel)
    }

    private func tapChannelSample(_ inputs: UnsafeMutableAudioBufferListPointer, frame: Int, channel: Int) -> Float {
        if tapInterleaved {
            guard let data = inputs[0].mData?.assumingMemoryBound(to: Float.self) else { return 0 }
            return data[frame * tapChannels + channel]
        }
        guard channel < inputs.count, let data = inputs[channel].mData?.assumingMemoryBound(to: Float.self) else { return 0 }
        return data[frame]
    }

    private static func clamp(_ gain: Float) -> Float { gain.isFinite ? min(max(gain, 0), 1) : 1 }
}

protocol ApplicationGainHardware: Sendable {
    func defaultOutputRoute() throws -> ApplicationGainRoute
    /// A private, process-specific stereo tap that mutes the process's direct
    /// output only while a client reads it (`.mutedWhenTapped`).
    func createTap(process: AudioObjectID, route: ApplicationGainRoute) throws -> AudioObjectID
    func format(tap: AudioObjectID) throws -> AudioStreamBasicDescription
    func createAggregate(tap: AudioObjectID, route: ApplicationGainRoute) throws -> AudioObjectID
    func createIOProc(device: AudioObjectID, renderer: ApplicationGainRenderer) throws -> AudioDeviceIOProcID
    func start(device: AudioObjectID, io: AudioDeviceIOProcID) throws
    func stop(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus
    func destroyIOProc(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus
    func destroyAggregate(_ id: AudioObjectID) -> OSStatus
    func destroyTap(_ id: AudioObjectID) -> OSStatus
}

enum ApplicationGainError: Error, Sendable, Equatable {
    case routeHasInput
    case unsupportedFormat
    case teardownIncomplete
}

/// Owns every per-app tap, aggregate and IOProc. An app at unity gain is never
/// tapped: it plays directly. Failure always prefers releasing the tap, which
/// returns the app to its own unmodified output.
actor ApplicationGainEngine {
    private final class Session {
        let process: AudioObjectID
        let renderer: ApplicationGainRenderer
        var tap: AudioObjectID?
        var device: AudioObjectID?
        var io: AudioDeviceIOProcID?
        var started = false
        var lastCycles: UInt64 = 0
        var idleChecks = 0
        init(process: AudioObjectID, renderer: ApplicationGainRenderer) { self.process = process; self.renderer = renderer }
        var isClosed: Bool { tap == nil && device == nil && io == nil }
    }

    static let unity = 0.999
    private let hardware: any ApplicationGainHardware
    private var sessions: [AudioObjectID: Session] = [:]
    /// Sessions whose teardown failed keep their HAL objects here for a later retry.
    private var orphaned: [Session] = []
    private var watchdog: Task<Void, Never>?
    private let watchdogInterval: Duration
    private let onStall: @Sendable (AudioObjectID) -> Void

    init(hardware: any ApplicationGainHardware = CoreAudioApplicationGainHardware(),
         watchdogInterval: Duration = .milliseconds(750),
         onStall: @escaping @Sendable (AudioObjectID) -> Void = { _ in }) {
        self.hardware = hardware
        self.watchdogInterval = watchdogInterval
        self.onStall = onStall
    }

    var activeProcesses: Set<AudioObjectID> { Set(sessions.keys) }

    /// `gain` is a linear amplitude in 0...1. Unity releases the app.
    func setGain(_ gain: Double, process: AudioObjectID) throws {
        guard gain.isFinite, (0...1).contains(gain) else { throw NativeAudioError.invalidValue }
        if gain >= Self.unity {
            try release(process)
            return
        }
        if let session = sessions[process] {
            session.renderer.setTarget(Float(gain))
            return
        }
        let route = try hardware.defaultOutputRoute()
        guard !route.hasInputStreams else { throw ApplicationGainError.routeHasInput }
        try open(process: process, gain: Float(gain), route: route)
        startWatchdogIfNeeded()
    }

    func release(_ process: AudioObjectID) throws {
        guard let session = sessions.removeValue(forKey: process) else { return }
        try close(session)
    }

    /// Device change, sleep, quit or disable: every app returns to direct output.
    func releaseAll() throws {
        var failed = false
        for process in Array(sessions.keys) {
            do { try release(process) } catch { failed = true }
        }
        for session in orphaned { if (try? close(session)) == nil { failed = true } }
        orphaned.removeAll { $0.isClosed }
        watchdog?.cancel(); watchdog = nil
        if failed { throw ApplicationGainError.teardownIncomplete }
    }

    /// One watchdog pass: a session whose IOProc stopped advancing is released
    /// (with `.mutedWhenTapped` the app is already audible again directly).
    /// A session that has not rendered yet gets four passes: Bluetooth outputs
    /// can take over a second to start IO.
    func checkStalls() {
        for (process, session) in sessions where session.started {
            let cycles = session.renderer.cycles
            if cycles == session.lastCycles {
                session.idleChecks += 1
                if cycles > 0 || session.idleChecks >= 4 {
                    try? release(process)
                    onStall(process)
                }
            } else {
                session.lastCycles = cycles
                session.idleChecks = 0
            }
        }
        if sessions.isEmpty { watchdog?.cancel(); watchdog = nil }
    }

    private func open(process: AudioObjectID, gain: Float, route: ApplicationGainRoute) throws {
        let tap = try hardware.createTap(process: process, route: route)
        var session: Session?
        do {
            let format = try hardware.format(tap: tap)
            let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, (1...2).contains(format.mChannelsPerFrame),
                  format.mSampleRate.isFinite, format.mSampleRate >= 8_000 else {
                throw ApplicationGainError.unsupportedFormat
            }
            let created = Session(process: process, renderer: ApplicationGainRenderer(
                gain: gain, tapChannels: Int(format.mChannelsPerFrame), tapInterleaved: interleaved))
            created.tap = tap
            session = created
            created.device = try hardware.createAggregate(tap: tap, route: route)
            created.io = try hardware.createIOProc(device: created.device!, renderer: created.renderer)
            // Reading starts here: the tap mutes direct output only once this
            // IOProc is replaying it, so there is no double playback window.
            try hardware.start(device: created.device!, io: created.io!)
            created.started = true
            sessions[process] = created
        } catch {
            if let session {
                if (try? close(session)) == nil { orphaned.append(session) }
            } else if hardware.destroyTap(tap) != noErr {
                let leftover = Session(process: process, renderer: ApplicationGainRenderer(gain: 1, tapChannels: 2, tapInterleaved: true))
                leftover.tap = tap
                orphaned.append(leftover)
            }
            throw error
        }
    }

    /// Stop → destroy IOProc → aggregate → tap. A failed step keeps the
    /// remaining objects owned instead of creating anything over them.
    private func close(_ session: Session) throws {
        var firstError: Error?
        if let device = session.device, let io = session.io {
            if session.started {
                let status = hardware.stop(device: device, io: io)
                if status == noErr { session.started = false } else { firstError = NativeAudioError.operationFailed(.stopDevice, status) }
            }
            let status = hardware.destroyIOProc(device: device, io: io)
            if status == noErr { session.io = nil; session.started = false }
            else { firstError = firstError ?? NativeAudioError.operationFailed(.destroyIOProc, status) }
        }
        if session.io == nil, let device = session.device {
            let status = hardware.destroyAggregate(device)
            if status == noErr { session.device = nil }
            else { firstError = firstError ?? NativeAudioError.operationFailed(.destroyAggregate, status) }
        }
        if session.io == nil, session.device == nil, let tap = session.tap {
            let status = hardware.destroyTap(tap)
            if status == noErr { session.tap = nil }
            else { firstError = firstError ?? NativeAudioError.operationFailed(.destroyTap, status) }
        }
        if let firstError {
            if !orphaned.contains(where: { $0 === session }) { orphaned.append(session) }
            throw firstError
        }
    }

    private func startWatchdogIfNeeded() {
        guard watchdog == nil else { return }
        let interval = watchdogInterval
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                await self.checkStalls()
            }
        }
    }
}

/// Supported public Core Audio calls only (macOS 14.2+ process taps).
final class CoreAudioApplicationGainHardware: ApplicationGainHardware, @unchecked Sendable {
    /// Format, start/stop and destroy calls are identical to the spectrum tap's.
    private let shared = CoreAudioTapHardware()

    func defaultOutputRoute() throws -> ApplicationGainRoute {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        try Self.check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device), .readFormat)
        guard device != kAudioObjectUnknown else { throw NativeAudioError.perApplicationRoutingUnavailable }
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidAddress = Self.address(kAudioDevicePropertyDeviceUID)
        try Self.check(AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid), .readFormat)
        guard let uid = uid?.takeRetainedValue() as String? else { throw NativeAudioError.perApplicationRoutingUnavailable }
        var inputAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var inputBytes: UInt32 = 0
        try Self.check(AudioObjectGetPropertyDataSize(device, &inputAddress, 0, nil, &inputBytes), .readFormat)
        return ApplicationGainRoute(uid: uid, hasInputStreams: inputBytes > 0)
    }

    func createTap(process: AudioObjectID, route: ApplicationGainRoute) throws -> AudioObjectID {
        guard #available(macOS 14.2, *) else { throw NativeAudioError.unsupportedPlatform }
        let description = Self.makeTapDescription(process: process, deviceUID: route.uid)
        var id = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(description, &id), .createTap)
        guard id != kAudioObjectUnknown else { throw NativeAudioError.operationFailed(.createTap, kAudioHardwareBadObjectError) }
        return id
    }

    @available(macOS 14.2, *)
    static func makeTapDescription(process: AudioObjectID, deviceUID: String) -> CATapDescription {
        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.name = "DynamicIsland App Volume"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        description.deviceUID = deviceUID
        return description
    }

    func format(tap: AudioObjectID) throws -> AudioStreamBasicDescription { try shared.format(tap: tap) }

    func createAggregate(tap: AudioObjectID, route: ApplicationGainRoute) throws -> AudioObjectID {
        var tapUID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = Self.address(kAudioTapPropertyUID)
        try Self.check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &tapUID), .createAggregate)
        guard let tapUID = tapUID?.takeRetainedValue() as String? else {
            throw NativeAudioError.operationFailed(.createAggregate, kAudioHardwareBadObjectError)
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "DynamicIsland App Volume",
            kAudioAggregateDeviceUIDKey: "com.local.dynamicisland.appvolume.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            // The real output device is the clock; the tap is resampled to it.
            kAudioAggregateDeviceMainSubDeviceKey: route.uid,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: route.uid]],
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]]
        ]
        var id = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &id), .createAggregate)
        guard id != kAudioObjectUnknown else { throw NativeAudioError.operationFailed(.createAggregate, kAudioHardwareBadObjectError) }
        return id
    }

    func createIOProc(device: AudioObjectID, renderer: ApplicationGainRenderer) throws -> AudioDeviceIOProcID {
        var io: AudioDeviceIOProcID?
        try Self.check(AudioDeviceCreateIOProcIDWithBlock(&io, device, nil) { _, input, _, output, _ in
            renderer.render(input: input, output: output)
        }, .createIOProc)
        guard let io else { throw NativeAudioError.operationFailed(.createIOProc, kAudioHardwareBadObjectError) }
        return io
    }

    func start(device: AudioObjectID, io: AudioDeviceIOProcID) throws { try shared.start(device: device, io: io) }
    func stop(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { shared.stop(device: device, io: io) }
    func destroyIOProc(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { shared.destroyIOProc(device: device, io: io) }
    func destroyAggregate(_ id: AudioObjectID) -> OSStatus { shared.destroyAggregate(id) }
    func destroyTap(_ id: AudioObjectID) -> OSStatus { shared.destroyTap(id) }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func check(_ status: OSStatus, _ operation: NativeAudioOperation) throws {
        if status == kAudioDevicePermissionsError { throw NativeAudioError.permissionDenied }
        if status != noErr { throw NativeAudioError.operationFailed(operation, status) }
    }
}
