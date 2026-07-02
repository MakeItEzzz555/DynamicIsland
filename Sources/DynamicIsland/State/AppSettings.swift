import Foundation
import SwiftUI

@MainActor
public final class AppSettings: ObservableObject {
    @Published public var overlayEnabled: Bool {
        didSet { save(overlayEnabled, for: "overlayEnabled") }
    }
    @Published public var launchAtLogin: Bool {
        didSet { save(launchAtLogin, for: "launchAtLogin") }
    }
    @Published public var hoverDelay: Double {
        didSet { save(hoverDelay, for: "hoverDelay") }
    }
    @Published public var autoCollapseDelay: Double {
        didSet { save(autoCollapseDelay, for: "autoCollapseDelay") }
    }
    @Published public var animationIntensity: Double {
        didSet { save(animationIntensity, for: "animationIntensity") }
    }
    @Published public var mediaEnabled: Bool {
        didSet { save(mediaEnabled, for: "mediaEnabled") }
    }
    @Published public var fileShelfEnabled: Bool {
        didSet { save(fileShelfEnabled, for: "fileShelfEnabled") }
    }
    @Published public var shortcutsEnabled: Bool {
        didSet { save(shortcutsEnabled, for: "shortcutsEnabled") }
    }

    public init(defaults: UserDefaults = .standard) {
        overlayEnabled = defaults.object(forKey: "overlayEnabled") as? Bool ?? true
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        hoverDelay = defaults.object(forKey: "hoverDelay") as? Double ?? 0.12
        autoCollapseDelay = defaults.object(forKey: "autoCollapseDelay") as? Double ?? 4.0
        animationIntensity = defaults.object(forKey: "animationIntensity") as? Double ?? 0.82
        mediaEnabled = defaults.object(forKey: "mediaEnabled") as? Bool ?? true
        fileShelfEnabled = defaults.object(forKey: "fileShelfEnabled") as? Bool ?? true
        shortcutsEnabled = defaults.object(forKey: "shortcutsEnabled") as? Bool ?? true
    }

    public var collapsedSize: CGSize {
        CGSize(width: 520, height: 58)
    }

    public var peekSize: CGSize {
        collapsedSize
    }

    public var expandedSize: CGSize {
        CGSize(width: 900, height: 410)
    }

    private func save(_ value: Any, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
