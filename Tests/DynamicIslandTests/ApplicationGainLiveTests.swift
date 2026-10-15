import AVFoundation
import CoreAudio
import XCTest
@testable import DynamicIsland

/// Real-hardware acceptance, skipped unless explicitly authorized with
/// `DYNAMIC_ISLAND_LIVE_APP_VOLUME=1`. It plays a quiet 440 Hz tone with
/// `afplay`, routes only that process through the real Core Audio engine on
/// the current output, and releases it. macOS may ask the test runner for
/// System Audio Recording. Listening checks stay in the manual checklist.
@MainActor
final class ApplicationGainLiveTests: XCTestCase {
    func testRealTapRoutesOnlyTheTonePlayerAndReleasesIt() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_APP_VOLUME"] == "1",
                          "Live per-app volume needs explicit authorization")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("app-volume-live-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tone = directory.appendingPathComponent("tone.caf")
        try Self.writeTone(to: tone, seconds: 8)

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = ["-v", "0.2", tone.path]
        try player.run()
        defer { if player.isRunning { player.terminate() } }

        var process: ApplicationAudioProcess?
        let deadline = ContinuousClock.now + .seconds(3)
        while process == nil, ContinuousClock.now < deadline {
            process = try ApplicationAudioDiscovery.readHALProcesses()
                .first { $0.pid == player.processIdentifier && $0.outputIORunning }
            if process == nil { try await Task.sleep(for: .milliseconds(50)) }
        }
        let target = try XCTUnwrap(process, "afplay never reported running output")

        let hardware = CoreAudioApplicationGainHardware()
        let route = try hardware.defaultOutputRoute()
        try XCTSkipIf(route.hasInputStreams, "The current output also has a microphone; v1 declines it by design")
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))

        try await engine.setGain(0.09, process: target.objectID) // slider 30%
        let routed = await engine.activeProcesses
        XCTAssertEqual(routed, [target.objectID])
        try await Task.sleep(for: .milliseconds(800))
        await engine.checkStalls()
        let afterFirstCheck = await engine.activeProcesses
        try await Task.sleep(for: .milliseconds(800))
        await engine.checkStalls()
        let afterSecondCheck = await engine.activeProcesses
        XCTAssertEqual(afterSecondCheck, afterFirstCheck, "the real IOProc keeps rendering, so the watchdog keeps the session")
        XCTAssertEqual(afterSecondCheck, [target.objectID])

        try await engine.setGain(0, process: target.objectID)
        try await Task.sleep(for: .milliseconds(600))
        try await engine.setGain(1, process: target.objectID)
        let released = await engine.activeProcesses
        XCTAssertTrue(released.isEmpty, "100% releases the tap; afplay plays directly again")
        try await engine.releaseAll()
    }

    private static func writeTone(to url: URL, seconds: Double) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(48_000 * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            let samples = try XCTUnwrap(buffer.floatChannelData)[channel]
            for index in 0..<Int(frames) { samples[index] = Float(sin(2 * .pi * 440 * Double(index) / 48_000) * 0.2) }
        }
        try file.write(from: buffer)
    }
}
