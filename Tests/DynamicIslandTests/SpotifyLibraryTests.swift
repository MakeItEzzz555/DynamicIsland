import Foundation
import XCTest
@testable import DynamicIsland

private final class SpotifyTestCredentialStore: SpotifyCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: SpotifyStoredCredentials
    private(set) var clearCount = 0

    init(_ value: SpotifyStoredCredentials = SpotifyStoredCredentials()) {
        self.value = value
    }

    func credentials() -> SpotifyStoredCredentials {
        lock.withLock { value }
    }

    func store(accessToken: String, expiresAt: Date, refreshToken: String?) {
        lock.withLock {
            value.accessToken = accessToken
            value.accessTokenExpiry = expiresAt
            if let refreshToken { value.refreshToken = refreshToken }
        }
    }

    func clear() {
        lock.withLock {
            value = SpotifyStoredCredentials()
            clearCount += 1
        }
    }
}

private final class SpotifyMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Response = (status: Int, headers: [String: String], data: Data)
    typealias Handler = @Sendable (URLRequest) throws -> Response
    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let response = try handler(request)
            let http = HTTPURLResponse(
                url: request.url!, statusCode: response.status,
                httpVersion: "HTTP/1.1", headerFields: response.headers
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLSession {
    static func spotifyTestSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpotifyMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class SpotifyRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

final class SpotifyLibraryTests: XCTestCase {
    override func tearDown() {
        SpotifyMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testPKCEChallengeMatchesRFC7636Example() {
        XCTAssertEqual(
            SpotifyWebAPI.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
        let verifier = SpotifyWebAPI.codeVerifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertNil(verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testAuthorizationRequestsExactRequiredScopesWithPKCE() throws {
        let url = SpotifyWebAPI.authorizationURL(clientID: "abc12345", challenge: "xyz", state: "s1")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(
            values["scope"],
            "user-read-playback-state user-modify-playback-state playlist-read-private playlist-read-collaborative user-library-read user-library-modify"
        )
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["response_type"], "code")
        XCTAssertEqual(values["redirect_uri"], "dynamicisland://spotify-callback")
        XCTAssertNil(values["client_secret"])
    }

    func testCallbackValidationRejectsWrongURLAndState() throws {
        XCTAssertEqual(
            try SpotifyWebAPI.authorizationCode(
                from: URL(string: "dynamicisland://spotify-callback?code=ok&state=s1")!, expectedState: "s1"
            ),
            "ok"
        )
        XCTAssertThrowsError(try SpotifyWebAPI.authorizationCode(
            from: URL(string: "wrong://spotify-callback?code=ok&state=s1")!, expectedState: "s1"
        ))
        XCTAssertThrowsError(try SpotifyWebAPI.authorizationCode(
            from: URL(string: "dynamicisland://spotify-callback?code=ok&state=wrong")!, expectedState: "s1"
        ))
        XCTAssertThrowsError(try SpotifyWebAPI.authorizationCode(
            from: URL(string: "dynamicisland://other?code=ok&state=s1")!, expectedState: "s1"
        ))
        XCTAssertThrowsError(try SpotifyWebAPI.authorizationCode(
            from: URL(string: "dynamicisland://spotify-callback?error=access_denied&state=s1")!, expectedState: "s1"
        )) { error in
            XCTAssertEqual(error as? SpotifyLibraryError, .authorizationCancelled)
        }
        XCTAssertThrowsError(try SpotifyWebAPI.authorizationCode(
            from: URL(string: "dynamicisland://spotify-callback?code=one&code=two&state=s1")!, expectedState: "s1"
        ))
        XCTAssertThrowsError(try SpotifyWebAPI.authorizationCode(
            from: URL(string: "dynamicisland://spotify-callback?code=ok&state=s1&state=s1")!, expectedState: "s1"
        ))
        XCTAssertThrowsError(try SpotifyWebAPI.authorizationCode(
            from: URL(string: "dynamicisland://spotify-callback?code=ok&error=access_denied&state=s1")!, expectedState: "s1"
        ))
    }

    func testAuthConfigurationValidatesInjectedClientID() {
        XCTAssertEqual(SpotifyAuthConfiguration.normalizedClientID("  AbC123456  "), "AbC123456")
        XCTAssertNil(SpotifyAuthConfiguration.normalizedClientID("client-id"))
        XCTAssertNil(SpotifyAuthConfiguration.normalizedClientID("abc"))
    }

    func testParsesQueuePlaylistsAndPagination() throws {
        let queue = Data("""
        {"currently_playing":{"uri":"spotify:track:11dFghVXANMlKmJXsNCbNl","name":"Feeling","type":"track","artists":[{"name":"Artist"}]},
         "queue":[{"uri":"spotify:episode:512ojhOuo1ktJprKbVcKyQ","name":"Episode 1","type":"episode","show":{"name":"A Show"}}]}
        """.utf8)
        let parsed = try SpotifyWebAPI.parseQueue(queue)
        XCTAssertEqual(parsed.current?.kind, .track)
        XCTAssertEqual(parsed.queue.first?.kind, .episode)

        let playlists = try SpotifyWebAPI.parsePlaylistsPage(Data("""
        {"items":[{"uri":"spotify:playlist:37i9dQZF1DXcBWIGoYBM5M","name":"Hits","owner":{"display_name":"Spotify"},"items":{"total":50}}],
         "next":"https://api.spotify.com/v1/me/playlists?offset=50&limit=50"}
        """.utf8))
        XCTAssertEqual(playlists.items.first?.subtitle, "Spotify · 50 tracks")
        XCTAssertEqual(playlists.items.first?.kind, .playlist)
        XCTAssertNotNil(playlists.next)

        let saved = try SpotifyWebAPI.parseSavedTracksPage(Data("""
        {"items":[{"track":{"uri":"spotify:track:4iV5W9uYEdYUVa79Axb7Rh","name":"New Song","type":"track","artists":[{"name":"A"},{"name":"B"}]}}],"next":null}
        """.utf8))
        XCTAssertEqual(saved.items.first?.subtitle, "A, B")
        XCTAssertNil(saved.next)
    }

    func testOnlyWellFormedSpotifyURIsCanBePlayed() {
        XCTAssertTrue(MediaController.isValidSpotifyURI("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"))
        XCTAssertTrue(MediaController.isValidSpotifyURI("spotify:track:4iV5W9uYEdYUVa79Axb7Rh"))
        XCTAssertFalse(MediaController.isValidSpotifyURI("spotify:track:abc\" to quit"))
        XCTAssertFalse(MediaController.isValidSpotifyURI("https://open.spotify.com/track/x"))
    }

    @MainActor
    func testWithoutAppConfigurationStateIsTruthfulAndNothingFetches() async {
        let credentials = SpotifyTestCredentialStore()
        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: nil, source: .unavailable),
            tokens: credentials,
            session: .spotifyTestSession()
        )
        XCTAssertEqual(controller.connectionState, .needsClientID)
        await controller.refresh()
        XCTAssertNil(controller.snapshot)
        await controller.connect()
        XCTAssertEqual(controller.connectionState, .needsClientID)
        XCTAssertEqual(controller.lastError, SpotifyLibraryError.appNotConfigured.errorDescription)
    }

    @MainActor
    func testDisconnectClearsAllStoredCredentials() {
        let credentials = SpotifyTestCredentialStore(SpotifyStoredCredentials(
            accessToken: "access", accessTokenExpiry: Date().addingTimeInterval(600), refreshToken: "refresh"
        ))
        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: credentials
        )
        XCTAssertEqual(controller.connectionState, .connected)
        controller.disconnect()
        XCTAssertEqual(controller.connectionState, .disconnected)
        XCTAssertEqual(credentials.credentials(), SpotifyStoredCredentials())
        XCTAssertEqual(credentials.clearCount, 1)
    }

    @MainActor
    func testSuccessfulPKCECallbackStoresCredentialsAndLoadsLibrary() async throws {
        let credentials = SpotifyTestCredentialStore()
        SpotifyMockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.host == "accounts.spotify.com" {
                return (200, [:], Data("""
                {"access_token":"access-1","expires_in":3600,"refresh_token":"refresh-1"}
                """.utf8))
            }
            switch url.path {
            case "/v1/me/player/queue":
                return (200, [:], Data("{\"queue\":[]}".utf8))
            case "/v1/me/playlists", "/v1/me/tracks":
                return (200, [:], Data("{\"items\":[],\"next\":null}".utf8))
            default:
                XCTFail("Unexpected Spotify URL: \(url)")
                return (404, [:], Data())
            }
        }

        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: credentials,
            session: .spotifyTestSession(),
            authenticator: { authorizationURL in
                let query = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let state = try XCTUnwrap(query.first(where: { $0.name == "state" })?.value)
                return URL(string: "dynamicisland://spotify-callback?code=auth-code&state=\(state)")!
            }
        )
        await controller.connect()
        XCTAssertEqual(controller.connectionState, .connected)
        XCTAssertNotNil(controller.snapshot)
        let stored = credentials.credentials()
        XCTAssertEqual(stored.accessToken, "access-1")
        XCTAssertEqual(stored.refreshToken, "refresh-1")
        XCTAssertGreaterThan(stored.accessTokenExpiry ?? .distantPast, Date())
    }

    @MainActor
    func testPaginationAppendsWithoutDuplicates() async {
        let credentials = SpotifyTestCredentialStore(SpotifyStoredCredentials(
            accessToken: "access", accessTokenExpiry: Date().addingTimeInterval(600), refreshToken: "refresh"
        ))
        SpotifyMockURLProtocol.handler = { request in
            let url = request.url!
            if url.path == "/v1/me/player/queue" { return (200, [:], Data("{\"queue\":[]}".utf8)) }
            if url.path == "/v1/me/tracks" { return (200, [:], Data("{\"items\":[],\"next\":null}".utf8)) }
            if url.path == "/v1/me/playlists", url.query?.contains("offset=50") == true {
                return (200, [:], Data("""
                {"items":[{"uri":"spotify:playlist:BBBBBBBB","name":"Second"}],"next":null}
                """.utf8))
            }
            if url.path == "/v1/me/playlists" {
                return (200, [:], Data("""
                {"items":[{"uri":"spotify:playlist:AAAAAAAA","name":"First"}],
                 "next":"https://api.spotify.com/v1/me/playlists?offset=50&limit=50"}
                """.utf8))
            }
            return (404, [:], Data())
        }
        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: credentials,
            session: .spotifyTestSession()
        )
        await controller.refresh()
        XCTAssertEqual(controller.snapshot?.playlists.map(\.title), ["First"])
        XCTAssertTrue(controller.hasMorePlaylists)
        await controller.loadMorePlaylists()
        XCTAssertEqual(controller.snapshot?.playlists.map(\.title), ["First", "Second"])
        XCTAssertFalse(controller.hasMorePlaylists)
    }

    @MainActor
    func testQueueForbiddenDoesNotPreventLibrarySectionsLoading() async {
        let credentials = SpotifyTestCredentialStore(SpotifyStoredCredentials(
            accessToken: "access", accessTokenExpiry: Date().addingTimeInterval(600), refreshToken: "refresh"
        ))
        SpotifyMockURLProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/me/player/queue":
                return (403, [:], Data())
            case "/v1/me/playlists":
                return (200, [:], Data("{\"items\":[{\"uri\":\"spotify:playlist:AAAAAAAA\",\"name\":\"Mine\"}],\"next\":null}".utf8))
            case "/v1/me/tracks":
                return (200, [:], Data("{\"items\":[{\"track\":{\"uri\":\"spotify:track:BBBBBBBB\",\"name\":\"Saved\",\"type\":\"track\"}}],\"next\":null}".utf8))
            default:
                return (404, [:], Data())
            }
        }
        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: credentials,
            session: .spotifyTestSession()
        )
        await controller.refresh()
        XCTAssertEqual(controller.snapshot?.playlists.map(\.title), ["Mine"])
        XCTAssertEqual(controller.snapshot?.likedSongs.map(\.title), ["Saved"])
        XCTAssertEqual(controller.lastError, SpotifyLibraryError.forbidden.errorDescription)
    }

    @MainActor
    func testRateLimitDoesNotRetryStorm() async {
        let credentials = SpotifyTestCredentialStore(SpotifyStoredCredentials(
            accessToken: "access", accessTokenExpiry: Date().addingTimeInterval(600), refreshToken: "refresh"
        ))
        let counter = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { request in
            counter.increment()
            if request.url!.path == "/v1/me/player/queue" {
                return (429, ["Retry-After": "7"], Data())
            }
            return (200, [:], Data("{\"items\":[],\"next\":null}".utf8))
        }
        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: credentials,
            session: .spotifyTestSession()
        )
        await controller.refresh()
        XCTAssertEqual(counter.value, 3)
        XCTAssertEqual(controller.lastError, SpotifyLibraryError.rateLimited(retryAfterSeconds: 7).errorDescription)
    }

    @MainActor
    func testUnauthorizedRequestRefreshesOnceThenRetriesOnce() async {
        let credentials = SpotifyTestCredentialStore(SpotifyStoredCredentials(
            accessToken: "old", accessTokenExpiry: Date().addingTimeInterval(600), refreshToken: "refresh"
        ))
        let queueCounter = SpotifyRequestCounter()
        let tokenCounter = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { request in
            let url = request.url!
            if url.host == "accounts.spotify.com" {
                tokenCounter.increment()
                return (200, [:], Data("{\"access_token\":\"new\",\"expires_in\":3600}".utf8))
            }
            if url.path == "/v1/me/player/queue" {
                queueCounter.increment()
                let authorization = request.value(forHTTPHeaderField: "Authorization")
                if authorization == "Bearer old" { return (401, [:], Data()) }
                return (200, [:], Data("{\"queue\":[]}".utf8))
            }
            return (200, [:], Data("{\"items\":[],\"next\":null}".utf8))
        }
        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: credentials,
            session: .spotifyTestSession()
        )
        await controller.refresh()
        XCTAssertEqual(queueCounter.value, 2)
        XCTAssertEqual(tokenCounter.value, 1)
        XCTAssertEqual(credentials.credentials().accessToken, "new")
        XCTAssertNil(controller.lastError)
    }

    @MainActor
    func testSaveAndUnsaveUseGenericLibraryEndpointAndUpdateLikedSongs() async {
        let credentials = SpotifyTestCredentialStore(SpotifyStoredCredentials(
            accessToken: "access", accessTokenExpiry: Date().addingTimeInterval(600), refreshToken: "refresh"
        ))
        let item = SpotifyMediaItem(
            uri: "spotify:track:BBBBBBBB", title: "Saved", subtitle: "Artist", imageURL: nil, kind: .track
        )
        let mutationCounter = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { request in
            let url = request.url!
            if url.path == "/v1/me/player/queue" { return (200, [:], Data("{\"queue\":[]}".utf8)) }
            if url.path == "/v1/me/playlists" { return (200, [:], Data("{\"items\":[],\"next\":null}".utf8)) }
            if url.path == "/v1/me/tracks" { return (200, [:], Data("{\"items\":[],\"next\":null}".utf8)) }
            if url.path == "/v1/me/library" {
                mutationCounter.increment()
                XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "uris" })?.value, item.uri)
                XCTAssertTrue(request.httpMethod == "PUT" || request.httpMethod == "DELETE")
                return (200, [:], Data())
            }
            return (404, [:], Data())
        }
        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: credentials,
            session: .spotifyTestSession()
        )
        await controller.refresh()
        await controller.setSaved(item, saved: true)
        XCTAssertEqual(controller.snapshot?.likedSongs.map(\.id), [item.id])
        await controller.setSaved(item, saved: false)
        XCTAssertTrue(controller.snapshot?.likedSongs.isEmpty ?? false)
        XCTAssertEqual(mutationCounter.value, 2)
    }
}
