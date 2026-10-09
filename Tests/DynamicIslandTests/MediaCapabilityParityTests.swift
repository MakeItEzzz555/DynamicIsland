import AppKit
import Combine
import XCTest
@testable import DynamicIsland

/// Phase 15 media capability parity: local Spotify/Music control must never
/// depend on Spotify Web API configuration, and Now Playing classification
/// must never route AppleScript commands to an app that is not the source.
private final class ParityLockedSources: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [String] = []

    func append(_ source: String) { lock.withLock { sources.append(source) } }
    var all: [String] { lock.withLock { sources } }
}

private final class ParityNoCredentialStore: SpotifyCredentialStoring, @unchecked Sendable {
    func credentials() -> SpotifyStoredCredentials { SpotifyStoredCredentials() }
    func store(accessToken: String, expiresAt: Date, refreshToken: String?, authorizationDate: Date?) {}
    func clear() {}
}

@MainActor
private final class ParityNoSystemProvider: MediaDetectionProvider {
    let name = "Test"
    func snapshot() async -> MediaSnapshot? { nil }
}

@MainActor
private final class ParityStaticMediaRemote: MediaRemoteProviding {
    let isAvailable = true
    let info: NSDictionary
    let displayName: String?

    init(info: [String: Any], displayName: String?) {
        self.info = info as NSDictionary
        self.displayName = displayName
    }

    func nowPlayingInfo() async -> NSDictionary? { info }
    func nowPlayingApplicationDisplayName() async -> String? { displayName }
}

final class MediaCapabilityParityTests: XCTestCase {
    @MainActor
    func testMissingSpotifyClientIDDoesNotRegressLocalSpotifyDetectionOrControls() async {
        let library = SpotifyLibraryController(
            defaults: UserDefaults(suiteName: "MediaCapabilityParityTests.\(UUID().uuidString)")!,
            configuration: SpotifyAuthConfiguration(clientID: nil, source: .unavailable),
            tokens: ParityNoCredentialStore(),
            session: .shared
        )
        XCTAssertEqual(library.connectionState, .needsClientID)
        XCTAssertFalse(library.isConfigured)

        let executed = ParityLockedSources()
        let commandsSent = expectation(description: "local Spotify commands executed")
        commandsSent.expectedFulfillmentCount = 2
        let executor = MediaAutomationExecutor(runner: { source, _ in
            executed.append(source)
            if source == "tell application \"Spotify\" to playpause" ||
                source == "tell application \"Spotify\" to next track" {
                commandsSent.fulfill()
            }
            if source.contains("with timeout"), source.contains("tell application \"Spotify\"") {
                return MediaAutomationScriptResult(
                    output: "Local Song||Local Artist||playing||Spotify||12||200||||40||spotify:track:AAAAAAAAAAAAAAAAAAAAAA",
                    failure: nil
                )
            }
            return MediaAutomationScriptResult(output: "", failure: nil)
        })
        let media = MediaController(
            automationExecutor: executor,
            systemNowPlayingProvider: ParityNoSystemProvider(),
            startsAutomatically: false
        )
        let published = expectation(description: "local Spotify published")
        let subscription = media.$title.sink { title in
            if title == "Local Song" { published.fulfill() }
        }

        media.refresh()
        await fulfillment(of: [published], timeout: 2)

        XCTAssertEqual(media.sourceName, "Spotify")
        XCTAssertTrue(media.isTransportControlAvailable)
        XCTAssertTrue(media.isSeekControlAvailable)
        XCTAssertTrue(media.isVolumeControlAvailable)

        media.playPause()
        media.nextTrack()
        await fulfillment(of: [commandsSent], timeout: 3)

        // The Spotify library stays truthfully unconfigured and never fetched.
        XCTAssertEqual(library.connectionState, .needsClientID)
        XCTAssertNil(library.snapshot)
        XCTAssertFalse(executed.all.contains { $0.hasPrefix("tell application \"Music\" to") })

        await executor.invalidateAndWaitForIdle()
        subscription.cancel()
    }

    func testNowPlayingClassificationRequiresExactSpotifyOrMusicIdentity() {
        typealias Provider = NowPlayingMediaProvider
        XCTAssertEqual(Provider.sourceKind(for: "com.spotify.client", sourceName: "Spotify"), .spotify)
        XCTAssertEqual(Provider.sourceKind(for: "com.apple.Music", sourceName: "Music"), .music)
        XCTAssertEqual(Provider.sourceKind(for: nil, sourceName: "Music"), .music)
        XCTAssertEqual(Provider.sourceKind(for: nil, sourceName: "Spotify"), .spotify)
        XCTAssertEqual(Provider.sourceKind(for: "com.apple.Safari", sourceName: "Safari"), .browser)

        // Third-party players whose names merely contain "Music"/"Spotify" must
        // not be treated as Music.app/Spotify.app (commands would be routed there).
        XCTAssertEqual(Provider.sourceKind(for: "com.github.th-ch.youtube-music", sourceName: "YouTube Music"), .system)
        XCTAssertEqual(Provider.sourceKind(for: nil, sourceName: "YouTube Music"), .system)
        XCTAssertEqual(Provider.sourceKind(for: "com.example.spotifyish", sourceName: "Spotify Helper"), .system)
        XCTAssertEqual(Provider.sourceKind(for: "com.apple.podcasts", sourceName: "Podcasts"), .system)
    }

    @MainActor
    func testSystemOnlySourceOffersNoTransportCommands() async {
        let remote = ParityStaticMediaRemote(info: [
            "kMRMediaRemoteNowPlayingInfoTitle": "Episode",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1.0
        ], displayName: "YouTube Music")
        let provider = NowPlayingMediaProvider(mediaRemote: remote)
        let snapshot = await provider.snapshot()
        XCTAssertEqual(snapshot?.sourceKind, .system)
        XCTAssertEqual(snapshot?.transportAvailable, false)
        XCTAssertEqual(snapshot?.seekAvailable, false)
        XCTAssertEqual(snapshot?.volumeAvailable, false)
    }

    func testUnconfiguredSpotifyCopyStaysTruthfulAboutLocalControls() {
        for copy in [SpotifySectionCopy.notConfigured, SpotifySectionCopy.settingsNotConfigured] {
            XCTAssertTrue(copy.localizedCaseInsensitiveContains("not"), copy)
            XCTAssertTrue(copy.contains("Spotify app"), copy)
            XCTAssertTrue(copy.localizedCaseInsensitiveContains("work"), copy)
        }
    }
}
