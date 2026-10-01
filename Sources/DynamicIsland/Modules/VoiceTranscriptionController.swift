import AppKit
import AVFoundation
import Foundation
import Speech

enum VoicePermissionState: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

struct VoiceRecognizerAvailability: Equatable, Sendable {
    /// `SFSpeechRecognizer` exists for the locale and reports `isAvailable`.
    var isAvailable: Bool
    /// `SFSpeechRecognizer.supportsOnDeviceRecognition` for the locale.
    var supportsOnDeviceRecognition: Bool
    var localeIdentifier: String
}

struct VoiceTranscript: Equatable, Sendable {
    let text: String
    let createdAt: Date
    let wasOnDevice: Bool
}

/// idle -> requestingPermission -> preparing -> recording -> stopping ->
/// transcribing -> completed, plus failed. `recording` is entered only after
/// the recorder confirms capture actually started.
enum VoiceTranscriptionPhase: Equatable, Sendable {
    case idle
    case requestingPermission
    case preparing
    case recording(startedAt: Date)
    case stopping
    case transcribing
    case completed(VoiceTranscript)
    case failed(String)
}

enum VoiceTranscriptionError: LocalizedError, Equatable {
    case disabled
    case busy
    case microphonePermissionRequired
    case noMicrophone
    case speechPermissionRequired
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case recordingFailed(String)
    case transcriptionFailed(String)
    case emptyTranscript
    case noTranscript
    case notRecording
    case unsupportedAction(IslandCapabilityAction)

    var errorDescription: String? {
        switch self {
        case .disabled:
            "Voice Transcribe is disabled."
        case .busy:
            "A recording or transcription is already in progress."
        case .microphonePermissionRequired:
            "Microphone access is required to record."
        case .noMicrophone:
            "No microphone available."
        case .speechPermissionRequired:
            "Speech Recognition access is required to transcribe."
        case .recognizerUnavailable:
            "Speech recognition is not available for the current language."
        case .onDeviceRecognitionUnavailable:
            "On-device speech recognition is not available for the current language. Allow Apple server recognition to continue."
        case .recordingFailed(let message):
            "Recording failed: \(message)"
        case .transcriptionFailed(let message):
            "Transcription failed: \(message)"
        case .emptyTranscript:
            "No speech was recognized."
        case .noTranscript:
            "There is no transcript yet."
        case .notRecording:
            "Voice Transcribe is not recording."
        case .unsupportedAction(let action):
            "Voice Transcribe does not support \(action.rawValue)."
        }
    }
}

@MainActor
protocol VoicePermissionProviding: AnyObject {
    var microphoneState: VoicePermissionState { get }
    var speechState: VoicePermissionState { get }
    func requestMicrophone() async -> VoicePermissionState
    func requestSpeech() async -> VoicePermissionState
}

@MainActor
protocol VoiceAudioRecording: AnyObject {
    /// A default audio input device exists right now.
    var hasInputDevice: Bool { get }
    /// Begins capturing microphone audio into `url`. Returns only after the
    /// recorder confirms it is actually recording.
    func startRecording(to url: URL) throws
    /// Stops capture and releases the microphone. Idempotent.
    func stopRecording()
    /// Stops capture, releases the microphone and discards the file. Idempotent.
    func cancelRecording()
}

@MainActor
protocol VoiceSpeechTranscribing: AnyObject {
    var availability: VoiceRecognizerAvailability { get }
    func transcribe(fileURL: URL, requiresOnDevice: Bool) async throws -> String
    /// Cancels the in-flight recognition task and request. Idempotent.
    func cancel()
}

// MARK: - System implementations

@MainActor
final class SystemVoicePermissionProvider: VoicePermissionProviding {
    /// TCC delivers the reply on a background queue. The reply must be
    /// `@Sendable` (non-isolated): a closure that inherits this type's main-
    /// actor isolation is checked by the Swift runtime when called from
    /// Objective-C and traps (EXC_BREAKPOINT in requestSpeech(), the
    /// production Voice crash).
    typealias SpeechAuthorizationRequest = @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void

    private let speechAuthorizationRequest: SpeechAuthorizationRequest

