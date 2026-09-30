import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

// Spotify Web API access for the right workspace (queue, playlists, liked
// songs). PKCE is used because a desktop app cannot keep a client secret.
// The application Client ID is injected into Info.plist at build/package
// time; release users never need a Spotify Developer account. Generic
// current-media detection and low-latency local playback remain owned by
// MediaController.

struct SpotifyAuthConfiguration: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case appBundle
        case developerOverride
        case unavailable
    }

    static let infoPlistClientIDKey = "DynamicIslandSpotifyClientID"
    static let developerOverrideKey = "spotify.webAPI.clientID"

    let clientID: String?
    let source: Source

    @MainActor
    static func resolve(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> SpotifyAuthConfiguration {
        #if DEBUG
        if let override = normalizedClientID(defaults.string(forKey: developerOverrideKey)) {
            return SpotifyAuthConfiguration(clientID: override, source: .developerOverride)
        }
        #endif
        if let bundled = normalizedClientID(bundle.object(forInfoDictionaryKey: infoPlistClientIDKey) as? String) {
            return SpotifyAuthConfiguration(clientID: bundled, source: .appBundle)
        }
        return SpotifyAuthConfiguration(clientID: nil, source: .unavailable)
    }

    static func normalizedClientID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, trimmed.count <= 128,
              trimmed.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }
        return trimmed
    }
}

enum SpotifyMediaKind: String, Equatable, Sendable {
    case track
    case episode
    case playlist
    case album
    case artist
    case show
    case unknown
}

struct SpotifyMediaItem: Equatable, Identifiable, Sendable {
    let uri: String
    let title: String
    let subtitle: String
    let imageURL: URL?
    let kind: SpotifyMediaKind

    var id: String { uri }

    var spotifyID: String? {
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify" else { return nil }
        return String(parts[2])
    }
}

struct SpotifyLibrarySnapshot: Equatable, Sendable {
    var currentlyPlaying: SpotifyMediaItem?
    var queue: [SpotifyMediaItem]
    var playlists: [SpotifyMediaItem]
    var likedSongs: [SpotifyMediaItem]
}

enum SpotifyLibraryError: LocalizedError, Equatable {
    case appNotConfigured
    case notConnected
    case authorizationCancelled
    case authorizationFailed
    case invalidCallback
    case unauthorized
    case forbidden
    case rateLimited(retryAfterSeconds: Int?)
    case requestFailed(Int)
    case invalidResponse
    case unsupportedItem

    var errorDescription: String? {
        switch self {
        case .appNotConfigured:
            return "Spotify is not configured in this build"
        case .notConnected:
            return "Spotify is not connected"
        case .authorizationCancelled:
            return "Spotify sign-in was cancelled"
        case .authorizationFailed:
            return "Spotify sign-in failed"
        case .invalidCallback:
            return "Spotify returned an invalid sign-in callback"
        case .unauthorized:
            return "Spotify access expired. Connect again"
        case .forbidden:
            return "Spotify denied this action. Check account eligibility and granted permissions."
        case .rateLimited(let seconds):
            if let seconds { return "Spotify is rate limiting requests. Try again in \(seconds)s." }
            return "Spotify is rate limiting requests. Try again shortly."
        case .requestFailed(let code):
            return "Spotify request failed (\(code))"
        case .invalidResponse:
            return "Spotify returned an unexpected response"
        case .unsupportedItem:
            return "That Spotify item cannot be used for this action"
        }
    }
}

