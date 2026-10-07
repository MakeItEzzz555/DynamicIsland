import Foundation
import Combine
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

    func store(accessToken: String, expiresAt: Date, refreshToken: String?, authorizationDate: Date?) {
        lock.withLock {
            value.accessToken = accessToken
            value.accessTokenExpiry = expiresAt
            if let refreshToken { value.refreshToken = refreshToken }
            if let authorizationDate { value.authorizationDate = authorizationDate }
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

@MainActor
private final class SpotifySeekNoSystemProvider: MediaDetectionProvider {
    let name = "Test"
    func snapshot() async -> MediaSnapshot? { nil }
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
        XCTAssertNotNil(stored.authorizationDate)
        XCTAssertLessThan(abs(stored.authorizationDate?.timeIntervalSinceNow ?? .infinity), 5)
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

    func testRefreshAuthorizationExpiresSixCalendarMonthsAfterOriginalAuthorization() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let authorized = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let fiveMonthsLater = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let sevenMonthsLater = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        XCTAssertFalse(SpotifyWebAPI.refreshAuthorizationExpired(authorizationDate: authorized, now: fiveMonthsLater))
        XCTAssertTrue(SpotifyWebAPI.refreshAuthorizationExpired(authorizationDate: authorized, now: sevenMonthsLater))
    }

    @MainActor
    func testExpiredStoredAuthorizationRequiresReconnectAndClearsCredentials() {
        let oldAuthorization = Calendar.current.date(byAdding: .month, value: -7, to: Date())!
        let credentials = SpotifyTestCredentialStore(SpotifyStoredCredentials(
            accessToken: "access",
            accessTokenExpiry: Date().addingTimeInterval(600),
            refreshToken: "refresh",
            authorizationDate: oldAuthorization
        ))
        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: credentials,
            session: .spotifyTestSession()
        )
        XCTAssertEqual(controller.connectionState, .reconnectRequired)
        XCTAssertEqual(controller.lastError, SpotifyLibraryError.reauthorizationRequired.errorDescription)
        XCTAssertEqual(credentials.credentials(), SpotifyStoredCredentials())
        XCTAssertEqual(credentials.clearCount, 1)
    }

    @MainActor
    func testExpiredRefreshTokenInvalidGrantRequiresReconnectWithoutRetryStorm() async {
        let credentials = SpotifyTestCredentialStore(SpotifyStoredCredentials(
            accessToken: "expired",
            accessTokenExpiry: Date().addingTimeInterval(-60),
            refreshToken: "refresh",
            authorizationDate: Date()
        ))
        let tokenCounter = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { request in
            if request.url?.host == "accounts.spotify.com" {
                tokenCounter.increment()
                return (400, [:], Data("{\"error\":\"invalid_grant\"}".utf8))
            }
            XCTFail("Web API request should not run after invalid_grant")
            return (500, [:], Data())
        }
        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: credentials,
            session: .spotifyTestSession()
        )
        await controller.refresh()
        XCTAssertEqual(tokenCounter.value, 1)
        XCTAssertEqual(controller.connectionState, .reconnectRequired)
        XCTAssertEqual(controller.lastError, SpotifyLibraryError.reauthorizationRequired.errorDescription)
        XCTAssertEqual(credentials.credentials(), SpotifyStoredCredentials())
        XCTAssertEqual(credentials.clearCount, 1)
    }

    @MainActor
    func testSuccessfulRefreshPreservesOriginalAuthorizationDate() async {
        let originalAuthorization = Date().addingTimeInterval(-60 * 60 * 24 * 30)
        let credentials = SpotifyTestCredentialStore(SpotifyStoredCredentials(
            accessToken: "expired",
            accessTokenExpiry: Date().addingTimeInterval(-60),
            refreshToken: "refresh",
            authorizationDate: originalAuthorization
        ))
        SpotifyMockURLProtocol.handler = { request in
            if request.url?.host == "accounts.spotify.com" {
                return (200, [:], Data("{\"access_token\":\"new-access\",\"expires_in\":3600}".utf8))
            }
            if request.url?.path == "/v1/me/player/queue" { return (200, [:], Data("{\"queue\":[]}".utf8)) }
            return (200, [:], Data("{\"items\":[],\"next\":null}".utf8))
        }
        let controller = SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: credentials,
            session: .spotifyTestSession()
        )
        await controller.refresh()
        XCTAssertEqual(credentials.credentials().authorizationDate, originalAuthorization)
        XCTAssertEqual(credentials.credentials().accessToken, "new-access")
        XCTAssertEqual(controller.connectionState, .connected)
    }

    @MainActor
    func testQuotaExceededIsDistinctFromOrdinaryRateLimitAndDoesNotRetry() async {
        let credentials = SpotifyTestCredentialStore(SpotifyStoredCredentials(
            accessToken: "access",
            accessTokenExpiry: Date().addingTimeInterval(600),
            refreshToken: "refresh",
            authorizationDate: Date()
        ))
        let counter = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { request in
            counter.increment()
            if request.url?.path == "/v1/me/player/queue" {
                return (429, ["Retry-After": "42"], Data("{\"error\":{\"status\":429,\"message\":\"Too many requests\",\"reason\":\"QUOTA_EXCEEDED\"}}".utf8))
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
        XCTAssertEqual(controller.lastError, SpotifyLibraryError.quotaExceeded(retryAfterSeconds: 42).errorDescription)
        XCTAssertEqual(controller.connectionState, .connected)
    }


    @MainActor
    private func seekController() -> SpotifyLibraryController {
        SpotifyLibraryController(
            configuration: SpotifyAuthConfiguration(clientID: "Abc123456", source: .appBundle),
            tokens: SpotifyTestCredentialStore(SpotifyStoredCredentials(
                accessToken: "access", accessTokenExpiry: Date().addingTimeInterval(600),
                refreshToken: "refresh", authorizationDate: Date()
            )), session: .spotifyTestSession()
        )
    }

    @MainActor
    func testSeekConvertsSecondsAndPinsVerifiedActiveDeviceExactlyOnce() async throws {
        let writes = SpotifyRequestCounter()
        let uri = "spotify:track:AAAAAAAAAAAAAAAAAAAAAA"
        SpotifyMockURLProtocol.handler = { request in
            if request.httpMethod == "GET" {
                return (200, [:], Data(#"{"shuffle_state":false,"repeat_state":"off","item":{"uri":"spotify:track:AAAAAAAAAAAAAAAAAAAAAA","duration_ms":200000},"device":{"id":"computer-123","is_active":true}}"#.utf8))
            }
            writes.increment()
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/v1/me/player/seek")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "position_ms" }?.value, "199750")
            XCTAssertEqual(query.first { $0.name == "device_id" }?.value, "computer-123")
            return (204, [:], Data())
        }
        let issued = try await seekController().seek(to: 205, duration: 200, expectedTrackURI: uri, isCurrent: { true })
        XCTAssertTrue(issued)
        XCTAssertEqual(writes.value, 1)
    }

    @MainActor
    func testSeekRejectsMismatchedTrackOrUnavailableActiveDeviceWithoutWriting() async throws {
        for response in [
            #"{"shuffle_state":false,"item":{"uri":"spotify:track:BBBBBBBBBBBBBBBBBBBBBB","duration_ms":200000},"device":{"id":"computer-123","is_active":true}}"#,
            #"{"shuffle_state":false,"item":{"uri":"spotify:track:AAAAAAAAAAAAAAAAAAAAAA","duration_ms":200000},"device":{"id":"computer-123","is_active":false}}"#,
            #"{"shuffle_state":false,"item":{"uri":"spotify:track:AAAAAAAAAAAAAAAAAAAAAA","duration_ms":200000},"device":{"is_active":true}}"#,
            #"{"shuffle_state":false,"item":{"uri":"spotify:track:AAAAAAAAAAAAAAAAAAAAAA","duration_ms":190000},"device":{"id":"computer-123","is_active":true}}"#
        ] {
            let writes = SpotifyRequestCounter()
            SpotifyMockURLProtocol.handler = { request in
                if request.httpMethod == "PUT" { writes.increment() }
                return (200, [:], Data(response.utf8))
            }
            let issued = try await seekController().seek(to: 195, duration: 200,
                expectedTrackURI: "spotify:track:AAAAAAAAAAAAAAAAAAAAAA", isCurrent: { true })
            XCTAssertFalse(issued)
            XCTAssertEqual(writes.value, 0)
        }
    }

    @MainActor
    func testTinyTrackAPISeekPinsDeviceAndUsesNonnegativeSafeMilliseconds() async throws {
        let writes = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { request in
            if request.httpMethod == "GET" {
                return (200, [:], Data(#"{"shuffle_state":false,"item":{"uri":"spotify:track:AAAAAAAAAAAAAAAAAAAAAA","duration_ms":100},"device":{"id":"computer-123","is_active":true}}"#.utf8))
            }
            writes.increment()
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "position_ms" }?.value, "0")
            XCTAssertEqual(query.first { $0.name == "device_id" }?.value, "computer-123")
            return (204, [:], Data())
        }
        let issued = try await seekController().seek(to: 0.1, duration: 0.1,
            expectedTrackURI: "spotify:track:AAAAAAAAAAAAAAAAAAAAAA", isCurrent: { true })
        XCTAssertTrue(issued)
        XCTAssertEqual(writes.value, 1)
    }

    @MainActor
    func testSeekRevalidatesLocalIdentityAfterAwaitedPlaybackRead() async throws {
        let writes = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { request in
            if request.httpMethod == "PUT" { writes.increment() }
            return (200, [:], Data(#"{"shuffle_state":false,"item":{"uri":"spotify:track:AAAAAAAAAAAAAAAAAAAAAA","duration_ms":200000},"device":{"id":"computer-123","is_active":true}}"#.utf8))
        }
        var checks = 0
        let issued = try await seekController().seek(to: 195, duration: 200,
            expectedTrackURI: "spotify:track:AAAAAAAAAAAAAAAAAAAAAA", isCurrent: {
                checks += 1
                return checks == 1
            })
        XCTAssertFalse(issued)
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(writes.value, 0)
    }

    @MainActor
    func testSeekWriteFailureIsNotAutomaticallyReplayed() async {
        let writes = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                writes.increment()
                return (503, [:], Data())
            }
            return (200, [:], Data(#"{"shuffle_state":false,"item":{"uri":"spotify:track:AAAAAAAAAAAAAAAAAAAAAA","duration_ms":200000},"device":{"id":"computer-123","is_active":true}}"#.utf8))
        }
        do {
            _ = try await seekController().seek(to: 195, duration: 200,
                expectedTrackURI: "spotify:track:AAAAAAAAAAAAAAAAAAAAAA", isCurrent: { true })
            XCTFail("Expected write failure")
        } catch {
            XCTAssertEqual(error as? SpotifyLibraryError, .requestFailed(503))
        }
        XCTAssertEqual(writes.value, 1)
    }

    @MainActor
    func testSeekRejectsInvalidInputBeforeNetworking() async throws {
        let requests = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { _ in
            requests.increment()
            return (204, [:], Data())
        }
        let controller = seekController()
        for position in [Double.nan, .infinity, -.infinity] {
            let issued = try await controller.seek(to: position, duration: 200,
                expectedTrackURI: "spotify:track:AAAAAAAAAAAAAAAAAAAAAA", isCurrent: { true })
            XCTAssertFalse(issued)
        }
        XCTAssertEqual(requests.value, 0)
    }


    @MainActor
    func testConnectedSpotifyReleasePrefersAPIAndNeverFallsBackAfterWriteFailure() async {
        let writes = SpotifyRequestCounter()
        let localSeeks = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                writes.increment()
                return (503, [:], Data())
            }
            return (200, [:], Data(#"{"shuffle_state":false,"item":{"uri":"spotify:track:AAAAAAAAAAAAAAAAAAAAAA","duration_ms":200000},"device":{"id":"computer-123","is_active":true}}"#.utf8))
        }
        let executor = MediaAutomationExecutor(runner: { source, _ in
            if source.contains("set player position") { localSeeks.increment() }
            if source.contains("set playbackState"), source.contains("Spotify") {
                return MediaAutomationScriptResult(
                    output: "Track A||Artist||playing||Spotify||12||200||||40||spotify:track:AAAAAAAAAAAAAAAAAAAAAA", failure: nil)
            }
            return MediaAutomationScriptResult(output: "", failure: nil)
        })
        let media = MediaController(automationExecutor: executor,
            systemNowPlayingProvider: SpotifySeekNoSystemProvider(), startsAutomatically: false)
        let published = expectation(description: "local Spotify source")
        let publishedSubscription = media.$playbackPosition.dropFirst().filter { $0 == 12 }.first()
            .sink { _ in published.fulfill() }
        media.refresh()
        await fulfillment(of: [published], timeout: 3)
        let failed = expectation(description: "API failure")
        let failureSubscription = media.$seekError.compactMap { $0 }.first().sink { _ in failed.fulfill() }
        media.setScrubbing(true)
        media.updateScrubPosition(198)
        let library = seekController()
        media.setScrubbing(false, spotify: library)
        media.setScrubbing(false, spotify: library)
        await fulfillment(of: [failed], timeout: 3)
        await executor.invalidateAndWaitForIdle()
        XCTAssertEqual(writes.value, 1)
        XCTAssertEqual(localSeeks.value, 0)
        XCTAssertEqual(media.displayedPlaybackPosition, media.playbackPosition)
        publishedSubscription.cancel()
        failureSubscription.cancel()
    }

    @MainActor
    func testConnectedSpotifyContextMismatchNeverFallsBackToLocalSeek() async {
        let writes = SpotifyRequestCounter()
        let localSeeks = SpotifyRequestCounter()
        SpotifyMockURLProtocol.handler = { request in
            if request.httpMethod == "PUT" { writes.increment() }
            return (200, [:], Data(#"{"shuffle_state":false,"item":{"uri":"spotify:track:BBBBBBBBBBBBBBBBBBBBBB","duration_ms":200000},"device":{"id":"computer-123","is_active":true}}"#.utf8))
        }
        let executor = MediaAutomationExecutor(runner: { source, _ in
            if source.contains("set player position") { localSeeks.increment() }
            if source.contains("set playbackState"), source.contains("Spotify") {
                return MediaAutomationScriptResult(output: "Track A||Artist||playing||Spotify||12||200||||40||spotify:track:AAAAAAAAAAAAAAAAAAAAAA", failure: nil)
            }
            return MediaAutomationScriptResult(output: "", failure: nil)
        })
        let media = MediaController(automationExecutor: executor,
            systemNowPlayingProvider: SpotifySeekNoSystemProvider(), startsAutomatically: false)
        let published = expectation(description: "local Spotify source")
        let initial = media.$playbackPosition.dropFirst().filter { $0 == 12 }.first().sink { _ in published.fulfill() }
        media.refresh()
        await fulfillment(of: [published], timeout: 3)
        initial.cancel()
        let refreshed = expectation(description: "refresh after refused API context")
        let completed = media.$playbackPosition.dropFirst().filter { $0 == 12 }.first().sink { _ in refreshed.fulfill() }
        media.setScrubbing(true)
        media.updateScrubPosition(198)
        media.setScrubbing(false, spotify: seekController())
        await fulfillment(of: [refreshed], timeout: 3)
        await executor.invalidateAndWaitForIdle()
        XCTAssertEqual(writes.value, 0)
        XCTAssertEqual(localSeeks.value, 0)
        XCTAssertEqual(media.displayedPlaybackPosition, media.playbackPosition)
        completed.cancel()
    }

}
