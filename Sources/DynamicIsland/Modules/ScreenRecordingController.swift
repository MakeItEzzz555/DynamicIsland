import AppKit
import AVFoundation
import Foundation
import ScreenCaptureKit

enum ScreenRecordingTargetKind: String, CaseIterable, Identifiable, Sendable {
    case display
    case window
    case area

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display: "Display"
        case .window: "Window"
        case .area: "Area"
        }
    }
}

struct ScreenRecordingDisplayChoice: Identifiable, Equatable, Sendable {
    let id: CGDirectDisplayID
    let name: String
    let logicalSize: CGSize
    let pixelSize: CGSize
}

struct ScreenRecordingWindowChoice: Identifiable, Equatable, Sendable {
    let id: CGWindowID
    let title: String
    let applicationName: String
    let frame: CGRect

    var displayTitle: String {
        title.isEmpty ? applicationName : "\(applicationName) — \(title)"
    }
}

/// What ScreenCaptureKit will actually allow this process to do.
enum ScreenCaptureAccessState: Equatable, Sendable {
    case unknown
    case granted
    /// Never allowed (or not yet asked): Allow / Open Settings.
    case notGranted
    /// Requested, or an entry exists, but capture is still refused: the
    /// process must be relaunched, or (rebuilt ad-hoc builds) the System
    /// Settings entry must be removed and re-added.
    case notActive
}

@MainActor
protocol ScreenCaptureAuthorizing: AnyObject {
    func preflight() -> Bool
    /// May show the system prompt; returns false immediately when an entry
    /// already exists, even a stale one.
    func request() -> Bool
    func shareableContent() async throws -> SCShareableContent
}

@MainActor
final class SystemScreenCaptureAuthorization: ScreenCaptureAuthorizing {
    func preflight() -> Bool { CGPreflightScreenCaptureAccess() }
    func request() -> Bool { CGRequestScreenCaptureAccess() }
    func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }
}

/// Relaunches the running app bundle (used when macOS only applies a
/// privacy grant to a new process).
@MainActor
enum AppRelauncher {
    static var canRelaunch: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func relaunch() {
        guard canRelaunch else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$1\"",
            "relaunch",
            Bundle.main.bundleURL.path
        ]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            // Leave the app running; the UI keeps the Open Settings path.
        }
    }

    /// True when the running bundle is ad-hoc signed (its identity changes
    /// with every rebuild, which invalidates existing privacy grants).
    static var isAdHocSigned: Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let flags = dictionary[kSecCodeInfoFlags as String] as? UInt32 else { return false }
        return flags & SecCodeSignatureFlags.adhoc.rawValue != 0
    }
}

struct ScreenRecordingOptions: Equatable, Sendable {
    var capturesSystemAudio = true
    var capturesMicrophone = false
    var showsCursor = true
    var excludesDynamicIsland = true
}

@MainActor
final class ScreenRecordingController: ObservableObject {
    static let liveActivityID = "screenRecording"

    @Published private(set) var phase: ScreenRecordingPhase = .idle
    @Published private(set) var statusText = "Ready"
    @Published private(set) var recordedDuration: TimeInterval = 0
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var displays: [ScreenRecordingDisplayChoice] = []
    @Published private(set) var windows: [ScreenRecordingWindowChoice] = []
    @Published private(set) var lastSavedURL: URL?
    @Published private(set) var accessState: ScreenCaptureAccessState = .unknown
    @Published var options = ScreenRecordingOptions()
    let isAdHocSigned: Bool

    private let liveActivities: LiveActivityStore
    private let capabilities: IslandCapabilityRegistry
    private let authorization: ScreenCaptureAuthorizing
    private var requestAttempted = false
    private var machine = ScreenRecordingStateMachine()
    private var shareableContent: SCShareableContent?
    private var displayObjects: [CGDirectDisplayID: SCDisplay] = [:]
    private var windowObjects: [CGWindowID: SCWindow] = [:]
    private var stream: SCStream?
    private var streamOutput: ScreenRecordingStreamOutput?
    private var lifecycleGeneration = 0
    /// Live Activity text only changes at whole-second boundaries. Publishing
    /// at display refresh rate needlessly invalidates the whole island tree.
    private var lastPublishedLiveActivitySecond: Int?