    init(speechAuthorizationRequest: @escaping SpeechAuthorizationRequest = { reply in
        SFSpeechRecognizer.requestAuthorization { @Sendable status in reply(status) }
    }) {
        self.speechAuthorizationRequest = speechAuthorizationRequest
    }

    var microphoneState: VoicePermissionState {
        Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    var speechState: VoicePermissionState {
        Self.map(SFSpeechRecognizer.authorizationStatus())
    }

    func requestMicrophone() async -> VoicePermissionState {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return microphoneState
    }

    func requestSpeech() async -> VoicePermissionState {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            speechAuthorizationRequest { @Sendable status in
                continuation.resume(returning: status)
            }
        }
        return Self.map(status)
    }

    nonisolated static func map(_ status: AVAuthorizationStatus) -> VoicePermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .denied
        }
    }

    nonisolated static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> VoicePermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .denied
        }
    }
}

@MainActor
final class AVFoundationVoiceRecorder: VoiceAudioRecording {
    private var recorder: AVAudioRecorder?

    var hasInputDevice: Bool { AVCaptureDevice.default(for: .audio) != nil }

    func startRecording(to url: URL) throws {
        cancelRecording()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        // `record()` returning true is not enough: require the recorder to
        // report live capture before the controller enters `.recording`.
        guard recorder.prepareToRecord(), recorder.record(), recorder.isRecording else {
            recorder.stop()
            recorder.deleteRecording()
            throw VoiceTranscriptionError.recordingFailed("The microphone could not be started.")
        }
        self.recorder = recorder
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
    }

    func cancelRecording() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        self.recorder = nil
    }
}

/// File-based recognition through `SFSpeechRecognizer`. When
/// `requiresOnDevice` is true the request sets
/// `requiresOnDeviceRecognition`, so audio never leaves the Mac.
@MainActor
final class SpeechFrameworkTranscriber: VoiceSpeechTranscribing {
    private let recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechURLRecognitionRequest?
    private var pending: RecognitionContinuation?

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    var availability: VoiceRecognizerAvailability {
        VoiceRecognizerAvailability(
            isAvailable: recognizer?.isAvailable ?? false,
            supportsOnDeviceRecognition: recognizer?.supportsOnDeviceRecognition ?? false,
            localeIdentifier: recognizer?.locale.identifier ?? Locale.current.identifier
        )
    }

    func transcribe(fileURL: URL, requiresOnDevice: Bool) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceTranscriptionError.recognizerUnavailable
        }
        cancel()

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = requiresOnDevice
        self.request = request

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
                let box = RecognitionContinuation(continuation)
                pending = box
                // @Sendable: Speech may call this off the main queue; it only
                // touches the thread-safe one-shot box.
                task = recognizer.recognitionTask(with: request) { @Sendable result, error in
                    if let error {
                        box.resume(throwing: VoiceTranscriptionError.transcriptionFailed(error.localizedDescription))
                    } else if let result, result.isFinal {
                        box.resume(returning: result.bestTranscription.formattedString)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        request = nil
        pending?.resume(throwing: CancellationError())
        pending = nil
    }
}

/// One-shot continuation guard: Speech may call the result handler several
/// times and cancellation may race completion.
private final class RecognitionContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, any Error>?

    init(_ continuation: CheckedContinuation<String, any Error>) {
        self.continuation = continuation
    }

    func resume(returning value: String) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: any Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<String, any Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}

// MARK: - Controller

@MainActor
final class VoiceTranscriptionController: ObservableObject, IslandCapabilityAdapter {
    static let recordingActivityID = "voice.recording"
    static let transcriptionActivityID = "voice.transcription"

    let capabilityID: IslandCapabilityID = .voiceTranscribe

    @Published private(set) var phase: VoiceTranscriptionPhase = .idle
    @Published private(set) var microphoneState: VoicePermissionState
    @Published private(set) var speechState: VoicePermissionState
    @Published private(set) var recognizerAvailability: VoiceRecognizerAvailability
    @Published private(set) var isEnabled = true
    @Published private(set) var lastSavedURL: URL?
    /// Explicit opt-in. When false, transcription runs only with
    /// `requiresOnDeviceRecognition`, and fails if that is unavailable.
    @Published var allowsServerRecognition = false

