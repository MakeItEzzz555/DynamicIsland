import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

// Spotify Web API access for the right workspace (queue, playlists, liked
// songs). Behavioral reference: Droppy Extensions/Spotify/SpotifyAuthManager
// (PKCE authorization code flow, Keychain token storage, user-supplied
// Client ID). Implemented independently for DynamicIsland: read-only
// scopes only, the system ASWebAuthenticationSession, and no bundled
// credentials. Playback selection uses Spotify's AppleScript dictionary.

struct SpotifyMediaItem: Equatable, Identifiable, Sendable {
    let uri: String
    let title: String
    let subtitle: String
    let imageURL: URL?

    var id: String { uri }
}

struct SpotifyLibrarySnapshot: Equatable, Sendable {
    var currentlyPlaying: SpotifyMediaItem?
    var queue: [SpotifyMediaItem]
    var playlists: [SpotifyMediaItem]
    var likedSongs: [SpotifyMediaItem]
}

enum SpotifyLibraryError: LocalizedError, Equatable {
    case missingClientID
    case notConnected
    case authorizationCancelled
    case authorizationFailed
    case unauthorized
    case rateLimited
    case requestFailed(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingClientID: "Add your Spotify app Client ID to connect"
        case .notConnected: "Spotify is not connected"
        case .authorizationCancelled: "Spotify sign-in was cancelled"
        case .authorizationFailed: "Spotify sign-in failed"
        case .unauthorized: "Spotify access expired. Connect again"
        case .rateLimited: "Spotify is rate limiting requests. Try again shortly"
        case .requestFailed(let code): "Spotify request failed (\(code))"
        case .invalidResponse: "Spotify returned an unexpected response"
        }
    }
}

