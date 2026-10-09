import AppKit
import Combine
import XCTest
@testable import DynamicIsland

private final class ScrubAutomationFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var output = "Track A||Artist||playing||Spotify||12||200||||40||spotify:track:AAAAAAAAAAAAAAAAAAAAAA"
    private var commands: [String] = []
    private var seekFailure: MediaAutomationFailure?
    var onSeek: (@Sendable () -> Void)?

    func setOutput(_ value: String) { lock.withLock { output = value } }
    func failSeek(_ failure: MediaAutomationFailure) { lock.withLock { seekFailure = failure } }
    var seekCommands: [String] { lock.withLock { commands } }

    func run(_ source: String) -> MediaAutomationScriptResult {
        if source.contains("set player position") {
            lock.withLock { commands.append(source) }
            onSeek?()
            return MediaAutomationScriptResult(output: "", failure: lock.withLock { seekFailure })
        }
        if source.contains("set playbackState"), source.contains("tell application \"Spotify\"") {
            return MediaAutomationScriptResult(output: lock.withLock { output }, failure: nil)
        }
        return MediaAutomationScriptResult(output: "", failure: nil)
    }
}

@MainActor
private final class ScrubNoSystemProvider: MediaDetectionProvider {
    let name = "Test"
    func snapshot() async -> MediaSnapshot? { nil }
}

@MainActor
private final class ScrubSystemProvider: MediaDetectionProvider {
    let name = "Test"
    var value: MediaSnapshot?
    func snapshot() async -> MediaSnapshot? { value }
}

final class MediaScrubStateTests: XCTestCase {
    private func context(track: String = "A", duration: Double = 200, generation: Int = 1,
                         player: MediaController.MediaPlayer = .spotify) -> MediaScrubContext {
        MediaScrubContext(identity: MediaSourceIdentity(sourceKind: player == .spotify ? .spotify : .music,
                                                       bundleIdentifier: player.rawValue, persistentID: track),
                          nativeTrackID: "spotify:track:AAAAAAAAAAAAAAAAAAAAAA", duration: duration,
                          player: player, title: track, artist: "Artist", generation: generation)
    }