    private let permissions: VoicePermissionProviding
    private let recorder: VoiceAudioRecording
    private let transcriber: VoiceSpeechTranscribing
    private let liveActivities: LiveActivityStore
    private let capabilities: IslandCapabilityRegistry
    private let shelfStorage: FileShelfTemporaryStorage
    private let addToShelf: ([URL]) -> Void
    private let writeToPasteboard: (String) -> Void
    private let workingDirectory: URL
    private let now: () -> Date
    private var generation = 0
    private var recordingURL: URL?

    init(
        liveActivities: LiveActivityStore,
        capabilities: IslandCapabilityRegistry,
        permissions: VoicePermissionProviding = SystemVoicePermissionProvider(),
        recorder: VoiceAudioRecording = AVFoundationVoiceRecorder(),
        transcriber: VoiceSpeechTranscribing = SpeechFrameworkTranscriber(),
        shelfStorage: FileShelfTemporaryStorage = .shared,
        addToShelf: @escaping ([URL]) -> Void,
        writeToPasteboard: @escaping (String) -> Void = VoiceTranscriptionController.systemPasteboardWriter,
        workingDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("VoiceTranscribe", isDirectory: true),
        now: @escaping () -> Date = Date.init
    ) {
        self.liveActivities = liveActivities
        self.capabilities = capabilities
        self.permissions = permissions
        self.recorder = recorder
        self.transcriber = transcriber
        self.shelfStorage = shelfStorage
        self.addToShelf = addToShelf
        self.writeToPasteboard = writeToPasteboard
        self.workingDirectory = workingDirectory
        self.now = now
        self.microphoneState = permissions.microphoneState
        self.speechState = permissions.speechState
        self.recognizerAvailability = transcriber.availability
        publishState()
    }

    static let systemPasteboardWriter: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var transcript: VoiceTranscript? {
        if case .completed(let transcript) = phase { return transcript }
        return nil
    }

    var isBusy: Bool {
        switch phase {
        case .requestingPermission, .preparing, .recording, .stopping, .transcribing: true
        case .idle, .completed, .failed: false
        }
    }

    /// True when the next transcription would stay on this Mac.
    var willTranscribeOnDevice: Bool {
        recognizerAvailability.supportsOnDeviceRecognition
    }

    var snapshot: IslandCapabilitySnapshot {
        let mapping = Self.capabilityMapping(
            microphone: microphoneState,
            speech: speechState,
            recognizer: recognizerAvailability,
            allowsServerRecognition: allowsServerRecognition
        )
        let health: IslandCapabilityHealth
        if case .failed(let message) = phase {
            health = .failed(message: message)
        } else {
            health = .healthy
        }
        var actions: Set<IslandCapabilityAction> = [.openSettings, .test]
        if case .recording = phase {
            actions.insert(.stop)
        } else if !isBusy {
            actions.insert(.start)
        }
        return IslandCapabilitySnapshot(
            id: .voiceTranscribe,
            isEnabled: isEnabled,
            permission: mapping.permission,
            availability: mapping.availability,
            health: health,
            supportedActions: actions,
            isActive: isEnabled && isBusy,
            progress: nil,
            statusText: statusText
        )
    }

    var statusText: String {
        guard isEnabled else { return "Disabled" }
        switch phase {
        case .idle: return willTranscribeOnDevice ? "Ready · on-device" : "Ready"
        case .requestingPermission: return "Waiting for permission"
        case .preparing: return "Preparing microphone"
        case .recording: return "Recording"
        case .stopping: return "Stopping"
        case .transcribing: return "Transcribing"
        case .completed: return "Transcript ready"
        case .failed(let message): return message
        }
    }

    static func capabilityMapping(
        microphone: VoicePermissionState,
        speech: VoicePermissionState,
        recognizer: VoiceRecognizerAvailability,
        allowsServerRecognition: Bool
    ) -> (permission: IslandCapabilityPermissionState, availability: IslandCapabilityAvailability) {
        let permission: IslandCapabilityPermissionState
        if microphone == .denied || microphone == .restricted || speech == .denied || speech == .restricted {
            permission = .denied
        } else if microphone == .authorized && speech == .authorized {
            permission = .granted
        } else {
            permission = .notDetermined
        }

        let availability: IslandCapabilityAvailability
        if microphone == .restricted || speech == .restricted {
            availability = .unsupported(reason: "Microphone or Speech Recognition is restricted on this Mac.")
        } else if !recognizer.isAvailable {
            availability = .temporarilyUnavailable(reason: "Speech recognition is unavailable for \(recognizer.localeIdentifier).")
        } else if !recognizer.supportsOnDeviceRecognition && !allowsServerRecognition {
            availability = .temporarilyUnavailable(reason: "On-device recognition is unavailable for \(recognizer.localeIdentifier).")
        } else {
            availability = .available
        }
        return (permission, availability)
    }

