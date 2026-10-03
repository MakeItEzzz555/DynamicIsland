import AVFoundation
import Foundation
import Speech
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
        speechRequests += 1
        speechState = speechGrant
        return speechState
    }
}

@MainActor
private final class FakeVoiceRecorder: VoiceAudioRecording {
    var hasInputDevice = true
    var normalizedLevel = 0.0
    var startError: Error?
    var isRecording = false
    var startedURLs: [URL] = []
    var stopCount = 0
    var cancelCount = 0

    func startRecording(to url: URL) throws {
        if let startError { throw startError }
        try Data("audio".utf8).write(to: url)
        startedURLs.append(url)
        isRecording = true
    }

    func stopRecording() {
        stopCount += 1
        isRecording = false
    }

    func cancelRecording() {
        cancelCount += 1
        isRecording = false
    }
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

    func cancel() {
        cancelCount += 1
        suspended?.resume(throwing: CancellationError())
        suspended = nil
    }
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

    func testPermissionMappingRequiresBothPermissions() {
        let available = VoiceRecognizerAvailability(isAvailable: true, supportsOnDeviceRecognition: true, localeIdentifier: "en")
        func map(_ mic: VoicePermissionState, _ speech: VoicePermissionState) -> IslandCapabilityPermissionState {
            VoiceTranscriptionController.capabilityMapping(
                microphone: mic, speech: speech, recognizer: available, allowsServerRecognition: false
            ).permission
        }
        XCTAssertEqual(map(.authorized, .authorized), .granted)
        XCTAssertEqual(map(.authorized, .notDetermined), .notDetermined)
        XCTAssertEqual(map(.notDetermined, .authorized), .notDetermined)
        XCTAssertEqual(map(.denied, .authorized), .denied)
        XCTAssertEqual(map(.authorized, .denied), .denied)
        XCTAssertEqual(map(.restricted, .authorized), .denied)
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

    func testAvailabilityIsTruthfulAboutOnDeviceRecognition() {
        let serverOnly = VoiceRecognizerAvailability(isAvailable: true, supportsOnDeviceRecognition: false, localeIdentifier: "xx")
        let blocked = VoiceTranscriptionController.capabilityMapping(
            microphone: .authorized, speech: .authorized, recognizer: serverOnly, allowsServerRecognition: false
        )
        guard case .temporarilyUnavailable = blocked.availability else {
            return XCTFail("Server-only recognizer must not look available without opt-in")
        }
        let optedIn = VoiceTranscriptionController.capabilityMapping(
            microphone: .authorized, speech: .authorized, recognizer: serverOnly, allowsServerRecognition: true
        )
        XCTAssertEqual(optedIn.availability, .available)

        let unavailable = VoiceRecognizerAvailability(isAvailable: false, supportsOnDeviceRecognition: false, localeIdentifier: "xx")
        guard case .temporarilyUnavailable = VoiceTranscriptionController.capabilityMapping(
            microphone: .authorized, speech: .authorized, recognizer: unavailable, allowsServerRecognition: true
        ).availability else {
            return XCTFail("Unavailable recognizer must be reported")
        }
    }

    func testConstructionAndRefreshNeverPrompt() async {
        let fixture = makeFixture()
        await fixture.controller.refresh()
        XCTAssertEqual(fixture.permissions.microphoneRequests, 0)
        XCTAssertEqual(fixture.permissions.speechRequests, 0)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testExplicitRequestAsksOnlyForUndeterminedPermissions() async {
        let fixture = makeFixture()
        fixture.permissions.microphoneState = .authorized

        await fixture.controller.requestPermissions()

        XCTAssertEqual(fixture.permissions.microphoneRequests, 0)
        XCTAssertEqual(fixture.permissions.speechRequests, 1)
        XCTAssertEqual(fixture.registry.snapshot(for: .voiceTranscribe)?.permission, .granted)
    }

    func testDeniedMicrophoneFailsClosedWithoutRecording() async {
        let fixture = makeFixture()
        fixture.permissions.microphoneState = .denied
        fixture.permissions.speechState = .authorized

        await XCTAssertThrowsVoiceError(.microphonePermissionRequired) {
            try await fixture.controller.startRecording()
        }
        XCTAssertTrue(fixture.recorder.startedURLs.isEmpty)
        XCTAssertEqual(fixture.activities.activities.map(\.kind), [.voiceStatus], "Only static recovery remains; capture and processing are removed")
        XCTAssertEqual(fixture.registry.snapshot(for: .voiceTranscribe)?.permission, .denied)
    }

    func testDeniedSpeechFailsClosedWithoutRecording() async {
        let fixture = makeFixture()
        fixture.permissions.microphoneState = .authorized
        fixture.permissions.speechGrant = .denied

        await XCTAssertThrowsVoiceError(.speechPermissionRequired) {
            try await fixture.controller.startRecording()
        }
        XCTAssertTrue(fixture.recorder.startedURLs.isEmpty)
    }

    func testUnavailableRecognizerFailsBeforeRecording() async {
        let fixture = makeFixture(authorized: true)
        fixture.transcriber.availability.isAvailable = false
        await fixture.controller.refresh()

        await XCTAssertThrowsVoiceError(.recognizerUnavailable) {
            try await fixture.controller.startRecording()
        }
        XCTAssertTrue(fixture.recorder.startedURLs.isEmpty)
    }

    func testServerOnlyRecognizerRequiresExplicitOptIn() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.transcriber.availability.supportsOnDeviceRecognition = false
        await fixture.controller.refresh()

        await XCTAssertThrowsVoiceError(.onDeviceRecognitionUnavailable) {
            try await fixture.controller.startRecording()
        }
        XCTAssertTrue(fixture.recorder.startedURLs.isEmpty)

        fixture.controller.reset()
        fixture.controller.allowsServerRecognition = true
        try await fixture.controller.startRecording()
        try await fixture.controller.stopAndTranscribe()

        XCTAssertEqual(fixture.transcriber.requestedOnDevice, [false])
        XCTAssertEqual(fixture.controller.transcript?.wasOnDevice, false)
    }

    func testRecordingPublishesActivityOnlyAfterRecorderStarts() async throws {
        let fixture = makeFixture(authorized: true)

        try await fixture.controller.startRecording()

        guard case .recording = fixture.controller.phase else {
            return XCTFail("Expected recording phase")
        }
        let activity = fixture.activities.activities.first
        XCTAssertEqual(activity?.kind, .voiceRecording)
        XCTAssertEqual(activity?.lifecycle.authority, .avFoundation)
        XCTAssertNil(activity?.progress)
    }

    func testRecorderStartFailureLeavesOnlyStaticRecovery() async {
        let fixture = makeFixture(authorized: true)
        fixture.recorder.startError = VoiceTranscriptionError.recordingFailed("busy")

        await XCTAssertThrowsVoiceError(.recordingFailed("busy")) {
            try await fixture.controller.startRecording()
        }
        XCTAssertEqual(fixture.activities.activities.map(\.kind), [.voiceStatus], "Only static recovery remains; capture and processing are removed")
        guard case .failed = fixture.registry.snapshot(for: .voiceTranscribe)?.health else {
            return XCTFail("Expected failed health")
        }
    }

    func testStopTranscribesOnDeviceAndTearsDown() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        let audioURL = try XCTUnwrap(fixture.recorder.startedURLs.first)

        try await fixture.controller.stopAndTranscribe()

        XCTAssertEqual(fixture.recorder.stopCount, 1)
        XCTAssertEqual(fixture.transcriber.cancelCount, 1, "A final result releases the recognition task/request")
        XCTAssertEqual(fixture.transcriber.requestedOnDevice, [true])
        XCTAssertEqual(fixture.transcriber.transcribedURLs, [audioURL])
        XCTAssertEqual(fixture.transcriber.observedActivitiesDuringWork, [[.voiceTranscription]])
        XCTAssertEqual(fixture.controller.transcript?.text, "hello world")
        XCTAssertEqual(fixture.controller.transcript?.wasOnDevice, true)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testTranscriptionFailureTearsDownAndReportsFailure() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.transcriber.result = .failure(NSError(domain: "speech", code: 1))
        try await fixture.controller.startRecording()
        let audioURL = try XCTUnwrap(fixture.recorder.startedURLs.first)

        do {
            try await fixture.controller.stopAndTranscribe()
            XCTFail("Expected failure")
        } catch {
            guard case .transcriptionFailed = error as? VoiceTranscriptionError else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        guard case .failed = fixture.controller.phase else {
            return XCTFail("Expected failed phase")
        }
        XCTAssertEqual(fixture.transcriber.cancelCount, 1, "Failure releases recognition resources")
        XCTAssertEqual(fixture.activities.activities.map(\.kind), [.voiceStatus], "Only static recovery remains; capture and processing are removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testEmptyTranscriptIsAFailureNotAResult() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.transcriber.result = .success("   ")
        try await fixture.controller.startRecording()

        await XCTAssertThrowsVoiceError(.emptyTranscript) {
            try await fixture.controller.stopAndTranscribe()
        }
        XCTAssertNil(fixture.controller.transcript)
    }

    func testCancelWhileRecordingIsIdempotentAndDiscardsAudio() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        let audioURL = try XCTUnwrap(fixture.recorder.startedURLs.first)

        fixture.controller.cancel()
        fixture.controller.cancel()

        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertFalse(fixture.recorder.isRecording)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertFalse(fixture.registry.snapshot(for: .voiceTranscribe)?.isActive ?? true)
    }

    func testCancelDuringTranscriptionStopsRecognitionWithoutFailure() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.transcriber.suspend = true
        try await fixture.controller.startRecording()

        let work = Task { try await fixture.controller.stopAndTranscribe() }
        for _ in 0..<50 where fixture.controller.phase != .transcribing {
            await Task.yield()
        }
        XCTAssertEqual(fixture.controller.phase, .transcribing)

        fixture.controller.cancel()
        _ = try? await work.value

        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertGreaterThanOrEqual(fixture.transcriber.cancelCount, 1)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testMeterIsOnlyReadDuringCaptureAndCancellationFailureRemovesBeam() async throws {
        let fixture = makeFixture(authorized: true)
        fixture.recorder.normalizedLevel = 0.7
        XCTAssertEqual(fixture.controller.liveAudioLevel, 0)
        try await fixture.controller.startRecording()
        XCTAssertEqual(fixture.controller.liveAudioLevel, 0.7)
        fixture.transcriber.result = .failure(CancellationError())
        do {
            try await fixture.controller.stopAndTranscribe()
            XCTFail("Recognizer cancellation must finish the lifecycle")
        } catch {
            guard case .failed = fixture.controller.phase else {
                return XCTFail("Current-generation cancellation must not leave transcription running")
            }
        }
        XCTAssertEqual(fixture.controller.liveAudioLevel, 0)
        XCTAssertEqual(fixture.activities.activities.map(\.kind), [.voiceStatus], "Only static recovery remains; capture and processing are removed")
        XCTAssertFalse(fixture.controller.isBusy)
    }

    func testDisableWhileRecordingTearsDown() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()

        fixture.controller.setEnabled(false)

        XCTAssertFalse(fixture.recorder.isRecording)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        await XCTAssertThrowsVoiceError(.disabled) {
            try await fixture.controller.startRecording()
        }
    }

