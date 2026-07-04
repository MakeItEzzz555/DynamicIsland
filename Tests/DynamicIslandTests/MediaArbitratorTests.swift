import XCTest
@testable import DynamicIsland

final class MediaArbitratorTests: XCTestCase {
    func testPausedSpotifyAndPausedYouTubeKeepsCurrentSpotify() {
        let spotify = spotifyCandidate(isPlaying: false)
        let youtube = youtubeCandidate(isPlaying: false)

        let selected = MediaArbitrator.selectBestCandidate(
            from: [spotify, youtube],
            currentIdentity: spotify.identity
        )

        XCTAssertEqual(selected?.identity, spotify.identity)
    }

    func testPausedYouTubeAndPausedSpotifyKeepsCurrentYouTube() {
        let spotify = spotifyCandidate(isPlaying: false)
        let youtube = youtubeCandidate(isPlaying: false)

        let selected = MediaArbitrator.selectBestCandidate(
            from: [youtube, spotify],
            currentIdentity: youtube.identity
        )

        XCTAssertEqual(selected?.identity, youtube.identity)
    }

    func testPlayingYouTubeBeatsPausedSpotify() {
        let spotify = spotifyCandidate(isPlaying: false)
        let youtube = youtubeCandidate(isPlaying: true)

        let selected = MediaArbitrator.selectBestCandidate(
            from: [spotify, youtube],
            currentIdentity: spotify.identity
        )

        XCTAssertEqual(selected?.identity, youtube.identity)
    }

    func testPlayingSpotifyBeatsPausedYouTube() {
        let spotify = spotifyCandidate(isPlaying: true)
        let youtube = youtubeCandidate(isPlaying: false)

        let selected = MediaArbitrator.selectBestCandidate(
            from: [youtube, spotify],
            currentIdentity: youtube.identity
        )

        XCTAssertEqual(selected?.identity, spotify.identity)
    }

    func testSpotifyPlayingBeatsPausedYouTubeWithoutCurrentSelection() {
        let spotify = spotifyCandidate(isPlaying: true)
        let youtube = youtubeCandidate(isPlaying: false)

        let selected = MediaArbitrator.selectBestCandidate(
            from: [youtube, spotify],
            currentIdentity: nil
        )

        XCTAssertEqual(selected?.identity, spotify.identity)
    }

    func testNativeSpotifyPlayingBeatsBrowserPlayingNoise() {
        let spotify = spotifyCandidate(isPlaying: true)
        let youtube = youtubeCandidate(isPlaying: true)

        let selected = MediaArbitrator.selectBestCandidate(
            from: [youtube, spotify],
            currentIdentity: spotify.identity
        )

        XCTAssertEqual(selected?.identity, spotify.identity)
    }

    func testSelectedSpotifyDisappearsFallsBackToPausedYouTube() {
        let spotify = spotifyCandidate(isPlaying: false)
        let youtube = youtubeCandidate(isPlaying: false)

        let selected = MediaArbitrator.selectBestCandidate(
            from: [youtube],
            currentIdentity: spotify.identity
        )

        XCTAssertEqual(selected?.identity, youtube.identity)
    }

    func testYouTubeMetadataEnrichmentDoesNotStealPausedSelectionFromSpotify() {
        let spotify = spotifyCandidate(isPlaying: false)
        let enrichedYouTube = youtubeCandidate(
            title: "Enriched YouTube Title",
            artist: "Enriched Channel",
            isPlaying: false
        )

        let selected = MediaArbitrator.selectBestCandidate(
            from: [spotify, enrichedYouTube],
            currentIdentity: spotify.identity
        )

        XCTAssertEqual(selected?.identity, spotify.identity)
    }

    func testNoCurrentSelectionUsesDeterministicPausedFallback() {
        let spotify = spotifyCandidate(isPlaying: false)
        let youtube = youtubeCandidate(isPlaying: false)

        let selected = MediaArbitrator.selectBestCandidate(
            from: [youtube, spotify],
            currentIdentity: nil
        )

        XCTAssertEqual(selected?.identity, spotify.identity)
    }

    func testYouTubeEnrichmentCannotPublishOverSelectedSpotify() {
        let spotify = spotifyCandidate(isPlaying: true)
        let youtube = youtubeCandidate(isPlaying: false)

        XCTAssertFalse(
            MediaPublishGuard.canApplyAsyncUpdate(
                selectedIdentity: spotify.identity,
                selectedGeneration: 4,
                requestIdentity: youtube.identity,
                requestGeneration: 4
            )
        )
    }

    func testYouTubeEnrichmentCanPublishForSameSelectedGeneration() {
        let youtube = youtubeCandidate(isPlaying: false)

        XCTAssertTrue(
            MediaPublishGuard.canApplyAsyncUpdate(
                selectedIdentity: youtube.identity,
                selectedGeneration: 4,
                requestIdentity: youtube.identity,
                requestGeneration: 4
            )
        )
    }

    func testStaleYouTubeEnrichmentCannotPublishForSameIdentityOldGeneration() {
        let youtube = youtubeCandidate(isPlaying: false)

        XCTAssertFalse(
            MediaPublishGuard.canApplyAsyncUpdate(
                selectedIdentity: youtube.identity,
                selectedGeneration: 5,
                requestIdentity: youtube.identity,
                requestGeneration: 4
            )
        )
    }