    // MARK: Lifecycle

    /// Explicit user action. May present the microphone and Speech prompts.
    func requestPermissions() async {
        if permissions.microphoneState == .notDetermined {
            microphoneState = await permissions.requestMicrophone()
        }
        if permissions.speechState == .notDetermined {
            speechState = await permissions.requestSpeech()
        }
        await refresh()
    }

    /// Explicit user action (Record). Requests any undetermined permission,
    /// then fails closed on denial before touching the microphone.
    func startRecording() async throws {
        guard isEnabled else { throw VoiceTranscriptionError.disabled }
        guard !isBusy else { throw VoiceTranscriptionError.busy }

        generation += 1
        let token = generation
        let needsPrompt = permissions.microphoneState == .notDetermined
            || permissions.speechState == .notDetermined
        phase = needsPrompt ? .requestingPermission : .preparing
        publishState()

        await requestPermissions()
        guard token == generation else { return }
        phase = .preparing
        publishState()

        do {
            guard microphoneState == .authorized else {
                throw VoiceTranscriptionError.microphonePermissionRequired
            }
            guard recorder.hasInputDevice else {
                throw VoiceTranscriptionError.noMicrophone
            }
            guard speechState == .authorized else {
                throw VoiceTranscriptionError.speechPermissionRequired
            }
            guard recognizerAvailability.isAvailable else {
                throw VoiceTranscriptionError.recognizerUnavailable
            }
            guard recognizerAvailability.supportsOnDeviceRecognition || allowsServerRecognition else {
                throw VoiceTranscriptionError.onDeviceRecognitionUnavailable
            }

            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let url = workingDirectory.appendingPathComponent("recording-\(UUID().uuidString).m4a")
            do {
                try recorder.startRecording(to: url)
            } catch let error as VoiceTranscriptionError {
                throw error
            } catch {
                throw VoiceTranscriptionError.recordingFailed(error.localizedDescription)
            }
            recordingURL = url
            let startedAt = now()
            phase = .recording(startedAt: startedAt)
            publishRecordingActivity(startedAt: startedAt)
            publishState()
        } catch {
            fail(error)
            throw error
        }
    }

