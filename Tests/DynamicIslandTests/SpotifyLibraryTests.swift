import XCTest
@testable import DynamicIsland

final class SpotifyLibraryTests: XCTestCase {
    func testPKCEChallengeMatchesRFC7636Example() {
        // RFC 7636 Appendix B.
        XCTAssertEqual(
            SpotifyWebAPI.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
        let verifier = SpotifyWebAPI.codeVerifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertNil(verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testAuthorizationRequestsOnlyReadScopesWithPKCE() throws {
        let url = SpotifyWebAPI.authorizationURL(clientID: "abc123", challenge: "xyz", state: "s1")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["scope"], "user-read-playback-state playlist-read-private user-library-read")
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["response_type"], "code")
        XCTAssertEqual(values["redirect_uri"], "dynamicisland://spotify-callback")
        XCTAssertFalse(values["scope"]!.contains("modify"))
    }

    func testParsesQueuePlaylistsAndSavedTracksFromWebAPIShapes() throws {
        let queue = Data("""
        {"currently_playing":{"uri":"spotify:track:11dFghVXANMlKmJXsNCbNl","name":"Cut To The Feeling",
          "artists":[{"name":"Carly Rae Jepsen"}],"album":{"images":[{"url":"https://i.scdn.co/a","width":640},{"url":"https://i.scdn.co/b","width":64}]}},
         "queue":[{"uri":"spotify:episode:512ojhOuo1ktJprKbVcKyQ","name":"Episode 1","show":{"name":"A Show"},"images":[]},
                  {"name":"missing uri"}]}
        """.utf8)
        let parsed = try SpotifyWebAPI.parseQueue(queue)
        XCTAssertEqual(parsed.current?.title, "Cut To The Feeling")
        XCTAssertEqual(parsed.current?.subtitle, "Carly Rae Jepsen")
        XCTAssertEqual(parsed.current?.imageURL, URL(string: "https://i.scdn.co/b"))
        XCTAssertEqual(parsed.queue.map(\.subtitle), ["A Show"])

        let empty = try SpotifyWebAPI.parseQueue(Data("{}".utf8))
        XCTAssertNil(empty.current)
        XCTAssertTrue(empty.queue.isEmpty)

        let playlists = try SpotifyWebAPI.parsePlaylists(Data("""
        {"items":[{"uri":"spotify:playlist:37i9dQZF1DXcBWIGoYBM5M","name":"Today's Top Hits",
          "owner":{"display_name":"Spotify"},"tracks":{"total":50},"images":[]}]}
        """.utf8))
        XCTAssertEqual(playlists.first?.subtitle, "Spotify · 50 tracks")

        let saved = try SpotifyWebAPI.parseSavedTracks(Data("""
        {"items":[{"track":{"uri":"spotify:track:4iV5W9uYEdYUVa79Axb7Rh","name":"New Song","artists":[{"name":"A"},{"name":"B"}]}}]}
        """.utf8))
        XCTAssertEqual(saved.first?.subtitle, "A, B")

        XCTAssertThrowsError(try SpotifyWebAPI.parsePlaylists(Data("[]".utf8)))
    }

    func testOnlyWellFormedSpotifyURIsCanBePlayed() {
        XCTAssertTrue(MediaController.isValidSpotifyURI("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"))
        XCTAssertTrue(MediaController.isValidSpotifyURI("spotify:track:4iV5W9uYEdYUVa79Axb7Rh"))
        XCTAssertFalse(MediaController.isValidSpotifyURI("spotify:track:abc\" to quit"))
        XCTAssertFalse(MediaController.isValidSpotifyURI("https://open.spotify.com/track/x"))
        XCTAssertFalse(MediaController.isValidSpotifyURI("spotify:user:me:collection"))
    }

    @MainActor
    func testWithoutClientIDTheStateIsTruthfulAndNothingIsFetched() async throws {
        let suite = "SpotifyLibraryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SpotifyLibraryController(
            defaults: defaults,
            tokens: SpotifyTokenStore(service: "com.local.dynamicisland.spotify.tests.\(UUID().uuidString)")
        )
        XCTAssertEqual(controller.connectionState, .needsClientID)
        await controller.refresh()
        XCTAssertNil(controller.snapshot)
        await controller.connect()
        XCTAssertEqual(controller.connectionState, .needsClientID)
        XCTAssertEqual(controller.lastError, SpotifyLibraryError.missingClientID.errorDescription)

        controller.setClientID("  client-id ")
        XCTAssertEqual(controller.clientID, "client-id")
        XCTAssertEqual(controller.connectionState, .disconnected)
        controller.setClientID("")
        XCTAssertEqual(controller.connectionState, .needsClientID)
    }
}