/// Exact scopes and endpoints; nothing broader is requested.
enum SpotifyWebAPI {
    static let scopes = ["user-read-playback-state", "playlist-read-private", "user-library-read"]
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
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { throw SpotifyLibraryError.invalidResponse }
        return items.compactMap { playlist in
            guard let uri = playlist["uri"] as? String,
                  let name = playlist["name"] as? String else { return nil }
            let owner = (playlist["owner"] as? [String: Any])?["display_name"] as? String
            let total = ((playlist["tracks"] as? [String: Any])?["total"] as? Int)
            let subtitle = [owner, total.map { "\($0) tracks" }].compactMap { $0 }.joined(separator: " · ")
            return SpotifyMediaItem(uri: uri, title: name, subtitle: subtitle, imageURL: firstImage(playlist["images"]))
        }
    }

    static func parseSavedTracks(_ data: Data) throws -> [SpotifyMediaItem] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { throw SpotifyLibraryError.invalidResponse }
        return items.compactMap { ($0["track"] as? [String: Any]).flatMap(item) }
    }

    /// Track or episode object.
    static func item(_ object: [String: Any]) -> SpotifyMediaItem? {
        guard let uri = object["uri"] as? String, let name = object["name"] as? String else { return nil }
        let artists = (object["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let show = (object["show"] as? [String: Any])?["name"] as? String
        let album = object["album"] as? [String: Any]
        let images = album?["images"] ?? object["images"]
        return SpotifyMediaItem(
            uri: uri,
            title: name,
            subtitle: artists.isEmpty ? (show ?? "") : artists.joined(separator: ", "),
            imageURL: firstImage(images)
        )
    }

    private static func firstImage(_ value: Any?) -> URL? {
        guard let images = value as? [[String: Any]] else { return nil }
        let sorted = images.sorted { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        let small = sorted.first { ($0["width"] as? Int ?? 0) >= 64 } ?? sorted.last
        return (small?["url"] as? String).flatMap(URL.init(string:))
    }
}

/// Keychain storage for the Spotify refresh token.
struct SpotifyTokenStore: Sendable {
    let service: String

    func refreshToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setRefreshToken(_ token: String?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let token else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "refresh-token"
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

    static let clientIDKey = "spotify.webAPI.clientID"

    @Published private(set) var connectionState: ConnectionState
    @Published private(set) var snapshot: SpotifyLibrarySnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var clientID: String

    private let defaults: UserDefaults
    private let tokens: SpotifyTokenStore
    private let session: URLSession
    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var authSession: ASWebAuthenticationSession?

    init(
        defaults: UserDefaults = .standard,
        tokens: SpotifyTokenStore = SpotifyTokenStore(service: "com.local.dynamicisland.spotify"),
        session: URLSession = .shared
    ) {
        self.defaults = defaults
        self.tokens = tokens
        self.session = session
        let storedID = defaults.string(forKey: Self.clientIDKey) ?? ""
        clientID = storedID
        if storedID.isEmpty {
            connectionState = .needsClientID
        } else {
            connectionState = tokens.refreshToken() == nil ? .disconnected : .connected
        }
        super.init()
    }

    func setClientID(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != clientID else { return }
        clientID = trimmed
        defaults.set(trimmed, forKey: Self.clientIDKey)
        disconnect()
        connectionState = trimmed.isEmpty ? .needsClientID : .disconnected
    }

    func disconnect() {
        tokens.setRefreshToken(nil)
        accessToken = nil
        accessTokenExpiry = nil
        snapshot = nil
        connectionState = clientID.isEmpty ? .needsClientID : .disconnected
    }

    /// Explicit user action: Spotify sign-in with PKCE in the system
    /// authentication sheet.
    func connect() async {
        guard !clientID.isEmpty else {
            lastError = SpotifyLibraryError.missingClientID.errorDescription
            connectionState = .needsClientID
            return
        }
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
            let callback = try await authenticate(url: url)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else {
                throw SpotifyLibraryError.authorizationFailed
            }
            try await exchange([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": SpotifyWebAPI.redirectURI,
                "client_id": clientID,
                "code_verifier": verifier
            ])
            connectionState = .connected
            await refresh()
        } catch let error as SpotifyLibraryError {
            lastError = error.errorDescription
            connectionState = .disconnected
        } catch {
            lastError = SpotifyLibraryError.authorizationFailed.errorDescription
            connectionState = .disconnected
        }
    }

    /// Reads queue, playlists and liked songs. Never fabricates items.
    func refresh() async {
        guard connectionState == .connected, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let queueData = get("me/player/queue")
            async let playlistData = get("me/playlists?limit=20")
            async let savedData = get("me/tracks?limit=20")
            let queue = try SpotifyWebAPI.parseQueue(try await queueData)
            snapshot = SpotifyLibrarySnapshot(
                currentlyPlaying: queue.current,
                queue: Array(queue.queue.prefix(20)),
                playlists: try SpotifyWebAPI.parsePlaylists(try await playlistData),
                likedSongs: try SpotifyWebAPI.parseSavedTracks(try await savedData)
            )
            lastError = nil
        } catch let error as SpotifyLibraryError {
            lastError = error.errorDescription
            if error == .unauthorized { disconnect() }
        } catch {
            lastError = "Spotify could not be reached"
        }
    }

    // MARK: Networking

    private func get(_ path: String) async throws -> Data {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: path, relativeTo: SpotifyWebAPI.apiBase)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyLibraryError.invalidResponse }
        switch http.statusCode {
        case 200: return data
        case 204: return Data("{}".utf8) // Nothing playing: empty queue.
        case 401: throw SpotifyLibraryError.unauthorized
        case 429: throw SpotifyLibraryError.rateLimited
        default: throw SpotifyLibraryError.requestFailed(http.statusCode)
        }
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, let accessTokenExpiry, accessTokenExpiry > Date().addingTimeInterval(30) {
            return accessToken
        }
        guard let refresh = tokens.refreshToken() else { throw SpotifyLibraryError.notConnected }
        try await exchange([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID
        ])
        guard let accessToken else { throw SpotifyLibraryError.unauthorized }
        return accessToken
    }

    private func exchange(_ form: [String: String]) async throws {
        var request = URLRequest(url: SpotifyWebAPI.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyLibraryError.invalidResponse }
        guard http.statusCode == 200 else {
            throw http.statusCode == 400 || http.statusCode == 401
                ? SpotifyLibraryError.unauthorized
                : SpotifyLibraryError.requestFailed(http.statusCode)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String else { throw SpotifyLibraryError.invalidResponse }
        accessToken = token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(object["expires_in"] as? Int ?? 3600))
        if let refresh = object["refresh_token"] as? String {
            tokens.setRefreshToken(refresh)
        }
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SpotifyWebAPI.redirectScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
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
}

extension SpotifyLibraryController: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        }
    }
}
