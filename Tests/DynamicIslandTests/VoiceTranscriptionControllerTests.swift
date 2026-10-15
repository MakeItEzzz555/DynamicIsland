import AVFoundation
import Combine
import Foundation
import Speech
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
private final class FakeVoicePermissions: VoicePermissionProviding {
    var microphoneState: VoicePermissionState = .notDetermined
    var speechState: VoicePermissionState = .notDetermined
    var microphoneGrant: VoicePermissionState = .authorized
    var speechGrant: VoicePermissionState = .authorized
    var microphoneRequests = 0
    var speechRequests = 0
    var onRequest: (() -> Void)?

    func requestMicrophone() async -> VoicePermissionState {
        onRequest?()
        microphoneRequests += 1
        microphoneState = microphoneGrant
        return microphoneState
    }

    func requestSpeech() async -> VoicePermissionState {
        onRequest?()
        speechRequests += 1
        speechState = speechGrant
        return speechState
    }
}

/// Writes real AAC audio (no microphone), like AVAudioRecorder would.
@MainActor
private final class FakeVoiceRecorder: VoiceAudioRecording {
    var hasInputDevice = true
    var normalizedLevel = 0.0
    var startError: Error?
    var writesReadableAudio = true
    var isRecording = false
    var startedURLs: [URL] = []
    var stopCount = 0
    var cancelCount = 0
    private var current: URL?

    func startRecording(to url: URL) throws {
        if let startError { throw startError }
        if writesReadableAudio {
            try writeTestAudio(to: url)
        } else {
            try Data("not audio".utf8).write(to: url)
        }
        startedURLs.append(url)
        current = url
        isRecording = true
    }

    func stopRecording() {
        stopCount += 1
        isRecording = false
        current = nil
    }

    func cancelRecording() {
        cancelCount += 1
        if let current { try? FileManager.default.removeItem(at: current) }
        current = nil
        isRecording = false
    }
}

@MainActor
private final class FakePlayer: VoiceAudioPlaying {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var onFinish: (() -> Void)?
    var playResult = true
    func play() -> Bool { isPlaying = playResult; return playResult }
    func pause() { isPlaying = false }
    func finish() { isPlaying = false; onFinish?() }
}

@MainActor
private final class PlayerSink {
    var players: [FakePlayer] = []
    var playResult = true
}

@MainActor
private final class FakeTranscriber: VoiceSpeechTranscribing {
    var availability = VoiceRecognizerAvailability(
        isAvailable: true,
        supportsOnDeviceRecognition: true,
        localeIdentifier: "en_US"
    )
    var result: Result<String, Error> = .success("hello world")
    var requestedOnDevice: [Bool] = []
    var transcribedURLs: [URL] = []
    var cancelCount = 0
    var suspend = false
    var observedActivitiesDuringWork: [[DynamicIslandLiveActivityKind]] = []
    weak var activities: LiveActivityStore?
    private var suspended: CheckedContinuation<String, Error>?

    func transcribe(fileURL: URL, requiresOnDevice: Bool) async throws -> String {
        requestedOnDevice.append(requiresOnDevice)
        transcribedURLs.append(fileURL)
        observedActivitiesDuringWork.append(activities?.activities.map(\.kind) ?? [])
        if suspend {
            return try await withCheckedThrowingContinuation { suspended = $0 }
        }
        return try result.get()
    }

    /// A recognizer that ignores cancel and still delivers a result.
    func deliverLate(_ text: String) {
        suspended?.resume(returning: text)
        suspended = nil
    }

    var ignoresCancel = false

    func cancel() {
        cancelCount += 1
        guard !ignoresCancel else { return }
        suspended?.resume(throwing: CancellationError())
        suspended = nil
    }
}

private func writeTestAudio(to url: URL, seconds: Double = 0.3) throws {
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1
    ], commonFormat: .pcmFormatFloat32, interleaved: false)
    let frames = AVAudioFrameCount(16_000 * seconds)
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
    buffer.frameLength = frames
    let samples = try XCTUnwrap(buffer.floatChannelData)[0]
    for index in 0..<Int(frames) { samples[index] = Float(sin(Double(index) * 0.06) * 0.25) }
    try file.write(from: buffer)
}

