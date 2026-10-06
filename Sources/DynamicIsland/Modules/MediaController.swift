import AppKit
import Foundation
import SwiftUI

enum MediaArtworkFlipDirection: String, Equatable {
    case next
    case previous
}

struct MediaArtworkFlipRequest: Identifiable {
    let id = UUID()
    let direction: MediaArtworkFlipDirection
    let sourceArtworkKey: String?
    let sourceTitle: String
    let requestedAt: Date
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }
}

struct ArtworkPresentationSnapshot: Equatable {
    let image: NSImage?
    let identity: String
    let fingerprint: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity &&
            lhs.fingerprint == rhs.fingerprint &&
            (lhs.image == nil) == (rhs.image == nil)
    }
}

enum ArtworkFlipPhase: Equatable {
    case idle
    case firstHalf
    case secondHalf
}

enum ArtworkFlipPresentationEffect: Equatable {
    case none
    case displayedDirectly(requestID: UUID?)
    case firstHalfStarted(generation: Int, direction: MediaArtworkFlipDirection)
    case queued
    case midpointCommitted(requestID: UUID?)
    case transitionCompleted
    case staleTransitionDiscarded
}

struct ArtworkFlipPresentationState: Equatable {
    private struct QueuedTransition: Equatable {
        let snapshot: ArtworkPresentationSnapshot
        let direction: MediaArtworkFlipDirection?
        let requestID: UUID?
        let shouldAnimate: Bool
    }

    private(set) var displayed: ArtworkPresentationSnapshot?
    private(set) var pending: ArtworkPresentationSnapshot?
    private(set) var phase: ArtworkFlipPhase = .idle
    private(set) var direction: MediaArtworkFlipDirection?
    private(set) var generation = 0
    private(set) var pendingRequestID: UUID?
    private var queued: QueuedTransition?

    init(initial: ArtworkPresentationSnapshot? = nil) {
        displayed = initial
    }

    var queuedSnapshot: ArtworkPresentationSnapshot? {
        queued?.snapshot
    }

    mutating func receive(
        _ snapshot: ArtworkPresentationSnapshot,
        direction requestedDirection: MediaArtworkFlipDirection?,
        requestID: UUID?,
        shouldAnimate: Bool
    ) -> ArtworkFlipPresentationEffect {
        guard let displayed else {
            self.displayed = snapshot
            return .displayedDirectly(requestID: requestID)
        }

        if phase != .idle {
            queued = QueuedTransition(
                snapshot: snapshot,
                direction: requestedDirection,
                requestID: requestID,
                shouldAnimate: shouldAnimate
            )
            return .queued
        }

        guard isMeaningfulTransition(from: displayed, to: snapshot) else {
            self.displayed = snapshot
            return .displayedDirectly(requestID: requestID)
        }

        guard shouldAnimate, let requestedDirection else {
            self.displayed = snapshot
            return .displayedDirectly(requestID: requestID)
        }

        return stageFirstHalf(
            snapshot: snapshot,
            direction: requestedDirection,
            requestID: requestID
        )
    }

    mutating func commitMidpoint(generation callbackGeneration: Int) -> ArtworkFlipPresentationEffect {
        guard callbackGeneration == generation, phase == .firstHalf, let pending else {
            return .staleTransitionDiscarded
        }

        displayed = pending
        self.pending = nil
        phase = .secondHalf
        return .midpointCommitted(requestID: pendingRequestID)
    }

    mutating func complete(generation callbackGeneration: Int) -> ArtworkFlipPresentationEffect {
        guard callbackGeneration == generation, phase == .secondHalf else {
            return .staleTransitionDiscarded
        }

        phase = .idle
        direction = nil
        pendingRequestID = nil

        guard let queued else {
            return .transitionCompleted
        }
        self.queued = nil

        if displayed?.identity == queued.snapshot.identity {
            displayed = queued.snapshot
            return .displayedDirectly(requestID: queued.requestID)
        }

        return receive(
            queued.snapshot,
            direction: queued.direction,
            requestID: queued.requestID,
            shouldAnimate: queued.shouldAnimate
        )
    }

    private mutating func stageFirstHalf(
        snapshot: ArtworkPresentationSnapshot,
        direction: MediaArtworkFlipDirection,
        requestID: UUID?
    ) -> ArtworkFlipPresentationEffect {
        generation += 1
        pending = snapshot
        phase = .firstHalf
        self.direction = direction
        pendingRequestID = requestID
        return .firstHalfStarted(generation: generation, direction: direction)
    }

    private func isMeaningfulTransition(
        from old: ArtworkPresentationSnapshot,
        to new: ArtworkPresentationSnapshot
    ) -> Bool {
        guard old.fingerprint != new.fingerprint else { return false }
        return old.image != nil || new.image != nil
    }
}

@MainActor
final class ArtworkPresentationCoordinator: ObservableObject {
    static let halfDuration: TimeInterval = 0.19

    @Published private(set) var state = ArtworkFlipPresentationState()
    @Published private(set) var rotationDegrees = 0.0

    var displayedSnapshot: ArtworkPresentationSnapshot? {
        state.displayed
    }

    func receiveRawArtwork(
        _ snapshot: ArtworkPresentationSnapshot,
        request: MediaArtworkFlipRequest?,
        reduceMotion: Bool,
        consumeRequest: @escaping (UUID) -> Void
    ) {
        debugArtworkFlip(
            "raw artwork received identity=\(snapshot.identity) fingerprint=\(snapshot.fingerprint)"
        )

        let validRequest = request.flatMap { $0.isExpired ? nil : $0 }
        let requestID = request?.id
        var nextState = state
        let effect = nextState.receive(
            snapshot,
            direction: validRequest?.direction,
            requestID: requestID,
            shouldAnimate: validRequest != nil && !reduceMotion
        )
        state = nextState
        handle(effect, consumeRequest: consumeRequest)
    }

    private func handle(
        _ effect: ArtworkFlipPresentationEffect,
        consumeRequest: @escaping (UUID) -> Void
    ) {
        switch effect {
        case .none:
            break
        case .displayedDirectly(let requestID):
            if let requestID {
                consumeRequest(requestID)
            }
            debugArtworkFlip(
                "transition completed direct identity=\(state.displayed?.identity ?? "nil")"
            )
        case .queued:
            debugArtworkFlip(
                "update queued identity=\(state.queuedSnapshot?.identity ?? "nil") generation=\(state.generation)"
            )
        case .firstHalfStarted(let generation, let direction):
            debugArtworkFlip(
                "latency T4 flip request emitted identity=\(state.pending?.identity ?? "nil") generation=\(generation)"
            )
            startFirstHalf(
                generation: generation,
                direction: direction,
                consumeRequest: consumeRequest
            )
        case .midpointCommitted, .transitionCompleted, .staleTransitionDiscarded:
            break
        }
    }

    private func startFirstHalf(
        generation: Int,
        direction: MediaArtworkFlipDirection,
        consumeRequest: @escaping (UUID) -> Void
    ) {
        let firstHalfDegrees = direction == .next ? -90.0 : 90.0
        debugArtworkFlip(
            "latency T5 visible first half started direction=\(direction.rawValue) generation=\(generation)"
        )

        withAnimation(.easeInOut(duration: Self.halfDuration)) {
            rotationDegrees = firstHalfDegrees
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.halfDuration) { [weak self] in
            self?.commitMidpoint(
                generation: generation,
                direction: direction,
                consumeRequest: consumeRequest
            )
        }
    }

    private func commitMidpoint(
        generation: Int,
        direction: MediaArtworkFlipDirection,
        consumeRequest: @escaping (UUID) -> Void
    ) {
        var nextState = state
        let effect = nextState.commitMidpoint(generation: generation)
        guard case .midpointCommitted(let requestID) = effect else {
            debugArtworkFlip("stale transition discarded boundary=midpoint generation=\(generation)")
            return
        }

        let secondHalfStartDegrees = direction == .next ? 90.0 : -90.0
        withTransaction(Transaction(animation: nil)) {
            state = nextState
            rotationDegrees = secondHalfStartDegrees
        }
        if let requestID {
            consumeRequest(requestID)
        }
        debugArtworkFlip(
            "midpoint artwork committed identity=\(state.displayed?.identity ?? "nil") generation=\(generation)"
        )
        debugArtworkFlip(
            "second half started direction=\(direction.rawValue) generation=\(generation)"
        )

        withAnimation(.easeInOut(duration: Self.halfDuration)) {
            rotationDegrees = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.halfDuration) { [weak self] in
            self?.completeTransition(generation: generation, consumeRequest: consumeRequest)
        }
    }

    private func completeTransition(
        generation: Int,
        consumeRequest: @escaping (UUID) -> Void
    ) {
        let completedIdentity = state.displayed?.identity ?? "nil"
        var nextState = state
        let effect = nextState.complete(generation: generation)
        guard effect != .staleTransitionDiscarded else {
            debugArtworkFlip("stale transition discarded boundary=completion generation=\(generation)")
            return
        }

        state = nextState
        debugArtworkFlip(
            "transition completed identity=\(completedIdentity) generation=\(generation)"
        )
        handle(effect, consumeRequest: consumeRequest)
    }