    /// Stops the microphone, then transcribes the captured audio.
    func stopAndTranscribe() async throws {
        guard case .recording = phase, let url = recordingURL else {
            throw VoiceTranscriptionError.notRecording
        }
        let token = generation
        phase = .stopping
        recorder.stopRecording()
        liveActivities.remove(id: Self.recordingActivityID)
        publishState()

        let onDevice = recognizerAvailability.supportsOnDeviceRecognition
        phase = .transcribing
        publishTranscriptionActivity()
        publishState()

        do {
            let text = try await transcriber.transcribe(fileURL: url, requiresOnDevice: onDevice)
            guard token == generation else { return }
            discardRecordingFile()
            liveActivities.remove(id: Self.transcriptionActivityID)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw VoiceTranscriptionError.emptyTranscript }
            phase = .completed(VoiceTranscript(text: trimmed, createdAt: now(), wasOnDevice: onDevice))
            publishState()
        } catch {
            guard token == generation else { return }
            let mapped: Error
            if error is VoiceTranscriptionError {
                mapped = error
            } else if error is CancellationError {
                return
            } else {
                mapped = VoiceTranscriptionError.transcriptionFailed(error.localizedDescription)
            }
            fail(mapped)
            throw mapped
        }
    }

    /// Safe from any phase; repeated calls are no-ops.
    func cancel() {
        generation += 1
        recorder.cancelRecording()
        transcriber.cancel()
        discardRecordingFile()
        removeActivities()
        if isBusy {
            phase = .idle
        }
        publishState()
    }

    func reset() {
        cancel()
        phase = .idle
        publishState()
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            cancel()
            phase = .idle
        }
        isEnabled = enabled
        publishState()
    }

    // MARK: Output

    func copyTranscript() throws {
        guard let transcript else { throw VoiceTranscriptionError.noTranscript }
        writeToPasteboard(transcript.text)
    }

    func saveTranscript(to url: URL) throws {
        guard let transcript else { throw VoiceTranscriptionError.noTranscript }
        try Data(transcript.text.utf8).write(to: url, options: .atomic)
        lastSavedURL = url
    }

    /// Writes the transcript as a text file into Shelf-owned storage and adds
    /// it to the existing File Shelf.
    @discardableResult
    func addTranscriptToShelf() throws -> URL {
        guard let transcript else { throw VoiceTranscriptionError.noTranscript }
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let staging = workingDirectory.appendingPathComponent("transcript-\(UUID().uuidString).txt")
        try Data(transcript.text.utf8).write(to: staging, options: .atomic)
        defer { try? FileManager.default.removeItem(at: staging) }
        let shelfURL = try shelfStorage.copyIntoShelf(
            staging,
            suggestedName: Self.transcriptFilename(for: transcript.createdAt)
        )
        addToShelf([shelfURL])
        return shelfURL
    }

    static func transcriptFilename(for date: Date) -> String {
        "Transcript \(filenameFormatter.string(from: date)).txt"
    }

    // MARK: IslandCapabilityAdapter

    func refresh() async {
        microphoneState = permissions.microphoneState
        speechState = permissions.speechState
        recognizerAvailability = transcriber.availability
        publishState()
    }

    func perform(_ action: IslandCapabilityAction) async throws {
        switch action {
        case .start:
            try await startRecording()
        case .stop:
            try await stopAndTranscribe()
        case .test:
            await refresh()
        case .openSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        case .configureShortcut:
            throw VoiceTranscriptionError.unsupportedAction(action)
        }
    }

    // MARK: Private

    private func fail(_ error: Error) {
        recorder.cancelRecording()
        discardRecordingFile()
        removeActivities()
        phase = .failed(error.localizedDescription)
        publishState()
    }

    private func discardRecordingFile() {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
    }

    private func removeActivities() {
        liveActivities.remove(id: Self.recordingActivityID)
        liveActivities.remove(id: Self.transcriptionActivityID)
    }

    private func publishRecordingActivity(startedAt: Date) {
        liveActivities.update(Self.makeRecordingActivity(startedAt: startedAt))
    }

    private func publishTranscriptionActivity() {
        liveActivities.update(
            Self.makeTranscriptionActivity(
                onDevice: recognizerAvailability.supportsOnDeviceRecognition,
                updatedAt: now()
            )
        )
    }

    /// Production activity shape; also used by Settings previews.
    static func makeRecordingActivity(startedAt: Date) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: recordingActivityID,
            kind: .voiceRecording,
            title: "Recording",
            subtitle: "Voice Transcribe",
            symbolName: "mic.fill",
            priority: 92,
            isActive: true,
            progress: nil,
            updatedAt: startedAt,
            lifecycle: LiveActivityLifecycleMetadata(
                authority: .avFoundation,
                startEvidence: "AVAudioRecorder reported recording started",
                progressEvidence: nil,
                completionEvidence: "AVAudioRecorder stopped and released the microphone",
                dismissPolicy: .untilSourceEnds,
                supportsCancellation: true
            )
        )
    }

    /// Production activity shape; also used by Settings previews.
    static func makeTranscriptionActivity(onDevice: Bool, updatedAt: Date) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: transcriptionActivityID,
            kind: .voiceTranscription,
            title: "Transcribing",
            subtitle: onDevice ? "On-device" : "Apple speech service",
            symbolName: "waveform",
            priority: 86,
            isActive: true,
            progress: nil,
            updatedAt: updatedAt,
            lifecycle: LiveActivityLifecycleMetadata(
                authority: .systemAPI,
                startEvidence: "Speech recognition task started",
                progressEvidence: nil,
                completionEvidence: "Speech recognition returned a final result or error",
                dismissPolicy: .untilSourceEnds,
                supportsCancellation: true
            )
        )
    }

    private func publishState() {
        capabilities.update(snapshot)
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()
}