@MainActor
final class VoiceTranscriptionControllerTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceTranscriptionControllerTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var recordingsDirectory: URL { directory.appendingPathComponent("Recordings", isDirectory: true) }
    private var workingDirectory: URL { recordingsDirectory.appendingPathComponent(".incomplete", isDirectory: true) }

    private func files(in url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                      options: .skipsHiddenFiles)) ?? []
    }

    // MARK: Authorization

    func testCapabilityNeedsOnlyMicrophone() {
        XCTAssertEqual(VoiceTranscriptionController.capabilityMapping(microphone: .authorized).permission, .granted)
        XCTAssertEqual(VoiceTranscriptionController.capabilityMapping(microphone: .authorized).availability, .available)
        XCTAssertEqual(VoiceTranscriptionController.capabilityMapping(microphone: .notDetermined).permission, .notDetermined)
        XCTAssertEqual(VoiceTranscriptionController.capabilityMapping(microphone: .denied).permission, .denied)
        guard case .unsupported = VoiceTranscriptionController.capabilityMapping(microphone: .restricted).availability else {
            return XCTFail("Restricted microphone is unsupported")
        }
    }

    func testSystemAuthorizationMapping() {
        XCTAssertEqual(SystemVoicePermissionProvider.map(.authorized as AVAuthorizationStatus), .authorized)
        XCTAssertEqual(SystemVoicePermissionProvider.map(.denied as AVAuthorizationStatus), .denied)
        XCTAssertEqual(SystemVoicePermissionProvider.map(.restricted as AVAuthorizationStatus), .restricted)
        XCTAssertEqual(SystemVoicePermissionProvider.map(.notDetermined as AVAuthorizationStatus), .notDetermined)
        XCTAssertEqual(SystemVoicePermissionProvider.map(.authorized as SFSpeechRecognizerAuthorizationStatus), .authorized)
        XCTAssertEqual(SystemVoicePermissionProvider.map(.denied as SFSpeechRecognizerAuthorizationStatus), .denied)
        XCTAssertEqual(SystemVoicePermissionProvider.map(.restricted as SFSpeechRecognizerAuthorizationStatus), .restricted)
        XCTAssertEqual(SystemVoicePermissionProvider.map(.notDetermined as SFSpeechRecognizerAuthorizationStatus), .notDetermined)
    }

    func testConstructionRefreshAndRestoreNeverPrompt() async {
        let fixture = makeFixture()
        await fixture.controller.refresh()
        fixture.controller.restoreRecordings()
        XCTAssertEqual(fixture.permissions.microphoneRequests, 0)
        XCTAssertEqual(fixture.permissions.speechRequests, 0)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertEqual(fixture.controller.phase, .idle)
    }

    func testSettingsRequestAsksOnlyForMicrophone() async {
        let fixture = makeFixture()
        await fixture.controller.requestMicrophoneAccess()
        XCTAssertEqual(fixture.permissions.microphoneRequests, 1)
        XCTAssertEqual(fixture.permissions.speechRequests, 0)
        XCTAssertEqual(fixture.registry.snapshot(for: .voiceTranscribe)?.permission, .granted)
    }

    func testRecordingWithoutSpeechPermissionOrRecognizer() async throws {
        let fixture = makeFixture()
        fixture.permissions.speechState = .denied
        fixture.transcriber.availability = .init(isAvailable: false, supportsOnDeviceRecognition: false, localeIdentifier: "xx")
        await fixture.controller.refresh()

        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()

        XCTAssertEqual(fixture.permissions.microphoneRequests, 1)
        XCTAssertEqual(fixture.permissions.speechRequests, 0, "Recording never asks for Speech Recognition")
        XCTAssertNotNil(fixture.controller.recentRecording)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertEqual(fixture.registry.snapshot(for: .voiceTranscribe)?.availability, .available)
        XCTAssertEqual(fixture.registry.snapshot(for: .voiceTranscribe)?.permission, .granted)
    }

    func testDeniedMicrophoneFailsClosedWithoutRecording() async {
        let fixture = makeFixture()
        fixture.permissions.microphoneState = .denied

        await XCTAssertThrowsVoiceError(.microphonePermissionRequired) {
            try await fixture.controller.startRecording()
        }
        XCTAssertTrue(fixture.recorder.startedURLs.isEmpty)
        XCTAssertEqual(fixture.activities.activities.map(\.kind), [.voiceStatus], "Only static recovery remains")
        XCTAssertEqual(fixture.registry.snapshot(for: .voiceTranscribe)?.permission, .denied)
    }

    // MARK: Recording ownership

    func testStopReleasesMicrophoneAndRetainsValidAudio() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        let capture = try XCTUnwrap(fixture.recorder.startedURLs.first)
        XCTAssertTrue(capture.path.hasPrefix(workingDirectory.path), "Captures stay out of the recordings list until valid")
        XCTAssertEqual(fixture.activities.activities.map(\.kind), [.voiceRecording])

        try fixture.controller.stopRecording()

        let recording = try XCTUnwrap(fixture.controller.recentRecording)
        XCTAssertEqual(fixture.recorder.stopCount, 1)
        XCTAssertFalse(fixture.recorder.isRecording)
        XCTAssertEqual(fixture.controller.liveAudioLevel, 0)
        XCTAssertTrue(fixture.activities.activities.isEmpty, "Stop clears the live activity immediately")
        XCTAssertFalse(fixture.registry.snapshot(for: .voiceTranscribe)?.isActive ?? true)
        XCTAssertEqual(recording.url.deletingLastPathComponent().standardizedFileURL, recordingsDirectory.standardizedFileURL)
        XCTAssertEqual(recording.url.pathExtension, "m4a")
        XCTAssertTrue(recording.url.lastPathComponent.hasPrefix("Voice Recording "))
        XCTAssertEqual(recording.duration, 0.3, accuracy: 0.1)
        XCTAssertEqual(try AVAudioFile(forReading: recording.url).fileFormat.channelCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.path), "Moved, not copied")
        XCTAssertTrue(files(in: workingDirectory).isEmpty)
        XCTAssertNil(fixture.controller.transcript, "Stop never transcribes")
        XCTAssertTrue(fixture.transcriber.transcribedURLs.isEmpty)
    }

    func testUnreadableCaptureIsLeftForRecoveryAndOnlyThenRemoved() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.recorder.writesReadableAudio = false
        try await fixture.controller.startRecording()
        let capture = try XCTUnwrap(fixture.recorder.startedURLs.first)

        XCTAssertThrowsError(try fixture.controller.stopRecording())
        XCTAssertFalse(fixture.recorder.isRecording)
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.path), "Stop never deletes a capture")
        XCTAssertNil(fixture.controller.recentRecording)

        fixture.controller.restoreRecordings()
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.path), "Launch recovery drops unreadable fragments")
        XCTAssertTrue(files(in: recordingsDirectory).isEmpty)
    }

    func testRelaunchRestoresNewestRecordingAndRecoversInterruptedCapture() async throws {
        let first = makeFixture(authorized: true)
        try await first.controller.startRecording()
        try first.controller.stopRecording()
        let kept = try XCTUnwrap(first.controller.recentRecording)
        // A crash left a readable capture behind in the working folder.
        let leftover = workingDirectory.appendingPathComponent("recording-\(UUID().uuidString).m4a")
        try writeTestAudio(to: leftover, seconds: 0.5)
        let unrelated = workingDirectory.appendingPathComponent("unrelated.txt")
        try Data("other".utf8).write(to: unrelated)

        let relaunched = makeFixture(authorized: true)
        XCTAssertNil(relaunched.controller.recentRecording, "Nothing is read until launch restore")
        relaunched.controller.restoreRecordings()

        let restored = try XCTUnwrap(relaunched.controller.recentRecording)
        XCTAssertNotEqual(restored.url, kept.url, "The recovered capture is the newest recording")
        XCTAssertEqual(restored.duration, 0.5, accuracy: 0.1)
        XCTAssertEqual(relaunched.controller.phase, .ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.url.path))
        XCTAssertEqual(files(in: recordingsDirectory).count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path), "Only abandoned captures are cleaned up")
    }

    func testRecoveryNeverDeletesReadableAudioWhenTheMoveFails() throws {
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let leftover = workingDirectory.appendingPathComponent("recording-\(UUID().uuidString).m4a")
        try writeTestAudio(to: leftover)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: recordingsDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: recordingsDirectory.path) }

        let fixture = makeFixture(authorized: true)
        fixture.controller.restoreRecordings()

        XCTAssertTrue(FileManager.default.fileExists(atPath: leftover.path), "Kept for the next launch")
        XCTAssertNil(fixture.controller.recentRecording)
    }

    func testRecordingsWithTheSameTimestampNeverOverwrite() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        let first = try XCTUnwrap(fixture.controller.recentRecording)
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        let second = try XCTUnwrap(fixture.controller.recentRecording)

        XCTAssertNotEqual(first.url, second.url)
        XCTAssertTrue(second.url.deletingPathExtension().lastPathComponent.hasSuffix(" 2"))
        XCTAssertEqual(files(in: recordingsDirectory).count, 2)
    }

    func testCancelDiscardsOnlyTheUnfinishedCapture() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        let finished = try XCTUnwrap(fixture.controller.recentRecording)

        try await fixture.controller.startRecording()
        let unfinished = try XCTUnwrap(fixture.recorder.startedURLs.last)
        fixture.controller.cancel()
        fixture.controller.cancel()

        XCTAssertFalse(fixture.recorder.isRecording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unfinished.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: finished.url.path))
        XCTAssertEqual(fixture.controller.recentRecording, finished)
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testTerminateAndDisableFinishAndKeepARunningCapture() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        let capture = try XCTUnwrap(fixture.recorder.startedURLs.last)
        fixture.controller.terminate()
        XCTAssertFalse(fixture.recorder.isRecording)
        XCTAssertEqual(fixture.recorder.stopCount, 1, "Quit finishes the capture instead of discarding it")
        XCTAssertNotNil(fixture.controller.recentRecording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.path))
        XCTAssertTrue(fixture.activities.activities.isEmpty)

        try await fixture.controller.startRecording()
        fixture.controller.setEnabled(false)
        XCTAssertFalse(fixture.recorder.isRecording)
        XCTAssertEqual(files(in: recordingsDirectory).count, 2)
        XCTAssertEqual(fixture.controller.phase, .ready)
        await XCTAssertThrowsVoiceError(.disabled) {
            try await fixture.controller.startRecording()
        }
    }

    func testDeleteRemovesOnlyTheShownRecording() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        let older = try XCTUnwrap(fixture.controller.recentRecording)
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        let newer = try XCTUnwrap(fixture.controller.recentRecording)
        let exported = directory.appendingPathComponent("export.m4a")
        try fixture.controller.exportRecording(to: exported)

        try fixture.controller.deleteRecording()
        XCTAssertFalse(FileManager.default.fileExists(atPath: newer.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path), "Saved copies are not deleted")
        XCTAssertEqual(fixture.controller.recentRecording?.url.lastPathComponent, older.url.lastPathComponent)

        try fixture.controller.deleteRecording()
        XCTAssertNil(fixture.controller.recentRecording)
        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertThrowsError(try fixture.controller.deleteRecording())
    }

    // MARK: Export

    func testSaveAsAndFileTrayCopyAndPreserveSource() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        let recording = try XCTUnwrap(fixture.controller.recentRecording)
        let source = try Data(contentsOf: recording.url)

        let destination = directory.appendingPathComponent("Saved.m4a")
        try Data("old".utf8).write(to: destination)
        try fixture.controller.exportRecording(to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), source, "Confirmed replacement writes the recording")
        XCTAssertEqual(fixture.controller.recentRecording?.savedURL, destination)

        let shelfURL = try fixture.controller.addRecordingToShelf()
        XCTAssertEqual(fixture.shelf.urls, [shelfURL])
        XCTAssertTrue(fixture.shelfStorage.isOwned(shelfURL))
        XCTAssertEqual(try Data(contentsOf: shelfURL), source)
        XCTAssertEqual(try Data(contentsOf: recording.url), source, "Source is preserved")
    }

    func testFailedExportPreservesSourceAndSavedState() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        let recording = try XCTUnwrap(fixture.controller.recentRecording)

        XCTAssertThrowsError(try fixture.controller.exportRecording(
            to: directory.appendingPathComponent("missing/folder/Saved.m4a")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.url.path))
        XCTAssertNil(fixture.controller.recentRecording?.savedURL)
    }

    func testOutputsRequireARecordingOrTranscript() {
        let fixture = makeFixture(authorized: true)
        XCTAssertThrowsError(try fixture.controller.addRecordingToShelf())
        XCTAssertThrowsError(try fixture.controller.exportRecording(to: directory.appendingPathComponent("x.m4a")))
        XCTAssertThrowsError(try fixture.controller.togglePlayback())
        XCTAssertThrowsError(try fixture.controller.copyTranscript())
        XCTAssertThrowsError(try fixture.controller.addTranscriptToShelf())
        XCTAssertTrue(fixture.shelf.urls.isEmpty)
    }

    // MARK: Playback

    func testPlaybackTogglesSeeksFinishesAndIsReleasedByNewCapture() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()

        try fixture.controller.togglePlayback()
        let player = try XCTUnwrap(fixture.playerSink.players.first)
        XCTAssertTrue(fixture.controller.isPlaying)
        try fixture.controller.seek(to: 99)
        XCTAssertEqual(player.currentTime, fixture.controller.recentRecording?.duration, "Seek clamps to the duration")
        try fixture.controller.togglePlayback()
        XCTAssertFalse(fixture.controller.isPlaying)
        try fixture.controller.togglePlayback()
        player.finish()
        XCTAssertFalse(fixture.controller.isPlaying)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(fixture.playerSink.players.count, 1, "One player per recording")

        try fixture.controller.togglePlayback()
        try await fixture.controller.startRecording()
        XCTAssertFalse(player.isPlaying, "Recording never captures our own playback")
        XCTAssertFalse(fixture.controller.isPlaying)
        player.isPlaying = true
        player.finish()
        XCTAssertFalse(fixture.controller.isPlaying, "A released player's late callback is ignored")
    }

    func testPlaybackFailureIsReported() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.playerSink.playResult = false
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        XCTAssertThrowsError(try fixture.controller.togglePlayback()) {
            XCTAssertEqual($0 as? VoiceTranscriptionError, .playbackFailed)
        }
        XCTAssertFalse(fixture.controller.isPlaying)
        XCTAssertNotNil(fixture.controller.recentRecording)
    }

    func testSystemPlayerLoadsAndSeeksARecordingWithoutPlaying() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tone.m4a")
        try writeTestAudio(to: url)
        let player = try AVFoundationVoicePlayer(url: url)
        player.currentTime = 0.1
        XCTAssertEqual(player.currentTime, 0.1, accuracy: 0.05)
        XCTAssertFalse(player.isPlaying)
    }

    // MARK: Transcription (explicit follow-up)

    func testTranscribeAsksForSpeechOnlyWhenChosenAndKeepsAudio() async throws {
        let fixture = makeFixture()
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        let recording = try XCTUnwrap(fixture.controller.recentRecording)
        XCTAssertEqual(fixture.permissions.speechRequests, 0)

        try await fixture.controller.transcribe()

        XCTAssertEqual(fixture.permissions.speechRequests, 1)
        XCTAssertEqual(fixture.transcriber.transcribedURLs, [recording.url])
        XCTAssertEqual(fixture.transcriber.requestedOnDevice, [true])
        XCTAssertEqual(fixture.transcriber.observedActivitiesDuringWork, [[.voiceTranscription]])
        XCTAssertEqual(fixture.transcriber.cancelCount, 1, "A final result releases the recognition task/request")
        XCTAssertEqual(fixture.controller.transcript?.text, "hello world")
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.url.path))
    }

    func testTranscriptionFailuresNeverDeleteTheRecording() async throws {
        let cases: [(VoiceTranscriptionError, (Fixture) -> Void)] = [
            (.speechPermissionRequired, { $0.permissions.speechGrant = .denied }),
            (.recognizerUnavailable, { $0.transcriber.availability.isAvailable = false }),
            (.onDeviceRecognitionUnavailable, { $0.transcriber.availability.supportsOnDeviceRecognition = false }),
            (.transcriptionFailed("Speech failed"), {
                $0.transcriber.result = .failure(VoiceTranscriptionError.transcriptionFailed("Speech failed"))
            }),
            (.transcriptionFailed("Transcription cancelled"), { $0.transcriber.result = .failure(CancellationError()) }),
            (.emptyTranscript, { $0.transcriber.result = .success("   ") })
        ]
        for (expected, configure) in cases {
            let fixture = makeFixture()
            try await fixture.controller.startRecording()
            try fixture.controller.stopRecording()
            let recording = try XCTUnwrap(fixture.controller.recentRecording)
            configure(fixture)

            await XCTAssertThrowsVoiceError(expected) { try await fixture.controller.transcribe() }

            XCTAssertEqual(fixture.controller.recentRecording, recording, "\(expected)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: recording.url.path), "\(expected)")
            XCTAssertNil(fixture.controller.transcript)
            XCTAssertFalse(fixture.controller.isBusy)
            XCTAssertEqual(fixture.activities.activities.map(\.kind), [.voiceStatus], "\(expected)")
        }
    }

    func testServerOnlyRecognizerRequiresExplicitOptIn() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.transcriber.availability.supportsOnDeviceRecognition = false
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()

        await XCTAssertThrowsVoiceError(.onDeviceRecognitionUnavailable) {
            try await fixture.controller.transcribe()
        }
        XCTAssertTrue(fixture.transcriber.transcribedURLs.isEmpty)

        fixture.controller.allowsServerRecognition = true
        try await fixture.controller.transcribe()
        XCTAssertEqual(fixture.transcriber.requestedOnDevice, [false])
        XCTAssertEqual(fixture.controller.transcript?.wasOnDevice, false)
    }

    func testCancelledTranscriptionKeepsAudioAndBlocksNothing() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.transcriber.suspend = true
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        let recording = try XCTUnwrap(fixture.controller.recentRecording)

        let work = Task { try await fixture.controller.transcribe() }
        for _ in 0..<50 where fixture.controller.phase != .transcribing { await Task.yield() }
        XCTAssertEqual(fixture.controller.phase, .transcribing)
        await XCTAssertThrowsVoiceError(.busy) { try await fixture.controller.startRecording() }

        fixture.controller.cancel()
        _ = try? await work.value

        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertNil(fixture.controller.transcript)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.url.path))
    }

    func testLateRecognitionResultAfterCancelIsIgnored() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        fixture.transcriber.suspend = true
        fixture.transcriber.ignoresCancel = true
        let work = Task { try await fixture.controller.transcribe() }
        for _ in 0..<50 where fixture.controller.phase != .transcribing { await Task.yield() }

        fixture.controller.cancel()
        fixture.transcriber.deliverLate("late")
        try await work.value

        XCTAssertNil(fixture.controller.transcript, "A stale generation never publishes")
        XCTAssertEqual(fixture.controller.phase, .ready)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testTranscriptOutputs() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        try await fixture.controller.transcribe()

        try fixture.controller.copyTranscript()
        XCTAssertEqual(fixture.pasteboard.values, ["hello world"])

        let saveURL = directory.appendingPathComponent("saved.txt")
        try fixture.controller.saveTranscript(to: saveURL)
        XCTAssertEqual(try String(contentsOf: saveURL, encoding: .utf8), "hello world")

        let shelfURL = try fixture.controller.addTranscriptToShelf()
        XCTAssertEqual(fixture.shelf.urls, [shelfURL])
        XCTAssertTrue(fixture.shelfStorage.isOwned(shelfURL))
        XCTAssertTrue(shelfURL.lastPathComponent.hasSuffix(".txt"))

        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        XCTAssertNil(fixture.controller.transcript, "A transcript belongs to the recording it came from")
    }

    // MARK: Meter, activities, races

    func testMeterIsOnlyReadDuringCapture() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.recorder.normalizedLevel = 0.7
        XCTAssertEqual(fixture.controller.liveAudioLevel, 0)
        try await fixture.controller.startRecording()
        XCTAssertEqual(fixture.controller.liveAudioLevel, 0.7)
        try fixture.controller.stopRecording()
        XCTAssertEqual(fixture.controller.liveAudioLevel, 0)
        try await fixture.controller.transcribe()
        XCTAssertEqual(fixture.controller.liveAudioLevel, 0)
    }

    func testRecordingPublishesActivityOnlyAfterRecorderStarts() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        let activity = try XCTUnwrap(fixture.activities.activities.first)
        XCTAssertEqual(activity.kind, .voiceRecording)
        XCTAssertEqual(activity.subtitle, "Voice Recording")
        XCTAssertEqual(activity.lifecycle.authority, .avFoundation)
        XCTAssertNil(activity.progress)
        XCTAssertNil(fixture.registry.snapshot(for: .voiceTranscribe)?.progress)
    }

    func testRecorderStartFailureLeavesOnlyStaticRecovery() async {
        let fixture = makeFixture(authorized: true)
        fixture.recorder.startError = VoiceTranscriptionError.recordingFailed("busy")

        await XCTAssertThrowsVoiceError(.recordingFailed("busy")) {
            try await fixture.controller.startRecording()
        }
        XCTAssertEqual(fixture.activities.activities.map(\.kind), [.voiceStatus])
        guard case .failed = fixture.registry.snapshot(for: .voiceTranscribe)?.health else {
            return XCTFail("Expected failed health")
        }
    }

    func testStopWithoutRecordingThrows() {
        let fixture = makeFixture(authorized: true)
        XCTAssertThrowsError(try fixture.controller.stopRecording()) {
            XCTAssertEqual($0 as? VoiceTranscriptionError, .notRecording)
        }
    }

    func testPermissionRequestIsAnExplicitPhaseNotRecording() async throws {
        let fixture = makeFixture()
        var observed: [VoiceTranscriptionPhase] = []
        fixture.permissions.onRequest = {
            observed.append(fixture.controller.phase)
            XCTAssertEqual(fixture.activities.activities.map(\.kind), [.voiceStatus])
            XCTAssertEqual(fixture.controller.liveAudioLevel, 0)
            XCTAssertTrue(fixture.recorder.startedURLs.isEmpty)
        }
        try await fixture.controller.startRecording()
        XCTAssertEqual(observed, [.requestingPermission])
        guard case .recording = fixture.controller.phase else { return XCTFail("expected recording") }
    }

    func testPermissionCancellationCannotStartCapture() async throws {
        let fixture = makeFixture()
        fixture.permissions.onRequest = { fixture.controller.cancel() }
        try await fixture.controller.startRecording()
        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertTrue(fixture.recorder.startedURLs.isEmpty)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testMissingInputDeviceFailsTruthfullyWithoutRecording() async {
        let fixture = makeFixture(authorized: true)
        fixture.recorder.hasInputDevice = false
        await XCTAssertThrowsVoiceError(.noMicrophone) {
            try await fixture.controller.startRecording()
        }
        XCTAssertTrue(fixture.recorder.startedURLs.isEmpty)
        XCTAssertEqual(fixture.controller.phase, .failed("No microphone available."))
    }

    func testPermissionGrantedAfterDenialRecoversOnNextStart() async throws {
        let fixture = makeFixture()
        fixture.permissions.microphoneState = .denied
        await XCTAssertThrowsVoiceError(.microphonePermissionRequired) {
            try await fixture.controller.startRecording()
        }
        fixture.permissions.microphoneState = .authorized
        try await fixture.controller.startRecording()
        guard case .recording = fixture.controller.phase else { return XCTFail("expected recording") }
        XCTAssertEqual(fixture.permissions.microphoneRequests, 0, "denied access is never re-prompted")
    }

    func testRepeatedStartStopCancelCyclesNeverLeaveARecorderRunning() async throws {
        let fixture = makeFixture(authorized: true)
        for cycle in 0..<24 {
            try await fixture.controller.startRecording()
            await XCTAssertThrowsVoiceError(.busy) { try await fixture.controller.startRecording() }
            if cycle.isMultiple(of: 2) {
                fixture.controller.cancel()
            } else {
                try fixture.controller.stopRecording()
            }
            XCTAssertFalse(fixture.recorder.isRecording)
            XCTAssertTrue(fixture.activities.activities.isEmpty)
        }
        XCTAssertEqual(files(in: recordingsDirectory).count, 12)
        XCTAssertTrue(files(in: workingDirectory).isEmpty)
    }

    func testStaticRecoveryExpiresWithoutKeepingControllerAlive() async throws {
        var fixture: Fixture? = makeFixture(authorized: true, recoveryDisplayDuration: .milliseconds(10))
        fixture!.recorder.startError = VoiceTranscriptionError.noMicrophone
        _ = try? await fixture!.controller.startRecording()
        let activities = fixture!.activities
        XCTAssertEqual(activities.activities.map(\.kind), [.voiceStatus])
        let expired = expectation(description: "Static voice recovery publishes its expiry")
        let observation = activities.$activities
            .first(where: { $0.isEmpty })
            .sink { _ in expired.fulfill() }
        defer { observation.cancel() }
        await fulfillment(of: [expired], timeout: 1)
        weak var controller = fixture!.controller
        fixture = nil
        XCTAssertNil(controller)
    }

    // MARK: Views

    func testPanelsAndCollapsedViewNeverStartCaptureOrPrompt() async throws {
        let fixture = makeFixture()
        try await fixture.controller.startRecording()
        try fixture.controller.stopRecording()
        let microphoneRequests = fixture.permissions.microphoneRequests
        let starts = fixture.recorder.startedURLs.count
        for compact in [true, false] {
            let host = NSHostingView(rootView: VoiceRecordingPanel(controller: fixture.controller, compact: compact)
                .frame(width: 360))
            host.layoutSubtreeIfNeeded()
        }
        let collapsed = NSHostingView(rootView: CollapsedVoiceBeamCompactView(
            controller: fixture.controller,
            activity: VoiceTranscriptionController.makeRecordingActivity(startedAt: Date())))
        collapsed.layoutSubtreeIfNeeded()
        XCTAssertEqual(fixture.recorder.startedURLs.count, starts)
        XCTAssertEqual(fixture.permissions.microphoneRequests, microphoneRequests)
        XCTAssertEqual(fixture.permissions.speechRequests, 0)
        XCTAssertEqual(fixture.controller.liveAudioLevel, 0)
    }

    func testCompactPanelFitsTheToolsPageInEveryState() async throws {
        let fixture = makeFixture(authorized: true)
        func size() -> CGSize {
            NSHostingView(rootView: VoiceRecordingPanel(controller: fixture.controller, compact: true)
                .environment(\.colorScheme, .dark)).fittingSize
        }
        let idle = size()
        try await fixture.controller.startRecording()
        let recording = size()
        try fixture.controller.stopRecording()
        let ready = size()
        try await fixture.controller.transcribe()
        let transcribed = size()
        for (state, measured) in [("idle", idle), ("recording", recording), ("ready", ready), ("transcribed", transcribed)] {
            XCTAssertLessThanOrEqual(measured.width, 340, state)
            XCTAssertLessThanOrEqual(measured.height, 150, state)
        }
        XCTAssertGreaterThan(ready.height, idle.height)
    }

    func testSilenceReturnsTheMicrophoneMeterToRest() {
        let envelope = VoiceBeamEnvelope()
        let config = VoiceBeamConfiguration()
        _ = envelope.sample(rawLevel: 1, timestamp: 0, configuration: config)
        var level = 1.0
        for step in 1...40 { level = envelope.sample(rawLevel: 0, timestamp: Double(step) * 0.1, configuration: config) }
        XCTAssertEqual(level, config.reactiveLevel(0), accuracy: 0.001, "Silence settles at the configured idle level")
        XCTAssertTrue(zip(MicrophoneBarMapper.levels(level: level, barCount: 12),
                          MicrophoneBarMapper.levels(level: 0.9, barCount: 12)).allSatisfy { $0 < $1 })
    }

    // MARK: Fixture

    private final class ShelfSink {
        var urls: [URL] = []
    }

    private final class PasteboardSink {
        var values: [String] = []
    }

    private struct Fixture {
        let controller: VoiceTranscriptionController
        let permissions: FakeVoicePermissions
        let recorder: FakeVoiceRecorder
        let transcriber: FakeTranscriber
        let activities: LiveActivityStore
        let registry: IslandCapabilityRegistry
        let shelf: ShelfSink
        let pasteboard: PasteboardSink
        let shelfStorage: FileShelfTemporaryStorage
        let playerSink: PlayerSink
    }

    private func makeFixture(authorized: Bool = false, recoveryDisplayDuration: Duration = .seconds(8)) -> Fixture {
        let permissions = FakeVoicePermissions()
        if authorized {
            permissions.microphoneState = .authorized
            permissions.speechState = .authorized
        }
        let recorder = FakeVoiceRecorder()
        let transcriber = FakeTranscriber()
        let activities = LiveActivityStore()
        transcriber.activities = activities
        let registry = IslandCapabilityRegistry()
        let shelf = ShelfSink()
        let pasteboard = PasteboardSink()
        let playerSink = PlayerSink()
        let shelfStorage = FileShelfTemporaryStorage(
            rootURL: directory.appendingPathComponent("Shelf", isDirectory: true),
            providerTemporaryRootURL: directory.appendingPathComponent("Provider", isDirectory: true)
        )
        let controller = VoiceTranscriptionController(
            liveActivities: activities,
            capabilities: registry,
            permissions: permissions,
            recorder: recorder,
            transcriber: transcriber,
            makePlayer: { _ in
                let player = FakePlayer()
                player.playResult = playerSink.playResult
                playerSink.players.append(player)
                return player
            },
            shelfStorage: shelfStorage,
            addToShelf: { shelf.urls.append(contentsOf: $0) },
            writeToPasteboard: { pasteboard.values.append($0) },
            recordingsDirectory: recordingsDirectory,
            now: { Date(timeIntervalSince1970: 1_000) },
            recoveryDisplayDuration: recoveryDisplayDuration
        )
        return Fixture(
            controller: controller, permissions: permissions, recorder: recorder, transcriber: transcriber,
            activities: activities, registry: registry, shelf: shelf, pasteboard: pasteboard,
            shelfStorage: shelfStorage, playerSink: playerSink
        )
    }
}

@MainActor
private func XCTAssertThrowsVoiceError(
    _ expected: VoiceTranscriptionError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? VoiceTranscriptionError, expected, file: file, line: line)
    }
}