    init(
        liveActivities: LiveActivityStore,
        capabilities: IslandCapabilityRegistry,
        authorization: ScreenCaptureAuthorizing = SystemScreenCaptureAuthorization(),
        isAdHocSigned: Bool = AppRelauncher.isAdHocSigned
    ) {
        self.liveActivities = liveActivities
        self.capabilities = capabilities
        self.authorization = authorization
        self.isAdHocSigned = isAdHocSigned
        publishCapability()
    }

    /// ScreenCaptureKit is the authority: a successful content query means
    /// capture is allowed even if the CGPreflight cache is stale.
    nonisolated static func accessState(
        preflight: Bool,
        contentAvailable: Bool?,
        requestAttempted: Bool
    ) -> ScreenCaptureAccessState {
        if contentAvailable == true { return .granted }
        if contentAvailable == nil, preflight { return .granted }
        if preflight || requestAttempted { return .notActive }
        return .notGranted
    }

    nonisolated static func isAuthorizationRefusal(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain &&
            nsError.code == SCStreamError.Code.userDeclined.rawValue
    }

    var accessMessage: String {
        switch accessState {
        case .unknown, .granted:
            return statusText
        case .notGranted:
            return "Screen Recording permission is required. Click Allow, or turn on DynamicIsland in System Settings → Privacy & Security → Screen & System Audio Recording."
        case .notActive:
            var text = "Screen Recording permission isn't active for this copy of DynamicIsland. If you just turned it on, Relaunch DynamicIsland to activate it."
            if isAdHocSigned {
                text += " This build is ad-hoc signed, so after a rebuild macOS keeps the old entry: remove DynamicIsland with −, add it again, then Relaunch."
            }
            return text
        }
    }

    private func applyAccess(_ state: ScreenCaptureAccessState) {
        accessState = state
        if state == .notGranted || state == .notActive {
            shareableContent = nil
            displayObjects = [:]
            windowObjects = [:]
            displays = []
            windows = []
            statusText = accessMessage
            publishCapability(permission: .required)
        }
    }

    var isActive: Bool {
        switch phase {
        case .preparing, .recording, .paused, .finalizing: true
        case .idle, .saved, .failed: false
        }
    }

    var isActuallyCapturing: Bool {
        phase == .recording || phase == .paused
    }

    var formattedDuration: String {
        Self.formatDuration(recordedDuration)
    }

    var microphoneCaptureAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    func prepareTargets(requestPermission: Bool = true) async {
        guard !isActuallyCapturing, phase != .finalizing else { return }
        statusText = "Checking Screen Recording access…"

        let preflight = authorization.preflight()
        if !preflight, requestPermission {
            requestAttempted = true
            _ = authorization.request()
        }
        guard preflight || requestPermission else {
            // Opening the setup panel never prompts.
            applyAccess(Self.accessState(preflight: false, contentAvailable: nil, requestAttempted: requestAttempted))
            return
        }

        do {
            let content = try await authorization.shareableContent()
            accessState = .granted
            shareableContent = content
            displayObjects = Dictionary(
                uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) }
            )

            let ownBundleID = Bundle.main.bundleIdentifier
            let usableWindows = content.windows.filter { window in
                guard window.frame.width >= 80, window.frame.height >= 60 else { return false }
                guard let app = window.owningApplication else { return false }
                if let ownBundleID, app.bundleIdentifier == ownBundleID { return false }
                return true
            }
            windowObjects = Dictionary(
                uniqueKeysWithValues: usableWindows.map { ($0.windowID, $0) }
            )