    private func debugArtworkFlip(_ message: String) {
        #if DEBUG
        print("[ArtworkFlip][\(String(format: "%.6f", ProcessInfo.processInfo.systemUptime))] \(message)")
        #endif
    }
}

private final class MediaRefreshTimerLifetime: @unchecked Sendable {
    var timer: Timer?

    deinit {
        timer?.invalidate()
    }
}

@MainActor
final class MediaController: ObservableObject {
    @Published private(set) var title = "Nothing Playing"
    @Published private(set) var artist = "Open Spotify or Music"
    @Published private(set) var isPlaying = false
    @Published private(set) var sourceName = "Media"
    @Published private(set) var artworkImage: NSImage?
    @Published private(set) var playbackPosition: Double = 0
    @Published private(set) var duration: Double = 1
    @Published private(set) var volume: Double = 0.5
    @Published private(set) var isVolumeControlAvailable = false
    @Published private(set) var hasActiveMediaSource = false
    @Published private(set) var isTransportControlAvailable = false
    @Published private(set) var isSeekControlAvailable = false
    @Published private(set) var hasPlaybackProgress = false
    @Published private(set) var sourceKind: MediaSourceKind = .unknown
    @Published private(set) var sourceBundleIdentifier: String?
    @Published private(set) var artworkKey: String?
    @Published private(set) var artworkImageKey: String?
    @Published private(set) var artworkImageRevision = 0
    @Published private(set) var artworkFlipRequest: MediaArtworkFlipRequest?
    let artworkPresentation = ArtworkPresentationCoordinator()

    private let systemNowPlayingProvider: any MediaDetectionProvider
    private let automationExecutor: MediaAutomationExecutor
    private let youtubeMetadataProvider = YouTubeMetadataProvider()
    private var activePlayer: MediaPlayer = .spotify
    private let refreshTimerLifetime = MediaRefreshTimerLifetime()
    private var currentArtworkURL: String?
    private var currentArtworkKey: String?
    private var currentArtworkImageKey: String?
    private var currentArtworkSourceIdentity: MediaSourceIdentity?
    private var artworkCache: [String: NSImage] = [:]
    private var currentYouTubeVideoID: String?
    private var lastPlaybackIdentity: String?
    private var lastPlaybackPosition: Double?
    private var lastPlaybackAdvancedAt: Date?
    private var lastSelectedSourceIdentity: MediaSourceIdentity?
    private var lastSelectedSourceSelectedAt: Date?
    private var lastSelectedSourceWasPlaying = false
    private var selectedPublishGeneration = 0
    private var pendingPausedSwitchIdentity: MediaSourceIdentity?
    private var pendingPausedSwitchFirstSeenAt: Date?
    private var pendingPausedSwitchCount = 0
    private var isScrubbing = false
    private var refreshCoordinator = MediaRefreshCoordinator()
    private var refreshCandidatesByGeneration: [Int: [MediaCandidate]] = [:]

    enum MediaPlayer: String, CaseIterable {
        case spotify = "Spotify"
        case music = "Music"

        var displayName: String {
            rawValue
        }

        var playPauseCommand: String {
            switch self {
            case .spotify:
                "playpause"
            case .music:
                "playpause"
            }
        }
    }

    init(
        automationExecutor: MediaAutomationExecutor = MediaAutomationExecutor(),
        systemNowPlayingProvider: any MediaDetectionProvider = NowPlayingMediaProvider(),
        startsAutomatically: Bool = true
    ) {
        self.automationExecutor = automationExecutor
        self.systemNowPlayingProvider = systemNowPlayingProvider
        guard startsAutomatically else { return }
        refresh()
        refreshTimerLifetime.timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        refreshCoordinator.invalidate()
        automationExecutor.invalidate()
    }

    // MARK: Settings preview role

    /// True only for the inert controller Settings uses to render the
    /// production media components with a labeled sample track. It never
    /// polls providers and never sends commands.
    private(set) var isSettingsPreview = false

    static func settingsPreview() -> MediaController {
        let controller = MediaController(startsAutomatically: false)
        controller.isSettingsPreview = true
        controller.title = "Preview Track"
        controller.artist = "Sample Artist"
        controller.sourceName = "Settings Preview"
        controller.isPlaying = true
        controller.hasActiveMediaSource = true
        controller.isTransportControlAvailable = true
        controller.isSeekControlAvailable = true
        controller.isVolumeControlAvailable = true
        controller.hasPlaybackProgress = true
        controller.playbackPosition = 74
        controller.duration = 212
        controller.volume = 0.6
        return controller
    }

    func refresh() {
        guard !isSettingsPreview else { return }
        guard let start = refreshCoordinator.request() else { return }
        beginRefresh(start)
    }

    private func beginRefresh(_ start: MediaRefreshCoordinator.Start) {
        logProviderAttempt("System Now Playing")
        let provider = systemNowPlayingProvider
        Task { @MainActor [weak self, provider] in
            let snapshot = await provider.snapshot()
            self?.continueRefresh(start, systemSnapshot: snapshot)
        }
    }

