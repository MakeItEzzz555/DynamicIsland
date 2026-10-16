import CoreAudio
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Records every HAL call; never touches real audio devices.
private final class FakeGainHardware: ApplicationGainHardware, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _renderers: [AudioObjectID: ApplicationGainRenderer] = [:]
    var route = ApplicationGainRoute(uid: "speakers", hasInputStreams: false)
    var format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
        mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    var tapError: Error?
    var startError: Error?
    var destroyTapStatus: OSStatus = noErr
    var onCreateTap: (@Sendable ([AudioObjectID]) -> Void)?
    private var nextID: AudioObjectID = 100

    var calls: [String] { lock.withLock { _calls } }
    func renderer(forDevice device: AudioObjectID) -> ApplicationGainRenderer? { lock.withLock { _renderers[device] } }
    var lastRenderer: ApplicationGainRenderer? { lock.withLock { _renderers.max { $0.key < $1.key }?.value } }
    private func log(_ call: String) { lock.withLock { _calls.append(call) } }
    private func id() -> AudioObjectID { lock.withLock { nextID += 1; return nextID } }

    func defaultOutputRoute() throws -> ApplicationGainRoute { route }
    func createTap(processes: [AudioObjectID], route: ApplicationGainRoute) throws -> AudioObjectID {
        onCreateTap?(processes)
        if let tapError { throw tapError }
        let tap = id(); log("tap \(processes)→\(route.uid)"); return tap
    }
    func format(tap: AudioObjectID) throws -> AudioStreamBasicDescription { format }
    func createAggregate(tap: AudioObjectID, route: ApplicationGainRoute) throws -> AudioObjectID {
        let device = id(); log("aggregate"); return device
    }
    func createIOProc(device: AudioObjectID, renderer: ApplicationGainRenderer) throws -> AudioDeviceIOProcID {
        lock.withLock { _renderers[device] = renderer }
        log("ioproc")
        return { _, _, _, _, _, _, _ in noErr }
    }
    func start(device: AudioObjectID, io: AudioDeviceIOProcID) throws {
        if let startError { throw startError }
        log("start")
    }
    func stop(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { log("stop"); return noErr }
    func destroyIOProc(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { log("destroyIOProc"); return noErr }
    func destroyAggregate(_ id: AudioObjectID) -> OSStatus { log("destroyAggregate"); return noErr }
    func destroyTap(_ id: AudioObjectID) -> OSStatus { log("destroyTap"); return destroyTapStatus }
}

/// Owns interleaved Float32 audio buffers for one render call.
private final class Buffers {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    init(frames: Int, channelsPerBuffer: [Int], fill: (Int, Int, Int) -> Float = { _, _, _ in 0 }) {
        list = AudioBufferList.allocate(maximumBuffers: channelsPerBuffer.count)
        for (index, channels) in channelsPerBuffer.enumerated() {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: frames * channels)
            for frame in 0..<frames { for channel in 0..<channels { data[frame * channels + channel] = fill(index, frame, channel) } }
            storage.append(data)
            list[index] = AudioBuffer(mNumberChannels: UInt32(channels), mDataByteSize: UInt32(frames * channels * 4), mData: data)
        }
    }
    deinit { storage.forEach { $0.deallocate() }; free(list.unsafeMutablePointer) }
    func sample(buffer: Int, frame: Int, channel: Int) -> Float {
        storage[buffer][frame * Int(list[buffer].mNumberChannels) + channel]
    }
}

final class ApplicationGainRendererTests: XCTestCase {
    private func stereoTap(frames: Int) -> Buffers {
        Buffers(frames: frames, channelsPerBuffer: [2]) { _, _, channel in channel == 0 ? 0.5 : -0.25 }
    }

