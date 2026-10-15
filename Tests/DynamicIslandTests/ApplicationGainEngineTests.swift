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
    private var nextID: AudioObjectID = 100

    var calls: [String] { lock.withLock { _calls } }
    func renderer(forDevice device: AudioObjectID) -> ApplicationGainRenderer? { lock.withLock { _renderers[device] } }
    var lastRenderer: ApplicationGainRenderer? { lock.withLock { _renderers.max { $0.key < $1.key }?.value } }
    private func log(_ call: String) { lock.withLock { _calls.append(call) } }
    private func id() -> AudioObjectID { lock.withLock { nextID += 1; return nextID } }

    func defaultOutputRoute() throws -> ApplicationGainRoute { route }
    func createTap(process: AudioObjectID) throws -> AudioObjectID {
        if let tapError { throw tapError }
        let tap = id(); log("tap \(process)→\(route.uid)"); return tap
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
        try await engine.setGain(1, process: 7)
        XCTAssertTrue(hardware.calls.isEmpty, "unity never taps an app")

        try await engine.setGain(0.3, process: 7)
        XCTAssertEqual(hardware.calls, ["tap 7→speakers", "aggregate", "ioproc", "start"])
        try await engine.setGain(0.5, process: 7)
        XCTAssertEqual(hardware.calls.count, 4, "a level change reuses the session")
        let activeAfterChange = await engine.activeProcesses
        XCTAssertEqual(activeAfterChange, [7])

        try await engine.setGain(1, process: 7)
        XCTAssertEqual(Array(hardware.calls.suffix(4)), ["stop", "destroyIOProc", "destroyAggregate", "destroyTap"])
        let active = await engine.activeProcesses
        XCTAssertTrue(active.isEmpty)
    }

    func testAppsAreIndependent() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, process: 1)
        try await engine.setGain(0, process: 2)
        try await engine.setGain(1, process: 1)
        let active = await engine.activeProcesses
        XCTAssertEqual(active, [2], "releasing one app leaves the other routed")
    }

    func testRoutesWithAMicrophoneAreDeclinedBeforeAnyTap() async {
        let hardware = FakeGainHardware()
        hardware.route = .init(uid: "airpods", hasInputStreams: true)
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        await XCTAssertThrowsAsync(try await engine.setGain(0.3, process: 7)) {
            XCTAssertEqual($0 as? ApplicationGainError, .routeHasInput)
        }
        XCTAssertTrue(hardware.calls.isEmpty)
    }

    func testFailuresTearDownEverythingTheyCreated() async {
        let hardware = FakeGainHardware()
        hardware.startError = NativeAudioError.operationFailed(.startDevice, -1)
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        await XCTAssertThrowsAsync(try await engine.setGain(0.3, process: 7))
        XCTAssertEqual(hardware.calls, ["tap 7→speakers", "aggregate", "ioproc", "destroyIOProc", "destroyAggregate", "destroyTap"])

        let unsupported = FakeGainHardware()
        unsupported.format.mChannelsPerFrame = 6
        let other = ApplicationGainEngine(hardware: unsupported, watchdogInterval: .seconds(60))
        await XCTAssertThrowsAsync(try await other.setGain(0.3, process: 7)) {
            XCTAssertEqual($0 as? ApplicationGainError, .unsupportedFormat)
        }
        XCTAssertEqual(unsupported.calls, ["tap 7→speakers", "destroyTap"])

        let denied = FakeGainHardware()
        denied.tapError = NativeAudioError.permissionDenied
        let third = ApplicationGainEngine(hardware: denied, watchdogInterval: .seconds(60))
        await XCTAssertThrowsAsync(try await third.setGain(0.3, process: 7)) {
            XCTAssertEqual($0 as? NativeAudioError, .permissionDenied)
        }
        let active = await third.activeProcesses
        XCTAssertTrue(active.isEmpty)
    }

    func testFailedTapDestroyIsRetainedAndRetriedByReleaseAll() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, process: 7)
        hardware.destroyTapStatus = -50
        await XCTAssertThrowsAsync(try await engine.setGain(1, process: 7))
        await XCTAssertThrowsAsync(try await engine.releaseAll())
        hardware.destroyTapStatus = noErr
        try await engine.releaseAll()
        XCTAssertEqual(hardware.calls.filter { $0 == "destroyTap" }.count, 3)
        XCTAssertEqual(hardware.calls.filter { $0 == "destroyAggregate" }.count, 1, "objects already gone are not destroyed twice")
    }

    func testStalledRenderingReturnsTheAppToDirectOutput() async throws {
        let hardware = FakeGainHardware()
        let stalled = LockedBox<[AudioObjectID]>([])
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60)) { process in stalled.mutate { $0.append(process) } }
        try await engine.setGain(0.3, process: 7)
        let renderer = try XCTUnwrap(hardware.lastRenderer)
        let input = Buffers(frames: 8, channelsPerBuffer: [2]), output = Buffers(frames: 8, channelsPerBuffer: [2])
        renderer.render(input: input.list.unsafePointer, output: output.list.unsafeMutablePointer)
        await engine.checkStalls()
        let stillActive = await engine.activeProcesses
        XCTAssertEqual(stillActive, [7], "an advancing IOProc is healthy")
        await engine.checkStalls()
        let active = await engine.activeProcesses
        XCTAssertTrue(active.isEmpty, "no render cycles since the last check releases the app")
        XCTAssertEqual(stalled.value, [7])
        XCTAssertEqual(hardware.calls.last, "destroyTap")
    }

    func testASlowStartingOutputGetsAGracePeriodBeforeItCountsAsStalled() async throws {
        let hardware = FakeGainHardware()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        try await engine.setGain(0.3, process: 7)
        for _ in 0..<3 { await engine.checkStalls() }
        let waiting = await engine.activeProcesses
        XCTAssertEqual(waiting, [7], "no render yet: still within the start grace")
        await engine.checkStalls()
        let released = await engine.activeProcesses
        XCTAssertTrue(released.isEmpty, "IO that never starts is released")
    }
}

@MainActor
final class ApplicationVolumeProviderTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "ApplicationVolumeProviderTests.\(UUID().uuidString)")
    }

    private func provider(_ hardware: FakeGainHardware, processes: LockedBox<[ApplicationAudioProcess]>) -> ApplicationAudioDiscovery {
        ApplicationAudioDiscovery(engine: ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60)),
                                  defaults: defaults, readProcesses: { processes.value })
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
        XCTAssertEqual(hardware.calls.first, "tap 11→speakers", "only Spotify is tapped")
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
        XCTAssertEqual(hardware.calls.filter { $0 == "tap 21→speakers" }.count, 1, "the saved level is applied before it plays")
        XCTAssertEqual(relaunched.outputs.first?.gain, 0.5, "an attenuated paused app keeps its row")
        XCTAssertEqual(try level(of: hardware.lastRenderer), 0.25, accuracy: 1e-6)

        processes.mutate { $0 = [] }
        try await relaunched.refresh()
        XCTAssertEqual(hardware.calls.last, "destroyTap", "an exited app's session is released")
        await relaunched.disableRouting()
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
