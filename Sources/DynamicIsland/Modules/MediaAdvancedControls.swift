import AppKit
import Combine
import CoreAudio
import Foundation

// MARK: - Capability model

/// Whether an advanced Now Playing control can act on the current source.
enum MediaCapabilityAvailability: Equatable, Sendable {
    case supported
    /// The provider supports it once the user connects (Spotify Web API).
    case authRequired
    /// No supported public backend for this source: shown disabled, never faked.
    case unsupported

    var isEnabled: Bool { self == .supported }
}

enum MediaRepeatMode: String, CaseIterable, Sendable {
    case off, all, one
}

/// Shuffle and repeat stay independent, exactly as providers expose them.
struct MediaPlaybackModeState: Equatable, Sendable {
    var shuffle = false
    var repeatMode: MediaRepeatMode = .off

    /// One compact control: repeat (one/all) wins the icon, then shuffle.
    var symbol: String {
        switch repeatMode {
        case .one: "repeat.1"
        case .all: "repeat"
        case .off: "shuffle"
        }
    }
    var isActive: Bool { shuffle || repeatMode != .off }
    var accessibilityValue: String {
        switch (shuffle, repeatMode) {
        case (false, .off): "Off"
        case (true, .off): "Shuffle"
        case (let s, .all): s ? "Shuffle and repeat all" : "Repeat all"
        case (let s, .one): s ? "Shuffle and repeat one" : "Repeat one"
        }
    }

    /// Click cycle through meaningful supported modes:
    /// off -> shuffle -> repeat all -> repeat one (if supported) -> off.
    func next(supportsRepeatOne: Bool) -> Self {
        switch (shuffle, repeatMode) {
        case (false, .off): Self(shuffle: true, repeatMode: .off)
        case (true, .off): Self(shuffle: false, repeatMode: .all)
        case (_, .all): supportsRepeatOne ? Self(shuffle: false, repeatMode: .one) : Self()
        case (_, .one): Self()
        }
    }
}

struct MediaControlCapabilities: Equatable, Sendable {
    var queue: MediaCapabilityAvailability = .unsupported
    var favorite: MediaCapabilityAvailability = .unsupported
    var playbackMode: MediaCapabilityAvailability = .unsupported
    var supportsRepeatOne = false
    var output: MediaCapabilityAvailability = .unsupported

    /// Real backends only:
    /// - Spotify: queue / liked / repeat-one through the authorized Web API;
    ///   shuffle + repeat-all also through Spotify's AppleScript without auth.
    /// - Music: shuffle, repeat off/one/all and favorite through AppleScript;
    ///   Music exposes no queue API.
    /// - System Now Playing / browsers: no public advanced-control API.
    /// - Output: CoreAudio default output device, for every source.
    static func resolve(source: MediaSourceKind, spotifyConnected: Bool, hasOutputDevices: Bool) -> Self {
        var value = Self()
        value.output = hasOutputDevices ? .supported : .unsupported
        switch source {
        case .spotify:
            value.queue = spotifyConnected ? .supported : .authRequired
            value.favorite = spotifyConnected ? .supported : .authRequired
            value.playbackMode = .supported
            value.supportsRepeatOne = spotifyConnected
        case .music:
            value.favorite = .supported
            value.playbackMode = .supported
            value.supportsRepeatOne = true
        case .system, .browser, .unknown:
            break
        }
        return value
    }

    static func reason(_ availability: MediaCapabilityAvailability, source: String) -> String? {
        switch availability {
        case .supported: nil
        case .authRequired: "Connect Spotify in the Apps & Media page to use this"
        case .unsupported: "Not available for \(source)"
        }
    }
}

// MARK: - Output devices (public CoreAudio)

struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    let id: AudioObjectID
    let name: String
}