    func testUnityCopiesAndGainScalesAfterOneRampedBuffer() {
        let renderer = ApplicationGainRenderer(gain: 1, tapChannels: 2, tapInterleaved: true)
        let input = stereoTap(frames: 64), output = Buffers(frames: 64, channelsPerBuffer: [2])
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 10, channel: 0), 0.5)
        XCTAssertEqual(output.sample(buffer: 0, frame: 10, channel: 1), -0.25)

        renderer.setTarget(0.3)
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        var previous: Float = 1
        for frame in 0..<64 {
            let gain = output.sample(buffer: 0, frame: frame, channel: 0) / 0.5
            XCTAssertLessThanOrEqual(gain, previous + 1e-6, "the ramp only moves toward the target")
            XCTAssertGreaterThan(gain, 0.29)
            previous = gain
        }
        XCTAssertEqual(output.sample(buffer: 0, frame: 63, channel: 0), 0.15, accuracy: 1e-6, "the ramp ends exactly on target")
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 0, channel: 1), -0.075, accuracy: 1e-6)
        XCTAssertEqual(renderer.cycles, 3)
    }

    func testZeroMutesAndInvalidTargetsFailOpenToUnity() {
        let renderer = ApplicationGainRenderer(gain: 0, tapChannels: 2, tapInterleaved: true)
        let input = stereoTap(frames: 32), output = Buffers(frames: 32, channelsPerBuffer: [2]) { _, _, _ in 9 }
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertTrue((0..<32).allSatisfy { output.sample(buffer: 0, frame: $0, channel: 0) == 0 })
        renderer.setTarget(.nan)
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 5, channel: 0), 0.5)
    }

    func testChannelMappingForPlanarMonoAndMultichannelDevices() {
        let planarTap = Buffers(frames: 16, channelsPerBuffer: [1, 1]) { buffer, _, _ in buffer == 0 ? 0.4 : 0.2 }
        let renderer = ApplicationGainRenderer(gain: 1, tapChannels: 2, tapInterleaved: false)
        let planarOut = Buffers(frames: 16, channelsPerBuffer: [1, 1])
        renderer.render(input: planarTap.list.unsafePointer, output: planarOut.list.unsafeMutablePointer)
        XCTAssertEqual(planarOut.sample(buffer: 0, frame: 3, channel: 0), 0.4)
        XCTAssertEqual(planarOut.sample(buffer: 1, frame: 3, channel: 0), 0.2)

        let mono = Buffers(frames: 16, channelsPerBuffer: [1])
        renderer.render(input: planarTap.list.unsafePointer, output: mono.list.unsafeMutablePointer)
        XCTAssertEqual(mono.sample(buffer: 0, frame: 3, channel: 0), 0.3, accuracy: 1e-6, "mono devices get the average")

        let quad = Buffers(frames: 16, channelsPerBuffer: [4]) { _, _, _ in 7 }
        renderer.render(input: planarTap.list.unsafePointer, output: quad.list.unsafeMutablePointer)
        XCTAssertEqual(quad.sample(buffer: 0, frame: 3, channel: 1), 0.2)
        XCTAssertEqual(quad.sample(buffer: 0, frame: 3, channel: 2), 0, "channels beyond stereo stay silent")
        XCTAssertEqual(quad.sample(buffer: 0, frame: 3, channel: 3), 0)
    }

    func testASixChannelStreamTapIsCopiedChannelForChannelAtItsTrueLevel() {
        let tap = Buffers(frames: 8, channelsPerBuffer: [6]) { _, _, channel in Float(channel + 1) / 10 }
        let renderer = ApplicationGainRenderer(gain: 1, tapChannels: 6, tapInterleaved: true)
        let output = Buffers(frames: 8, channelsPerBuffer: [6]) { _, _, _ in 9 }
        renderer.render(input: tap.list.unsafePointer, output: output.list.unsafeMutablePointer)
        for channel in 0..<6 { XCTAssertEqual(output.sample(buffer: 0, frame: 2, channel: channel), Float(channel + 1) / 10, accuracy: 1e-6) }
        renderer.setTarget(0.5)
        renderer.render(input: tap.list.unsafePointer, output: output.list.unsafeMutablePointer)
        renderer.render(input: tap.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 2, channel: 5), 0.3, accuracy: 1e-6)
    }

    func testTheTapIsTheTrailingInputWhenTheRouteHasItsOwnInput() {
        let loopback = Buffers(frames: 16, channelsPerBuffer: [6, 2]) { buffer, _, channel in buffer == 0 ? 0.9 : (channel == 0 ? 0.4 : -0.2) }
        let renderer = ApplicationGainRenderer(gain: 1, tapChannels: 2, tapInterleaved: true)
        let output = Buffers(frames: 16, channelsPerBuffer: [6]) { _, _, _ in 7 }
        renderer.render(input: loopback.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 3, channel: 0), 0.4, "the device's own input is not mistaken for the app")
        XCTAssertEqual(output.sample(buffer: 0, frame: 3, channel: 1), -0.2)
        XCTAssertEqual(output.sample(buffer: 0, frame: 3, channel: 2), 0)

        let planar = Buffers(frames: 16, channelsPerBuffer: [6, 1, 1]) { buffer, _, _ in buffer == 0 ? 0.9 : (buffer == 1 ? 0.4 : 0.2) }
        let planarRenderer = ApplicationGainRenderer(gain: 1, tapChannels: 2, tapInterleaved: false)
        planarRenderer.render(input: planar.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 3, channel: 0), 0.4)
        XCTAssertEqual(output.sample(buffer: 0, frame: 3, channel: 1), 0.2)
    }

    func testShortTapIsZeroFilledInsteadOfReadingPastItsEnd() {
        let renderer = ApplicationGainRenderer(gain: 1, tapChannels: 2, tapInterleaved: true)
        let input = stereoTap(frames: 8), output = Buffers(frames: 16, channelsPerBuffer: [2]) { _, _, _ in 9 }
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 7, channel: 0), 0.5)
        XCTAssertEqual(output.sample(buffer: 0, frame: 8, channel: 0), 0)
        XCTAssertEqual(output.sample(buffer: 0, frame: 15, channel: 1), 0)
    }
}

final class ApplicationGainEngineTests: XCTestCase {
    func testOnlyAttenuatedAppsAreTappedAndUnityReleasesInSafeOrder() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(1, application: "app", processes: [7])
        XCTAssertTrue(hardware.calls.isEmpty, "unity never taps an app")

        try await engine.setGain(0.3, application: "app", processes: [7])
        XCTAssertEqual(hardware.calls, ["tap [7]→speakers", "aggregate", "ioproc", "start"])
        try await engine.setGain(0.5, application: "app", processes: [7])
        XCTAssertEqual(hardware.calls.count, 4, "a level change reuses the session")
        let activeAfterChange = await engine.activeApplications
        XCTAssertEqual(activeAfterChange, ["app"])

