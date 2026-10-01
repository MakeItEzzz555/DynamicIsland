import AVFoundation
import Foundation
import XCTest
@testable import DynamicIsland

/// Opt-in real microphone acceptance (DYNAMIC_ISLAND_LIVE_VOICE_RECORDING=1).
/// Uses the production recorder; never substitutes generated audio and never
/// prompts (an undetermined microphone permission is reported as blocked).
@MainActor
final class VoiceRecordingLiveTests: XCTestCase {
    func testRealMicrophoneRecordsTwiceAndFilesValidate() async throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_VOICE_RECORDING"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_VOICE_RECORDING=1 to use the real microphone.")
        }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("LIVE-VOICE microphone=\(status.rawValue) device=\(AVCaptureDevice.default(for: .audio)?.localizedName ?? "none")")
        guard status == .authorized else {
            throw XCTSkip("IMPLEMENTED BUT REAL VALIDATION BLOCKED: microphone authorization is \(status.rawValue) for this process.")
        }
        let recorder = AVFoundationVoiceRecorder()
        XCTAssertTrue(recorder.hasInputDevice)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceLive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 1...2 {
            let url = directory.appendingPathComponent("take-\(index).m4a")
            try recorder.startRecording(to: url)
            try await Task.sleep(for: .seconds(3))
            recorder.stopRecording()

            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            let duration = try await asset.load(.duration).seconds
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: try XCTUnwrap(tracks.first), outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(output)
            reader.startReading()
            var samples = 0
            while let buffer = output.copyNextSampleBuffer() { samples += CMSampleBufferGetNumSamples(buffer) }
            print("LIVE-VOICE take \(index): bytes=\(size) tracks=\(tracks.count) duration=\(String(format: "%.2f", duration))s samples=\(samples)")
            XCTAssertGreaterThan(size, 1_000)
            XCTAssertEqual(tracks.count, 1)
            XCTAssertGreaterThan(duration, 2.5)
            XCTAssertGreaterThan(samples, 16_000 * 2)
        }
    }
}