            displays = content.displays.map { display in
                let screen = NSScreen.screens.first {
                    Self.displayID(for: $0) == display.displayID
                }
                return ScreenRecordingDisplayChoice(
                    id: display.displayID,
                    name: screen?.localizedName ?? "Display \(display.displayID)",
                    logicalSize: screen?.frame.size ??
                        CGSize(width: display.width, height: display.height),
                    pixelSize: CGSize(width: display.width, height: display.height)
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            windows = usableWindows.map { window in
                ScreenRecordingWindowChoice(
                    id: window.windowID,
                    title: window.title ?? "",
                    applicationName: window.owningApplication?.applicationName ?? "Application",
                    frame: window.frame
                )
            }
            .sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }

            statusText = "Choose what to record"
            publishCapability(permission: .granted)
        } catch where Self.isAuthorizationRefusal(error) || !preflight {
            applyAccess(Self.accessState(preflight: preflight, contentAvailable: false, requestAttempted: requestAttempted))
        } catch {
            accessState = .granted
            statusText = error.localizedDescription
            publishCapability(
                permission: .granted,
                health: .degraded(message: error.localizedDescription)
            )
        }
    }

    func startDisplay(_ displayID: CGDirectDisplayID) async {
        await start(.display(displayID))
    }

    func startWindow(_ windowID: CGWindowID) async {
        await start(.window(windowID))
    }

    func startArea(displayID: CGDirectDisplayID, sourceRect: CGRect) async {
        await start(.area(displayID, sourceRect))
    }

    func pause() {
        guard machine.pause() else { return }
        if let frozen = streamOutput?.pause() {
            recordedDuration = max(frozen, 0)
        }
        phase = machine.phase
        statusText = "Paused"
        publishLiveActivity()
        publishCapability(permission: .granted)
    }

    func resume() {
        guard machine.resume() else { return }
        streamOutput?.resume()
        phase = machine.phase
        statusText = "Recording"
        publishLiveActivity()
        publishCapability(permission: .granted)
    }

    func togglePause() {
        phase == .paused ? resume() : pause()
    }

    func stopAndSave() async {
        // The movie ends when the user pressed Stop, not after stopCapture's
        // round trip.
        let stoppedAt = ScreenRecordingTimelineClock.hostNow()
        guard machine.beginFinalizing() else { return }
        let generation = lifecycleGeneration
        phase = machine.phase
        statusText = "Saving…"
        publishLiveActivity()
        publishCapability(permission: .granted)

        do {
            // An intentional SCStream stop can still deliver a terminal delegate
            // callback on some macOS/driver combinations. The explicit stop call
            // itself remains authoritative here; writer finalization below owns
            // success/failure from this point forward.
            streamOutput?.onFailure = nil
            streamOutput?.markStopRequested(at: stoppedAt)
            if let stream {
                try await stream.stopCapture()
            }
            guard generation == lifecycleGeneration, let output = streamOutput else {
                return
            }
            let url = try await output.finish(stoppedAt: stoppedAt)
            let duration = try await Self.validateRecording(at: url)
            guard generation == lifecycleGeneration else { return }

            recordedDuration = duration
            lastSavedURL = url
            _ = machine.didSave()
            phase = machine.phase
            statusText = "Saved \(url.lastPathComponent)"
            self.stream = nil
            streamOutput = nil
            previewImage = nil
            liveActivities.remove(id: Self.liveActivityID)
            publishCapability(permission: .granted)
        } catch {
            guard generation == lifecycleGeneration else { return }
            await failAndCleanup(error, generation: generation)
        }
    }

    func revealLastRecording() {
        guard let lastSavedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastSavedURL])
    }

    func resetPresentation() {
        guard !isActive else { return }
        machine.reset()
        phase = machine.phase
        statusText = "Ready"
        recordedDuration = 0
        previewImage = nil
        publishCapability()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private enum Target {
        case display(CGDirectDisplayID)
        case window(CGWindowID)
        case area(CGDirectDisplayID, CGRect)
    }

    private struct ResolvedTarget {
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
        let width: Int
        let height: Int
    }

    private func start(_ target: Target) async {
        guard machine.beginPreparing() else { return }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        phase = machine.phase
        statusText = "Preparing…"
        recordedDuration = 0
        previewImage = nil
        lastSavedURL = nil
        lastPublishedLiveActivitySecond = nil
        publishCapability()

        do {
            // Fresh authority and targets on every Start: a stale grant or a
            // stale window list must fail visibly, never silently.
            await refreshTargetsForStart()
            guard generation == lifecycleGeneration else { return }
            switch accessState {
            case .notGranted: throw ScreenRecordingError.permissionDenied
            case .notActive: throw ScreenRecordingError.permissionNotActive
            case .unknown, .granted: break
            }
            guard let content = shareableContent else {
                throw ScreenRecordingError.captureUnavailable(statusText)
            }

            if options.capturesMicrophone {
                guard microphoneCaptureAvailable else {
                    throw ScreenRecordingError.captureUnavailable("Direct microphone capture requires macOS 15 or later")
                }
                let microphoneGranted: Bool
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized:
                    microphoneGranted = true
                case .notDetermined:
                    microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
                case .denied, .restricted:
                    microphoneGranted = false
                @unknown default:
                    microphoneGranted = false
                }
                guard microphoneGranted else {
                    throw ScreenRecordingError.captureUnavailable("Microphone permission is required for microphone audio")
                }
            }

            let resolved = try resolveTarget(target, content: content)
            let outputURL = try Self.makeOutputURL()
            let output = try ScreenRecordingStreamOutput(
                outputURL: outputURL,
                width: resolved.width,
                height: resolved.height,
                capturesSystemAudio: options.capturesSystemAudio,
                capturesMicrophone: options.capturesMicrophone &&
                    microphoneCaptureAvailable
            )
            connect(output, generation: generation)

            let config = resolved.configuration
            config.showsCursor = options.showsCursor
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 6
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.capturesAudio = options.capturesSystemAudio
            if options.capturesSystemAudio {
                config.sampleRate = 48_000
                config.channelCount = 2
                config.excludesCurrentProcessAudio = false
            }
            if #available(macOS 15.0, *), options.capturesMicrophone {
                config.captureMicrophone = true
            }

            let stream = SCStream(
                filter: resolved.filter,
                configuration: config,
                delegate: output
            )
            try stream.addStreamOutput(
                output,
                type: .screen,
                sampleHandlerQueue: output.queue
            )
            if options.capturesSystemAudio {
                try stream.addStreamOutput(
                    output,
                    type: .audio,
                    sampleHandlerQueue: output.queue
                )
            }
            if #available(macOS 15.0, *), options.capturesMicrophone {
                try stream.addStreamOutput(
                    output,
                    type: .microphone,
                    sampleHandlerQueue: output.queue
                )
            }

            self.stream = stream
            streamOutput = output
            try await stream.startCapture()

            // Remain preparing until a real video sample arrives.
            statusText = "Starting capture…"
            publishCapability(permission: .granted)
        } catch {
            guard generation == lifecycleGeneration else { return }
            await failAndCleanup(error, generation: generation)
        }
    }

    private func refreshTargetsForStart() async {
        await prepareTargets(requestPermission: true)
        if accessState == .granted { statusText = "Preparing…" }
    }

    private func connect(
        _ output: ScreenRecordingStreamOutput,
        generation: Int
    ) {
        output.onFirstVideoFrame = { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.lifecycleGeneration else { return }
                guard self.machine.didStart() else { return }
                self.phase = self.machine.phase
                self.statusText = "Recording"
                self.publishLiveActivity()
                self.publishCapability(permission: .granted)
            }
        }
        output.onTimeline = { [weak self] seconds in
            Task { @MainActor in
                guard let self, generation == self.lifecycleGeneration else { return }
                self.recordedDuration = max(seconds, 0)
                if self.phase == .recording || self.phase == .paused {
                    let second = Int(self.recordedDuration.rounded(.down))
                    if second != self.lastPublishedLiveActivitySecond {
                        self.lastPublishedLiveActivitySecond = second
                        self.publishLiveActivity()
                    }
                }
            }
        }
        output.onPreview = { [weak self] image in
            Task { @MainActor in
                guard let self, generation == self.lifecycleGeneration else { return }
                self.previewImage = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
            }
        }
        output.onFailure = { [weak self] error in
            Task { @MainActor in
                guard let self, generation == self.lifecycleGeneration else { return }
                await self.failAndCleanup(error, generation: generation)
            }
        }
    }

    private func resolveTarget(
        _ target: Target,
        content: SCShareableContent
    ) throws -> ResolvedTarget {
        let ownBundleID = Bundle.main.bundleIdentifier
        let ownWindows = options.excludesDynamicIsland
            ? content.windows.filter {
                $0.owningApplication?.bundleIdentifier == ownBundleID
            }
            : []

        switch target {
        case .display(let displayID):
            guard let display = displayObjects[displayID] ??
                    content.displays.first(where: { $0.displayID == displayID }) else {
                throw ScreenRecordingError.noDisplay
            }
            let config = SCStreamConfiguration()
            config.width = max(display.width, 1)
            config.height = max(display.height, 1)
            config.scalesToFit = false
            config.captureResolution = .best
            return ResolvedTarget(
                filter: SCContentFilter(display: display, excludingWindows: ownWindows),
                configuration: config,
                width: config.width,
                height: config.height
            )

        case .window(let windowID):
            guard let window = windowObjects[windowID] ??
                    content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenRecordingError.noWindow
            }
            let scale = Self.backingScale(for: window.frame)
            let width = max(Int((window.frame.width * scale).rounded()), 1)
            let height = max(Int((window.frame.height * scale).rounded()), 1)
            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.scalesToFit = true
            config.captureResolution = .best
            return ResolvedTarget(
                filter: SCContentFilter(desktopIndependentWindow: window),
                configuration: config,
                width: width,
                height: height
            )

        case .area(let displayID, let sourceRect):
            guard sourceRect.width >= 20, sourceRect.height >= 20 else {
                throw ScreenRecordingError.invalidArea
            }
            guard let display = displayObjects[displayID] ??
                    content.displays.first(where: { $0.displayID == displayID }) else {
                throw ScreenRecordingError.noDisplay
            }
            let screen = NSScreen.screens.first {
                Self.displayID(for: $0) == displayID
            }
            let logicalBounds = CGRect(
                origin: .zero,
                size: screen?.frame.size ??
                    CGSize(width: display.width, height: display.height)
            )
            let clamped = sourceRect.standardized.intersection(logicalBounds)
            guard clamped.width >= 20, clamped.height >= 20 else {
                throw ScreenRecordingError.invalidArea
            }

            let scale = Self.backingScale(
                forDisplayID: displayID,
                fallback: screen?.backingScaleFactor ?? 1
            )
            let width = max(Int((clamped.width * scale).rounded()), 1)
            let height = max(Int((clamped.height * scale).rounded()), 1)
            let config = SCStreamConfiguration()
            config.sourceRect = clamped
            config.width = width
            config.height = height
            config.scalesToFit = false
            config.captureResolution = .best
            return ResolvedTarget(
                filter: SCContentFilter(display: display, excludingWindows: ownWindows),
                configuration: config,
                width: width,
                height: height
            )
        }
    }

    private func failAndCleanup(_ error: Error, generation: Int) async {
        guard generation == lifecycleGeneration else { return }
        let activeStream = stream
        let activeOutput = streamOutput
        // An intentional cleanup stop can itself produce SCStream delegate
        // termination callbacks. Detach failure delivery before stopping.
        activeOutput?.onFailure = nil
        stream = nil
        streamOutput = nil

        if let activeStream {
            try? await activeStream.stopCapture()
        }
        await activeOutput?.cancel()
        guard generation == lifecycleGeneration else { return }
        transitionToFailure(error)
    }

    private func transitionToFailure(_ error: Error) {
        lifecycleGeneration &+= 1
        machine.fail()
        phase = machine.phase
        let nsError = error as NSError
        let reason = nsError.localizedFailureReason.map { " · \($0)" } ?? ""
        switch error as? ScreenRecordingError {
        case .permissionDenied?, .permissionNotActive?:
            // Actionable recovery text, not an error code.
            statusText = accessMessage
        default:
            statusText = "\(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]\(reason)"
        }
        liveActivities.remove(id: Self.liveActivityID)
        previewImage = nil
        lastPublishedLiveActivitySecond = nil
        publishCapability(
            permission: error as? ScreenRecordingError == .permissionDenied ||
                error as? ScreenRecordingError == .permissionNotActive
                ? .required : nil,
            health: .failed(message: error.localizedDescription)
        )
    }

    private func publishLiveActivity() {
        guard phase == .recording || phase == .paused || phase == .finalizing else {
            liveActivities.remove(id: Self.liveActivityID)
            return
        }

        let stateText: String
        switch phase {
        case .recording: stateText = "REC · \(formattedDuration)"
        case .paused: stateText = "Paused · \(formattedDuration)"
        case .finalizing: stateText = "Saving · \(formattedDuration)"
        default: return
        }

        liveActivities.update(
            DynamicIslandLiveActivity(
                id: Self.liveActivityID,
                kind: .screenRecording,
                title: "Screen Recording",
                subtitle: stateText,
                symbolName: phase == .paused
                    ? "pause.circle.fill" : "record.circle.fill",
                priority: 146,
                isActive: phase == .recording,
                progress: nil,
                updatedAt: Date(),
                lifecycle: LiveActivityLifecycleMetadata(
                    authority: .systemAPI,
                    startEvidence: "ScreenCaptureKit emitted a video frame",
                    progressEvidence: "retimed ScreenCaptureKit presentation timestamps",
                    completionEvidence: "AVAssetWriter finalized and AVFoundation validated output",
                    dismissPolicy: .untilSourceEnds,
                    supportsCancellation: true
                )
            )
        )
    }

    private func publishCapability(
        permission: IslandCapabilityPermissionState? = nil,
        health: IslandCapabilityHealth? = nil
    ) {
        let granted = CGPreflightScreenCaptureAccess()
        capabilities.update(
            IslandCapabilitySnapshot(
                id: .screenRecording,
                permission: permission ?? (granted ? .granted : .required),
                availability: .available,
                health: health ??
                    (phase == .failed
                        ? .degraded(message: statusText)
                        : .healthy),
                supportedActions: isActuallyCapturing
                    ? [.stop]
                    : [.start, .openSettings],
                isActive: isActuallyCapturing,
                statusText: statusText
            )
        )
    }

    nonisolated static func formatDuration(_ seconds: TimeInterval) -> String {
        let clamped = max(Int(seconds.rounded(.down)), 0)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func makeOutputURL() throws -> URL {
        let root = try FileManager.default.url(
            for: .moviesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent(
            "DynamicIsland Recordings",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return directory.appendingPathComponent(
            "DynamicIsland Recording \(formatter.string(from: Date())).mp4"
        )
    }

    private static func validateRecording(at url: URL) async throws -> TimeInterval {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScreenRecordingError.invalidOutput
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let seconds = CMTimeGetSeconds(duration)
        guard !tracks.isEmpty, seconds.isFinite, seconds > 0 else {
            throw ScreenRecordingError.invalidOutput
        }
        return seconds
    }

    nonisolated static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    nonisolated static func backingScale(for frame: CGRect) -> CGFloat {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        guard let screen else { return 1 }
        return backingScale(
            forDisplayID: displayID(for: screen),
            fallback: screen.backingScaleFactor
        )
    }

    nonisolated static func backingScale(
        forDisplayID displayID: CGDirectDisplayID?,
        fallback: CGFloat
    ) -> CGFloat {
        guard let displayID, let mode = CGDisplayCopyDisplayMode(displayID) else {
            return max(fallback, 1)
        }
        let logicalWidth = max(CGFloat(mode.width), 1)
        let logicalHeight = max(CGFloat(mode.height), 1)
        let sx = CGFloat(mode.pixelWidth) / logicalWidth
        let sy = CGFloat(mode.pixelHeight) / logicalHeight
        let scale = min(sx, sy)
        return scale.isFinite && scale > 0 ? scale : max(fallback, 1)
    }
}