/// Exact scopes and endpoints; nothing broader is requested. Spotify's Queue
/// endpoint accepts `user-read-playback-state`, so a separate
/// `user-read-currently-playing` grant is not required by this feature set.
enum SpotifyWebAPI {
    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
        "user-library-modify"
    ]
    static let redirectScheme = "dynamicisland"
    static let redirectURI = "dynamicisland://spotify-callback"
    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let apiBase = URL(string: "https://api.spotify.com/v1/")!

    static func authorizationURL(clientID: String, challenge: String, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " "))
        ]
        return components.url!
    }

    static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        guard callback.scheme?.lowercased() == redirectScheme,
              callback.host?.lowercased() == "spotify-callback",
              callback.user == nil,
              callback.password == nil,
              callback.port == nil,
              callback.path.isEmpty || callback.path == "/" else {
            throw SpotifyLibraryError.invalidCallback
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func exactlyOne(_ name: String) -> String? {
            let matches = items.filter { $0.name == name }
            guard matches.count == 1, let value = matches[0].value, !value.isEmpty else { return nil }
            return value
        }
        guard exactlyOne("state") == expectedState else {
            throw SpotifyLibraryError.invalidCallback
        }
        let code = exactlyOne("code")
        let error = exactlyOne("error")
        guard (code == nil) != (error == nil) else {
            throw SpotifyLibraryError.invalidCallback
        }
        if let error {
            if error == "access_denied" { throw SpotifyLibraryError.authorizationCancelled }
            throw SpotifyLibraryError.authorizationFailed
        }
        guard let code else { throw SpotifyLibraryError.invalidCallback }
        return code
    }

    // MARK: Parsing (pure)

    static func parseQueue(_ data: Data) throws -> (current: SpotifyMediaItem?, queue: [SpotifyMediaItem]) {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpotifyLibraryError.invalidResponse
        }
        let current = (object["currently_playing"] as? [String: Any]).flatMap(item)
        let queue = (object["queue"] as? [[String: Any]] ?? []).compactMap(item)
        return (current, queue)
    }

    static func parsePlaylists(_ data: Data) throws -> [SpotifyMediaItem] {
        try parsePlaylistsPage(data).items
    }

    static func parsePlaylistsPage(_ data: Data) throws -> SpotifyPage {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { throw SpotifyLibraryError.invalidResponse }
        let parsed = items.compactMap { playlist -> SpotifyMediaItem? in
            guard let uri = playlist["uri"] as? String,
                  let name = playlist["name"] as? String else { return nil }
            let owner = (playlist["owner"] as? [String: Any])?["display_name"] as? String
            let total = ((playlist["tracks"] as? [String: Any])?["total"] as? Int)
                ?? ((playlist["items"] as? [String: Any])?["total"] as? Int)
            let subtitle = [owner, total.map { "\($0) tracks" }].compactMap { $0 }.joined(separator: " · ")
            return SpotifyMediaItem(
                uri: uri,
                title: name,
                subtitle: subtitle,
                imageURL: firstImage(playlist["images"]),
                kind: .playlist
            )
        }
        return SpotifyPage(items: parsed, next: nextURL(from: object))
    }

    static func parseSavedTracks(_ data: Data) throws -> [SpotifyMediaItem] {
        try parseSavedTracksPage(data).items
    }

    static func parseSavedTracksPage(_ data: Data) throws -> SpotifyPage {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { throw SpotifyLibraryError.invalidResponse }
        let parsed = items.compactMap { ($0["track"] as? [String: Any]).flatMap(item) }
        return SpotifyPage(items: parsed, next: nextURL(from: object))
    }

    static func parsePlaylistItemsPage(_ data: Data) throws -> SpotifyPage {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { throw SpotifyLibraryError.invalidResponse }
        let parsed = items.compactMap { entry -> SpotifyMediaItem? in
            if let object = entry["item"] as? [String: Any] { return item(object) }
            if let object = entry["track"] as? [String: Any] { return item(object) }
            return item(entry)
        }
        return SpotifyPage(items: parsed, next: nextURL(from: object))
    }

    /// Track or episode object.
    static func item(_ object: [String: Any]) -> SpotifyMediaItem? {
        guard let uri = object["uri"] as? String, let name = object["name"] as? String else { return nil }
        let artists = (object["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let show = (object["show"] as? [String: Any])?["name"] as? String
        let album = object["album"] as? [String: Any]
        let images = album?["images"] ?? object["images"]
        let type = (object["type"] as? String).flatMap(SpotifyMediaKind.init(rawValue:))
            ?? SpotifyMediaKind(rawValue: String(uri.split(separator: ":").dropFirst().first ?? "")) ?? .unknown
        return SpotifyMediaItem(
            uri: uri,
            title: name,
            subtitle: artists.isEmpty ? (show ?? "") : artists.joined(separator: ", "),
            imageURL: firstImage(images),
            kind: type
        )
    }

    private static func nextURL(from object: [String: Any]) -> URL? {
        guard let next = object["next"] as? String, !next.isEmpty else { return nil }
        return URL(string: next)
    }

    private static func firstImage(_ value: Any?) -> URL? {
        guard let images = value as? [[String: Any]] else { return nil }
        let sorted = images.sorted { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        let small = sorted.first { ($0["width"] as? Int ?? 0) >= 64 } ?? sorted.last
        return (small?["url"] as? String).flatMap(URL.init(string:))
    }
}

struct SpotifyPage: Equatable, Sendable {
    let items: [SpotifyMediaItem]
    let next: URL?
}

/// Spotify credentials are kept in Keychain. Access tokens are short-lived,
/// but storing them there avoids ever persisting bearer credentials in
/// UserDefaults or files and lets a relaunched app reuse a still-valid token.
struct SpotifyStoredCredentials: Equatable, Sendable {
    var accessToken: String?
    var accessTokenExpiry: Date?
    var refreshToken: String?
}

protocol SpotifyCredentialStoring: Sendable {
    func credentials() -> SpotifyStoredCredentials
    func store(accessToken: String, expiresAt: Date, refreshToken: String?)
    func clear()
}

struct SpotifyTokenStore: SpotifyCredentialStoring, Sendable {
    let service: String

    func credentials() -> SpotifyStoredCredentials {
        let expiry = read(account: "access-expiry").flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        return SpotifyStoredCredentials(
            accessToken: read(account: "access-token"),
            accessTokenExpiry: expiry,
            refreshToken: read(account: "refresh-token")
        )
    }

    func refreshToken() -> String? {
        credentials().refreshToken
    }

    func store(accessToken: String, expiresAt: Date, refreshToken: String?) {
        write(accessToken, account: "access-token")
        write(String(expiresAt.timeIntervalSince1970), account: "access-expiry")
        if let refreshToken {
            write(refreshToken, account: "refresh-token")
        }
    }

    func setRefreshToken(_ token: String?) {
        write(token, account: "refresh-token")
    }

    func clear() {
        ["access-token", "access-expiry", "refresh-token"].forEach { account in
            SecItemDelete(query(account: account) as CFDictionary)
        }
    }

    private func read(account: String) -> String? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String?, account: String) {
        let query = query(account: account)
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

@MainActor
final class SpotifyLibraryController: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case needsClientID
        case disconnected
        case connecting
        case connected
    }

    typealias Authenticator = @MainActor (URL) async throws -> URL

    static let clientIDKey = SpotifyAuthConfiguration.developerOverrideKey

    @Published private(set) var connectionState: ConnectionState
    @Published private(set) var snapshot: SpotifyLibrarySnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMorePlaylists = false
    @Published private(set) var isLoadingMoreLikedSongs = false
    @Published private(set) var isLoadingPlaylist = false
    @Published private(set) var lastError: String?
    @Published private(set) var clientID: String
    @Published private(set) var configurationSource: SpotifyAuthConfiguration.Source
    @Published private(set) var selectedPlaylist: SpotifyMediaItem?
    @Published private(set) var playlistItems: [SpotifyMediaItem] = []
    @Published private(set) var pendingItemURIs: Set<String> = []

    var hasMorePlaylists: Bool { nextPlaylistsURL != nil }
    var hasMoreLikedSongs: Bool { nextLikedSongsURL != nil }
    var isConfigured: Bool { !clientID.isEmpty }

    private let defaults: UserDefaults
    private let tokens: any SpotifyCredentialStoring
    private let session: URLSession
    private let authenticatorOverride: Authenticator?
    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var authSession: ASWebAuthenticationSession?
    private var refreshTask: Task<String, Error>?
    private var lifecycleGeneration = 0
    private var nextPlaylistsURL: URL?
    private var nextLikedSongsURL: URL?
    private var nextPlaylistItemsURL: URL?

    init(
        defaults: UserDefaults = .standard,
        configuration: SpotifyAuthConfiguration? = nil,
        tokens: any SpotifyCredentialStoring = SpotifyTokenStore(service: "com.local.dynamicisland.spotify"),
        session: URLSession = .shared,
        authenticator: Authenticator? = nil
    ) {
        self.defaults = defaults
        self.tokens = tokens
        self.session = session
        self.authenticatorOverride = authenticator

        let resolved = configuration ?? SpotifyAuthConfiguration.resolve(defaults: defaults)
        let resolvedID = resolved.clientID ?? ""
        clientID = resolvedID
        configurationSource = resolved.source

        let stored = tokens.credentials()
        accessToken = stored.accessToken
        accessTokenExpiry = stored.accessTokenExpiry
        connectionState = resolvedID.isEmpty
            ? .needsClientID
            : (stored.refreshToken == nil ? .disconnected : .connected)
        super.init()
    }

    #if DEBUG
    /// Development-only escape hatch. Release UI never exposes a Client ID.
    func setDeveloperClientID(_ value: String) {
        let normalized = SpotifyAuthConfiguration.normalizedClientID(value)
        if let normalized {
            defaults.set(normalized, forKey: Self.clientIDKey)
            clientID = normalized
            configurationSource = .developerOverride
        } else {
            defaults.removeObject(forKey: Self.clientIDKey)
            let bundled = SpotifyAuthConfiguration.normalizedClientID(
                Bundle.main.object(forInfoDictionaryKey: SpotifyAuthConfiguration.infoPlistClientIDKey) as? String
            )
            clientID = bundled ?? ""
            configurationSource = bundled == nil ? .unavailable : .appBundle
        }
        disconnect()
    }
    #endif

    func disconnect() {
        lifecycleGeneration &+= 1
        authSession?.cancel()
        authSession = nil
        refreshTask?.cancel()
        refreshTask = nil
        tokens.clear()
        accessToken = nil
        accessTokenExpiry = nil
        snapshot = nil
        selectedPlaylist = nil
        playlistItems = []
        nextPlaylistsURL = nil
        nextLikedSongsURL = nil
        nextPlaylistItemsURL = nil
        pendingItemURIs = []
        lastError = nil
        connectionState = clientID.isEmpty ? .needsClientID : .disconnected
    }

    /// Explicit user action: Spotify sign-in with PKCE in the system
    /// authentication sheet. No client secret is embedded or requested.
    func connect() async {
        guard !clientID.isEmpty else {
            lastError = SpotifyLibraryError.appNotConfigured.errorDescription
            connectionState = .needsClientID
            return
        }

        lifecycleGeneration &+= 1
        let operationGeneration = lifecycleGeneration
        connectionState = .connecting
        lastError = nil
        let verifier = SpotifyWebAPI.codeVerifier()
        let state = UUID().uuidString
        let url = SpotifyWebAPI.authorizationURL(
            clientID: clientID,
            challenge: SpotifyWebAPI.codeChallenge(for: verifier),
            state: state
        )

        do {
            let callback: URL
            if let authenticatorOverride {
                callback = try await authenticatorOverride(url)
            } else {
                callback = try await authenticate(url: url)
            }
            let code = try SpotifyWebAPI.authorizationCode(from: callback, expectedState: state)
            try await exchange(
                [
                    "grant_type": "authorization_code",
                    "code": code,
                    "redirect_uri": SpotifyWebAPI.redirectURI,
                    "client_id": clientID,
                    "code_verifier": verifier
                ],
                invalidGrantError: .authorizationFailed,
                generation: operationGeneration
            )
            guard operationGeneration == lifecycleGeneration else { return }
            connectionState = .connected
            await refresh()
        } catch let error as SpotifyLibraryError {
            guard operationGeneration == lifecycleGeneration else { return }
            lastError = error.errorDescription
            connectionState = .disconnected
        } catch is CancellationError {
            guard operationGeneration == lifecycleGeneration else { return }
            connectionState = .disconnected
        } catch {
            guard operationGeneration == lifecycleGeneration else { return }
            lastError = SpotifyLibraryError.authorizationFailed.errorDescription
            connectionState = .disconnected
        }
    }

    /// Reads queue, playlists and liked songs. Never fabricates items. A
    /// provider-specific failure (for example Queue being unavailable for the
    /// current account) does not erase independently available library data.
    func refresh() async {
        guard connectionState == .connected, !isLoading else { return }
        let operationGeneration = lifecycleGeneration
        isLoading = true
        defer { isLoading = false }

        var next = snapshot ?? SpotifyLibrarySnapshot(
            currentlyPlaying: nil,
            queue: [],
            playlists: [],
            likedSongs: []
        )
        var firstError: Error?

        do {
            let queue = try SpotifyWebAPI.parseQueue(try await get("me/player/queue"))
            guard operationGeneration == lifecycleGeneration, connectionState == .connected else { return }
            next.currentlyPlaying = queue.current
            next.queue = Array(queue.queue.prefix(20))
        } catch {
            guard operationGeneration == lifecycleGeneration else { return }
            if case SpotifyLibraryError.unauthorized = error {
                handle(error)
                return
            }
            firstError = firstError ?? error
        }

        do {
            let page = try SpotifyWebAPI.parsePlaylistsPage(try await get("me/playlists?limit=50"))
            guard operationGeneration == lifecycleGeneration, connectionState == .connected else { return }
            next.playlists = page.items
            nextPlaylistsURL = page.next
        } catch {
            guard operationGeneration == lifecycleGeneration else { return }
            if case SpotifyLibraryError.unauthorized = error {
                handle(error)
                return
            }
            firstError = firstError ?? error
        }

        do {
            let page = try SpotifyWebAPI.parseSavedTracksPage(try await get("me/tracks?limit=50"))
            guard operationGeneration == lifecycleGeneration, connectionState == .connected else { return }
            next.likedSongs = page.items
            nextLikedSongsURL = page.next
        } catch {
            guard operationGeneration == lifecycleGeneration else { return }
            if case SpotifyLibraryError.unauthorized = error {
                handle(error)
                return
            }
            firstError = firstError ?? error
        }

        guard operationGeneration == lifecycleGeneration, connectionState == .connected else { return }
        snapshot = next
        if let firstError {
            handle(firstError)
        } else {
            lastError = nil
        }
    }

    func loadMorePlaylists() async {
        guard connectionState == .connected,
              let next = nextPlaylistsURL,
              !isLoadingMorePlaylists else { return }
        let operationGeneration = lifecycleGeneration
        isLoadingMorePlaylists = true
        defer { isLoadingMorePlaylists = false }
        do {
            let page = try SpotifyWebAPI.parsePlaylistsPage(try await get(next))
            guard operationGeneration == lifecycleGeneration, connectionState == .connected else { return }
            nextPlaylistsURL = page.next
            appendUnique(page.items, to: \.playlists)
            lastError = nil
        } catch {
            guard operationGeneration == lifecycleGeneration else { return }
            handle(error)
        }
    }

    func loadMoreLikedSongs() async {
        guard connectionState == .connected,
              let next = nextLikedSongsURL,
              !isLoadingMoreLikedSongs else { return }
        let operationGeneration = lifecycleGeneration
        isLoadingMoreLikedSongs = true
        defer { isLoadingMoreLikedSongs = false }
        do {
            let page = try SpotifyWebAPI.parseSavedTracksPage(try await get(next))
            guard operationGeneration == lifecycleGeneration, connectionState == .connected else { return }
            nextLikedSongsURL = page.next
            appendUnique(page.items, to: \.likedSongs)
            lastError = nil
        } catch {
            guard operationGeneration == lifecycleGeneration else { return }
            handle(error)
        }
    }

    func loadPlaylist(_ playlist: SpotifyMediaItem) async {
        guard playlist.kind == .playlist, let id = playlist.spotifyID else {
            handle(SpotifyLibraryError.unsupportedItem)
            return
        }
        let operationGeneration = lifecycleGeneration
        selectedPlaylist = playlist
        playlistItems = []
        nextPlaylistItemsURL = nil
        isLoadingPlaylist = true
        defer { isLoadingPlaylist = false }

        do {
            let path = "playlists/\(id)/items?limit=50"
            let page = try SpotifyWebAPI.parsePlaylistItemsPage(try await get(path))
            guard operationGeneration == lifecycleGeneration,
                  connectionState == .connected,
                  selectedPlaylist?.id == playlist.id else { return }
            playlistItems = page.items
            nextPlaylistItemsURL = page.next
            lastError = nil
        } catch {
            guard operationGeneration == lifecycleGeneration,
                  selectedPlaylist?.id == playlist.id else { return }
            handle(error)
        }
    }

    func loadMorePlaylistItems() async {
        guard let playlistID = selectedPlaylist?.id,
              let next = nextPlaylistItemsURL,
              !isLoadingPlaylist else { return }
        let operationGeneration = lifecycleGeneration
        isLoadingPlaylist = true
        defer { isLoadingPlaylist = false }
        do {
            let page = try SpotifyWebAPI.parsePlaylistItemsPage(try await get(next))
            guard operationGeneration == lifecycleGeneration,
                  connectionState == .connected,
                  selectedPlaylist?.id == playlistID else { return }
            nextPlaylistItemsURL = page.next
            let existing = Set(playlistItems.map(\.id))
            playlistItems += page.items.filter { !existing.contains($0.id) }
            lastError = nil
        } catch {
            guard operationGeneration == lifecycleGeneration,
                  selectedPlaylist?.id == playlistID else { return }
            handle(error)
        }
    }

    func closePlaylist() {
        selectedPlaylist = nil
        playlistItems = []
        nextPlaylistItemsURL = nil
    }

    func addToQueue(_ item: SpotifyMediaItem) async {
        guard item.kind == .track || item.kind == .episode else {
            handle(SpotifyLibraryError.unsupportedItem)
            return
        }
        guard !pendingItemURIs.contains(item.uri) else { return }
        let operationGeneration = lifecycleGeneration
        pendingItemURIs.insert(item.uri)
        defer { pendingItemURIs.remove(item.uri) }

        do {
            try await send(
                method: "POST",
                path: "me/player/queue",
                query: [URLQueryItem(name: "uri", value: item.uri)],
                expectedStatusCodes: [204]
            )
            guard operationGeneration == lifecycleGeneration, connectionState == .connected else { return }
            await refreshQueueOnly()
            guard operationGeneration == lifecycleGeneration else { return }
            lastError = nil
        } catch {
            guard operationGeneration == lifecycleGeneration else { return }
            handle(error)
        }
    }

    func setSaved(_ item: SpotifyMediaItem, saved: Bool) async {
        guard item.kind == .track || item.kind == .episode else {
            handle(SpotifyLibraryError.unsupportedItem)
            return
        }
        guard !pendingItemURIs.contains(item.uri) else { return }
        let operationGeneration = lifecycleGeneration
        pendingItemURIs.insert(item.uri)
        defer { pendingItemURIs.remove(item.uri) }

        do {
            try await send(
                method: saved ? "PUT" : "DELETE",
                path: "me/library",
                query: [URLQueryItem(name: "uris", value: item.uri)],
                expectedStatusCodes: [200]
            )
            guard operationGeneration == lifecycleGeneration, connectionState == .connected else { return }
            if var current = snapshot {
                if saved {
                    if !current.likedSongs.contains(where: { $0.id == item.id }) {
                        current.likedSongs.insert(item, at: 0)
                    }
                } else {
                    current.likedSongs.removeAll { $0.id == item.id }
                }
                snapshot = current
            }
            lastError = nil
        } catch {
            guard operationGeneration == lifecycleGeneration else { return }
            handle(error)
        }
    }

    // MARK: Networking

    private func appendUnique(
        _ newItems: [SpotifyMediaItem],
        to keyPath: WritableKeyPath<SpotifyLibrarySnapshot, [SpotifyMediaItem]>
    ) {
        guard var current = snapshot else { return }
        let existing = Set(current[keyPath: keyPath].map(\.id))
        current[keyPath: keyPath].append(contentsOf: newItems.filter { !existing.contains($0.id) })
        snapshot = current
    }

    private func refreshQueueOnly() async {
        do {
            let queue = try SpotifyWebAPI.parseQueue(try await get("me/player/queue"))
            guard var current = snapshot else { return }
            current.currentlyPlaying = queue.current
            current.queue = Array(queue.queue.prefix(20))
            snapshot = current
        } catch {
            handle(error)
        }
    }

    private func get(_ path: String) async throws -> Data {
        try await authenticatedRequest(method: "GET", url: apiURL(path), expectedStatusCodes: [200, 204])
    }

    private func get(_ url: URL) async throws -> Data {
        try await authenticatedRequest(method: "GET", url: url, expectedStatusCodes: [200, 204])
    }

    private func send(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        expectedStatusCodes: Set<Int>
    ) async throws {
        var components = URLComponents(url: apiURL(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        guard let url = components.url else { throw SpotifyLibraryError.invalidResponse }
        _ = try await authenticatedRequest(method: method, url: url, expectedStatusCodes: expectedStatusCodes)
    }

    private func apiURL(_ path: String) -> URL {
        URL(string: path, relativeTo: SpotifyWebAPI.apiBase)!.absoluteURL
    }

    private func authenticatedRequest(
        method: String,
        url: URL,
        expectedStatusCodes: Set<Int>
    ) async throws -> Data {
        let token = try await validAccessToken()
        do {
            return try await performRequest(
                method: method,
                url: url,
                token: token,
                expectedStatusCodes: expectedStatusCodes
            )
        } catch SpotifyLibraryError.unauthorized {
            // Exactly one retry after a forced refresh. No recursive retry.
            let refreshed = try await validAccessToken(forceRefresh: true)
            return try await performRequest(
                method: method,
                url: url,
                token: refreshed,
                expectedStatusCodes: expectedStatusCodes
            )
        }
    }

    private func performRequest(
        method: String,
        url: URL,
        token: String,
        expectedStatusCodes: Set<Int>
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyLibraryError.invalidResponse
        }
        if expectedStatusCodes.contains(http.statusCode) {
            return data.isEmpty ? Data("{}".utf8) : data
        }

        switch http.statusCode {
        case 401:
            throw SpotifyLibraryError.unauthorized
        case 403:
            throw SpotifyLibraryError.forbidden
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw SpotifyLibraryError.rateLimited(retryAfterSeconds: retry)
        default:
            throw SpotifyLibraryError.requestFailed(http.statusCode)
        }
    }

    private func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh,
           let accessToken,
           let accessTokenExpiry,
           accessTokenExpiry > Date().addingTimeInterval(30) {
            return accessToken
        }
        return try await refreshAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let refresh = tokens.credentials().refreshToken else {
            throw SpotifyLibraryError.notConnected
        }
        guard !clientID.isEmpty else {
            throw SpotifyLibraryError.appNotConfigured
        }

        let task = Task { @MainActor [weak self] () throws -> String in
            guard let self else { throw SpotifyLibraryError.notConnected }
            try await self.exchange(
                [
                    "grant_type": "refresh_token",
                    "refresh_token": refresh,
                    "client_id": self.clientID
                ],
                invalidGrantError: .unauthorized
            )
            guard let token = self.accessToken else { throw SpotifyLibraryError.unauthorized }
            return token
        }
        refreshTask = task
        do {
            let token = try await task.value
            refreshTask = nil
            return token
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func exchange(
        _ form: [String: String],
        invalidGrantError: SpotifyLibraryError,
        generation: Int? = nil
    ) async throws {
        var request = URLRequest(url: SpotifyWebAPI.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyLibraryError.invalidResponse
        }
        guard http.statusCode == 200 else {
            switch http.statusCode {
            case 400, 401:
                throw invalidGrantError
            case 403:
                throw SpotifyLibraryError.forbidden
            case 429:
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                throw SpotifyLibraryError.rateLimited(retryAfterSeconds: retry)
            default:
                throw SpotifyLibraryError.requestFailed(http.statusCode)
            }
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String,
              !token.isEmpty else {
            throw SpotifyLibraryError.invalidResponse
        }

        if let generation, generation != lifecycleGeneration {
            throw CancellationError()
        }
        let expiry = Date().addingTimeInterval(TimeInterval(object["expires_in"] as? Int ?? 3600))
        let refresh = (object["refresh_token"] as? String) ?? tokens.credentials().refreshToken
        accessToken = token
        accessTokenExpiry = expiry
        tokens.store(accessToken: token, expiresAt: expiry, refreshToken: refresh)
    }

    private func authenticate(url: URL) async throws -> URL {
        defer { authSession = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SpotifyWebAPI.redirectScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyLibraryError.authorizationCancelled)
                } else {
                    continuation.resume(throwing: SpotifyLibraryError.authorizationFailed)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            NSApp.activate(ignoringOtherApps: true)
            if !session.start() {
                continuation.resume(throwing: SpotifyLibraryError.authorizationFailed)
            }
        }
    }

    private func handle(_ error: Error) {
        if let spotify = error as? SpotifyLibraryError {
            lastError = spotify.errorDescription
            if spotify == .unauthorized {
                disconnect()
                lastError = spotify.errorDescription
            }
        } else if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
            // Cancellation is stale work, not a user-visible failure.
            return
        } else {
            lastError = "Spotify could not be reached"
        }
    }
}

extension SpotifyLibraryController: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        }
    }
}
