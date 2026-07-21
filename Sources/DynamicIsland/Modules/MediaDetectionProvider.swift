import AppKit
import Foundation

enum MediaSourceKind: Hashable {
    case system
    case spotify
    case music
    case browser
    case unknown
}

struct MediaSnapshot {
    var sourceKind: MediaSourceKind
    var sourceName: String
    var bundleIdentifier: String?
    var title: String
    var artist: String?
    var album: String?
    var artwork: NSImage?
    var isPlaying: Bool
    var duration: TimeInterval?
    var elapsedTime: TimeInterval?
    var transportAvailable: Bool
    var seekAvailable: Bool
    var volumeAvailable: Bool
}

@MainActor
protocol MediaDetectionProvider {
    var name: String { get }
    func snapshot() async -> MediaSnapshot?
}