    func testStopWithoutRecordingThrows() async {
        let fixture = makeFixture(authorized: true)
        await XCTAssertThrowsVoiceError(.notRecording) {
            try await fixture.controller.stopAndTranscribe()
        }
    }

    func testCopySaveAndShelfHandoff() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        try await fixture.controller.stopAndTranscribe()

        try fixture.controller.copyTranscript()
        XCTAssertEqual(fixture.pasteboard.values, ["hello world"])

        let saveURL = directory.appendingPathComponent("saved.txt")
        try fixture.controller.saveTranscript(to: saveURL)
        XCTAssertEqual(try String(contentsOf: saveURL, encoding: .utf8), "hello world")

        let shelfURL = try fixture.controller.addTranscriptToShelf()
        XCTAssertEqual(fixture.shelf.urls, [shelfURL])
        XCTAssertTrue(fixture.shelfStorage.isOwned(shelfURL))
        XCTAssertTrue(shelfURL.lastPathComponent.hasSuffix(".txt"))
        XCTAssertEqual(try String(contentsOf: shelfURL, encoding: .utf8), "hello world")
    }

    func testOutputsRequireATranscript() {
        let fixture = makeFixture(authorized: true)
        XCTAssertThrowsError(try fixture.controller.copyTranscript())
        XCTAssertThrowsError(try fixture.controller.addTranscriptToShelf())
        XCTAssertTrue(fixture.shelf.urls.isEmpty)
    }

    func testNoFakeProgressInSnapshots() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        XCTAssertNil(fixture.registry.snapshot(for: .voiceTranscribe)?.progress)
        XCTAssertTrue(fixture.activities.activities.allSatisfy { $0.progress == nil })
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
            shelfStorage: shelfStorage,
            addToShelf: { shelf.urls.append(contentsOf: $0) },
            writeToPasteboard: { pasteboard.values.append($0) },
            workingDirectory: directory.appendingPathComponent("Work", isDirectory: true),
            now: { Date(timeIntervalSince1970: 1_000) },
            recoveryDisplayDuration: recoveryDisplayDuration
        )
        return Fixture(
            controller: controller,
            permissions: permissions,
            recorder: recorder,
            transcriber: transcriber,
            activities: activities,
            registry: registry,
            shelf: shelf,
            pasteboard: pasteboard,
            shelfStorage: shelfStorage
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


// MARK: - Production crash / lifecycle regressions

extension VoiceTranscriptionControllerTests {
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

    func testMissingInputDeviceFailsTruthfullyWithoutRecording() async {
        let fixture = makeFixture(authorized: true)
        fixture.recorder.hasInputDevice = false
        await XCTAssertThrowsVoiceError(.noMicrophone) {
            try await fixture.controller.startRecording()
        }
        XCTAssertTrue(fixture.recorder.startedURLs.isEmpty)
        XCTAssertEqual(fixture.activities.activities.map(\.kind), [.voiceStatus], "Only static recovery remains; capture and processing are removed")
        XCTAssertEqual(fixture.controller.phase, .failed("No microphone available."))
    }

    func testPermissionGrantedAfterDenialRecoversOnNextStart() async throws {
        let fixture = makeFixture()
        fixture.permissions.microphoneState = .denied
        fixture.permissions.speechState = .authorized
        await XCTAssertThrowsVoiceError(.microphonePermissionRequired) {
            try await fixture.controller.startRecording()
        }
        // The user grants access in System Settings and comes back.
        fixture.permissions.microphoneState = .authorized
        try await fixture.controller.startRecording()
        guard case .recording = fixture.controller.phase else { return XCTFail("expected recording") }
        XCTAssertEqual(fixture.permissions.microphoneRequests, 0, "denied access is never re-prompted")
    }

    func testStopThenImmediatelyStartAgainRecordsTwice() async throws {
        let fixture = makeFixture(authorized: true)
        try await fixture.controller.startRecording()
        try await fixture.controller.stopAndTranscribe()
        try await fixture.controller.startRecording()
        guard case .recording = fixture.controller.phase else { return XCTFail("expected second recording") }
        XCTAssertEqual(fixture.recorder.startedURLs.count, 2)
        XCTAssertNotEqual(fixture.recorder.startedURLs[0], fixture.recorder.startedURLs[1])
    }

    func testRepeatedStartStopCancelCyclesNeverLeaveARecorderRunning() async throws {
        let fixture = makeFixture(authorized: true)
        for _ in 0..<25 {
            try await fixture.controller.startRecording()
            fixture.controller.cancel()
            XCTAssertFalse(fixture.recorder.isRecording)
            XCTAssertTrue(fixture.activities.activities.isEmpty)
        }
    }
}


extension VoiceTranscriptionControllerTests {
    func testStaticRecoveryExpiresWithoutKeepingControllerAlive() async throws {
        var fixture: Fixture? = makeFixture(authorized: true, recoveryDisplayDuration: .milliseconds(10))
        fixture!.recorder.startError = VoiceTranscriptionError.noMicrophone
        _ = try? await fixture!.controller.startRecording()
        let activities = fixture!.activities
        XCTAssertEqual(activities.activities.map(\.kind), [.voiceStatus])
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(activities.activities.isEmpty)
        weak var controller = fixture!.controller
        fixture = nil
        XCTAssertNil(controller)
    }

    func testPermissionCancellationRemovesStaticStatusAndCannotStartCapture() async throws {
        let fixture = makeFixture()
        fixture.permissions.onRequest = { fixture.controller.cancel() }
        try await fixture.controller.startRecording()
        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertTrue(fixture.recorder.startedURLs.isEmpty)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }
}