        try await engine.setGain(1, application: "app", processes: [7])
        XCTAssertEqual(Array(hardware.calls.suffix(4)), ["stop", "destroyIOProc", "destroyAggregate", "destroyTap"])
        let active = await engine.activeApplications
        XCTAssertTrue(active.isEmpty)
    }

    func testAppsAreIndependent() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, application: "one", processes: [1])
        try await engine.setGain(0, application: "two", processes: [2])
        try await engine.setGain(1, application: "one", processes: [1])
        let active = await engine.activeApplications
        XCTAssertEqual(active, ["two"], "releasing one app leaves the other routed")
    }

    func testAllOfAnAppsProcessesShareOneTapAndOneGain() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, application: "discord", processes: [9, 7, 8])
        XCTAssertEqual(hardware.calls, ["tap [7, 8, 9]→speakers", "aggregate", "ioproc", "start"], "one session taps the main app and its helpers")
        let tapped = await engine.tappedProcesses(of: "discord")
        XCTAssertEqual(tapped, [7, 8, 9])
        try await engine.setGain(0.4, application: "discord", processes: [7, 8, 9])
        XCTAssertEqual(hardware.calls.count, 4, "the same process set, in any order, keeps the session")
        try await engine.setGain(0.4, application: "discord", processes: [])
        let active = await engine.activeApplications
        XCTAssertTrue(active.isEmpty, "an app with no audio processes left is released")
    }

    func testAHelperJoiningRebuildsTheSessionMakeBeforeBreak() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, application: "app", processes: [7])
        let old = try XCTUnwrap(hardware.lastRenderer)
        try await engine.setGain(0.3, application: "app", processes: [7, 8])
        XCTAssertEqual(hardware.calls, [
            "tap [7]→speakers", "aggregate", "ioproc", "start",
            "tap [7, 8]→speakers", "aggregate", "ioproc", "start",   // the new tap mutes the same app before the old one stops
            "stop", "destroyIOProc", "destroyAggregate", "destroyTap"])
        let tapped = await engine.tappedProcesses(of: "app")
        XCTAssertEqual(tapped, [7, 8])
        let input = Buffers(frames: 8, channelsPerBuffer: [2]) { _, _, _ in 1 }, output = Buffers(frames: 8, channelsPerBuffer: [2])
        old.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        old.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 0, channel: 0), 0, "the replaced replay is silenced, so nothing is doubled")
        let active = await engine.activeApplications
        XCTAssertEqual(active, ["app"])
    }

    func testAFailedRebuildKeepsTheWorkingSessionAtItsLevel() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, application: "app", processes: [7])
        let old = try XCTUnwrap(hardware.lastRenderer)
        hardware.startError = NativeAudioError.operationFailed(.startDevice, -1)
        await XCTAssertThrowsAsync(try await engine.setGain(0.3, application: "app", processes: [7, 8]))
        let tapped = await engine.tappedProcesses(of: "app")
        XCTAssertEqual(tapped, [7], "the old session still owns the app")
        let input = Buffers(frames: 8, channelsPerBuffer: [2]) { _, _, _ in 1 }, output = Buffers(frames: 8, channelsPerBuffer: [2])
        old.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        old.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 0, channel: 0), 0.3, accuracy: 1e-6, "its replay was restored")
    }

    func testRoutesWithAMicrophoneAreDeclinedButLoopbackDevicesAreNot() async throws {
        let hardware = FakeGainHardware()
        hardware.route = .init(uid: "airpods", hasInputStreams: true)
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        await XCTAssertThrowsAsync(try await engine.setGain(0.3, application: "app", processes: [7])) {
            XCTAssertEqual($0 as? ApplicationGainError, .routeHasInput)
        }
        XCTAssertTrue(hardware.calls.isEmpty)

        hardware.route = .init(uid: "BoomAudio", hasInputStreams: true, isVirtual: true)
        try await engine.setGain(0.3, application: "app", processes: [7])
        XCTAssertEqual(hardware.calls.first, "tap [7]→BoomAudio", "a virtual output with a loopback input is routable")
        try await engine.releaseAll()
    }

    func testFailuresTearDownEverythingTheyCreated() async {
        let hardware = FakeGainHardware()
        hardware.startError = NativeAudioError.operationFailed(.startDevice, -1)
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        await XCTAssertThrowsAsync(try await engine.setGain(0.3, application: "app", processes: [7]))
        XCTAssertEqual(hardware.calls, ["tap [7]→speakers", "aggregate", "ioproc", "destroyIOProc", "destroyAggregate", "destroyTap"])

        let unsupported = FakeGainHardware()
        unsupported.format.mChannelsPerFrame = 40
        let other = ApplicationGainEngine(hardware: unsupported, watchdogInterval: .seconds(60))
        await XCTAssertThrowsAsync(try await other.setGain(0.3, application: "app", processes: [7])) {
            XCTAssertEqual($0 as? ApplicationGainError, .unsupportedFormat)
        }
        XCTAssertEqual(unsupported.calls, ["tap [7]→speakers", "destroyTap"])

        let denied = FakeGainHardware()
        denied.tapError = NativeAudioError.permissionDenied
        let third = ApplicationGainEngine(hardware: denied, watchdogInterval: .seconds(60))
        await XCTAssertThrowsAsync(try await third.setGain(0.3, application: "app", processes: [7])) {
            XCTAssertEqual($0 as? NativeAudioError, .permissionDenied)
        }
        let active = await third.activeApplications
        XCTAssertTrue(active.isEmpty)
    }

    func testFailedTapDestroyIsRetainedAndRetriedByReleaseAll() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, application: "app", processes: [7])
        hardware.destroyTapStatus = -50
        await XCTAssertThrowsAsync(try await engine.setGain(1, application: "app", processes: [7]))
        await XCTAssertThrowsAsync(try await engine.releaseAll())
        hardware.destroyTapStatus = noErr
        try await engine.releaseAll()
        XCTAssertEqual(hardware.calls.filter { $0 == "destroyTap" }.count, 3)
        XCTAssertEqual(hardware.calls.filter { $0 == "destroyAggregate" }.count, 1, "objects already gone are not destroyed twice")
    }

    func testFailedTeardownPreventsAnotherTapForTheSameApplicationUntilRecovery() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, application: "app", processes: [7])
        hardware.destroyTapStatus = -50
        await XCTAssertThrowsAsync(try await engine.releaseAll())

        await XCTAssertThrowsAsync(try await engine.setGain(0.2, application: "app", processes: [8]))
        XCTAssertEqual(hardware.calls.filter { $0.hasPrefix("tap ") }.count, 1,
                       "failed teardown must not be covered by a second tap")
        try await engine.setGain(0.4, application: "other", processes: [9])
        let other = await engine.tappedProcesses(of: "other")
        XCTAssertEqual(other, [9], "one application's cleanup must not block another")

        hardware.destroyTapStatus = noErr
        let recoveryStart = hardware.calls.count
        try await engine.setGain(0.2, application: "app", processes: [8])
        XCTAssertEqual(Array(hardware.calls.dropFirst(recoveryStart).prefix(2)), ["destroyTap", "tap [8]→speakers"],
                       "the old resource must be gone before a replacement is created")
        let recovered = await engine.tappedProcesses(of: "app")
        XCTAssertEqual(recovered, [8])
        try await engine.releaseAll()
    }

    func testRetainedOldTapDoesNotBlockLevelChangesOnTheWorkingSession() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, application: "app", processes: [7])
        hardware.destroyTapStatus = -50
        try await engine.setGain(0.2, application: "app", processes: [7, 8])
        do { try await engine.setGain(0.5, application: "app", processes: [7, 8]) }
        catch { XCTFail("A level update creates no resources and must preserve the working route: \(error)") }
        let renderer = try XCTUnwrap(hardware.lastRenderer)
        let input = Buffers(frames: 8, channelsPerBuffer: [2]) { _, _, _ in 1 }
        let output = Buffers(frames: 8, channelsPerBuffer: [2])
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(buffer: 0, frame: 0, channel: 0), 0.5, accuracy: 1e-6)
        XCTAssertEqual(hardware.calls.filter { $0.hasPrefix("tap ") }.count, 2)
        await XCTAssertThrowsAsync(try await engine.setGain(0.4, application: "app", processes: [7, 8, 9]))
        XCTAssertEqual(hardware.calls.filter { $0.hasPrefix("tap ") }.count, 2,
                       "another rebuild still must wait for the retained resource")
        hardware.destroyTapStatus = noErr
        try await engine.releaseAll()
    }

    func testUnityRetriesTheApplicationsFailedTeardown() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, application: "app", processes: [7])
        hardware.destroyTapStatus = -50
        await XCTAssertThrowsAsync(try await engine.setGain(1, application: "app", processes: [7]))
        await XCTAssertThrowsAsync(try await engine.setGain(1, application: "app", processes: [7]))
        hardware.destroyTapStatus = noErr
        try await engine.setGain(1, application: "app", processes: [7])
        XCTAssertEqual(hardware.calls.filter { $0 == "destroyTap" }.count, 3)
        XCTAssertEqual(hardware.calls.filter { $0.hasPrefix("tap ") }.count, 1)
        try await engine.releaseAll()
        XCTAssertEqual(hardware.calls.filter { $0 == "destroyTap" }.count, 3,
                       "successful recovery removes the retained resource")
    }

    func testStalledRenderingReturnsTheAppToDirectOutput() async throws {
        let hardware = FakeGainHardware()
        let stalled = LockedBox<[String]>([])
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60)) { key in stalled.mutate { $0.append(key) } }
        try await engine.setGain(0.3, application: "app", processes: [7])
        let renderer = try XCTUnwrap(hardware.lastRenderer)
        let input = Buffers(frames: 8, channelsPerBuffer: [2]), output = Buffers(frames: 8, channelsPerBuffer: [2])
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        await engine.checkStalls()
        let stillActive = await engine.activeApplications
        XCTAssertEqual(stillActive, ["app"], "an advancing IOProc is healthy")
        await engine.checkStalls()
        let active = await engine.activeApplications
        XCTAssertTrue(active.isEmpty, "no render cycles since the last check releases the app")
        XCTAssertEqual(stalled.value, ["app"])
        XCTAssertEqual(hardware.calls.last, "destroyTap")
    }

    func testASlowStartingOutputGetsAGracePeriodBeforeItCountsAsStalled() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, application: "app", processes: [7])
        for _ in 0..<3 { await engine.checkStalls() }
        let waiting = await engine.activeApplications
        XCTAssertEqual(waiting, ["app"], "no render yet: still within the start grace")
        await engine.checkStalls()
        let released = await engine.activeApplications
        XCTAssertTrue(released.isEmpty, "IO that never starts is released")
    }
}

