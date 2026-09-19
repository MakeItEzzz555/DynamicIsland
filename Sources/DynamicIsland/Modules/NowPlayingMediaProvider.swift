import AppKit
import Darwin
import Foundation

@MainActor
final class NowPlayingMediaProvider: MediaDetectionProvider {
    let name = "System Now Playing"

    private let mediaRemote: any MediaRemoteProviding

    init(mediaRemote: any MediaRemoteProviding = MediaRemoteClient()) {
        self.mediaRemote = mediaRemote
    }

    func snapshot() async -> MediaSnapshot? {
        guard mediaRemote.isAvailable else {
            debugLog("unavailable: MediaRemote framework or symbols missing")
            return nil
        }

        guard let info = await mediaRemote.nowPlayingInfo() else {
            debugLog("failed: no now playing info returned")
            return nil
        }

        let appName = await mediaRemote.nowPlayingApplicationDisplayName()
        guard let title = stringValue(from: info, keys: [
            "kMRMediaRemoteNowPlayingInfoTitle",
            "title",
            "Title"
        ]), !title.isEmpty else {
            debugLog("failed: now playing info did not include a title")
            return nil
        }

        let bundleIdentifier = stringValue(from: info, keys: [
            "kMRMediaRemoteNowPlayingApplicationBundleIdentifier",
            "kMRMediaRemoteNowPlayingInfoBundleIdentifier",
            "bundleIdentifier",
            "BundleIdentifier"
        ])
        let resolvedSourceName = appName ??
            sourceName(for: bundleIdentifier) ??
            stringValue(from: info, keys: [
                "kMRMediaRemoteNowPlayingApplicationDisplayName",
                "kMRMediaRemoteNowPlayingInfoApplicationDisplayName",
                "sourceName",
                "Source"
            ]) ??
            "Now Playing"
        let sourceKind = sourceKind(for: bundleIdentifier, sourceName: resolvedSourceName)
        let playbackRate = doubleValue(from: info, keys: [
            "kMRMediaRemoteNowPlayingInfoPlaybackRate",
            "playbackRate",
            "PlaybackRate"
        ]) ?? 0
        let isPlaying = playbackRate > 0.01
        let artwork = artworkImage(from: info)
        let duration = doubleValue(from: info, keys: [
            "kMRMediaRemoteNowPlayingInfoDuration",
            "duration",
            "Duration"
        ])
        let elapsedTime = doubleValue(from: info, keys: [
            "kMRMediaRemoteNowPlayingInfoElapsedTime",
            "elapsedTime",
            "ElapsedTime"
        ])

        let snapshot = MediaSnapshot(
            sourceKind: sourceKind,
            sourceName: resolvedSourceName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: stringValue(from: info, keys: [
                "kMRMediaRemoteNowPlayingInfoArtist",
                "artist",
                "Artist"
            ]),
            album: stringValue(from: info, keys: [
                "kMRMediaRemoteNowPlayingInfoAlbum",
                "album",
                "Album"
            ]),
            artwork: artwork,
            isPlaying: isPlaying,
            duration: duration,
            elapsedTime: elapsedTime,
            transportAvailable: sourceKind == .spotify || sourceKind == .music,
            seekAvailable: sourceKind == .spotify || sourceKind == .music,
            volumeAvailable: sourceKind == .spotify || sourceKind == .music
        )

        debugLog(
            "succeeded: source=\(snapshot.sourceName) bundle=\(snapshot.bundleIdentifier ?? "nil") " +
                "title=\(snapshot.title) isPlaying=\(snapshot.isPlaying) " +
                "artwork=\(snapshot.artwork != nil) duration=\(snapshot.duration != nil) " +
                "elapsed=\(snapshot.elapsedTime != nil)"
        )
        return snapshot
    }

    private func stringValue(from dictionary: NSDictionary, keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func doubleValue(from dictionary: NSDictionary, keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? Double {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.doubleValue
            }
        }
        return nil
    }

    private func artworkImage(from dictionary: NSDictionary) -> NSImage? {
        let artworkKeys = [
            "kMRMediaRemoteNowPlayingInfoArtworkData",
            "artworkData",
            "ArtworkData"
        ]
        for key in artworkKeys {
            if let data = dictionary[key] as? Data {
                return NSImage(data: data)
            }
        }
        return nil
    }

    private func sourceName(for bundleIdentifier: String?) -> String? {
        switch bundleIdentifier {
        case "com.spotify.client":
            return "Spotify"
        case "com.apple.Music":
            return "Music"
        case "com.brave.Browser":
            return "Brave"
        case "com.apple.Safari":
            return "Safari"
        case "com.google.Chrome":
            return "Chrome"
        case "company.thebrowser.Browser":
            return "Arc"
        case "com.microsoft.edgemac":
            return "Microsoft Edge"
        default:
            return nil
        }
    }

    private func sourceKind(for bundleIdentifier: String?, sourceName: String) -> MediaSourceKind {
        if bundleIdentifier == "com.spotify.client" || sourceName.localizedCaseInsensitiveContains("Spotify") {
            return .spotify
        }
        if bundleIdentifier == "com.apple.Music" || sourceName.localizedCaseInsensitiveContains("Music") {
            return .music
        }
        if let bundleIdentifier, [
            "com.brave.Browser",
            "com.apple.Safari",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "com.microsoft.edgemac"
        ].contains(bundleIdentifier) {
            return .browser
        }
        return .system
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        debugPrint("DynamicIsland NowPlayingMediaProvider", message)
        #endif
    }
}

