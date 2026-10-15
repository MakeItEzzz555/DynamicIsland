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

/// A finished, validated recording in the app-managed recordings folder.
struct VoiceRecording: Equatable, Sendable {
    let url: URL
    let createdAt: Date
    let duration: TimeInterval
    /// Last Save As destination this session (enables Reveal in Finder).
    var savedURL: URL?
}

/// idle -> requestingPermission -> preparing -> recording -> stopping -> ready,
/// plus transcribing (an explicit follow-up from ready) and failed.
/// `recording` is entered only after the recorder confirms capture started.
/// Transcription and its failures never remove the finished recording.
enum VoiceTranscriptionPhase: Equatable, Sendable {
    case idle
    case requestingPermission
    case preparing
    case recording(startedAt: Date)
    case stopping
    case ready
    case transcribing
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
    case noRecording
    case playbackFailed
    case notRecording
    case unsupportedAction(IslandCapabilityAction)

    var errorDescription: String? {
        switch self {
        case .disabled:
            "Voice Recording is disabled."
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
        case .noRecording:
            "There is no recording yet."
        case .playbackFailed:
            "The recording could not be played."
        case .notRecording:
            "Voice Recording is not recording."
        case .unsupportedAction(let action):
            "Voice Recording does not support \(action.rawValue)."
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
    /// Current microphone envelope normalized to 0...1. Implementations that
    /// cannot meter may use the protocol default of zero.
    var normalizedLevel: Double { get }
    /// Begins capturing microphone audio into `url`. Returns only after the
    /// recorder confirms it is actually recording.
    func startRecording(to url: URL) throws
    /// Stops capture and releases the microphone. Idempotent.
    func stopRecording()
    /// Stops capture, releases the microphone and discards the file. Idempotent.
    func cancelRecording()
}

extension VoiceAudioRecording {
    var normalizedLevel: Double { 0 }
}

@MainActor
protocol VoiceAudioPlaying: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get set }
    /// Called on the main actor when playback reaches the end.
    var onFinish: (() -> Void)? { get set }
    func play() -> Bool
    func pause()
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

    var normalizedLevel: Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        guard decibels.isFinite else { return 0 }
        let linear = min(max((decibels + 60) / 60, 0), 1)
        return pow(linear, 1.55)
    }

    func startRecording(to url: URL) throws {
        cancelRecording()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
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

@MainActor
final class AVFoundationVoicePlayer: NSObject, VoiceAudioPlaying, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onFinish: (() -> Void)?

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
        player.prepareToPlay()
    }

    var isPlaying: Bool { player.isPlaying }
    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }

    func play() -> Bool { player.play() }
    func pause() { player.pause() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.onFinish?() }
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

/// Voice Recording. Recording needs only the microphone; a stopped capture is
/// validated and moved into `recordingsDirectory`, where it stays until the
/// user deletes it. Transcription (Speech permission included) is a separate,
/// explicit follow-up that never deletes audio. The user-facing name changed
/// from Voice Transcribe; the type and capability ID keep their names so saved
/// layouts and settings stay valid.
@MainActor
final class VoiceTranscriptionController: ObservableObject, IslandCapabilityAdapter {
    static let recordingActivityID = "voice.recording"
    static let transcriptionActivityID = "voice.transcription"
    static let statusActivityID = "voice.status"

    let capabilityID: IslandCapabilityID = .voiceTranscribe

    @Published private(set) var phase: VoiceTranscriptionPhase = .idle
    @Published private(set) var microphoneState: VoicePermissionState
    @Published private(set) var speechState: VoicePermissionState
    @Published private(set) var recognizerAvailability: VoiceRecognizerAvailability
    @Published private(set) var isEnabled = true
    /// The newest finished recording; survives relaunch via `restoreRecordings()`.
    @Published private(set) var recentRecording: VoiceRecording?
    /// Transcript of `recentRecording`, only after the user asked for one.
    @Published private(set) var transcript: VoiceTranscript?
    @Published private(set) var isPlaying = false
    /// Explicit opt-in. When false, transcription runs only with
    /// `requiresOnDeviceRecognition`, and fails if that is unavailable.
    @Published var allowsServerRecognition = false