    private func continueRefresh(
        _ start: MediaRefreshCoordinator.Start,
        systemSnapshot: MediaSnapshot?
    ) {
        var candidates: [MediaCandidate] = []

        if let snapshot = systemSnapshot {
            logProviderResult("System Now Playing", succeeded: true, snapshot: snapshot)
            let candidate = MediaCandidate(providerName: "System Now Playing", snapshot: snapshot)
            candidates.append(candidate)
            publishImmediateSystemArtworkIfSafe(candidate, generation: start.generation)
        } else {
            logProviderResult("System Now Playing", succeeded: false)
        }

        guard refreshCoordinator.accepts(start.generation) else {
            finishRefresh(start.generation)
            return
        }

        logProviderAttempt("Spotify AppleScript")
        logProviderAttempt("Music AppleScript")
        logProviderAttempt("Browser AppleScript")
        let browsers = runningBrowserOperations()
        refreshCandidatesByGeneration[start.generation] = candidates

        let request = MediaAutomationDetectionRequest(
            spotify: MediaAutomationOperation(target: .spotify, source: playerScript(for: .spotify)),
            music: MediaAutomationOperation(target: .music, source: playerScript(for: .music)),
            browsers: browsers,
            cancellation: start.cancellation
        )
        automationExecutor.submitDetection(request) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.applyAutomationRefresh(result, generation: start.generation)
            }
        }
    }

    private func publishImmediateSystemArtworkIfSafe(
        _ candidate: MediaCandidate,
        generation: Int
    ) {
        guard refreshCoordinator.accepts(generation),
              MediaImmediateSystemHandoff.canPublish(
                  candidate: candidate,
                  currentIdentity: lastSelectedSourceIdentity
              )
        else {
            return
        }

        debugArtworkFlip(
            "System Now Playing confirmed same-source track and embedded artwork; publishing before automation arbitration"
        )
        publishSelectedCandidate(
            candidate,
            reason: "System Now Playing confirmed same-source artwork handoff"
        )
    }

    private func applyAutomationRefresh(
        _ result: MediaAutomationDetectionResult,
        generation: Int
    ) {
        var candidates = refreshCandidatesByGeneration.removeValue(forKey: generation) ?? []
        guard refreshCoordinator.accepts(generation) else {
            finishRefresh(generation)
            return
        }

        if let spotify = readPlayerCandidate(.spotify, execution: result.spotify) {
            candidates.append(spotify)
        }
        if let music = readPlayerCandidate(.music, execution: result.music) {
            candidates.append(music)
        }
        if let browser = readBrowserCandidate(from: result.browsers) {
            candidates.append(browser)
        }

        guard let selected = selectBestSnapshot(from: candidates) else {
            clearMediaState()
            finishRefresh(generation)
            return
        }

        let reason = MediaArbitrator.selectionReason(
            selected,
            candidates: candidates,
            currentIdentity: lastSelectedSourceIdentity
        )
        guard let publishCandidate = candidateConfirmedForPublishing(selected, reason: reason) else {
            finishRefresh(generation)
            return
        }
        publishSelectedCandidate(publishCandidate.candidate, reason: publishCandidate.reason)
        finishRefresh(generation)
    }

    private func finishRefresh(_ generation: Int) {
        refreshCandidatesByGeneration[generation] = nil
        if let next = refreshCoordinator.complete(generation) {
            beginRefresh(next)
        }
    }

    private func clearMediaState() {
        title = "Nothing Playing"
        artist = "Open Spotify or Music"
        isPlaying = false
        sourceName = "Media"
        clearArtwork(reason: "clearing inactive media")
        lastPlaybackIdentity = nil
        lastPlaybackPosition = nil
        lastPlaybackAdvancedAt = nil
        playbackPosition = 0
        duration = 1
        isVolumeControlAvailable = false
        hasActiveMediaSource = false
        isTransportControlAvailable = false
        isSeekControlAvailable = false
        hasPlaybackProgress = false
        sourceKind = .unknown
        sourceBundleIdentifier = nil
        currentYouTubeVideoID = nil
        lastSelectedSourceIdentity = nil
        lastSelectedSourceSelectedAt = nil
        lastSelectedSourceWasPlaying = false
        selectedPublishGeneration += 1
        resetPendingPausedSwitch()
        logProviderResult("All providers", succeeded: false)
        logMediaDetection(source: "none")
    }

    func playPause() {
        guard isTransportControlAvailable else { return }
        send(command: activePlayer.playPauseCommand, to: activePlayer)
        refresh()
    }

    /// Plays a Spotify item through Spotify's own scripting dictionary
    /// (`play track`). Only well-formed Spotify URIs are accepted, so no
    /// caller text is ever interpolated into the script.
    @discardableResult
    func playSpotifyURI(_ uri: String) -> Bool {
        guard Self.isValidSpotifyURI(uri) else { return false }
        send(command: "play track \"\(uri)\"", to: .spotify)
        refresh()
        return true
    }

    nonisolated static func isValidSpotifyURI(_ uri: String) -> Bool {
        uri.range(
            of: #"^spotify:(track|album|playlist|episode|show|artist):[A-Za-z0-9]{8,40}$"#,
            options: .regularExpression
        ) != nil
    }

    func nextTrack() {
        guard isTransportControlAvailable else { return }
        requestArtworkFlip(direction: .next, reason: "nextTrack command")
        sendTransportCommand(
            "next track",
            to: activePlayer,
            artworkRequestID: artworkFlipRequest?.id
        )
    }

    func previousTrack() {
        guard isTransportControlAvailable else { return }
        requestArtworkFlip(direction: .previous, reason: "previousTrack command")
        sendTransportCommand(
            "previous track",
            to: activePlayer,
            artworkRequestID: artworkFlipRequest?.id
        )
    }

    private func sendTransportCommand(
        _ command: String,
        to player: MediaPlayer,
        artworkRequestID: UUID?
    ) {
        debugArtworkFlip("latency T0 transport command submitted command=\(command)")
        send(command: command, to: player) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard result.failure == nil else {
                    if let artworkRequestID {
                        self.consumeArtworkFlipRequest(id: artworkRequestID)
                    }
                    return
                }
                self.debugArtworkFlip("transport command succeeded; requesting immediate refresh command=\(command)")
                self.refresh()
            }
        }
    }

    private func requestArtworkFlipIfNeeded(direction: MediaArtworkFlipDirection, reason: String) {
        if let existingRequest = artworkFlipRequest, !existingRequest.isExpired {
            debugArtworkFlip(
                "kept pending flip direction=\(existingRequest.direction.rawValue) reason=\(reason)"
            )
            return
        }

        requestArtworkFlip(direction: direction, reason: reason)
    }

    private func requestArtworkFlip(direction: MediaArtworkFlipDirection, reason: String) {
        let request = MediaArtworkFlipRequest(
            direction: direction,
            sourceArtworkKey: artworkImageKey ?? artworkKey,
            sourceTitle: title,
            requestedAt: Date(),
            expiresAt: Date().addingTimeInterval(6.0)
        )

        artworkFlipRequest = request

        debugArtworkFlip(
            "pending direction=\(direction.rawValue) reason=\(reason) sourceArtworkKey=\(request.sourceArtworkKey ?? "nil") sourceTitle=\(title)"
        )
    }

    func consumeArtworkFlipRequest(id: UUID) {
        guard artworkFlipRequest?.id == id else { return }
        artworkFlipRequest = nil
    }

    func updateScrubPosition(_ position: Double) {
        guard isSeekControlAvailable else { return }
        isScrubbing = true
        playbackPosition = min(max(0, position), duration)
    }

    func seek(to position: Double) {
        guard isSeekControlAvailable else { return }
        let clampedPosition = min(max(0, position), duration)
        send(command: "set player position to \(clampedPosition)", to: activePlayer)
        isScrubbing = false
        refresh()
    }

    func setVolume(_ value: Double) {
        let clampedVolume = min(max(0, value), 1)
        volume = clampedVolume

        // Browser and future non-scriptable sources can expose playback state
        // without app volume control. Keep the slider safe in those cases.
        guard isVolumeControlAvailable else { return }

        let scriptVolume = Int((clampedVolume * 100).rounded())
        send(command: "set sound volume to \(scriptVolume)", to: activePlayer, isVolume: true)
        refresh()
    }

    func openMusicApp() {
        AppLaunchService.open(.music)
    }

    func openSpotifyApp() {
        AppLaunchService.open(.spotify)
    }

    func openYouTube() {
        AppLaunchService.openYouTube(preferredBrowserBundleIdentifier: sourceBundleIdentifier)
    }

    @discardableResult
    func openActiveMediaSource() -> Bool {
        let target = MediaSourceOpenTarget.resolve(
            sourceKind: sourceKind,
            sourceName: sourceName,
            bundleIdentifier: sourceBundleIdentifier
        )
        logMediaSourceOpenRequested(target: target)

        guard let target else {
            logMediaSourceOpenResult(targetDescription: "none", fallbackUsed: false, succeeded: false)
            return false
        }

        let succeeded: Bool
        switch target {
        case .app(let app):
            succeeded = AppLaunchService.open(app)
            logMediaSourceOpenResult(
                targetDescription: app.displayName,
                fallbackUsed: false,
                succeeded: succeeded
            )
        case .bundleIdentifier(let bundleIdentifier):
            succeeded = AppLaunchService.openApp(bundleIdentifier: bundleIdentifier)
            logMediaSourceOpenResult(
                targetDescription: bundleIdentifier,
                fallbackUsed: false,
                succeeded: succeeded
            )
        case .youtube:
            succeeded = AppLaunchService.openYouTube()
            logMediaSourceOpenResult(
                targetDescription: "YouTube default browser",
                fallbackUsed: true,
                succeeded: succeeded
            )
        }
        return succeeded
    }

    private func playerScript(for player: MediaPlayer) -> String {
        """
        with timeout of 1 seconds
            tell application "\(player.rawValue)"
                if it is running then
                    set playbackState to player state as text
                    try
                        set trackName to name of current track
                        if trackName is not "" then
                            return trackName & "||" & (artist of current track) & "||" & playbackState & "||\(player.displayName)" & "||" & (player position as text) & "||" & (\(durationExpression(for: player)) as text) & "||" & \(artworkExpression(for: player)) & "||" & (sound volume as text)
                        end if
                    end try
                end if
            end tell
        end timeout
        return ""
        """
    }

    private func readPlayerCandidate(
        _ player: MediaPlayer,
        execution: MediaAutomationScriptResult
    ) -> MediaCandidate? {
        if !execution.output.isEmpty {
            let parts = execution.output.components(separatedBy: "||")
            if parts.count >= 4 {
                let trackTitle = parts[0]
                let trackArtist = parts[1]
                let reportedPlaybackState = parts[2]
                let parsedPlaybackPosition = Double(parts[safe: 4] ?? "") ?? 0
                let parsedDuration = max(1, Double(parts[safe: 5] ?? "") ?? 1)
                let reportedVolume = Double(parts[safe: 7] ?? "")
                let snapshot = MediaSnapshot(
                    sourceKind: player == .spotify ? .spotify : .music,
                    sourceName: parts[3],
                    bundleIdentifier: bundleIdentifier(for: player),
                    title: trackTitle,
                    artist: trackArtist,
                    album: nil,
                    artwork: nil,
                    isPlaying: reportedPlaybackState == "playing",
                    duration: parsedDuration,
                    elapsedTime: parsedPlaybackPosition,
                    transportAvailable: true,
                    seekAvailable: true,
                    volumeAvailable: true
                )
                return MediaCandidate(
                    providerName: "\(player.displayName) AppleScript",
                    snapshot: snapshot,
                    hasPlaybackProgress: true,
                    artworkURL: parts[safe: 6],
                    volume: reportedVolume.map { min(max(0, $0 / 100), 1) },
                    activePlayer: player
                )
            }
        }
        return nil
    }

    private func browserTargets() -> [BrowserScriptTarget] {
        [
            BrowserScriptTarget(
                applicationName: "Brave Browser",
                bundleIdentifier: "com.brave.Browser",
                usesChromeScripting: true
            ),
            BrowserScriptTarget(
                applicationName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                usesChromeScripting: false
            ),
            BrowserScriptTarget(
                applicationName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                usesChromeScripting: true
            ),
            BrowserScriptTarget(
                applicationName: "Arc",
                bundleIdentifier: "company.thebrowser.Browser",
                usesChromeScripting: true
            ),
            BrowserScriptTarget(
                applicationName: "Microsoft Edge",
                bundleIdentifier: "com.microsoft.edgemac",
                usesChromeScripting: true
            )
        ]
    }

    private func runningBrowserOperations() -> [MediaAutomationBrowserOperation] {
        browserTargets().compactMap { browser in
            let isRunning = isApplicationRunning(browser)
            logBrowserDetectionAttempt(browser: browser, isRunning: isRunning, phase: "start")
            guard isRunning else { return nil }
            return MediaAutomationBrowserOperation(
                applicationName: browser.applicationName,
                bundleIdentifier: browser.bundleIdentifier,
                source: browserScript(for: browser)
            )
        }
    }

    private func readBrowserCandidate(
        from results: [MediaAutomationBrowserResult]
    ) -> MediaCandidate? {
        for browserResult in results {
            guard let browser = browserTargets().first(where: {
                $0.bundleIdentifier == browserResult.bundleIdentifier
            }) else { continue }
            let execution = browserResult.result
            let isRunning = true
            logBrowserDetectionAttempt(
                browser: browser,
                isRunning: isRunning,
                phase: "script-result",
                rawResult: execution.output,
                errorDescription: execution.errorDescription
            )

            guard execution.output.hasPrefix("media||") else {
                continue
            }

            let parts = execution.output.components(separatedBy: "||")
            if parts.count >= 6 {
                let browserTitle = parts[safe: 1]?.isEmpty == false ? parts[1] : "Browser Audio"
                let browserSource = parts[safe: 2]?.isEmpty == false ? parts[2] : browser.applicationName
                let playbackState = parts[safe: 5] ?? "paused"
                let pageURL = parts[safe: 6] ?? ""
                let youtubeVideoID = YouTubeMetadataProvider.videoID(from: pageURL)
                let parsedPosition = Double(parts[safe: 3] ?? "")
                let parsedDuration = Double(parts[safe: 4] ?? "")
                let hasRealProgress = parsedDuration.map { $0.isFinite && $0 > 1 } == true
                let playbackProvider = playbackState == "unknown" ? "fallback unknown" : "Browser JS"
                let snapshot = MediaSnapshot(
                    sourceKind: .browser,
                    sourceName: browserSource,
                    bundleIdentifier: browser.bundleIdentifier,
                    title: browserTitle,
                    artist: browserSource,
                    album: nil,
                    artwork: nil,
                    isPlaying: playbackState == "playing",
                    duration: hasRealProgress ? max(1, parsedDuration ?? 1) : nil,
                    elapsedTime: hasRealProgress ? (parsedPosition ?? 0) : nil,
                    transportAvailable: false,
                    seekAvailable: false,
                    volumeAvailable: false
                )
                logBrowserDetectionAttempt(
                    browser: browser,
                    isRunning: isRunning,
                    phase: "parsed-session",
                    rawResult: execution.output
                )
                logBrowserPlaybackSelection(
                    provider: playbackProvider,
                    pageURL: pageURL,
                    videoID: youtubeVideoID,
                    hasProgress: hasRealProgress,
                    playbackState: playbackState
                )
                return MediaCandidate(
                    providerName: "Browser AppleScript",
                    snapshot: snapshot,
                    hasPlaybackProgress: hasRealProgress,
                    youtubePageURL: pageURL,
                    youtubeVideoID: youtubeVideoID,
                    playbackProvider: playbackProvider
                )
            }
        }
        return nil
    }

    private func browserScript(for browser: BrowserScriptTarget) -> String {
        let mediaMetadataCheck = """
        (() => { const clean = (value) => String(value || '').replace(/\\|\\|/g, ' ').trim(); const host = clean(location.hostname); const href = clean(location.href); const isYouTube = /(^|\\.)youtube\\.com$|(^|\\.)youtu\\.be$/.test(location.hostname); const isYouTubeWatch = isYouTube && /\\/watch(\\?|$)/.test(location.pathname + location.search); const candidates = Array.from(document.querySelectorAll('video,audio')).filter((element) => { const hasDuration = Number.isFinite(element.duration) && element.duration > 0; const hasProgress = Number.isFinite(element.currentTime) && element.currentTime > 0; const hasSource = Boolean(element.currentSrc || element.src); return !element.ended && (element.readyState >= 1 || hasDuration || hasProgress || hasSource); }); candidates.sort((first, second) => Number(first.paused) - Number(second.paused)); const media = candidates[0]; if (!media && !isYouTubeWatch) { return ''; } const rawTitle = clean(document.title).replace(/ - YouTube$/, ''); const title = rawTitle || (isYouTube ? 'YouTube' : 'Browser Audio'); const source = isYouTube ? 'YouTube' : (host || 'Browser'); const current = media && Number.isFinite(media.currentTime) ? String(media.currentTime) : ''; const duration = media && Number.isFinite(media.duration) && media.duration > 0 ? String(media.duration) : ''; const state = media ? ((!media.paused && !media.ended) ? 'playing' : 'paused') : 'unknown'; return ['media', title, source, current, duration, state, href].join('||'); })()
        """
        if browser.usesChromeScripting {
            return """
            with timeout of 1 seconds
                tell application "\(browser.applicationName)"
                    if it is running then
                        repeat with browserWindow in windows
                            repeat with browserTab in tabs of browserWindow
                                try
                                    set mediaState to execute browserTab javascript "\(Self.appleScriptEscaped(mediaMetadataCheck))"
                                    if mediaState is not "" then return mediaState
                                end try
                                try
                                    set tabURL to URL of browserTab as text
                                    if tabURL contains "youtube.com/watch" or tabURL contains "youtu.be/" then
                                        set tabTitle to title of browserTab as text
                                        return "media||" & tabTitle & "||YouTube||||||unknown||" & tabURL
                                    end if
                                end try
                            end repeat
                        end repeat
                    end if
                end tell
            end timeout
            return ""
            """
        }

        return """
        with timeout of 1 seconds
            tell application "\(browser.applicationName)"
                if it is running then
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                set mediaState to do JavaScript "\(Self.appleScriptEscaped(mediaMetadataCheck))" in browserTab
                                if mediaState is not "" then return mediaState
                            end try
                            try
                                set tabURL to URL of browserTab as text
                                if tabURL contains "youtube.com/watch" or tabURL contains "youtu.be/" then
                                    set tabTitle to name of browserTab as text
                                    return "media||" & tabTitle & "||YouTube||||||unknown||" & tabURL
                                end if
                            end try
                        end repeat
                    end repeat
                end if
            end tell
        end timeout
        return ""
        """
    }

    private func artworkExpression(for player: MediaPlayer) -> String {
        switch player {
        case .spotify:
            "artwork url of current track"
        case .music:
            "\"\""
        }
    }

    private func durationExpression(for player: MediaPlayer) -> String {
        switch player {
        case .spotify:
            "((duration of current track) / 1000)"
        case .music:
            "duration of current track"
        }
    }

    private func bundleIdentifier(for player: MediaPlayer) -> String {
        switch player {
        case .spotify:
            "com.spotify.client"
        case .music:
            "com.apple.Music"
        }
    }

    private func selectBestSnapshot(from candidates: [MediaCandidate]) -> MediaCandidate? {
        guard !candidates.isEmpty else { return nil }
        let ranked = candidates.map { candidate in
            (candidate, MediaArbitrator.score(candidate, currentIdentity: lastSelectedSourceIdentity))
        }

        #if DEBUG
        for (candidate, score) in ranked {
            logCandidate(candidate, score: score)
        }
        #endif

        if let selected = MediaArbitrator.selectBestCandidate(
            from: candidates,
            currentIdentity: lastSelectedSourceIdentity
        ) {
            let reason = MediaArbitrator.selectionReason(
                selected,
                candidates: candidates,
                currentIdentity: lastSelectedSourceIdentity
            )
            if reason == "paused current source still valid" {
                logPausedHysteresisKept(current: selected, candidates: candidates)
            }
            logSelection(
                selected,
                score: MediaArbitrator.score(selected, currentIdentity: lastSelectedSourceIdentity),
                reason: reason
            )
            return selected
        }

        return nil
    }

    private func candidateConfirmedForPublishing(
        _ candidate: MediaCandidate,
        reason: String
    ) -> (candidate: MediaCandidate, reason: String)? {
        let identityChanged = candidate.identity != lastSelectedSourceIdentity
        if !identityChanged {
            resetPendingPausedSwitch()
            return (candidate, reason)
        }

        if candidate.snapshot.isPlaying {
            resetPendingPausedSwitch()
            return (candidate, reason)
        }

        let decision = MediaPausedSwitchGate.decision(
            candidateIdentity: candidate.identity,
            currentIdentity: lastSelectedSourceIdentity,
            currentWasPlaying: lastSelectedSourceWasPlaying,
            pendingIdentity: pendingPausedSwitchIdentity,
            pendingFirstSeenAt: pendingPausedSwitchFirstSeenAt,
            pendingCount: pendingPausedSwitchCount,
            now: Date()
        )

        pendingPausedSwitchIdentity = candidate.identity
        pendingPausedSwitchFirstSeenAt = decision.firstSeenAt
        pendingPausedSwitchCount = decision.count

        guard decision.shouldPublish else {
            logPausedSwitchPending(candidate, reason: decision.reason)
            return nil
        }

        resetPendingPausedSwitch()
        return (candidate, decision.reason)
    }

    private func resetPendingPausedSwitch() {
        pendingPausedSwitchIdentity = nil
        pendingPausedSwitchFirstSeenAt = nil
        pendingPausedSwitchCount = 0
    }

    private func publishSelectedCandidate(_ candidate: MediaCandidate, reason: String) {
        let previousSource = sourceName
        let previousTitle = title
        let previousPlaying = isPlaying
        let previousYouTubeVideoID = currentYouTubeVideoID
        let previousIdentity = lastSelectedSourceIdentity
        let snapshot = candidate.snapshot
        let identityChanged = candidate.identity != lastSelectedSourceIdentity
        if identityChanged {
            selectedPublishGeneration += 1
            lastSelectedSourceSelectedAt = Date()
        }
        let publishGeneration = selectedPublishGeneration
        let sameYouTubeVideo = candidate.youtubeVideoID != nil &&
            candidate.youtubeVideoID == previousYouTubeVideoID
        let hadDisplayedArtwork = artworkImage != nil && artworkImageKey != nil

        logSelectedCandidatePublish(candidate, reason: reason, identityChanged: identityChanged)
        if identityChanged {
            debugArtworkFlip(
                "latency T1 selected track identity observed identity=\(candidate.identity.debugDescription)"
            )
        }

        if identityChanged, previousIdentity != nil, hadDisplayedArtwork {
            requestArtworkFlipIfNeeded(
                direction: .next,
                reason: "detected selected media identity change"
            )
        }

        title = snapshot.title
        if sameYouTubeVideo,
           snapshot.artist == "YouTube",
           artist != "YouTube",
           !artist.isEmpty {
            // Keep the already enriched channel while the same YouTube video remains selected.
        } else {
            artist = snapshot.artist ?? snapshot.sourceName
        }
        sourceName = snapshot.sourceName
        sourceBundleIdentifier = snapshot.bundleIdentifier
        sourceKind = snapshot.sourceKind
        hasActiveMediaSource = true
        isPlaying = snapshot.isPlaying
        if !isScrubbing {
            playbackPosition = candidate.hasPlaybackProgress ? (snapshot.elapsedTime ?? 0) : 0
        }
        duration = candidate.hasPlaybackProgress ? max(1, snapshot.duration ?? 1) : 1
        isTransportControlAvailable = snapshot.transportAvailable
        isSeekControlAvailable = snapshot.seekAvailable
        isVolumeControlAvailable = snapshot.volumeAvailable
        hasPlaybackProgress = candidate.hasPlaybackProgress
        currentYouTubeVideoID = candidate.youtubeVideoID
        lastSelectedSourceIdentity = candidate.identity
        lastSelectedSourceWasPlaying = candidate.snapshot.isPlaying
        if let candidateVolume = candidate.volume {
            volume = candidateVolume
        }

        if let candidatePlayer = candidate.activePlayer {
            activePlayer = candidatePlayer
        } else {
            switch snapshot.sourceKind {
            case .spotify:
                activePlayer = .spotify
            case .music:
                activePlayer = .music
            case .browser, .system, .unknown:
                break
            }
        }

        publishArtwork(for: candidate, generation: publishGeneration, sourceChanged: identityChanged)

        if let youtubePageURL = candidate.youtubePageURL,
           let youtubeVideoID = candidate.youtubeVideoID {
            enrichYouTubeMetadata(
                pageURL: youtubePageURL,
                videoID: youtubeVideoID,
                identity: candidate.identity,
                generation: publishGeneration
            )
        }

        logSourceSwitch(
            previousIdentity: previousIdentity,
            previousSource: previousSource,
            previousTitle: previousTitle,
            previousPlaying: previousPlaying,
            selected: candidate
        )
        logSelectedProvider(candidate.providerName, snapshot: snapshot)
        logMediaDetection(source: snapshot.sourceName, usesPlaceholderArtwork: snapshot.artwork == nil)
    }

    private func enrichYouTubeMetadata(
        pageURL: String,
        videoID: String,
        identity: MediaSourceIdentity,
        generation: Int
    ) {
        logYouTubeMetadata(
            phase: "request",
            pageURL: pageURL,
            videoID: videoID,
            title: title,
            authorName: artist,
            thumbnailURLExists: false,
            thumbnailLoaded: artworkImage != nil
        )

        Task {
            guard let metadata = await youtubeMetadataProvider.metadata(for: pageURL) else {
                await MainActor.run {
                    self.logYouTubeMetadata(
                        phase: "unavailable",
                        pageURL: pageURL,
                        videoID: videoID,
                        title: self.title,
                        authorName: self.artist,
                        thumbnailURLExists: false,
                        thumbnailLoaded: self.artworkImage != nil
                    )
                }
                return
            }

            await MainActor.run {
                guard self.currentYouTubeVideoID == metadata.videoID,
                      MediaPublishGuard.canApplyAsyncUpdate(
                        selectedIdentity: self.lastSelectedSourceIdentity,
                        selectedGeneration: self.selectedPublishGeneration,
                        requestIdentity: identity,
                        requestGeneration: generation
                      )
                else {
                    self.logYouTubeMetadata(
                        phase: "discarded-not-selected",
                        pageURL: pageURL,
                        videoID: metadata.videoID,
                        title: metadata.title,
                        authorName: metadata.authorName,
                        thumbnailURLExists: metadata.thumbnailURL != nil,
                        thumbnailLoaded: metadata.thumbnailData != nil
                    )
                    return
                }

                if let metadataTitle = metadata.title, !metadataTitle.isEmpty {
                    self.title = metadataTitle
                }
                if let authorName = metadata.authorName, !authorName.isEmpty {
                    self.artist = authorName
                } else if self.artist.isEmpty {
                    self.artist = "YouTube"
                }
                if let thumbnailData = metadata.thumbnailData,
                   let image = NSImage(data: thumbnailData) {
                    let key = metadata.thumbnailURL
                        .map { "url:\($0.absoluteString)" } ??
                        "youtube:\(metadata.videoID)"
                    self.assignArtwork(
                        image,
                        key: key,
                        sourceIdentity: identity,
                        reason: "YouTube oEmbed thumbnail",
                        force: false
                    )
                }

                self.logYouTubeMetadata(
                    phase: "applied",
                    pageURL: pageURL,
                    videoID: metadata.videoID,
                    title: self.title,
                    authorName: self.artist,
                    thumbnailURLExists: metadata.thumbnailURL != nil,
                    thumbnailLoaded: self.artworkImage != nil
                )
                self.logMediaDetection(source: self.sourceName, usesPlaceholderArtwork: self.artworkImage == nil)
            }
        }
    }

    private func publishArtwork(for candidate: MediaCandidate, generation: Int, sourceChanged: Bool) {
        let key = candidate.artworkKey

        if let embeddedArtwork = candidate.snapshot.artwork,
           let key {
            debugArtworkFlip("latency T2 embedded artwork identity known key=\(key)")
            assignArtwork(
                embeddedArtwork,
                key: key,
                sourceIdentity: candidate.identity,
                reason: "selected candidate has embedded artwork",
                force: sourceChanged
            )
            return
        }

        if let key, let cachedArtwork = artworkCache[key] {
            debugArtworkFlip("latency T2 cached artwork identity known key=\(key)")
            assignArtwork(
                cachedArtwork,
                key: key,
                sourceIdentity: candidate.identity,
                reason: "cached artwork",
                force: sourceChanged
            )
            return
        }

        if let artworkURL = candidate.artworkURL,
           let key {
            debugArtworkFlip("latency T2 artwork URL known key=\(key)")
            if currentArtworkSourceIdentity == candidate.identity,
               currentArtworkKey == key,
               artworkImage != nil {
                logArtworkAssignment(
                    reason: "skipped unchanged artwork while load may be in flight",
                    sourceIdentity: candidate.identity,
                    oldKey: currentArtworkKey,
                    newKey: key,
                    skipped: true
                )
                return
            }

            currentArtworkKey = key
            artworkKey = key
            currentArtworkSourceIdentity = candidate.identity
            currentArtworkURL = artworkURL
            loadArtwork(
                from: artworkURL,
                key: key,
                identity: candidate.identity,
                generation: generation
            )
            return
        }

        if currentArtworkSourceIdentity == candidate.identity, artworkImage != nil {
            logArtworkAssignment(
                reason: "kept existing artwork because candidate artwork is temporarily unavailable",
                sourceIdentity: candidate.identity,
                oldKey: currentArtworkKey,
                newKey: key,
                skipped: true
            )
            return
        }

        let placeholderKey = candidate.artworkKey ?? "placeholder:\(candidate.identity.debugDescription)"
        let oldKey = currentArtworkKey
        if currentArtworkSourceIdentity == candidate.identity,
           currentArtworkKey == placeholderKey,
           artworkImage == nil {
            logArtworkAssignment(
                reason: "skipped unchanged placeholder",
                sourceIdentity: candidate.identity,
                oldKey: currentArtworkKey,
                newKey: placeholderKey,
                skipped: true
            )
            return
        }

        currentArtworkKey = placeholderKey
        artworkKey = placeholderKey
        currentArtworkImageKey = nil
        artworkImageKey = nil
        currentArtworkSourceIdentity = candidate.identity
        currentArtworkURL = nil
        artworkImage = nil
        artworkImageRevision += 1
        synchronizeArtworkPresentation(reason: "placeholder published")
        logArtworkAssignment(
            reason: sourceChanged ? "source changed with no artwork; using placeholder" : "using placeholder fallback",
            sourceIdentity: candidate.identity,
            oldKey: oldKey,
            newKey: placeholderKey,
            skipped: false
        )
    }

    private func assignArtwork(
        _ image: NSImage,
        key: String,
        sourceIdentity: MediaSourceIdentity,
        reason: String,
        force: Bool
    ) {
        let oldKey = currentArtworkKey
        if !force,
           currentArtworkSourceIdentity == sourceIdentity,
           currentArtworkKey == key,
           currentArtworkImageKey == key,
           artworkImage != nil {
            logArtworkAssignment(
                reason: "skipped unchanged artwork",
                sourceIdentity: sourceIdentity,
                oldKey: oldKey,
                newKey: key,
                skipped: true
            )
            return
        }

        artworkCache[key] = image
        currentArtworkKey = key
        artworkKey = key
        currentArtworkImageKey = key
        artworkImageKey = key
        currentArtworkSourceIdentity = sourceIdentity
        currentArtworkURL = key.hasPrefix("url:") ? String(key.dropFirst(4)) : currentArtworkURL
        artworkImage = image
        artworkImageRevision += 1
        debugArtworkFlip(
            "latency T3 artwork image available key=\(key) revision=\(artworkImageRevision)"
        )
        synchronizeArtworkPresentation(reason: reason)
        debugArtworkFlip("artwork image assigned key=\(key) revision=\(artworkImageRevision) reason=\(reason)")
        logArtworkAssignment(
            reason: reason,
            sourceIdentity: sourceIdentity,
            oldKey: oldKey,
            newKey: key,
            skipped: false
        )
    }

    private func clearArtwork(reason: String) {
        let oldKey = currentArtworkKey
        artworkImage = nil
        artworkImageRevision += 1
        currentArtworkURL = nil
        currentArtworkKey = nil
        currentArtworkImageKey = nil
        artworkImageKey = nil
        artworkKey = nil
        currentArtworkSourceIdentity = nil
        synchronizeArtworkPresentation(reason: reason)
        logArtworkAssignment(
            reason: reason,
            sourceIdentity: lastSelectedSourceIdentity,
            oldKey: oldKey,
            newKey: nil,
            skipped: false
        )
    }

    private func loadArtwork(
        from rawValue: String,
        key: String,
        identity: MediaSourceIdentity,
        generation: Int
    ) {
        guard let url = URL(string: rawValue), !rawValue.isEmpty else {
            logArtworkAssignment(
                reason: "skipped invalid artwork URL",
                sourceIdentity: identity,
                oldKey: currentArtworkKey,
                newKey: key,
                skipped: true
            )
            return
        }

        Task {
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = NSImage(data: data)
            else {
                return
            }
            await MainActor.run {
                guard MediaPublishGuard.canApplyAsyncUpdate(
                    selectedIdentity: self.lastSelectedSourceIdentity,
                    selectedGeneration: self.selectedPublishGeneration,
                    requestIdentity: identity,
                    requestGeneration: generation
                ),
                    self.currentArtworkKey == key
                else {
                    self.logAsyncArtworkDiscarded(
                        rawValue: rawValue,
                        key: key,
                        identity: identity,
                        generation: generation
                    )
                    return
                }
                self.assignArtwork(
                    image,
                    key: key,
                    sourceIdentity: identity,
                    reason: "downloaded Spotify artwork",
                    force: false
                )
            }
        }
    }

    /// Runs one AppleScript through the shared serialized executor (same
    /// timeouts/backoff as transport commands). Used by the advanced Now
    /// Playing controls; never called from the detection loop.
    func runAutomation(_ source: String, target: MediaAutomationTarget) async -> MediaAutomationScriptResult {
        guard !isSettingsPreview else { return MediaAutomationScriptResult(output: "", failure: .cancelled) }
        return await withCheckedContinuation { continuation in
            automationExecutor.submitCommand(MediaAutomationOperation(target: target, source: source)) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func send(
        command: String,
        to player: MediaPlayer,
        isVolume: Bool = false,
        completion: @escaping @Sendable (MediaAutomationScriptResult) -> Void = { _ in }
    ) {
        guard !isSettingsPreview else { return }
        let target: MediaAutomationTarget = player == .spotify ? .spotify : .music
        automationExecutor.submitCommand(
            MediaAutomationOperation(
                target: target,
                source: "tell application \"\(player.rawValue)\" to \(command)"
            ),
            isVolume: isVolume,
            completion: completion
        )
    }

    private func logMediaDetection(source: String, usesPlaceholderArtwork: Bool = false) {
        #if DEBUG
        debugPrint(
            "DynamicIsland media",
            "source=\(source)",
            "title=\(title)",
            "artist=\(artist)",
            "sourceKind=\(sourceKind)",
            "hasActiveMediaSource=\(hasActiveMediaSource)",
            "isPlaying=\(isPlaying)",
            "bundleIdentifier=\(sourceBundleIdentifier ?? "nil")",
            "hasArtwork=\(artworkImage != nil)",
            "usesPlaceholderArtwork=\(usesPlaceholderArtwork || artworkImage == nil)",
            "transport=\(isTransportControlAvailable)",
            "seek=\(isSeekControlAvailable)",
            "hasProgress=\(hasPlaybackProgress)",
            "duration=\(hasPlaybackProgress ? String(duration) : "unknown")",
            "currentTime=\(hasPlaybackProgress ? String(playbackPosition) : "unknown")"
        )
        #endif
    }

    private func debugArtworkFlip(_ message: String) {
        #if DEBUG
        print("[ArtworkFlip][\(String(format: "%.6f", ProcessInfo.processInfo.systemUptime))] \(message)")
        #endif
    }

    private func synchronizeArtworkPresentation(reason: String) {
        let snapshot = ArtworkPresentationSnapshot(
            image: artworkImage,
            identity: currentArtworkPresentationIdentity,
            fingerprint: artworkPresentationFingerprint(for: artworkImage)
        )
        debugArtworkFlip(
            "raw artwork received reason=\(reason) identity=\(snapshot.identity) fingerprint=\(snapshot.fingerprint)"
        )
        artworkPresentation.receiveRawArtwork(
            snapshot,
            request: artworkFlipRequest,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ) { [weak self] requestID in
            self?.consumeArtworkFlipRequest(id: requestID)
        }
    }

    private var currentArtworkPresentationIdentity: String {
        [sourceName, title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }

    private func artworkPresentationFingerprint(for image: NSImage?) -> String {
        guard let image else { return "placeholder" }

        let representationDescription = image.representations
            .map { "\($0.pixelsWide)x\($0.pixelsHigh)" }
            .joined(separator: ",")
        let dataHash = image.tiffRepresentation?.hashValue ?? ObjectIdentifier(image).hashValue
        return "\(Int(image.size.width))x\(Int(image.size.height))|\(representationDescription)|\(dataHash)"
    }

    private func logProviderAttempt(_ provider: String) {
        #if DEBUG
        debugPrint("DynamicIsland media provider", "attempt=\(provider)")
        #endif
    }

    private func logProviderResult(_ provider: String, succeeded: Bool, snapshot: MediaSnapshot? = nil) {
        #if DEBUG
        if let snapshot {
            debugPrint(
                "DynamicIsland media provider",
                "provider=\(provider)",
                "succeeded=\(succeeded)",
                "title=\(snapshot.title)",
                "source=\(snapshot.sourceName)",
                "bundleIdentifier=\(snapshot.bundleIdentifier ?? "nil")",
                "sourceKind=\(snapshot.sourceKind)",
                "isPlaying=\(snapshot.isPlaying)",
                "hasArtwork=\(snapshot.artwork != nil)",
                "duration=\(snapshot.duration.map { String($0) } ?? "nil")",
                "elapsed=\(snapshot.elapsedTime.map { String($0) } ?? "nil")"
            )
        } else {
            debugPrint(
                "DynamicIsland media provider",
                "provider=\(provider)",
                "succeeded=\(succeeded)"
            )
        }
        #endif
    }

    private func logSelectedProvider(_ provider: String, snapshot: MediaSnapshot? = nil) {
        #if DEBUG
        if let snapshot {
            debugPrint(
                "DynamicIsland media provider",
                "selected=\(provider)",
                "title=\(snapshot.title)",
                "source=\(snapshot.sourceName)",
                "bundleIdentifier=\(snapshot.bundleIdentifier ?? "nil")",
                "isPlaying=\(snapshot.isPlaying)"
            )
        } else {
            debugPrint(
                "DynamicIsland media provider",
                "selected=\(provider)",
                "title=\(title)",
                "source=\(sourceName)",
                "bundleIdentifier=\(sourceBundleIdentifier ?? "nil")",
                "isPlaying=\(isPlaying)"
            )
        }
        #endif
    }

    private func logCandidate(_ candidate: MediaCandidate, score: Int) {
        #if DEBUG
        debugPrint(
            "DynamicIsland media candidate",
            "identity=\(candidate.identity.debugDescription)",
            "provider=\(candidate.providerName)",
            "sourceKind=\(candidate.snapshot.sourceKind)",
            "title=\(candidate.snapshot.title)",
            "source=\(candidate.snapshot.sourceName)",
            "bundleIdentifier=\(candidate.snapshot.bundleIdentifier ?? "nil")",
            "isPlaying=\(candidate.snapshot.isPlaying)",
            "hasArtwork=\(candidate.snapshot.artwork != nil || candidate.artworkURL != nil)",
            "hasProgress=\(candidate.hasPlaybackProgress)",
            "matchesCurrent=\(candidate.identity == lastSelectedSourceIdentity)",
            "score=\(score)"
        )
        #endif
    }

    private func logSelection(_ candidate: MediaCandidate, score: Int, reason: String) {
        #if DEBUG
        debugPrint(
            "DynamicIsland media selection",
            "identity=\(candidate.identity.debugDescription)",
            "provider=\(candidate.providerName)",
            "sourceKind=\(candidate.snapshot.sourceKind)",
            "title=\(candidate.snapshot.title)",
            "source=\(candidate.snapshot.sourceName)",
            "isPlaying=\(candidate.snapshot.isPlaying)",
            "score=\(score)",
            "reason=\(reason)"
        )
        #endif
    }

    private func logSelectedCandidatePublish(
        _ candidate: MediaCandidate,
        reason: String,
        identityChanged: Bool
    ) {
        #if DEBUG
        debugPrint(
            "DynamicIsland media publishing selected candidate",
            "provider=\(candidate.providerName)",
            "identity=\(candidate.identity.debugDescription)",
            "source=\(candidate.snapshot.sourceName)",
            "title=\(candidate.snapshot.title)",
            "isPlaying=\(candidate.snapshot.isPlaying)",
            "reason=\(reason)",
            "identityChanged=\(identityChanged)",
            "generation=\(selectedPublishGeneration)"
        )
        #endif
    }

    private func logAsyncArtworkDiscarded(
        rawValue: String,
        key: String,
        identity: MediaSourceIdentity,
        generation: Int
    ) {
        #if DEBUG
        debugPrint(
            "DynamicIsland media async artwork discarded",
            "requestIdentity=\(identity.debugDescription)",
            "requestGeneration=\(generation)",
            "selectedIdentity=\(lastSelectedSourceIdentity?.debugDescription ?? "nil")",
            "selectedGeneration=\(selectedPublishGeneration)",
            "key=\(key)",
            "url=\(rawValue)"
        )
        #endif
    }

    private func logArtworkAssignment(
        reason: String,
        sourceIdentity: MediaSourceIdentity?,
        oldKey: String?,
        newKey: String?,
        skipped: Bool
    ) {
        #if DEBUG
        debugPrint(
            "DynamicIsland media artwork",
            "reason=\(reason)",
            "skipped=\(skipped)",
            "sourceIdentity=\(sourceIdentity?.debugDescription ?? "nil")",
            "selectedIdentity=\(lastSelectedSourceIdentity?.debugDescription ?? "nil")",
            "sourceKind=\(sourceKind)",
            "title=\(title)",
            "artist=\(artist)",
            "oldKey=\(oldKey ?? "nil")",
            "newKey=\(newKey ?? "nil")",
            "currentKey=\(currentArtworkKey ?? "nil")",
            "hasArtwork=\(artworkImage != nil)"
        )
        #endif
    }

    private func logPausedSwitchPending(_ candidate: MediaCandidate, reason: String) {
        #if DEBUG
        debugPrint(
            "DynamicIsland media arbitration",
            "paused switch not published",
            "reason=\(reason)",
            "current=\(lastSelectedSourceIdentity?.debugDescription ?? "nil")",
            "candidate=\(candidate.identity.debugDescription)",
            "candidateTitle=\(candidate.snapshot.title)",
            "candidatePlaying=\(candidate.snapshot.isPlaying)",
            "currentWasPlaying=\(lastSelectedSourceWasPlaying)",
            "pendingCount=\(pendingPausedSwitchCount)"
        )
        #endif
    }

    private func logPausedHysteresisKept(current: MediaCandidate, candidates: [MediaCandidate]) {
        #if DEBUG
        for candidate in candidates where candidate.identity != current.identity {
            debugPrint(
                "DynamicIsland media arbitration",
                "blocked paused-source switch",
                "current=\(current.identity.debugDescription)",
                "candidate=\(candidate.identity.debugDescription)",
                "currentTitle=\(current.snapshot.title)",
                "candidateTitle=\(candidate.snapshot.title)",
                "reason=current paused source still valid; no playback activity"
            )
        }
        #endif
    }

    private func logSourceSwitch(
        previousIdentity: MediaSourceIdentity?,
        previousSource: String,
        previousTitle: String,
        previousPlaying: Bool,
        selected: MediaCandidate
    ) {
        #if DEBUG
        guard previousSource != selected.snapshot.sourceName ||
            previousTitle != selected.snapshot.title ||
            previousPlaying != selected.snapshot.isPlaying
        else {
            return
        }
        debugPrint(
            "DynamicIsland media source switch",
            "previousIdentity=\(previousIdentity?.debugDescription ?? "nil")",
            "previousSource=\(previousSource)",
            "previousTitle=\(previousTitle)",
            "previousPlaying=\(previousPlaying)",
            "newIdentity=\(selected.identity.debugDescription)",
            "newSource=\(selected.snapshot.sourceName)",
            "newTitle=\(selected.snapshot.title)",
            "newPlaying=\(selected.snapshot.isPlaying)"
        )
        #endif
    }

    private func logMediaSourceOpenRequested(target: MediaSourceOpenTarget?) {
        #if DEBUG
        debugPrint(
            "DynamicIsland media source open requested",
            "sourceKind=\(sourceKind)",
            "source=\(sourceName)",
            "bundle=\(sourceBundleIdentifier ?? "nil")",
            "title=\(title)",
            "target=\(target?.debugDescription ?? "nil")"
        )
        #endif
    }

    private func logMediaSourceOpenResult(
        targetDescription: String,
        fallbackUsed: Bool,
        succeeded: Bool
    ) {
        #if DEBUG
        debugPrint(
            "DynamicIsland media source open",
            "target=\(targetDescription)",
            "fallback=\(fallbackUsed)",
            "succeeded=\(succeeded)"
        )
        #endif
    }

    private func logBrowserDetectionAttempt(
        browser: BrowserScriptTarget,
        isRunning: Bool,
        phase: String,
        rawResult: String = "",
        errorDescription: String? = nil
    ) {
        #if DEBUG
        debugPrint(
            "DynamicIsland browser detection",
            "phase=\(phase)",
            "browser=\(browser.applicationName)",
            "bundleIdentifier=\(browser.bundleIdentifier)",
            "isRunning=\(isRunning)",
            "rawResult=\(rawResult)",
            "error=\(errorDescription ?? "none")",
            "hasActiveMediaSource=\(hasActiveMediaSource)",
            "isPlaying=\(isPlaying)",
            "title=\(title)",
            "source=\(sourceName)"
        )
        #endif
    }

    private func logBrowserPlaybackSelection(
        provider: String,
        pageURL: String,
        videoID: String?,
        hasProgress: Bool,
        playbackState: String
    ) {
        #if DEBUG
        debugPrint(
            "DynamicIsland browser playback",
            "provider=\(provider)",
            "pageURL=\(pageURL)",
            "videoID=\(videoID ?? "nil")",
            "state=\(playbackState)",
            "isPlaying=\(isPlaying)",
            "hasProgress=\(hasProgress)",
            "duration=\(hasProgress ? String(duration) : "unknown")",
            "currentTime=\(hasProgress ? String(playbackPosition) : "unknown")"
        )
        #endif
    }

    private func logYouTubeMetadata(
        phase: String,
        pageURL: String,
        videoID: String,
        title: String?,
        authorName: String?,
        thumbnailURLExists: Bool,
        thumbnailLoaded: Bool
    ) {
        #if DEBUG
        debugPrint(
            "DynamicIsland YouTube metadata",
            "phase=\(phase)",
            "pageURL=\(pageURL)",
            "videoID=\(videoID)",
            "title=\(title ?? "nil")",
            "author=\(authorName ?? "nil")",
            "thumbnailURL=\(thumbnailURLExists)",
            "thumbnailLoaded=\(thumbnailLoaded)",
            "finalTitle=\(self.title)",
            "finalArtist=\(self.artist)",
            "finalArtwork=\(self.artworkImage != nil)",
            "isPlaying=\(self.isPlaying)",
            "hasProgress=\(self.hasPlaybackProgress)"
        )
        #endif
    }

    private func isApplicationRunning(_ browser: BrowserScriptTarget) -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == browser.bundleIdentifier ||
                application.localizedName == browser.applicationName
        }
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct BrowserScriptTarget {
    let applicationName: String
    let bundleIdentifier: String
    let usesChromeScripting: Bool
}

struct MediaSourceIdentity: Hashable {
    let sourceKind: MediaSourceKind
    let bundleIdentifier: String?
    let persistentID: String?

    init(sourceKind: MediaSourceKind, bundleIdentifier: String?, persistentID: String?) {
        self.sourceKind = sourceKind
        self.bundleIdentifier = bundleIdentifier?.lowercased()
        self.persistentID = persistentID?.lowercased()
    }

    var debugDescription: String {
        [
            "\(sourceKind)",
            bundleIdentifier ?? "nil",
            persistentID ?? "nil"
        ].joined(separator: "|")
    }
}

enum MediaImmediateSystemHandoff {
    static func canPublish(
        candidate: MediaCandidate,
        currentIdentity: MediaSourceIdentity?
    ) -> Bool {
        guard candidate.providerName == "System Now Playing",
              candidate.snapshot.artwork != nil,
              let currentIdentity,
              candidate.identity != currentIdentity,
              candidate.identity.sourceKind == currentIdentity.sourceKind,
              let candidateBundle = candidate.identity.bundleIdentifier,
              !candidateBundle.isEmpty,
              candidateBundle == currentIdentity.bundleIdentifier
        else {
            return false
        }
        return true
    }
}

enum MediaArbitrator {
    static func selectBestCandidate(
        from candidates: [MediaCandidate],
        currentIdentity: MediaSourceIdentity?
    ) -> MediaCandidate? {
        guard !candidates.isEmpty else { return nil }

        let playingCandidates = candidates.filter { $0.snapshot.isPlaying }
        if !playingCandidates.isEmpty {
            return bestCandidate(from: playingCandidates, currentIdentity: currentIdentity)
        }

        if let currentIdentity,
           let currentCandidate = candidates.first(where: { $0.identity == currentIdentity }) {
            return currentCandidate
        }

        return bestCandidate(from: candidates, currentIdentity: currentIdentity)
    }

    static func selectionReason(
        _ selected: MediaCandidate,
        candidates: [MediaCandidate],
        currentIdentity: MediaSourceIdentity?
    ) -> String {
        if selected.snapshot.isPlaying {
            return "playing candidate won"
        }
        if let currentIdentity,
           selected.identity == currentIdentity {
            return "paused current source still valid"
        }
        if let currentIdentity,
           !candidates.contains(where: { $0.identity == currentIdentity }) {
            return "current source disappeared"
        }
        return "deterministic paused fallback"
    }

    static func score(_ candidate: MediaCandidate, currentIdentity: MediaSourceIdentity?) -> Int {
        var value = 0
        if candidate.snapshot.isPlaying {
            value += 1_000
        }
        if candidate.providerName == "System Now Playing", candidate.snapshot.isPlaying {
            value += 100
        }
        if (candidate.snapshot.sourceKind == .spotify || candidate.snapshot.sourceKind == .music),
           candidate.providerName.contains("AppleScript") {
            value += 150
        }
        if candidate.identity == currentIdentity {
            value += 500
        }
        if candidate.snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value -= 500
        }
        return value
    }

    static func providerTieBreakRank(_ candidate: MediaCandidate) -> Int {
        switch candidate.providerName {
        case "Spotify AppleScript", "Music AppleScript":
            return 4
        case "Browser AppleScript":
            return 3
        case "System Now Playing":
            return 2
        default:
            return 1
        }
    }

    private static func bestCandidate(
        from candidates: [MediaCandidate],
        currentIdentity: MediaSourceIdentity?
    ) -> MediaCandidate? {
        candidates.max { first, second in
            let firstScore = score(first, currentIdentity: currentIdentity)
            let secondScore = score(second, currentIdentity: currentIdentity)
            if firstScore == secondScore {
                return providerTieBreakRank(first) < providerTieBreakRank(second)
            }
            return firstScore < secondScore
        }
    }
}

enum MediaPublishGuard {
    static func canApplyAsyncUpdate(
        selectedIdentity: MediaSourceIdentity?,
        selectedGeneration: Int,
        requestIdentity: MediaSourceIdentity,
        requestGeneration: Int
    ) -> Bool {
        selectedIdentity == requestIdentity && selectedGeneration == requestGeneration
    }
}

enum MediaPausedSwitchGate {
    struct Decision {
        let shouldPublish: Bool
        let firstSeenAt: Date?
        let count: Int
        let reason: String
    }

    static let confirmationInterval: TimeInterval = 0.35
    static let requiredConsecutivePolls = 2

    static func decision(
        candidateIdentity: MediaSourceIdentity,
        currentIdentity: MediaSourceIdentity?,
        currentWasPlaying: Bool,
        pendingIdentity: MediaSourceIdentity?,
        pendingFirstSeenAt: Date?,
        pendingCount: Int,
        now: Date
    ) -> Decision {
        guard currentIdentity != nil else {
            return Decision(
                shouldPublish: true,
                firstSeenAt: nil,
                count: 0,
                reason: "initial paused candidate selected"
            )
        }

        let firstSeenAt: Date
        let count: Int
        if pendingIdentity == candidateIdentity, let existingFirstSeenAt = pendingFirstSeenAt {
            firstSeenAt = existingFirstSeenAt
            count = pendingCount + 1
        } else {
            firstSeenAt = now
            count = 1
        }

        let elapsed = now.timeIntervalSince(firstSeenAt)
        let confirmed = count >= requiredConsecutivePolls && elapsed >= confirmationInterval
        if confirmed {
            return Decision(
                shouldPublish: true,
                firstSeenAt: firstSeenAt,
                count: count,
                reason: currentWasPlaying
                    ? "confirmed paused switch after playing source disappeared"
                    : "confirmed paused switch"
            )
        }

        return Decision(
            shouldPublish: false,
            firstSeenAt: firstSeenAt,
            count: count,
            reason: currentWasPlaying
                ? "blocked paused candidate from publishing over playing source"
                : "pending paused switch confirmation"
        )
    }
}

enum MediaSourceOpenTarget: Equatable {
    case app(AppLaunchService.SupportedApp)
    case bundleIdentifier(String)
    case youtube

    static func resolve(
        sourceKind: MediaSourceKind,
        sourceName: String,
        bundleIdentifier: String?
    ) -> MediaSourceOpenTarget? {
        let normalizedSource = sourceName.lowercased()
        let normalizedBundle = bundleIdentifier?.lowercased()

        if sourceKind == .spotify ||
            normalizedBundle == AppLaunchService.SupportedApp.spotify.bundleIdentifier.lowercased() ||
            normalizedSource.contains("spotify") {
            return .app(.spotify)
        }

        if sourceKind == .music ||
            normalizedBundle == AppLaunchService.SupportedApp.music.bundleIdentifier.lowercased() ||
            normalizedSource.contains("music") ||
            normalizedSource.contains("apple music") {
            return .app(.music)
        }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return .bundleIdentifier(bundleIdentifier)
        }

        if sourceKind == .browser ||
            normalizedSource.contains("youtube") ||
            normalizedSource.contains("browser") {
            return .youtube
        }

        return nil
    }

    var debugDescription: String {
        switch self {
        case .app(let app):
            app.displayName
        case .bundleIdentifier(let bundleIdentifier):
            bundleIdentifier
        case .youtube:
            "YouTube default browser"
        }
    }
}