@MainActor
protocol MediaRemoteProviding: AnyObject {
    var isAvailable: Bool { get }
    func nowPlayingInfo() async -> NSDictionary?
    func nowPlayingApplicationDisplayName() async -> String?
}

struct MediaRemoteDeadlineToken: @unchecked Sendable {
    let cancel: () -> Void
}

struct MediaRemoteDeadlineScheduler: Sendable {
    let schedule: @Sendable (
        _ delay: TimeInterval,
        _ action: @escaping @Sendable () -> Void
    ) -> MediaRemoteDeadlineToken

    static let live = Self { delay, action in
        let workItem = DispatchWorkItem(block: action)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
        return MediaRemoteDeadlineToken(cancel: workItem.cancel)
    }
}

enum MediaRemoteCallbackBridge {
    @MainActor
    static func wait<Value: Sendable>(
        timeout: TimeInterval,
        scheduler: MediaRemoteDeadlineScheduler = .live,
        start: @escaping (@escaping @Sendable (Value?) -> Void) -> Void
    ) async -> Value? {
        let state = MediaRemoteCallbackState<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard state.install(continuation) else { return }

                let deadline = scheduler.schedule(timeout) { [weak state] in
                    state?.resolve(nil)
                }
                state.install(deadline)

                guard state.isPending else { return }
                start { [weak state] value in
                    state?.resolve(value)
                }
            }
        } onCancel: { [weak state] in
            state?.resolve(nil)
        }
    }
}

private final class MediaRemoteCallbackState<Value: Sendable>: @unchecked Sendable {
    private enum Completion {
        case value(Value?)
    }

    private let lock = NSLock()
    private var completion: Completion?
    private var continuation: CheckedContinuation<Value?, Never>?
    private var deadline: MediaRemoteDeadlineToken?

    var isPending: Bool {
        lock.withLock { completion == nil }
    }

    func install(_ continuation: CheckedContinuation<Value?, Never>) -> Bool {
        let completedValue: Value?? = lock.withLock {
            if case let .value(value) = completion {
                return .some(value)
            }
            self.continuation = continuation
            return nil
        }
        if let completedValue {
            continuation.resume(returning: completedValue)
            return false
        }
        return true
    }

    func install(_ deadline: MediaRemoteDeadlineToken) {
        let shouldCancel = lock.withLock {
            guard completion == nil else { return true }
            self.deadline = deadline
            return false
        }
        if shouldCancel {
            deadline.cancel()
        }
    }

    func resolve(_ value: Value?) {
        let terminal: (CheckedContinuation<Value?, Never>?, MediaRemoteDeadlineToken?)? = lock.withLock {
            guard completion == nil else { return nil }
            completion = .value(value)
            let terminal = (continuation, deadline)
            continuation = nil
            deadline = nil
            return terminal
        }
        guard let terminal else { return }
        terminal.1?.cancel()
        terminal.0?.resume(returning: value)
    }
}

@MainActor
final class MediaRemoteClient: MediaRemoteProviding {
    private typealias NowPlayingInfoCompletion = @convention(block) (CFDictionary?) -> Void
    private typealias GetNowPlayingInfoFunction = @convention(c) (DispatchQueue, NowPlayingInfoCompletion) -> Void
    private typealias AppDisplayNameCompletion = @convention(block) (CFString?) -> Void
    private typealias CopyAppDisplayNameFunction = @convention(c) (DispatchQueue, AppDisplayNameCompletion) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let getNowPlayingInfo: GetNowPlayingInfoFunction?
    private let copyAppDisplayName: CopyAppDisplayNameFunction?

    // MediaRemote normally answers immediately; this bounds a missing private-framework callback
    // below the ordinary refresh cadence while allowing reasonable run-loop scheduling headroom.
    static let callbackTimeout: TimeInterval = 0.5

    var isAvailable: Bool {
        getNowPlayingInfo != nil
    }

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        if let handle {
            getNowPlayingInfo = Self.loadSymbol(
                "MRMediaRemoteGetNowPlayingInfo",
                from: handle,
                as: GetNowPlayingInfoFunction.self
            )
            copyAppDisplayName = Self.loadSymbol(
                "MRMediaRemoteCopyNowPlayingApplicationDisplayName",
                from: handle,
                as: CopyAppDisplayNameFunction.self
            )
        } else {
            getNowPlayingInfo = nil
            copyAppDisplayName = nil
        }
    }

    func nowPlayingInfo() async -> NSDictionary? {
        guard let getNowPlayingInfo else { return nil }
        return await MediaRemoteCallbackBridge.wait(timeout: Self.callbackTimeout) { completion in
            let nativeCompletion: NowPlayingInfoCompletion = { info in
                let dictionary = info.map { MediaRemoteDictionary(value: $0 as NSDictionary) }
                completion(dictionary)
            }
            getNowPlayingInfo(.main, nativeCompletion)
        }?.value
    }

    func nowPlayingApplicationDisplayName() async -> String? {
        guard let copyAppDisplayName else { return nil }
        return await MediaRemoteCallbackBridge.wait(timeout: Self.callbackTimeout) { completion in
            let nativeCompletion: AppDisplayNameCompletion = { value in
                completion(value as String?)
            }
            copyAppDisplayName(.main, nativeCompletion)
        }
    }

    private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer, as type: T.Type) -> T? {
        guard let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }
}

private struct MediaRemoteDictionary: @unchecked Sendable {
    let value: NSDictionary
}