    private let permissions: VoicePermissionProviding
    private let recorder: VoiceAudioRecording
    private let transcriber: VoiceSpeechTranscribing
    private let makePlayer: (URL) throws -> VoiceAudioPlaying
    private let liveActivities: LiveActivityStore
    private let capabilities: IslandCapabilityRegistry
    private let shelfStorage: FileShelfTemporaryStorage
    private let addToShelf: ([URL]) -> Void
    private let writeToPasteboard: (String) -> Void
    private let recordingsDirectory: URL
    private let now: () -> Date
    private var generation = 0
    /// The unfinished capture; the only file Cancel may discard.
    private var recordingURL: URL?
    private var player: VoiceAudioPlaying?
    private let recoveryDisplayDuration: Duration
    private var recoveryDismissTask: Task<Void, Never>?

    init(
        liveActivities: LiveActivityStore,
        capabilities: IslandCapabilityRegistry,
        permissions: VoicePermissionProviding = SystemVoicePermissionProvider(),
        recorder: VoiceAudioRecording = AVFoundationVoiceRecorder(),
        transcriber: VoiceSpeechTranscribing = SpeechFrameworkTranscriber(),
        makePlayer: @escaping (URL) throws -> VoiceAudioPlaying = { try AVFoundationVoicePlayer(url: $0) },
        shelfStorage: FileShelfTemporaryStorage = .shared,
        addToShelf: @escaping ([URL]) -> Void,
        writeToPasteboard: @escaping (String) -> Void = VoiceTranscriptionController.systemPasteboardWriter,
        recordingsDirectory: URL = VoiceTranscriptionController.defaultRecordingsDirectory,
        now: @escaping () -> Date = Date.init,
        recoveryDisplayDuration: Duration = .seconds(8)
    ) {
        self.liveActivities = liveActivities
        self.capabilities = capabilities
        self.permissions = permissions
        self.recorder = recorder
        self.transcriber = transcriber
        self.makePlayer = makePlayer
        self.shelfStorage = shelfStorage
        self.addToShelf = addToShelf
        self.writeToPasteboard = writeToPasteboard
        self.recordingsDirectory = recordingsDirectory
        self.now = now
        self.recoveryDisplayDuration = recoveryDisplayDuration
        self.microphoneState = permissions.microphoneState
        self.speechState = permissions.speechState
        self.recognizerAvailability = transcriber.availability
        publishState()
    }

    deinit { recoveryDismissTask?.cancel() }

    nonisolated static let defaultRecordingsDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DynamicIsland", isDirectory: true)
        .appendingPathComponent("Voice Recordings", isDirectory: true)

    static let systemPasteboardWriter: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Captures in progress live here (hidden) and move out atomically once valid.
    private var workingDirectory: URL {
        recordingsDirectory.appendingPathComponent(".incomplete", isDirectory: true)
    }

    var liveAudioLevel: Double {
        guard case .recording = phase else { return 0 }
        return recorder.normalizedLevel
    }

    var isBusy: Bool {
        switch phase {
        case .requestingPermission, .preparing, .recording, .stopping, .transcribing: true
        case .idle, .ready, .failed: false
        }
    }

    /// True when the next transcription would stay on this Mac.
    var willTranscribeOnDevice: Bool {
        recognizerAvailability.supportsOnDeviceRecognition
    }

    var playbackTime: TimeInterval { player?.currentTime ?? 0 }

