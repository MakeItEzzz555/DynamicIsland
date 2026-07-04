import XCTest
@testable import DynamicIsland

@MainActor
final class MediaSourceOpenTargetTests: XCTestCase {
    func testSpotifySourceMapsToSpotifyApp() {
        XCTAssertEqual(
            MediaSourceOpenTarget.resolve(
                sourceKind: .spotify,
                sourceName: "Spotify",
                bundleIdentifier: "com.spotify.client"
            ),
            .app(.spotify)
        )
    }

    func testMusicSourceMapsToMusicApp() {
        XCTAssertEqual(
            MediaSourceOpenTarget.resolve(
                sourceKind: .music,
                sourceName: "Music",
                bundleIdentifier: "com.apple.Music"
            ),
            .app(.music)
        )
    }

    func testYouTubeBraveSourceMapsToOwningBrowserBundle() {
        XCTAssertEqual(
            MediaSourceOpenTarget.resolve(
                sourceKind: .browser,
                sourceName: "YouTube",
                bundleIdentifier: "com.brave.Browser"
            ),
            .bundleIdentifier("com.brave.Browser")
        )
    }

    func testYouTubeWithoutBundleFallsBackToYouTube() {
        XCTAssertEqual(
            MediaSourceOpenTarget.resolve(
                sourceKind: .browser,
                sourceName: "YouTube",
                bundleIdentifier: nil
            ),
            .youtube
        )
    }

    func testUnknownSourceWithoutBundleFailsSafely() {
        XCTAssertNil(
            MediaSourceOpenTarget.resolve(
                sourceKind: .unknown,
                sourceName: "Unknown",
                bundleIdentifier: nil
            )
        )
    }
}