struct MediaCandidate {
    let providerName: String
    let snapshot: MediaSnapshot
    let hasPlaybackProgress: Bool
    let artworkURL: String?
    let volume: Double?
    let activePlayer: MediaController.MediaPlayer?
    let youtubePageURL: String?
    let youtubeVideoID: String?
    let playbackProvider: String?
    let identity: MediaSourceIdentity
    let artworkKey: String?

    init(
        providerName: String,
        snapshot: MediaSnapshot,
        hasPlaybackProgress: Bool? = nil,
        artworkURL: String? = nil,
        volume: Double? = nil,
        activePlayer: MediaController.MediaPlayer? = nil,
        youtubePageURL: String? = nil,
        youtubeVideoID: String? = nil,
        playbackProvider: String? = nil
    ) {
        self.providerName = providerName
        self.snapshot = snapshot
        self.hasPlaybackProgress = hasPlaybackProgress ??
            (snapshot.duration.map { $0.isFinite && $0 > 1 } == true &&
                snapshot.elapsedTime.map { $0.isFinite } == true)
        self.artworkURL = artworkURL?.isEmpty == false ? artworkURL : nil
        self.volume = volume
        self.activePlayer = activePlayer
        self.youtubePageURL = youtubePageURL?.isEmpty == false ? youtubePageURL : nil
        self.youtubeVideoID = youtubeVideoID?.isEmpty == false ? youtubeVideoID : nil
        self.playbackProvider = playbackProvider
        self.identity = MediaSourceIdentity(
            sourceKind: snapshot.sourceKind,
            bundleIdentifier: snapshot.bundleIdentifier,
            persistentID: Self.persistentID(
                snapshot: snapshot,
                youtubePageURL: self.youtubePageURL,
                youtubeVideoID: self.youtubeVideoID
            )
        )
        self.artworkKey = Self.artworkKey(
            identity: self.identity,
            artworkURL: self.artworkURL,
            youtubePageURL: self.youtubePageURL,
            youtubeVideoID: self.youtubeVideoID,
            hasEmbeddedArtwork: snapshot.artwork != nil
        )
    }

    var sourceKey: String {
        identity.debugDescription
    }

    private static func persistentID(
        snapshot: MediaSnapshot,
        youtubePageURL: String?,
        youtubeVideoID: String?
    ) -> String {
        if let youtubeVideoID {
            return "youtube:\(youtubeVideoID)"
        }
        if let youtubePageURL {
            return "url:\(youtubePageURL)"
        }
        let normalizedTitle = snapshot.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedArtist = (snapshot.artist ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(snapshot.sourceKind)|\(normalizedTitle)|\(normalizedArtist)"
    }

    private static func artworkKey(
        identity: MediaSourceIdentity,
        artworkURL: String?,
        youtubePageURL: String?,
        youtubeVideoID: String?,
        hasEmbeddedArtwork: Bool
    ) -> String? {
        if let artworkURL, !artworkURL.isEmpty {
            return "url:\(artworkURL)"
        }
        if let youtubeVideoID, !youtubeVideoID.isEmpty {
            return "youtube:\(youtubeVideoID)"
        }
        if let youtubePageURL, !youtubePageURL.isEmpty {
            return "url:\(youtubePageURL)"
        }
        if hasEmbeddedArtwork {
            return "embedded:\(identity.debugDescription)"
        }
        return nil
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