@MainActor
final class ApplicationVolumeProviderTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "ApplicationVolumeProviderTests.\(UUID().uuidString)")
    }

    private func provider(_ hardware: FakeGainHardware, processes: LockedBox<[ApplicationAudioProcess]>,
                          owners: @escaping @MainActor ([ApplicationAudioProcess]) -> [UInt32: ApplicationAudioOwner] = { _ in [:] }) -> ApplicationAudioDiscovery {
        ApplicationAudioDiscovery(engine: ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60)),
                                  defaults: defaults, readProcesses: { processes.value }, resolveOwners: owners)
    }

    private static let discord = ApplicationAudioOwner(bundleIdentifier: "com.hnc.Discord", name: "Discord", url: nil)
    private static func discordOwners(_ processes: [ApplicationAudioProcess]) -> [UInt32: ApplicationAudioOwner] {
        Dictionary(uniqueKeysWithValues: processes.filter { $0.bundleIdentifier?.hasPrefix("com.hnc.Discord") == true }.map { ($0.objectID, discord) })
    }

    private func level(of renderer: ApplicationGainRenderer?) throws -> Float {
        let renderer = try XCTUnwrap(renderer)
        let input = Buffers(frames: 8, channelsPerBuffer: [2]) { _, _, _ in 1 }
        let output = Buffers(frames: 8, channelsPerBuffer: [2])
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        return output.sample(buffer: 0, frame: 0, channel: 0)
    }

    func testSliderMovesRealGainPersistsAndUnityReleases() async throws {
        let hardware = FakeGainHardware()
        let processes = LockedBox([ApplicationAudioProcess(objectID: 11, pid: 4001, bundleIdentifier: "com.spotify.client", outputIORunning: true),
                                   ApplicationAudioProcess(objectID: 12, pid: 4002, bundleIdentifier: "com.apple.Music", outputIORunning: true)])
        let discovery = provider(hardware, processes: processes)
        await discovery.setGainEnabled(true)
        let spotify = try XCTUnwrap(discovery.outputs.first { $0.bundleIdentifier == "com.spotify.client" })
        XCTAssertEqual(spotify.gain, 1); XCTAssertTrue(spotify.controlAvailable)
        XCTAssertTrue(hardware.calls.isEmpty, "enabling taps nothing until a slider leaves 100%")

        let result = await discovery.requestGain(0.3, application: spotify.identity)
        XCTAssertEqual(result, .verified(volume: 0.3, muted: false))
        XCTAssertEqual(hardware.calls.first, "tap [11]→speakers", "only Spotify is tapped")
        XCTAssertEqual(try level(of: hardware.lastRenderer), 0.09, accuracy: 1e-6, "30% → 0.09 amplitude reaches the output buffer")
        XCTAssertEqual(discovery.outputs.first { $0.bundleIdentifier == "com.spotify.client" }?.gain, 0.3)
        XCTAssertEqual(discovery.outputs.first { $0.bundleIdentifier == "com.apple.Music" }?.gain, 1)

        let muted = await discovery.requestGain(0, application: try XCTUnwrap(discovery.outputs.first { $0.bundleIdentifier == "com.spotify.client" }).identity)
        XCTAssertEqual(muted, .verified(volume: 0, muted: true))
        XCTAssertEqual(try level(of: hardware.lastRenderer), 0)

        let restored = await discovery.requestGain(1, application: try XCTUnwrap(discovery.outputs.first { $0.bundleIdentifier == "com.spotify.client" }).identity)
        XCTAssertEqual(restored, .verified(volume: 1, muted: false))
        XCTAssertEqual(hardware.calls.last, "destroyTap", "100% returns Spotify to its own output")
        XCTAssertNil((defaults.dictionary(forKey: ApplicationAudioDiscovery.levelsKey) ?? [:])["com.spotify.client"])
        await discovery.disableRouting()
    }

    func testOverlappingDragRequestsConvergeOnTheLastLevel() async throws {
        let hardware = FakeGainHardware()
        let processes = LockedBox([ApplicationAudioProcess(objectID: 11, pid: 4001, bundleIdentifier: "com.spotify.client", outputIORunning: true)])
        let discovery = provider(hardware, processes: processes)
        await discovery.setGainEnabled(true)
        let identity = try XCTUnwrap(discovery.outputs.first).identity
        let drags = (0..<20).map { step in Task { await discovery.requestGain(0.9 - Double(step) * 0.035, application: identity) } }
        for drag in drags { _ = await drag.value }
        XCTAssertEqual(discovery.outputs.first?.gain ?? 0, 0.235, accuracy: 1e-9)
        XCTAssertEqual(try level(of: hardware.lastRenderer), Float(0.235 * 0.235), accuracy: 1e-5, "the audio follows the last slider value")
        XCTAssertEqual(hardware.calls.filter { $0.hasPrefix("tap") }.count, 1)
        await discovery.disableRouting()
    }

    func testFailedDisableReportsRetainedResourcesAndSuccessfulCleanupClearsTheIssue() async throws {
        let hardware = FakeGainHardware()
        let processes = LockedBox([ApplicationAudioProcess(objectID: 11, pid: 4001,
            bundleIdentifier: "com.spotify.client", outputIORunning: true)])
        let discovery = provider(hardware, processes: processes)
        await discovery.setGainEnabled(true)
        let identity = try XCTUnwrap(discovery.outputs.first).identity
        let result = await discovery.requestGain(0.3, application: identity)
        XCTAssertEqual(result, .verified(volume: 0.3, muted: false))

        hardware.destroyTapStatus = -50
        await discovery.setGainEnabled(false)
        XCTAssertFalse(discovery.isGainEnabled)
        XCTAssertNotNil(discovery.routingIssue, "disable must not conceal incomplete HAL cleanup")
        XCTAssertTrue(discovery.outputs.allSatisfy { !$0.controlAvailable })

        await discovery.disableRouting()
        XCTAssertNotNil(discovery.routingIssue, "shutdown also reports resources that remain owned")
        hardware.destroyTapStatus = noErr
        await discovery.disableRouting()
        XCTAssertNil(discovery.routingIssue, "successful cleanup clears the previous teardown issue")
        XCTAssertTrue(discovery.outputs.isEmpty)
    }

    func testDisablingDuringReconciliationDoesNotTapTheRemainingApps() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        let processes = [ApplicationAudioProcess(objectID: 11, pid: 4001, bundleIdentifier: "com.spotify.client", outputIORunning: true),
                         ApplicationAudioProcess(objectID: 12, pid: 4002, bundleIdentifier: "com.apple.Music", outputIORunning: true)]
        let discovery = ApplicationAudioDiscovery(engine: engine, defaults: defaults, readProcesses: { processes }, resolveOwners: { _ in [:] })
        await discovery.setGainEnabled(true)
        defaults.set(["com.spotify.client": 0.5, "com.apple.Music": 0.5], forKey: ApplicationAudioDiscovery.levelsKey)
        let entered = expectation(description: "first app routing suspended")
        let resume = DispatchSemaphore(value: 0)
        hardware.onCreateTap = { members in
            guard members == [11] else { return }
            entered.fulfill()
            _ = resume.wait(timeout: .now() + 3)
        }
        defer { resume.signal() }
        let refresh = Task { try await discovery.refresh() }
        await fulfillment(of: [entered], timeout: 3)
        let disable = Task { await discovery.setGainEnabled(false) }
        let deadline = ContinuousClock.now + .seconds(3)
        while discovery.isGainEnabled, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertFalse(discovery.isGainEnabled)
        resume.signal()
        await disable.value
        try await refresh.value
        let active = await engine.activeApplications
        XCTAssertTrue(active.isEmpty, "a stale refresh must not restore taps after disable")
        XCTAssertEqual(hardware.calls.filter { $0.hasPrefix("tap") }, ["tap [11]→speakers"], "the remaining app must never be tapped")
        XCTAssertTrue(discovery.outputs.allSatisfy { $0.gain == nil && !$0.controlAvailable })
        await discovery.disableRouting()
    }

    func testDisablingDuringSliderWriteCancelsTheQueuedLevel() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        let process = ApplicationAudioProcess(objectID: 11, pid: 4001, bundleIdentifier: "com.spotify.client", outputIORunning: true)
        let discovery = ApplicationAudioDiscovery(engine: engine, defaults: defaults, readProcesses: { [process] }, resolveOwners: { _ in [:] })
        await discovery.setGainEnabled(true)
        let identity = try XCTUnwrap(discovery.outputs.first).identity
        let entered = expectation(description: "slider routing suspended")
        let resume = DispatchSemaphore(value: 0)
        hardware.onCreateTap = { _ in
            entered.fulfill()
            _ = resume.wait(timeout: .now() + 3)
        }
        defer { resume.signal() }
        let first = Task { await discovery.requestGain(0.5, application: identity) }
        await fulfillment(of: [entered], timeout: 3)
        let queued = await discovery.requestGain(0.2, application: identity)
        XCTAssertEqual(queued, .superseded)
        let disable = Task { await discovery.setGainEnabled(false) }
        let deadline = ContinuousClock.now + .seconds(3)
        while discovery.isGainEnabled, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertFalse(discovery.isGainEnabled)
        resume.signal()
        await disable.value
        let result = await first.value
        XCTAssertEqual(result, .superseded, "the old slider loop must stop instead of applying its queued value")
        let active = await engine.activeApplications
        XCTAssertTrue(active.isEmpty)
        XCTAssertNil(defaults.dictionary(forKey: ApplicationAudioDiscovery.levelsKey)?["com.spotify.client"], "stale completion must not persist a cancelled level")
        await discovery.disableRouting()
    }

    func testOffOnWhileAnOldSliderWriteIsSuspendedKeepsTheNewLevelOwner() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        let process = ApplicationAudioProcess(objectID: 11, pid: 4001, bundleIdentifier: "com.spotify.client", outputIORunning: true)
        let discovery = ApplicationAudioDiscovery(engine: engine, defaults: defaults, readProcesses: { [process] }, resolveOwners: { _ in [:] })
        await discovery.setGainEnabled(true)
        let identity = try XCTUnwrap(discovery.outputs.first).identity
        let entered = expectation(description: "old routing lifetime suspended")
        let resume = DispatchSemaphore(value: 0), blocked = LockedBox(false)
        hardware.onCreateTap = { _ in
            guard !blocked.value else { return }
            blocked.mutate { $0 = true }
            entered.fulfill()
            _ = resume.wait(timeout: .now() + 5)
        }
        defer { resume.signal() }
        let oldWrite = Task { await discovery.requestGain(0.5, application: identity) }
        await fulfillment(of: [entered], timeout: 3)
        let disable = Task { await discovery.setGainEnabled(false) }
        var deadline = ContinuousClock.now + .seconds(1)
        while discovery.isGainEnabled, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertFalse(discovery.isGainEnabled)
        let enable = Task { await discovery.setGainEnabled(true) }
        deadline = ContinuousClock.now + .seconds(1)
        while discovery.outputs.first?.identity == identity, ContinuousClock.now < deadline { await Task.yield() }
        let replacement = try XCTUnwrap(discovery.outputs.first).identity
        XCTAssertNotEqual(replacement, identity)
        let newWrite = Task { await discovery.requestGain(0.3, application: replacement) }
        deadline = ContinuousClock.now + .seconds(1)
        while discovery.outputs.first?.gain != 0.3, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(discovery.outputs.first?.gain, 0.3, "the new routing lifetime owns its own pending level")
        resume.signal()
        await disable.value
        await enable.value
        let oldResult = await oldWrite.value, newResult = await newWrite.value
        XCTAssertEqual(oldResult, .superseded)
        XCTAssertEqual(newResult, .verified(volume: 0.3, muted: false))
        XCTAssertTrue(discovery.isGainEnabled)
        XCTAssertEqual(discovery.outputs.first?.gain, 0.3)
        XCTAssertEqual(try level(of: hardware.lastRenderer), 0.09, accuracy: 1e-6)
        let active = await engine.activeApplications
        XCTAssertEqual(active, ["com.spotify.client"])
        await discovery.disableRouting()
    }

    func testRelaunchedAppGetsItsSavedLevelAndExitedAppIsReleased() async throws {
        let hardware = FakeGainHardware()
        let processes = LockedBox([ApplicationAudioProcess(objectID: 11, pid: 4001, bundleIdentifier: "com.spotify.client", outputIORunning: true)])
        let first = provider(hardware, processes: processes)
        await first.setGainEnabled(true)
        _ = await first.requestGain(0.5, application: try XCTUnwrap(first.outputs.first).identity)
        await first.disableRouting()
        XCTAssertEqual(hardware.calls.last, "destroyTap")

        // Spotify relaunched (new process object), paused for now.
        processes.mutate { $0 = [ApplicationAudioProcess(objectID: 21, pid: 4100, bundleIdentifier: "com.spotify.client", outputIORunning: false)] }
        let relaunched = provider(hardware, processes: processes)
        await relaunched.setGainEnabled(true)
        XCTAssertEqual(hardware.calls.filter { $0 == "tap [21]→speakers" }.count, 1, "the saved level is applied before it plays")
        XCTAssertEqual(relaunched.outputs.first?.gain, 0.5, "an attenuated paused app keeps its row")
        XCTAssertEqual(try level(of: hardware.lastRenderer), 0.25, accuracy: 1e-6)

        processes.mutate { $0 = [] }
        try await relaunched.refresh()
        XCTAssertEqual(hardware.calls.last, "destroyTap", "an exited app's session is released")
        await relaunched.disableRouting()
    }

    func testHelperProcessesAreOneRowTappedTogetherAndTheTapFollowsThem() async throws {
        let hardware = FakeGainHardware()
        let main = ApplicationAudioProcess(objectID: 31, pid: 5001, bundleIdentifier: "com.hnc.Discord", outputIORunning: false)
        let renderer = ApplicationAudioProcess(objectID: 32, pid: 5002, bundleIdentifier: "com.hnc.Discord.helper.Renderer", outputIORunning: true)
        let helper = ApplicationAudioProcess(objectID: 33, pid: 5003, bundleIdentifier: "com.hnc.Discord.helper", outputIORunning: false)
        let other = ApplicationAudioProcess(objectID: 40, pid: 5100, bundleIdentifier: "com.spotify.client", outputIORunning: true)
        let processes = LockedBox([main, renderer, helper, other])
        let discovery = provider(hardware, processes: processes, owners: Self.discordOwners)
        await discovery.setGainEnabled(true)

        XCTAssertEqual(discovery.outputs.map(\.name).sorted(), ["Discord", "com.spotify.client"], "one row per application, not per process")
        let discord = try XCTUnwrap(discovery.outputs.first { $0.bundleIdentifier == "com.hnc.Discord" })
        XCTAssertEqual(discord.identity.processObjectIDs, [31, 32, 33])
        XCTAssertEqual(discord.identity.pid, 5002, "the process that actually plays leads the group")

        let result = await discovery.requestGain(0.5, application: discord.identity)
        XCTAssertEqual(result, .verified(volume: 0.5, muted: false))
        XCTAssertEqual(hardware.calls.first, "tap [31, 32, 33]→speakers", "the idle main process and helpers are tapped with the playing renderer")
        XCTAssertEqual(try level(of: hardware.lastRenderer), 0.25, accuracy: 1e-6)
        XCTAssertEqual(defaults.dictionary(forKey: ApplicationAudioDiscovery.levelsKey)?["com.hnc.Discord"] as? Double, 0.5, "saved per application, not per helper")
        XCTAssertEqual(discovery.outputs.first { $0.bundleIdentifier == "com.spotify.client" }?.gain, 1)

        // A new helper process appears: the session is rebuilt to include it.
        processes.mutate { $0.append(ApplicationAudioProcess(objectID: 34, pid: 5004, bundleIdentifier: "com.hnc.Discord.helper", outputIORunning: true)) }
        try await discovery.refresh()
        XCTAssertEqual(hardware.calls.filter { $0.hasPrefix("tap") }, ["tap [31, 32, 33]→speakers", "tap [31, 32, 33, 34]→speakers"])
        XCTAssertEqual(try level(of: hardware.lastRenderer), 0.25, accuracy: 1e-6, "the saved level carries over")

        // A helper exits.
        processes.mutate { $0.removeAll { $0.objectID == 33 } }
        try await discovery.refresh()
        XCTAssertEqual(hardware.calls.filter { $0.hasPrefix("tap") }.last, "tap [31, 32, 34]→speakers")

        // Back to 100% releases the whole application.
        let current = try XCTUnwrap(discovery.outputs.first { $0.bundleIdentifier == "com.hnc.Discord" })
        _ = await discovery.requestGain(1, application: current.identity)
        XCTAssertEqual(hardware.calls.last, "destroyTap")
        XCTAssertNil(defaults.dictionary(forKey: ApplicationAudioDiscovery.levelsKey)?["com.hnc.Discord"])
        await discovery.disableRouting()
    }

    func testStandaloneProcessesSharingABundleIDStaySeparateRows() async throws {
        let hardware = FakeGainHardware()
        let processes = LockedBox([ApplicationAudioProcess(objectID: 51, pid: 6001, bundleIdentifier: "com.apple.WebKit.GPU", outputIORunning: true),
                                   ApplicationAudioProcess(objectID: 52, pid: 6002, bundleIdentifier: "com.apple.WebKit.GPU", outputIORunning: true),
                                   ApplicationAudioProcess(objectID: 53, pid: 6003, bundleIdentifier: nil, outputIORunning: true)])
        let discovery = provider(hardware, processes: processes)
        await discovery.setGainEnabled(true)
        XCTAssertEqual(discovery.outputs.count, 3, "two WebKit services of different client apps are never merged")
        await discovery.disableRouting()
    }

    func testDisabledOrUnsupportedRoutesNeverClaimControl() async throws {
        let hardware = FakeGainHardware()
        hardware.route = .init(uid: "airpods", hasInputStreams: true)
        let processes = LockedBox([ApplicationAudioProcess(objectID: 11, pid: 4001, bundleIdentifier: "com.spotify.client", outputIORunning: true)])
        let discovery = provider(hardware, processes: processes)
        try await discovery.refresh()
        XCTAssertNil(discovery.outputs.first?.gain)
        let off = await discovery.requestGain(0.3, application: try XCTUnwrap(discovery.outputs.first).identity)
        XCTAssertEqual(off, .unsupported)

        await discovery.setGainEnabled(true)
        let declined = await discovery.requestGain(0.3, application: try XCTUnwrap(discovery.outputs.first).identity)
        XCTAssertEqual(declined, .failed(.perApplicationRoutingUnavailable))
        XCTAssertNotNil(discovery.routingIssue)
        XCTAssertEqual(discovery.outputs.first?.gain, 1, "the row shows the truth: still at 100%")
        XCTAssertTrue(hardware.calls.isEmpty)
        await discovery.disableRouting()
    }

    /// Renders the real widget (and a pill gallery) to PNGs for visual inspection when
    /// `DYNAMIC_ISLAND_SNAPSHOT_DIR` is set; always asserts the pills draw something.
    func testPillWidgetRendersAtEverySizeWithSeveralRows() async throws {
        let hardware = FakeGainHardware()
        func owner(_ id: String, _ name: String, _ path: String) -> ApplicationAudioOwner {
            ApplicationAudioOwner(bundleIdentifier: id, name: name, url: URL(fileURLWithPath: path))
        }
        let owners: [UInt32: ApplicationAudioOwner] = [
            1: owner("com.spotify.client", "Spotify", "/Applications/Spotify.app"),
            2: owner("com.hnc.Discord", "Discord", "/Applications/Discord.app"),
            3: owner("com.brave.Browser", "Brave Browser", "/Applications/Brave Browser.app"),
            4: owner("com.apple.Safari", "Safari", "/Applications/Safari.app"),
            5: owner("x.long", "An Application With A Remarkably Long Name", "/Applications/Xcode.app")]
        let saved: [String: Double] = ["com.spotify.client": 0.7, "com.hnc.Discord": 0.3, "com.apple.Safari": 0.0, "x.long": 0.45]
        defaults.set(saved, forKey: ApplicationAudioDiscovery.levelsKey)
        var list: [ApplicationAudioProcess] = []
        for id in 1...5 {
            let process = ApplicationAudioProcess(objectID: UInt32(id), pid: Int32(7000 + id), bundleIdentifier: owners[UInt32(id)]?.bundleIdentifier, outputIORunning: id != 4)
            list.append(process)
        }
        let processes = LockedBox(list)
        let discovery = provider(hardware, processes: processes, owners: { _ in owners })
        await discovery.setGainEnabled(true)
        let settings = AppSettings(defaults: defaults)
        settings.perAppVolumeEnabled = true
        let directory = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        let canvases: [(WidgetPresentationSize, CGSize)] = [(.standard, CGSize(width: 332, height: 162)), (.large, CGSize(width: 332, height: 332)), (.compact, CGSize(width: 162, height: 162))]
        for (size, canvas) in canvases {
            let view = AppVolumeWidgetView(discovery: discovery, settings: settings, systemHUD: nil)
                .environment(\.workspaceWidgetPlacement, WorkspaceWidgetPlacementContext(isSole: true, size: canvas, fillsRow: true, presentationSize: size))
            let data = try await Self.png(view, size: canvas)
            XCTAssertGreaterThan(data.count, 2000)
            try directory.map { try data.write(to: $0.appendingPathComponent("app-volume-\(size.rawValue).png")) }
        }
        struct Row: Identifiable { let id: String; let level: Double; let style: AppVolumePill.Style; let enabled: Bool }
        // Footer states in the tightest size: a declined route (issue text) and the feature switched off.
        let declined = FakeGainHardware()
        declined.route = .init(uid: "airpods", hasInputStreams: true)
        let issueDiscovery = provider(declined, processes: processes, owners: { _ in owners })
        await issueDiscovery.setGainEnabled(true)
        _ = await issueDiscovery.requestGain(0.5, application: try XCTUnwrap(issueDiscovery.outputs.first { $0.bundleIdentifier == "com.spotify.client" }).identity)
        XCTAssertNotNil(issueDiscovery.routingIssue)
        let offSettings = AppSettings(defaults: UserDefaults(suiteName: "ApplicationVolumeProviderTests.off.\(UUID().uuidString)")!)
        let standardCanvas = CGSize(width: 332, height: 162)
        for (name, view) in [("issue", AnyView(AppVolumeWidgetView(discovery: issueDiscovery, settings: settings, systemHUD: nil))),
                             ("off", AnyView(AppVolumeWidgetView(discovery: ApplicationAudioDiscovery(engine: ApplicationGainEngine(hardware: FakeGainHardware()), defaults: defaults, readProcesses: { processes.value }, resolveOwners: { _ in owners }), settings: offSettings, systemHUD: nil)))] {
            let placed = view.environment(\.workspaceWidgetPlacement, WorkspaceWidgetPlacementContext(isSole: true, size: standardCanvas, fillsRow: true, presentationSize: .standard))
            let data = try await Self.png(placed, size: standardCanvas)
            try directory.map { try data.write(to: $0.appendingPathComponent("app-volume-standard-\(name).png")) }
        }
        await issueDiscovery.disableRouting()
        let galleryRows: [Row] = [Row(id: "Spotify", level: 0, style: .app, enabled: true), Row(id: "Discord", level: 0.3, style: .app, enabled: true),
            Row(id: "Brave Browser", level: 0.7, style: .app, enabled: true), Row(id: "Safari", level: 1, style: .app, enabled: true),
            Row(id: "An Application With A Remarkably Long Name", level: 0.45, style: .app, enabled: true),
            Row(id: "System", level: 0.6, style: .system, enabled: true), Row(id: "Disabled", level: 0.5, style: .app, enabled: false)]
        let gallery = VStack(spacing: 6) {
            ForEach(galleryRows) { row in
                AppVolumePill(name: row.id, icon: AnyView(Image(systemName: "app.fill").frame(width: 22, height: 22)), level: row.level,
                              enabled: row.enabled, style: row.style, height: 30, onChange: { _ in }, onMute: {})
            }
        }.padding(12).foregroundStyle(.white)
        let galleryData = try await Self.png(gallery, size: CGSize(width: 332, height: 300))
        try directory.map { try galleryData.write(to: $0.appendingPathComponent("app-volume-pill-gallery.png")) }
        await discovery.disableRouting()
    }

    func testPillPointerMappingSnapsToTheEnds() {
        XCTAssertEqual(AppVolumePill.level(atX: -20, width: 200), 0)
        XCTAssertEqual(AppVolumePill.level(atX: 2, width: 200), 0, "the first 1.5% is 0%")
        XCTAssertEqual(AppVolumePill.level(atX: 100, width: 200), 0.5)
        XCTAssertEqual(AppVolumePill.level(atX: 199, width: 200), 1)
        XCTAssertEqual(AppVolumePill.level(atX: 500, width: 200), 1)
    }

    private static func png<Content: View>(_ content: Content, size: CGSize) async throws -> Data {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).background(Color.black).environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<12 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(3))
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    func testWidgetMountReadsButNeverRoutes() async throws {
        let hardware = FakeGainHardware()
        let processes = LockedBox([ApplicationAudioProcess(objectID: 11, pid: 4001, bundleIdentifier: "com.spotify.client", outputIORunning: true)])
        let discovery = provider(hardware, processes: processes)
        let settings = AppSettings(defaults: defaults)
        for size in WidgetPresentationSize.allCases {
            let host = NSHostingView(rootView: AppVolumeWidgetView(discovery: discovery, settings: settings, systemHUD: nil)
                .environment(\.workspaceWidgetPlacement, WorkspaceWidgetPlacementContext(isSole: true, size: CGSize(width: 330, height: 330), fillsRow: true, presentationSize: size))
                .frame(width: 330, height: 330))
            host.layoutSubtreeIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(hardware.calls.isEmpty)
        XCTAssertFalse(settings.perAppVolumeEnabled)
    }
}