    func testPausedSwitchFirstPollIsBlockedWhenCurrentWasPlaying() {
        let spotify = spotifyCandidate(isPlaying: true)
        let youtube = youtubeCandidate(isPlaying: false)
        let now = Date()

        let decision = MediaPausedSwitchGate.decision(
            candidateIdentity: youtube.identity,
            currentIdentity: spotify.identity,
            currentWasPlaying: true,
            pendingIdentity: nil,
            pendingFirstSeenAt: nil,
            pendingCount: 0,
            now: now
        )

        XCTAssertFalse(decision.shouldPublish)
        XCTAssertEqual(decision.count, 1)
    }

    func testPausedSwitchSecondConfirmedPollIsAllowed() {
        let spotify = spotifyCandidate(isPlaying: true)
        let youtube = youtubeCandidate(isPlaying: false)
        let firstSeenAt = Date()

        let decision = MediaPausedSwitchGate.decision(
            candidateIdentity: youtube.identity,
            currentIdentity: spotify.identity,
            currentWasPlaying: true,
            pendingIdentity: youtube.identity,
            pendingFirstSeenAt: firstSeenAt,
            pendingCount: 1,
            now: firstSeenAt.addingTimeInterval(0.5)
        )

        XCTAssertTrue(decision.shouldPublish)
        XCTAssertEqual(decision.count, 2)
    }

    func testInitialPausedSelectionIsAllowedWithoutDebounce() {
        let youtube = youtubeCandidate(isPlaying: false)

        let decision = MediaPausedSwitchGate.decision(
            candidateIdentity: youtube.identity,
            currentIdentity: nil,
            currentWasPlaying: false,
            pendingIdentity: nil,
            pendingFirstSeenAt: nil,
            pendingCount: 0,
            now: Date()
        )

        XCTAssertTrue(decision.shouldPublish)
    }

    func testSameSpotifyArtworkURLProducesStableArtworkKey() {
        let first = spotifyCandidate(isPlaying: true, artworkURL: "https://i.scdn.co/image/abc")
        let second = spotifyCandidate(isPlaying: true, artworkURL: "https://i.scdn.co/image/abc")

        XCTAssertEqual(first.artworkKey, second.artworkKey)
        XCTAssertEqual(first.artworkKey, "url:https://i.scdn.co/image/abc")
    }

    func testSpotifyMissingArtworkURLKeepsStableMediaIdentity() {
        let withArtwork = spotifyCandidate(isPlaying: true, artworkURL: "https://i.scdn.co/image/abc")
        let withoutArtwork = spotifyCandidate(isPlaying: true)

        XCTAssertEqual(withArtwork.identity, withoutArtwork.identity)
        XCTAssertNil(withoutArtwork.artworkKey)
    }

    func testYouTubeArtworkKeyUsesVideoIDWhenThumbnailURLMissing() {
        let youtube = youtubeCandidate(isPlaying: true)

        XCTAssertEqual(youtube.artworkKey, "youtube:abc123")
    }

    private func spotifyCandidate(isPlaying: Bool, artworkURL: String? = nil) -> MediaCandidate {
        mediaCandidate(
            providerName: "Spotify AppleScript",
            sourceKind: .spotify,
            sourceName: "Spotify",
            bundleIdentifier: "com.spotify.client",
            title: "Paused Spotify Track",
            artist: "Spotify Artist",
            isPlaying: isPlaying,
            artworkURL: artworkURL
        )
    }

    private func youtubeCandidate(
        title: String = "Paused YouTube Video",
        artist: String = "YouTube",
        isPlaying: Bool
    ) -> MediaCandidate {
        mediaCandidate(
            providerName: "Browser AppleScript",
            sourceKind: .browser,
            sourceName: "YouTube",
            bundleIdentifier: "com.brave.Browser",
            title: title,
            artist: artist,
            isPlaying: isPlaying,
            youtubePageURL: "https://www.youtube.com/watch?v=abc123",
            youtubeVideoID: "abc123"
        )
    }

    private func mediaCandidate(
        providerName: String,
        sourceKind: MediaSourceKind,
        sourceName: String,
        bundleIdentifier: String?,
        title: String,
        artist: String?,
        isPlaying: Bool,
        artworkURL: String? = nil,
        youtubePageURL: String? = nil,
        youtubeVideoID: String? = nil
    ) -> MediaCandidate {
        MediaCandidate(
            providerName: providerName,
            snapshot: MediaSnapshot(
                sourceKind: sourceKind,
                sourceName: sourceName,
                bundleIdentifier: bundleIdentifier,
                title: title,
                artist: artist,
                album: nil,
                artwork: nil,
                isPlaying: isPlaying,
                duration: nil,
                elapsedTime: nil,
                transportAvailable: false,
                seekAvailable: false,
                volumeAvailable: false
            ),
            hasPlaybackProgress: false,
            artworkURL: artworkURL,
            youtubePageURL: youtubePageURL,
            youtubeVideoID: youtubeVideoID
        )
    }
}