    func testTimesRejectNonfiniteAndUnknownDurationAndClampBothBoundaries() {
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(MediaPlaybackTime.clampedPosition(invalid, duration: 200))
            XCTAssertNil(MediaPlaybackTime.validDuration(invalid))
        }
        for invalidDuration in [Double.nan, .infinity, -.infinity, 0, -1, .greatestFiniteMagnitude, Double(Int.max)] {
            XCTAssertNil(MediaPlaybackTime.clampedPosition(12, duration: invalidDuration))
            XCTAssertNil(MediaPlaybackTime.validDuration(invalidDuration))
        }
        XCTAssertNil(MediaPlaybackTime.validDuration(nil))
        XCTAssertEqual(MediaPlaybackTime.clampedPosition(-5, duration: 200), 0)
        XCTAssertEqual(MediaPlaybackTime.clampedPosition(205, duration: 200), 200)
        XCTAssertEqual(MediaPlaybackTime.clampedPosition(0.4, duration: 0.5), 0.4)
    }

    func testSpotifySecondsFloorToMillisecondsWithinLiveVerifiedEndGuard() {
        XCTAssertEqual(MediaPlaybackTime.spotifyMilliseconds(12.3459, duration: 200), 12_345)
        XCTAssertEqual(MediaPlaybackTime.spotifyMilliseconds(200, duration: 200), 199_750)
        XCTAssertEqual(MediaPlaybackTime.spotifyMilliseconds(210, duration: 200), 199_750)
        XCTAssertEqual(MediaPlaybackTime.spotifyMilliseconds(-1, duration: 200), 0)
        XCTAssertNil(MediaPlaybackTime.spotifyMilliseconds(.greatestFiniteMagnitude, duration: .greatestFiniteMagnitude))
    }

    func testSpotifySafeMaximumPreservesGenericProviderDurationAndSupportsTinyTracks() {
        XCTAssertEqual(MediaPlaybackTime.maximumSeekPosition(duration: 216.923, player: .spotify)!, 216.673, accuracy: 0.000_001)
        XCTAssertEqual(MediaPlaybackTime.clampedSeekPosition(216.923, duration: 216.923, player: .spotify)!, 216.673, accuracy: 0.000_001)
        XCTAssertEqual(MediaPlaybackTime.maximumSeekPosition(duration: 216.923, player: .music), 216.923)
        XCTAssertEqual(MediaPlaybackTime.clampedPosition(216.923, duration: 216.923), 216.923)
        for duration in [0.001, 0.1, 0.25] {
            XCTAssertEqual(MediaPlaybackTime.maximumSeekPosition(duration: duration, player: .spotify), 0)
            XCTAssertEqual(MediaPlaybackTime.clampedSeekPosition(duration, duration: duration, player: .spotify), 0)
            XCTAssertEqual(MediaPlaybackTime.spotifyMilliseconds(duration, duration: duration), 0)
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(MediaPlaybackTime.clampedSeekPosition(invalid, duration: 200, player: .spotify))
            XCTAssertNil(MediaPlaybackTime.maximumSeekPosition(duration: invalid, player: .spotify))
        }
        // Provider duration quantization may differ by a binary rounding
        // fraction; integer commands still cannot exceed duration_ms - 250.
        XCTAssertLessThanOrEqual(MediaPlaybackTime.spotifyMilliseconds(312.34500000000003, duration: 312.34500000000003)!, 312_095)
    }

    func testNormalizedProgressRejectsInvalidTimingAndClampsBothBoundaries() {
        XCTAssertEqual(MediaPlaybackTime.normalizedProgress(position: 50, duration: 200), 0.25)
        XCTAssertEqual(MediaPlaybackTime.normalizedProgress(position: 0, duration: 200), 0)
        XCTAssertEqual(MediaPlaybackTime.normalizedProgress(position: -1, duration: 200), 0)
        XCTAssertEqual(MediaPlaybackTime.normalizedProgress(position: 200, duration: 200), 1)
        XCTAssertEqual(MediaPlaybackTime.normalizedProgress(position: 205, duration: 200), 1)
        XCTAssertEqual(MediaPlaybackTime.normalizedProgress(position: .leastNonzeroMagnitude, duration: .leastNonzeroMagnitude), 1)
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(MediaPlaybackTime.normalizedProgress(position: invalid, duration: 200), 0)
        }
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1, .greatestFiniteMagnitude, Double(Int.max)] {
            XCTAssertEqual(MediaPlaybackTime.normalizedProgress(position: 50, duration: invalid), 0)
        }
    }

    func testRemainingLabelUsesValidatedTrackBoundsWithoutIntegerOverflow() {
        XCTAssertEqual(MediaAdvancedController.remainingLabel(position: -12, duration: 61), "-1:01")
        XCTAssertEqual(MediaAdvancedController.remainingLabel(position: 70, duration: 61), "-0:00")
        XCTAssertEqual(MediaAdvancedController.remainingLabel(position: .nan, duration: 61), "-1:01")
        XCTAssertEqual(MediaAdvancedController.remainingLabel(position: .infinity, duration: 61), "-1:01")
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1, .greatestFiniteMagnitude, Double(Int.max)] {
            XCTAssertEqual(MediaAdvancedController.remainingLabel(position: 12, duration: invalid), "-0:00")
        }
    }

    func testSpotifyProviderDurationRecoversQuantizedMilliseconds() {
        for milliseconds in [1, 1_001, 200_000, 312_345, 999_999] {
            XCTAssertEqual(MediaPlaybackTime.spotifyDurationMilliseconds(Double(milliseconds) / 1_000), milliseconds)
        }
        XCTAssertEqual(MediaPlaybackTime.spotifyDurationMilliseconds(312.34500000000003), 312_345)
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1, .greatestFiniteMagnitude] {
            XCTAssertNil(MediaPlaybackTime.spotifyDurationMilliseconds(invalid))
        }
    }

    func testSystemSeekIdentityEnrichmentRequiresMatchingLocalSourceTrackAndDuration() {
        let snapshot = MediaSnapshot(sourceKind: .spotify, sourceName: "Spotify", bundleIdentifier: "com.spotify.client",
            title: "Track A", artist: "Artist", album: nil, artwork: nil, isPlaying: true, duration: 200,
            elapsedTime: 12, transportAvailable: true, seekAvailable: true, volumeAvailable: true)
        let selected = MediaCandidate(providerName: "System Now Playing", snapshot: snapshot)
        var local = snapshot
        local.nativeTrackID = "spotify:track:AAAAAAAAAAAAAAAAAAAAAA"
        let matching = MediaCandidate(providerName: "Spotify AppleScript", snapshot: local, activePlayer: .spotify)
        XCTAssertEqual(MediaController.seekNativeTrackID(for: selected, candidates: [matching]), local.nativeTrackID)
        XCTAssertNil(selected.snapshot.nativeTrackID)
        for mismatch in 0..<4 {
            var changed = local
            switch mismatch {
            case 0: changed.duration = 250
            case 1: changed.title = "track a" // metadata identity is normalized; command enrichment is exact.
            case 2: changed.artist = "Other Artist"
            default: changed.bundleIdentifier = "com.apple.Music"; changed.sourceKind = .music
            }
            let candidate = MediaCandidate(providerName: "Spotify AppleScript", snapshot: changed, activePlayer: .spotify)
            XCTAssertNil(MediaController.seekNativeTrackID(for: selected, candidates: [candidate]))
        }
        XCTAssertNil(MediaController.seekNativeTrackID(for: selected,
            candidates: [MediaCandidate(providerName: "System Now Playing", snapshot: local)]))
    }

    func testPreviewCapturesDurationAndConsumesExactlyOneRelease() {
        let original = context()
        var state = MediaScrubState()
        state.begin(context: original, position: 12)
        state.update(120)
        state.update(210)
        XCTAssertEqual(state.previewPosition, 199.75)
        XCTAssertEqual(state.context?.duration, 200)
        XCTAssertEqual(state.finish(context: original)?.position, 199.75)
        XCTAssertFalse(state.isEditing)
        XCTAssertNil(state.previewPosition)
        XCTAssertNil(state.finish(context: original))
    }

    func testTrackDurationSourceAndGenerationChangesRejectLateUpdatesUntilRelease() {
        let original = context()
        for replacement in [context(track: "B"), context(duration: 100), context(generation: 2), context(player: .music)] {
            var state = MediaScrubState()
            state.begin(context: original, position: 12)
            state.update(150)
            state.reconcile(context: replacement)
            state.begin(context: replacement, position: 0)
            state.update(75)
            XCTAssertTrue(state.isEditing)
            XCTAssertNil(state.previewPosition)
            XCTAssertNil(state.finish(context: replacement))
            state.begin(context: replacement, position: 0)
            state.update(15)
            XCTAssertEqual(state.finish(context: replacement)?.position, 15)
        }
    }

    func testCapabilityLossAndInvalidInputCancelWithoutSeeking() {
        let original = context()
        for invalid in [Double.nan, .infinity, -.infinity] {
            var state = MediaScrubState()
            state.begin(context: original, position: 12)
            state.update(invalid)
            state.update(40)
            XCTAssertNil(state.finish(context: original))
        }
        var state = MediaScrubState()
        state.begin(context: original, position: 12)
        state.reconcile(context: nil)
        state.update(40)
        XCTAssertNil(state.finish(context: nil))
        state.begin(context: original, position: 12)
        state.cancel()
        XCTAssertNil(state.finish(context: original))
    }

    func testLocalCommandPinsNativeTrackAndDurationWithEscapedMetadataFallback() {
        let request = MediaSeekRequest(context: context(), position: 200)
        let script = MediaController.seekScript(request)
        XCTAssertTrue(script.contains("id of current track as text"))
        XCTAssertTrue(script.contains("considering case"))
        XCTAssertTrue(script.contains("((duration of current track) / 1000) is 200.0"))
        XCTAssertTrue(script.contains("set player position to 199.75"))
        XCTAssertFalse(script.contains("next track"))
        let music = MediaScrubContext(identity: context().identity, nativeTrackID: nil, duration: 200,
                                      player: .music, title: "A\"\\B", artist: "Artist", generation: 1)
        let fallback = MediaController.seekScript(MediaSeekRequest(context: music, position: 15))
        XCTAssertTrue(fallback.contains("\"A\\\"\\\\B\""))
        XCTAssertTrue(fallback.contains("duration of current track is 200.0"))
        XCTAssertFalse(fallback.contains("/ 1000"))
    }

    @MainActor
    private func makeController(_ fixture: ScrubAutomationFixture) -> (MediaController, MediaAutomationExecutor) {
        let executor = MediaAutomationExecutor(backoff: MediaAutomationBackoff(initialDelay: 0, maximumDelay: 0),
                                               runner: { source, _ in fixture.run(source) })
        let controller = MediaController(automationExecutor: executor,
                                         systemNowPlayingProvider: ScrubNoSystemProvider(), startsAutomatically: false)
        return (controller, executor)
    }

    @MainActor
    private func refresh(_ media: MediaController, position: Double) async {
        let published = expectation(description: "provider position \(position)")
        let subscription = media.$playbackPosition.dropFirst().filter { $0 == position }.first()
            .sink { _ in published.fulfill() }
        media.refresh()
        await fulfillment(of: [published], timeout: 3)
        subscription.cancel()
    }

    @MainActor
    func testProviderProgressKeepsUpdatingDuringPreviewAndReleaseSendsOneSeek() async {
        let fixture = ScrubAutomationFixture()
        let (media, executor) = makeController(fixture)
        await refresh(media, position: 12)
        media.setScrubbing(true)
        media.updateScrubPosition(198)
        XCTAssertEqual(media.playbackPosition, 12)
        XCTAssertEqual(media.displayedPlaybackPosition, 198)
        XCTAssertTrue(fixture.seekCommands.isEmpty)
        fixture.setOutput("Track A||Artist||playing||Spotify||15||200||||40||spotify:track:AAAAAAAAAAAAAAAAAAAAAA")
        await refresh(media, position: 15)
        XCTAssertEqual(media.playbackPosition, 15)
        XCTAssertEqual(media.displayedPlaybackPosition, 198)
        let sent = expectation(description: "one seek")
        fixture.onSeek = { sent.fulfill() }
        media.setScrubbing(false)
        media.setScrubbing(false)
        await fulfillment(of: [sent], timeout: 3)
        XCTAssertEqual(media.displayedPlaybackPosition, media.playbackPosition)
        await executor.invalidateAndWaitForIdle()
        XCTAssertEqual(fixture.seekCommands.count, 1)
        XCTAssertTrue(fixture.seekCommands[0].contains("set player position to 198.0"))
    }

    @MainActor
    func testDirectSpotifyEndpointSeekUsesSafeSecondsWithoutNextTrackCommand() async {
        let fixture = ScrubAutomationFixture()
        let (media, executor) = makeController(fixture)
        await refresh(media, position: 12)
        let sent = expectation(description: "safe direct endpoint seek")
        fixture.onSeek = { sent.fulfill() }
        media.seek(to: 200)
        await fulfillment(of: [sent], timeout: 3)
        await executor.invalidateAndWaitForIdle()
        XCTAssertEqual(fixture.seekCommands.count, 1)
        XCTAssertTrue(fixture.seekCommands[0].contains("set player position to 199.75"))
        XCTAssertTrue(fixture.seekCommands[0].contains("((duration of current track) / 1000) is 200.0"))
        XCTAssertFalse(fixture.seekCommands[0].contains("next track"))
        XCTAssertEqual(media.duration, 200)
    }

    @MainActor
    func testSpotifyEndpointSliderUsesSafeRangeWhileProviderTimingStaysTrue() async {
        let fixture = ScrubAutomationFixture()
        fixture.setOutput("Track A||Artist||playing||Spotify||200||200||||40||spotify:track:AAAAAAAAAAAAAAAAAAAAAA")
        let (media, executor) = makeController(fixture)
        await refresh(media, position: 200)
        XCTAssertEqual(media.playbackPosition, 200)
        XCTAssertEqual(media.displayedPlaybackPosition, 200)
        XCTAssertEqual(media.playbackSliderDuration, 199.75)
        XCTAssertEqual(media.playbackSliderPosition, 199.75)
        media.setScrubbing(true)
        media.updateScrubPosition(205)
        XCTAssertEqual(media.displayedPlaybackPosition, 199.75)
        XCTAssertEqual(media.duration, 200)
        XCTAssertEqual(media.playbackPosition, 200)
        let sent = expectation(description: "safe endpoint release")
        fixture.onSeek = { sent.fulfill() }
        media.setScrubbing(false)
        media.setScrubbing(false)
        await fulfillment(of: [sent], timeout: 3)
        await executor.invalidateAndWaitForIdle()
        XCTAssertEqual(fixture.seekCommands.count, 1)
        XCTAssertTrue(fixture.seekCommands[0].contains("set player position to 199.75"))
        XCTAssertEqual(media.displayedPlaybackPosition, 200)
        XCTAssertEqual(media.playbackSliderPosition, 199.75)
    }

    @MainActor
    func testTinySpotifyTrackKeepsSliderValuesFiniteAndSeeksOnlyToZero() async {
        let fixture = ScrubAutomationFixture()
        fixture.setOutput("Track A||Artist||playing||Spotify||0.1||0.1||||40||spotify:track:AAAAAAAAAAAAAAAAAAAAAA")
        let (media, executor) = makeController(fixture)
        await refresh(media, position: 0.1)
        XCTAssertEqual(media.playbackSliderDuration, 0)
        XCTAssertEqual(media.playbackSliderPosition, 0)
        XCTAssertEqual(media.displayedPlaybackPosition, 0.1)
        let sent = expectation(description: "zero seek on tiny track")
        fixture.onSeek = { sent.fulfill() }
        media.seek(to: 0.1)
        await fulfillment(of: [sent], timeout: 3)
        await executor.invalidateAndWaitForIdle()
        XCTAssertEqual(fixture.seekCommands.count, 1)
        XCTAssertTrue(fixture.seekCommands[0].contains("set player position to 0.0"))
        XCTAssertEqual(media.duration, 0.1)
    }

    @MainActor
    func testNaturalTrackChangeDuringDragCannotSeekReplacementTrack() async {
        let fixture = ScrubAutomationFixture()
        let (media, executor) = makeController(fixture)
        await refresh(media, position: 12)
        media.setScrubbing(true)
        media.updateScrubPosition(199)
        fixture.setOutput("Track B||Artist||playing||Spotify||1||250||||40||spotify:track:BBBBBBBBBBBBBBBBBBBBBB")
        await refresh(media, position: 1)
        media.updateScrubPosition(199)
        media.setScrubbing(false)
        XCTAssertEqual(media.title, "Track B")
        XCTAssertEqual(media.displayedPlaybackPosition, 1)
        XCTAssertEqual(media.duration, 250)
        await executor.invalidateAndWaitForIdle()
        XCTAssertTrue(fixture.seekCommands.isEmpty)
    }

    @MainActor
    func testImmediateSystemArtworkHandoffPreservesCapturedLocalSeekIdentity() async {
        let fixture = ScrubAutomationFixture()
        let provider = ScrubSystemProvider()
        let executor = MediaAutomationExecutor(runner: { source, _ in fixture.run(source) })
        let media = MediaController(automationExecutor: executor, systemNowPlayingProvider: provider, startsAutomatically: false)
        await refresh(media, position: 12)
        media.setScrubbing(true)
        media.updateScrubPosition(198)
        provider.value = MediaSnapshot(sourceKind: .spotify, sourceName: "Spotify", bundleIdentifier: "com.spotify.client",
            title: "Track A", artist: "Artist", album: nil, artwork: NSImage(size: NSSize(width: 8, height: 8)),
            isPlaying: true, duration: 200, elapsedTime: 13, transportAvailable: true,
            seekAvailable: true, volumeAvailable: true)
        fixture.setOutput("Track A||Artist||playing||Spotify||15||200||||40||spotify:track:AAAAAAAAAAAAAAAAAAAAAA")
        await refresh(media, position: 15)
        XCTAssertEqual(media.displayedPlaybackPosition, 198)
        XCTAssertTrue(media.isSeekControlAvailable)
        let sent = expectation(description: "seek after system handoff")
        fixture.onSeek = { sent.fulfill() }
        media.setScrubbing(false)
        await fulfillment(of: [sent], timeout: 3)
        await executor.invalidateAndWaitForIdle()
        XCTAssertEqual(fixture.seekCommands.count, 1)
    }

    @MainActor
    func testDurationChangeAndDisappearanceDiscardPendingSeek() async {
        let fixture = ScrubAutomationFixture()
        let (media, executor) = makeController(fixture)
        await refresh(media, position: 12)
        media.setScrubbing(true)
        media.updateScrubPosition(190)
        fixture.setOutput("Track A||Artist||playing||Spotify||13||100||||40||spotify:track:AAAAAAAAAAAAAAAAAAAAAA")
        await refresh(media, position: 13)
        media.updateScrubPosition(99)
        media.setScrubbing(false)
        media.setScrubbing(true)
        media.updateScrubPosition(50)
        media.cancelScrubbing()
        media.setScrubbing(false)
        await executor.invalidateAndWaitForIdle()
        XCTAssertTrue(fixture.seekCommands.isEmpty)
        XCTAssertEqual(media.displayedPlaybackPosition, 13)
    }

    @MainActor
    func testInvalidProviderProgressDisablesSeekAndClearsPreview() async {
        let fixture = ScrubAutomationFixture()
        let (media, executor) = makeController(fixture)
        await refresh(media, position: 12)
        media.setScrubbing(true)
        media.updateScrubPosition(190)
        fixture.setOutput("Track A||Artist||playing||Spotify||nan||inf||||40")
        await refresh(media, position: 0)
        XCTAssertFalse(media.hasPlaybackProgress)
        XCTAssertFalse(media.isSeekControlAvailable)
        XCTAssertTrue(media.duration.isFinite)
        media.setScrubbing(false)
        media.seek(to: .nan)
        await executor.invalidateAndWaitForIdle()
        XCTAssertTrue(fixture.seekCommands.isEmpty)
    }

    @MainActor
    func testSpotifyWithoutNativeTrackIdentityDoesNotOfferOrIssueSeek() async {
        let fixture = ScrubAutomationFixture()
        fixture.setOutput("Track A||Artist||playing||Spotify||12||200||||40")
        let (media, executor) = makeController(fixture)
        await refresh(media, position: 12)
        XCTAssertTrue(media.hasPlaybackProgress)
        XCTAssertFalse(media.isSeekControlAvailable)
        media.setScrubbing(true)
        media.updateScrubPosition(198)
        media.setScrubbing(false)
        media.seek(to: 198)
        await executor.invalidateAndWaitForIdle()
        XCTAssertTrue(fixture.seekCommands.isEmpty)
    }

    @MainActor
    func testFailedSeekReleasesPreviewAndResumesProviderAuthorityWithoutRetry() async {
        let fixture = ScrubAutomationFixture()
        fixture.failSeek(.timedOut)
        let (media, executor) = makeController(fixture)
        await refresh(media, position: 12)
        media.setScrubbing(true)
        media.updateScrubPosition(198)
        let failed = expectation(description: "seek failure published")
        let subscription = media.$seekError.compactMap { $0 }.first().sink { _ in failed.fulfill() }
        media.setScrubbing(false)
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertEqual(media.seekError, "AppleScript timed out")
        XCTAssertEqual(media.displayedPlaybackPosition, media.playbackPosition)
        fixture.setOutput("Track A||Artist||playing||Spotify||14||200||||40||spotify:track:AAAAAAAAAAAAAAAAAAAAAA")
        await refresh(media, position: 14)
        XCTAssertEqual(media.displayedPlaybackPosition, 14)
        await executor.invalidateAndWaitForIdle()
        XCTAssertEqual(fixture.seekCommands.count, 1)
        subscription.cancel()
    }
}