final class ApplicationAudioOwnershipTests: XCTestCase {
    private typealias Ownership = ApplicationAudioOwnership
    private let discord = Ownership.RunningApp(bundleIdentifier: "com.hnc.Discord", name: "Discord", url: URL(fileURLWithPath: "/Applications/Discord.app"), isRegular: true)
    private let safari = Ownership.RunningApp(bundleIdentifier: "com.apple.Safari", name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"), isRegular: true)
    private func process(_ bundle: String?, path: String? = nil) -> ApplicationAudioProcess {
        .init(objectID: 1, pid: 1, bundleIdentifier: bundle, outputIORunning: true, executablePath: path)
    }

    func testHelperExecutablePathsResolveToTheOutermostApp() {
        XCTAssertEqual(Ownership.outerApplicationURL(executablePath: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/Discord Helper (Renderer)")?.path,
                       "/Applications/Discord.app")
        XCTAssertEqual(Ownership.outerApplicationURL(executablePath: "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/Versions/155/Helpers/Brave Browser Helper.app/Contents/MacOS/Brave Browser Helper")?.path,
                       "/Applications/Brave Browser.app")
        XCTAssertNil(Ownership.outerApplicationURL(executablePath: "/usr/bin/afplay"))
        XCTAssertNil(Ownership.outerApplicationURL(executablePath: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"))
    }

    func testBundleIDPrefixAndWebKitServiceNamesFindTheOwner() {
        XCTAssertEqual(Ownership.parentApplication(ofHelper: "com.hnc.Discord.helper.Renderer", among: [safari, discord]), discord)
        XCTAssertNil(Ownership.parentApplication(ofHelper: "com.hnc.DiscordX", among: [discord]), "only whole dotted components match")
        XCTAssertEqual(Ownership.webKitOwnerName(fromServiceName: "Safari Graphics and Media"), "Safari")
        XCTAssertNil(Ownership.webKitOwnerName(fromServiceName: "Safari"))
    }

    func testOwnerPrecedence() {
        let info: (URL) -> (bundleIdentifier: String, name: String)? = { $0.lastPathComponent == "Discord.app" ? ("com.hnc.Discord", "Discord") : nil }
        let renderer = process("com.hnc.Discord.helper.Renderer", path: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/x")
        XCTAssertEqual(Ownership.owner(of: renderer, itself: nil, regularApps: [], bundleInfo: info)?.bundleIdentifier, "com.hnc.Discord")
        let byPrefix = process("com.hnc.Discord.helper", path: "/opt/x/helper")
        XCTAssertEqual(Ownership.owner(of: byPrefix, itself: nil, regularApps: [discord], bundleInfo: info)?.name, "Discord")
        let gpu = process("com.apple.WebKit.GPU", path: "/System/Library/Frameworks/WebKit.framework/x.xpc/Contents/MacOS/x")
        let service = Ownership.RunningApp(bundleIdentifier: "com.apple.WebKit.GPU", name: "Safari Graphics and Media", url: nil, isRegular: false)
        XCTAssertEqual(Ownership.owner(of: gpu, itself: service, regularApps: [safari, discord], bundleInfo: info)?.bundleIdentifier, "com.apple.Safari")
        XCTAssertNil(Ownership.owner(of: gpu, itself: service, regularApps: [discord], bundleInfo: info), "an unknown owner leaves the service its own row")
        XCTAssertEqual(Ownership.owner(of: process("com.hnc.Discord"), itself: discord, regularApps: [], bundleInfo: info)?.bundleIdentifier, "com.hnc.Discord")
        XCTAssertNil(Ownership.owner(of: process(nil, path: "/usr/bin/afplay"), itself: nil, regularApps: [discord], bundleInfo: info))
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}

private func XCTAssertThrowsAsync(_ expression: @autoclosure () async throws -> Void,
                                  file: StaticString = #filePath, line: UInt = #line,
                                  _ handler: (Error) -> Void = { _ in }) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        handler(error)
    }
}