/// Enumerates real output devices and sets the system default output device
/// through public CoreAudio. AirPlay receivers appear here only when macOS
/// exposes them as an output device; individual AirPlay routing is not
/// available through a public API, so it is not imitated.
enum AudioOutputRouter {
    static func outputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard outputChannelCount(id) > 0, let name = name(of: id) else { return nil }
            return AudioOutputDevice(id: id, name: name)
        }
    }

    static func currentOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    @discardableResult
    static func select(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &device) == noErr
    }

    private static func outputChannelCount(_ id: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }
}

// MARK: - Controller

/// Advanced Now Playing state and actions for the active source. Refreshes
/// on track/source change and on demand (a player appearing), never on a
/// timer. Every action goes to a real provider backend; failures surface.
@MainActor
final class MediaAdvancedController: ObservableObject {
    @Published private(set) var capabilities = MediaControlCapabilities()
    @Published private(set) var mode = MediaPlaybackModeState()
    @Published private(set) var isFavorite = false
    @Published private(set) var outputDevices: [AudioOutputDevice] = []
    @Published private(set) var currentOutputID: AudioObjectID?
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy = false

    let media: MediaController
    let spotify: SpotifyLibraryController
    private var spotifyItemURI: String?
    private var refreshGeneration = 0
    private var cancellables: Set<AnyCancellable> = []

    init(media: MediaController, spotify: SpotifyLibraryController) {
        self.media = media
        self.spotify = spotify
        media.$title.combineLatest(media.$sourceKind)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
        spotify.$connectionState.removeDuplicates().dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
        Task { [weak self] in await self?.refresh() }
    }

