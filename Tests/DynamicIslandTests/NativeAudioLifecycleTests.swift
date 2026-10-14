import CoreAudio
import XCTest
@testable import DynamicIsland

@MainActor
final class NativeAudioLifecycleTests: XCTestCase {
    func testNativeDescriptionIsPrivateAndNeverMutesOrdinaryPlayback() throws {
        guard #available(macOS 14.2, *) else { throw XCTSkip("public taps require macOS 14.2") }
        let description = CoreAudioTapHardware.makeTapDescription()
        XCTAssertTrue(description.isPrivate)
        XCTAssertEqual(description.muteBehavior, .unmuted)
        XCTAssertTrue(description.isExclusive)
        XCTAssertFalse(description.isMono)
    }

    func testIdempotentStartStopAndStaleStopCannotKillNewSession() async throws {
        let hardware = TestAudioTapHardware()
        let backend = CoreAudioSpectrumBackend(hardware: hardware)
        let first = try await backend.start(generation: 1)
        let repeated = try await backend.start(generation: 1)
        XCTAssertTrue(first === repeated)
        XCTAssertEqual(hardware.count("tap"), 1)
        try await backend.stop(generation: 1)
        try await backend.stop(generation: 1)
        XCTAssertEqual(hardware.count("destroyTap"), 1)
        _ = try await backend.start(generation: 2)
        try await backend.stop(generation: 1)
        XCTAssertEqual(hardware.count("destroyTap"), 1)
        try await backend.stop(generation: 2)
        XCTAssertEqual(hardware.count("destroyTap"), 2)
        XCTAssertEqual(hardware.count("stop"), 2)
    }

    func testEveryFailedStartReleasesOnlyCreatedResourcesAndNeverMutesOutput() async {
        for failure in ["tap", "format", "aggregate", "io", "observe", "start"] {
            let hardware = TestAudioTapHardware(failure: failure)
            let backend = CoreAudioSpectrumBackend(hardware: hardware)
            do { _ = try await backend.start(generation: 1); XCTFail("expected failure") } catch {}
            try? await backend.stop(generation: 1)
            let events = hardware.events
            XCTAssertEqual(hardware.count("destroyTap"), failure == "tap" ? 0 : 1)
            XCTAssertEqual(hardware.count("destroyAggregate"), ["tap", "format", "aggregate"].contains(failure) ? 0 : 1)
            XCTAssertEqual(hardware.count("destroyIO"), ["observe", "start"].contains(failure) ? 1 : 0)
            if let io = events.firstIndex(of: "destroyIO"), let device = events.firstIndex(of: "destroyAggregate") { XCTAssertLessThan(io, device) }
            if let device = events.firstIndex(of: "destroyAggregate"), let tap = events.firstIndex(of: "destroyTap") { XCTAssertLessThan(device, tap) }
            XCTAssertFalse(events.contains("mute"))
        }
    }

    func testFailedTeardownRetainsResourceForRetryWithoutDuplicateDestruction() async throws {
        let hardware = TestAudioTapHardware()
        let backend = CoreAudioSpectrumBackend(hardware: hardware)
        _ = try await backend.start(generation: 1)
        hardware.failNextDestroy = true
        do { try await backend.stop(generation: 1); XCTFail("teardown must report error") } catch {}
        XCTAssertEqual(hardware.count("destroyAggregate"), 0)
        try await backend.stop(generation: 1)
        XCTAssertEqual(hardware.count("destroyIO"), 2)
        XCTAssertEqual(hardware.count("stop"), 1)
        XCTAssertEqual(hardware.count("destroyAggregate"), 1)
        XCTAssertEqual(hardware.count("destroyTap"), 1)
    }

    func testUnsupportedFormatDestroysTapBeforeCreatingDevice() async {
        let hardware = TestAudioTapHardware()
        hardware.formatValue.mBitsPerChannel = 16
        let backend = CoreAudioSpectrumBackend(hardware: hardware)
        do { _ = try await backend.start(generation: 1); XCTFail("format rejected") }
        catch { XCTAssertEqual(error as? NativeAudioError, .unsupportedFormat) }
        XCTAssertEqual(hardware.count("aggregate"), 0)
        XCTAssertEqual(hardware.count("destroyTap"), 1)
    }
}

final class TestAudioTapHardware: AudioTapHardware, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var failure: String?
    var failNextDestroy = false
    var formatValue = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
        mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    init(failure: String? = nil) { self.failure = failure }
    var events: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    func count(_ value: String) -> Int { events.filter { $0 == value }.count }
    private func log(_ value: String) { lock.lock(); recorded.append(value); lock.unlock() }
    private func step(_ value: String) throws {
        log(value)
        if failure == value { throw value == "tap" ? NativeAudioError.permissionDenied : .operationFailed(.startDevice, -1) }
    }
    func createTap() throws -> AudioObjectID { try step("tap"); return 11 }
    func format(tap: AudioObjectID) throws -> AudioStreamBasicDescription { try step("format"); return formatValue }
    func createAggregate(tap: AudioObjectID) throws -> AudioObjectID { try step("aggregate"); return 12 }
    func createIOProc(device: AudioObjectID, processor: RealtimeSpectrumProcessor) throws -> AudioDeviceIOProcID {
        try step("io"); return { _, _, _, _, _, _, _ in noErr }
    }
    func observeChanges(tap: AudioObjectID, mailbox: AudioSpectrumMailbox) throws { try step("observe") }
    func removeObservers() { log("unobserve") }
    func start(device: AudioObjectID, io: AudioDeviceIOProcID) throws { try step("start") }
    func stop(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { log("stop"); return noErr }
    func destroyIOProc(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus {
        log("destroyIO"); if failNextDestroy { failNextDestroy = false; return -1 }; return noErr
    }
    func destroyAggregate(_ id: AudioObjectID) -> OSStatus { log("destroyAggregate"); return noErr }
    func destroyTap(_ id: AudioObjectID) -> OSStatus { log("destroyTap"); return noErr }
}