    var snapshot: IslandCapabilitySnapshot {
        let mapping = Self.capabilityMapping(microphone: microphoneState)
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
        case .idle: return "Ready"
        case .requestingPermission: return "Waiting for permission"
        case .preparing: return "Preparing microphone"
        case .recording: return "Recording"
        case .stopping: return "Saving recording"
        case .ready: return "Recording ready"
        case .transcribing: return "Transcribing"
        case .failed(let message): return message
        }
    }

    /// Recording needs only the microphone; Speech is asked for at Transcribe.
    static func capabilityMapping(
        microphone: VoicePermissionState
    ) -> (permission: IslandCapabilityPermissionState, availability: IslandCapabilityAvailability) {
        switch microphone {
        case .authorized: (.granted, .available)
        case .notDetermined: (.notDetermined, .available)
        case .denied: (.denied, .available)
        case .restricted: (.denied, .unsupported(reason: "Microphone access is restricted on this Mac."))
        }
    }

    // MARK: Recording

    /// Explicit user action (Settings). May present only the microphone prompt.
    func requestMicrophoneAccess() async {
        if permissions.microphoneState == .notDetermined {
            microphoneState = await permissions.requestMicrophone()
        }
        await refresh()
    }

    /// Explicit user action (Record). Requests an undetermined microphone
    /// permission, then fails closed on denial before touching the microphone.
    func startRecording() async throws {
        guard isEnabled else { throw VoiceTranscriptionError.disabled }
        guard !isBusy else { throw VoiceTranscriptionError.busy }

        generation += 1
        let token = generation
        stopPlayback()
        clearStatusActivity()
        let needsPrompt = permissions.microphoneState == .notDetermined
        phase = needsPrompt ? .requestingPermission : .preparing
        publishStatusActivity(title: needsPrompt ? "Mic permission" : "Preparing mic", subtitle: statusText)
        publishState()

        if needsPrompt {
            microphoneState = await permissions.requestMicrophone()
            guard token == generation else { return }
        } else {
            microphoneState = permissions.microphoneState
        }
        phase = .preparing
        publishStatusActivity(title: "Preparing mic", subtitle: statusText)
        publishState()

        do {
            guard microphoneState == .authorized else {
                throw VoiceTranscriptionError.microphonePermissionRequired
            }
            guard recorder.hasInputDevice else {
                throw VoiceTranscriptionError.noMicrophone
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
            clearStatusActivity()
            publishRecordingActivity(startedAt: startedAt)
            publishState()
        } catch {
            fail(error)
            throw error
        }
    }

    /// Releases the microphone immediately, then keeps the capture as a
    /// validated `.m4a`. An unreadable capture stays in the working folder
    /// for launch recovery instead of being deleted here.
    func stopRecording() throws {
        guard case .recording(let startedAt) = phase, let url = recordingURL else {
            throw VoiceTranscriptionError.notRecording
        }
        generation += 1
        phase = .stopping
        publishState()
        recorder.stopRecording()
        recordingURL = nil
        liveActivities.remove(id: Self.recordingActivityID)
        do {
            setRecent(try finalize(url, createdAt: startedAt))
            phase = .ready
            publishState()
        } catch {
            fail(error)
            throw error
        }
    }

    /// Launch-time only, before any capture: finishes captures that a crash
    /// left behind (readable audio is kept, unreadable fragments removed) and
    /// shows the newest recording.
    func restoreRecordings() {
        guard !isBusy else { return }
        let fileManager = FileManager.default
        let leftovers = (try? fileManager.contentsOfDirectory(
            at: workingDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for url in leftovers where url.lastPathComponent.hasPrefix("recording-") {
            guard Self.audioDuration(of: url) != nil else {
                try? fileManager.removeItem(at: url)
                continue
            }
            // Readable audio is never deleted; a failed move is retried next launch.
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now()
            _ = try? finalize(url, createdAt: created)
        }
        showNewestRecording()
    }

    // MARK: Recording output

    func togglePlayback() throws {
        let player = try loadedPlayer()
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else if player.play() {
            isPlaying = true
        } else {
            stopPlayback()
            throw VoiceTranscriptionError.playbackFailed
        }
    }

    func seek(to time: TimeInterval) throws {
        guard let recording = recentRecording else { throw VoiceTranscriptionError.noRecording }
        try loadedPlayer().currentTime = min(max(time, 0), recording.duration)
        objectWillChange.send()
    }

    func stopPlayback() {
        player?.pause()
        player = nil
        isPlaying = false
    }

    /// Save As: copies, so the app-managed recording is kept whatever happens.
    func exportRecording(to destination: URL) throws {
        guard let recording = recentRecording else { throw VoiceTranscriptionError.noRecording }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            // NSSavePanel already confirmed the replacement; swap atomically.
            let staging = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                              appropriateFor: destination, create: true)
            defer { try? fileManager.removeItem(at: staging) }
            let copy = staging.appendingPathComponent(destination.lastPathComponent)
            try fileManager.copyItem(at: recording.url, to: copy)
            _ = try fileManager.replaceItemAt(destination, withItemAt: copy)
        } else {
            try fileManager.copyItem(at: recording.url, to: destination)
        }
        recentRecording?.savedURL = destination
    }

    /// Copies into Shelf-owned storage; the recording itself stays put.
    @discardableResult
    func addRecordingToShelf() throws -> URL {
        guard let recording = recentRecording else { throw VoiceTranscriptionError.noRecording }
        let shelfURL = try shelfStorage.copyIntoShelf(recording.url, suggestedName: recording.url.lastPathComponent)
        addToShelf([shelfURL])
        return shelfURL
    }

    /// Deletes the shown recording (the UI confirms first); exported copies
    /// are untouched. The next newest recording, if any, is shown.
    func deleteRecording() throws {
        guard !isBusy else { throw VoiceTranscriptionError.busy }
        guard let recording = recentRecording else { throw VoiceTranscriptionError.noRecording }
        generation += 1
        stopPlayback()
        try FileManager.default.removeItem(at: recording.url)
        showNewestRecording()
    }

    // MARK: Transcription (explicit follow-up)

    /// The only path that may present the Speech Recognition prompt.
    func transcribe() async throws {
        guard isEnabled else { throw VoiceTranscriptionError.disabled }
        guard !isBusy else { throw VoiceTranscriptionError.busy }
        guard let recording = recentRecording else { throw VoiceTranscriptionError.noRecording }

        generation += 1
        let token = generation
        clearStatusActivity()
        if permissions.speechState == .notDetermined {
            phase = .requestingPermission
            publishStatusActivity(title: "Speech permission", subtitle: statusText)
            publishState()
            speechState = await permissions.requestSpeech()
            guard token == generation else { return }
        } else {
            speechState = permissions.speechState
        }
        recognizerAvailability = transcriber.availability

        do {
            guard speechState == .authorized else {
                throw VoiceTranscriptionError.speechPermissionRequired
            }
            guard recognizerAvailability.isAvailable else {
                throw VoiceTranscriptionError.recognizerUnavailable
            }
            let onDevice = recognizerAvailability.supportsOnDeviceRecognition
            guard onDevice || allowsServerRecognition else {
                throw VoiceTranscriptionError.onDeviceRecognitionUnavailable
            }
            clearStatusActivity()
            phase = .transcribing
            liveActivities.update(Self.makeTranscriptionActivity(onDevice: onDevice, updatedAt: now()))
            publishState()

            let text: String
            do {
                text = try await transcriber.transcribe(fileURL: recording.url, requiresOnDevice: onDevice)
            } catch {
                guard token == generation else { return }
                if error is VoiceTranscriptionError { throw error }
                throw VoiceTranscriptionError.transcriptionFailed(
                    error is CancellationError ? "Transcription cancelled" : error.localizedDescription)
            }
            guard token == generation else { return }
            // Speech owns its task and URL request until explicitly released.
            transcriber.cancel()
            liveActivities.remove(id: Self.transcriptionActivityID)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw VoiceTranscriptionError.emptyTranscript }
            transcript = VoiceTranscript(text: trimmed, createdAt: now(), wasOnDevice: onDevice)
            phase = .ready
            publishState()
        } catch {
            fail(error)
            throw error
        }
    }

    // MARK: Lifecycle

    /// Safe from any phase; repeated calls are no-ops. Discards only an
    /// unfinished capture; a finished recording is never touched.
    func cancel() {
        generation += 1
        recorder.cancelRecording()
        transcriber.cancel()
        discardUnfinishedCapture()
        removeActivities()
        if isBusy {
            phase = recentRecording == nil ? .idle : .ready
        }
        publishState()
    }

    /// Quit or disable: a running capture is finished and kept, never discarded.
    func terminate() {
        if case .recording = phase {
            try? stopRecording()
        }
        cancel()
        stopPlayback()
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            terminate()
            phase = recentRecording == nil ? .idle : .ready
        }
        isEnabled = enabled
        publishState()
    }

    // MARK: Transcript output

    func copyTranscript() throws {
        guard let transcript else { throw VoiceTranscriptionError.noTranscript }
        writeToPasteboard(transcript.text)
    }

    func saveTranscript(to url: URL) throws {
        guard let transcript else { throw VoiceTranscriptionError.noTranscript }
        try Data(transcript.text.utf8).write(to: url, options: .atomic)
    }

    /// Writes the transcript as a text file into Shelf-owned storage and adds
    /// it to the existing File Shelf.
    @discardableResult
    func addTranscriptToShelf() throws -> URL {
        guard let transcript else { throw VoiceTranscriptionError.noTranscript }
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-\(UUID().uuidString).txt")
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

    /// Duration of a readable, non-empty audio file; nil for anything else.
    nonisolated static func audioDuration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
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
            try stopRecording()
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

    /// Validates, then moves into the recordings folder under a fresh name.
    /// `moveItem` fails instead of overwriting, so no recording is replaced.
    private func finalize(_ workingURL: URL, createdAt: Date) throws -> VoiceRecording {
        guard let duration = Self.audioDuration(of: workingURL) else {
            throw VoiceTranscriptionError.recordingFailed("The capture is not readable audio.")
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        let base = "Voice Recording \(Self.filenameFormatter.string(from: createdAt))"
        for attempt in 1...999 {
            let name = attempt == 1 ? base : "\(base) \(attempt)"
            let destination = recordingsDirectory.appendingPathComponent(name).appendingPathExtension("m4a")
            do {
                try fileManager.moveItem(at: workingURL, to: destination)
                return VoiceRecording(url: destination, createdAt: createdAt, duration: duration)
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw VoiceTranscriptionError.recordingFailed("No free recording filename.")
    }

    private func showNewestRecording() {
        let keys: Set<URLResourceKey> = [.creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)) ?? []
        let newestFirst = files
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .map { ($0, (try? $0.resourceValues(forKeys: keys).creationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        let newest = newestFirst.lazy.compactMap { url, created in
            Self.audioDuration(of: url).map { VoiceRecording(url: url, createdAt: created, duration: $0) }
        }.first
        setRecent(newest)
        if !isBusy {
            phase = newest == nil ? .idle : .ready
        }
        publishState()
    }

    private func setRecent(_ recording: VoiceRecording?) {
        stopPlayback()
        transcript = nil
        recentRecording = recording
    }

    private func loadedPlayer() throws -> VoiceAudioPlaying {
        if let player { return player }
        guard let recording = recentRecording else { throw VoiceTranscriptionError.noRecording }
        let player: VoiceAudioPlaying
        do { player = try makePlayer(recording.url) } catch { throw VoiceTranscriptionError.playbackFailed }
        player.onFinish = { [weak self, weak player] in
            guard let self, let player, self.player === player else { return }
            self.isPlaying = false
            player.currentTime = 0
        }
        self.player = player
        return player
    }

    private func fail(_ error: Error) {
        recorder.cancelRecording()
        transcriber.cancel()
        discardUnfinishedCapture()
        removeActivities()
        phase = .failed(error.localizedDescription)
        publishStatusActivity(title: "Voice Recording", subtitle: error.localizedDescription)
        let token = generation
        let delay = recoveryDisplayDuration
        recoveryDismissTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.generation == token else { return }
            self.liveActivities.remove(id: Self.statusActivityID)
            self.recoveryDismissTask = nil
        }
        publishState()
    }

    private func discardUnfinishedCapture() {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
    }

    private func removeActivities() {
        clearStatusActivity()
        liveActivities.remove(id: Self.recordingActivityID)
        liveActivities.remove(id: Self.transcriptionActivityID)
    }

    private func clearStatusActivity() {
        recoveryDismissTask?.cancel()
        recoveryDismissTask = nil
        liveActivities.remove(id: Self.statusActivityID)
    }

    private func publishStatusActivity(title: String, subtitle: String) {
        liveActivities.update(Self.makeStatusActivity(title: title, subtitle: subtitle, updatedAt: now()))
    }

    /// Static feedback, distinct from a recording or recognition task.
    static func makeStatusActivity(title: String, subtitle: String, updatedAt: Date) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: statusActivityID, kind: .voiceStatus, title: title, subtitle: subtitle,
            symbolName: "mic.badge.exclamationmark", priority: 140, isActive: false,
            progress: nil, updatedAt: updatedAt,
            lifecycle: LiveActivityLifecycleMetadata(
                authority: .applicationState, startEvidence: "Explicit voice permission, preparation or recovery",
                progressEvidence: nil, completionEvidence: "Voice proceeds, cancels or recovery notice expires",
                dismissPolicy: .untilSourceEnds, supportsCancellation: false
            )
        )
    }

    private func publishRecordingActivity(startedAt: Date) {
        liveActivities.update(Self.makeRecordingActivity(startedAt: startedAt))
    }

    /// Production activity shape; also used by Settings previews.
    static func makeRecordingActivity(startedAt: Date) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: recordingActivityID,
            kind: .voiceRecording,
            title: "Recording",
            subtitle: "Voice Recording",
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