    var queue: [SpotifyMediaItem] { spotify.snapshot?.queue ?? [] }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshOutputDevices()
        let connected = spotify.connectionState == .connected
        let source = media.hasActiveMediaSource ? media.sourceKind : .unknown
        capabilities = .resolve(source: source, spotifyConnected: connected, hasOutputDevices: !outputDevices.isEmpty)
        switch source {
        case .spotify where connected:
            do {
                if let state = try await spotify.playbackState() {
                    guard generation == refreshGeneration else { return }
                    mode = MediaPlaybackModeState(shuffle: state.shuffle, repeatMode: Self.mode(state.repeatState))
                    spotifyItemURI = state.itemURI
                    if let uri = state.itemURI { isFavorite = try await spotify.isSaved(uri: uri) }
                }
                await spotify.refreshQueue()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        case .spotify:
            let result = await media.runAutomation("tell application \"Spotify\" to return (shuffling as string) & \"||\" & (repeating as string)", target: .spotify)
            guard generation == refreshGeneration else { return }
            if let parsed = Self.parseFlags(result.output) {
                mode = MediaPlaybackModeState(shuffle: parsed.0, repeatMode: parsed.1 ? .all : .off)
            }
        case .music:
            let script = "tell application \"Music\" to return (shuffle enabled as string) & \"||\" & (song repeat as string) & \"||\" & (favorited of current track as string)"
            let result = await media.runAutomation(script, target: .music)
            guard generation == refreshGeneration else { return }
            let parts = result.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "||")
            if parts.count == 3 {
                mode = MediaPlaybackModeState(shuffle: parts[0] == "true", repeatMode: MediaRepeatMode(rawValue: parts[1]) ?? .off)
                isFavorite = parts[2] == "true"
            }
        default:
            mode = MediaPlaybackModeState()
            isFavorite = false
        }
    }

    func refreshOutputDevices() {
        outputDevices = AudioOutputRouter.outputDevices()
        currentOutputID = AudioOutputRouter.currentOutputDeviceID()
    }

    // MARK: Actions

    func cycleMode() async {
        await apply(mode: mode.next(supportsRepeatOne: capabilities.supportsRepeatOne))
    }

    func setShuffle(_ on: Bool) async {
        var next = mode; next.shuffle = on
        await apply(mode: next)
    }

    func setRepeat(_ repeatMode: MediaRepeatMode) async {
        var next = mode; next.repeatMode = repeatMode
        await apply(mode: next)
    }

    func toggleFavorite() async {
        guard capabilities.favorite.isEnabled else { return }
        let target = !isFavorite
        isBusy = true
        defer { isBusy = false }
        switch media.sourceKind {
        case .spotify:
            guard let uri = spotifyItemURI else { lastError = "Spotify reports no playing item"; return }
            do { try await spotify.setSaved(uri: uri, saved: target); isFavorite = target; lastError = nil }
            catch { lastError = error.localizedDescription }
        case .music:
            let result = await media.runAutomation("tell application \"Music\" to set favorited of current track to \(target)", target: .music)
            if let message = result.errorDescription { lastError = message } else { isFavorite = target; lastError = nil }
        default:
            break
        }
    }

    func selectOutput(_ device: AudioOutputDevice) {
        if AudioOutputRouter.select(device.id) {
            currentOutputID = device.id
            lastError = nil
        } else {
            lastError = "macOS refused to switch the output to \(device.name)"
        }
    }

    private func apply(mode next: MediaPlaybackModeState) async {
        guard capabilities.playbackMode.isEnabled else { return }
        let target = capabilities.supportsRepeatOne || next.repeatMode != .one ? next
            : MediaPlaybackModeState(shuffle: next.shuffle, repeatMode: .all)
        isBusy = true
        defer { isBusy = false }
        switch media.sourceKind {
        case .spotify where spotify.connectionState == .connected:
            do {
                if target.shuffle != mode.shuffle { try await spotify.setShuffle(target.shuffle) }
                if target.repeatMode != mode.repeatMode { try await spotify.setRepeat(Self.spotifyRepeat(target.repeatMode)) }
                mode = target; lastError = nil
            } catch { lastError = error.localizedDescription }
        case .spotify:
            let script = "tell application \"Spotify\"\nset shuffling to \(target.shuffle)\nset repeating to \(target.repeatMode != .off)\nend tell"
            let result = await media.runAutomation(script, target: .spotify)
            if let message = result.errorDescription { lastError = message } else { mode = target; lastError = nil }
        case .music:
            let script = "tell application \"Music\"\nset shuffle enabled to \(target.shuffle)\nset song repeat to \(target.repeatMode.rawValue)\nend tell"
            let result = await media.runAutomation(script, target: .music)
            if let message = result.errorDescription { lastError = message } else { mode = target; lastError = nil }
        default:
            break
        }
    }

    // MARK: Pure mapping (tested)

    nonisolated static func mode(_ state: SpotifyPlaybackState.Repeat) -> MediaRepeatMode {
        switch state {
        case .off: .off
        case .context: .all
        case .track: .one
        }
    }

    nonisolated static func spotifyRepeat(_ mode: MediaRepeatMode) -> SpotifyPlaybackState.Repeat {
        switch mode {
        case .off: .off
        case .all: .context
        case .one: .track
        }
    }

    nonisolated static func parseFlags(_ output: String) -> (Bool, Bool)? {
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "||")
        guard parts.count == 2 else { return nil }
        return (parts[0] == "true", parts[1] == "true")
    }

    /// "-3:16": remaining time with a negative prefix (Now Playing style).
    nonisolated static func remainingLabel(position: Double, duration: Double) -> String {
        guard let duration = MediaPlaybackTime.validDuration(duration) else { return "-0:00" }
        let position = MediaPlaybackTime.clampedPosition(position.isFinite ? position : 0, duration: duration) ?? 0
        let whole = Int((duration - position).rounded())
        return "-\(whole / 60):" + String(format: "%02d", whole % 60)
    }
}

// MARK: - Environment

import SwiftUI

private struct MediaAdvancedControlsKey: EnvironmentKey {
    static let defaultValue: MediaAdvancedController? = nil
}

extension EnvironmentValues {
    var mediaAdvancedControls: MediaAdvancedController? {
        get { self[MediaAdvancedControlsKey.self] }
        set { self[MediaAdvancedControlsKey.self] = newValue }
    }
}
