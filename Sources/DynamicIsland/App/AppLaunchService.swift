import AppKit
import Foundation

@MainActor
enum AppLaunchService {
    enum SupportedApp: CaseIterable, Equatable {
        case music
        case spotify
        case safari
        case brave
        case chrome
        case arc
        case edge
        case finder
        case systemSettings

        var displayName: String {
            switch self {
            case .music: "Apple Music"
            case .spotify: "Spotify"
            case .safari: "Safari"
            case .brave: "Brave"
            case .chrome: "Google Chrome"
            case .arc: "Arc"
            case .edge: "Microsoft Edge"
            case .finder: "Finder"
            case .systemSettings: "System Settings"
            }
        }

        var bundleIdentifier: String {
            switch self {
            case .music: "com.apple.Music"
            case .spotify: "com.spotify.client"
            case .safari: "com.apple.Safari"
            case .brave: "com.brave.Browser"
            case .chrome: "com.google.Chrome"
            case .arc: "company.thebrowser.Browser"
            case .edge: "com.microsoft.edgemac"
            case .finder: "com.apple.finder"
            case .systemSettings: "com.apple.systempreferences"
            }
        }

        var fallbackPaths: [String] {
            switch self {
            case .music:
                ["/System/Applications/Music.app", "/Applications/Music.app"]
            case .spotify:
                ["/Applications/Spotify.app"]
            case .safari:
                ["/Applications/Safari.app"]
            case .brave:
                ["/Applications/Brave Browser.app"]
            case .chrome:
                ["/Applications/Google Chrome.app"]
            case .arc:
                ["/Applications/Arc.app"]
            case .edge:
                ["/Applications/Microsoft Edge.app"]
            case .finder:
                ["/System/Library/CoreServices/Finder.app"]
            case .systemSettings:
                ["/System/Applications/System Settings.app", "/Applications/System Settings.app"]
            }
        }

        var knownPathNames: [String] {
            fallbackPaths.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() }
        }
    }

    @discardableResult
    static func open(_ app: SupportedApp) -> Bool {
        if let runningApplication = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == app.bundleIdentifier
        }) {
            runningApplication.activate(options: [])
            debugLog("focused running \(app.displayName) via \(app.bundleIdentifier)")
            return true
        }

        if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            openApplication(at: applicationURL, appName: app.displayName, resolution: "bundle")
            return true
        }

        for path in app.fallbackPaths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            openApplication(at: url, appName: app.displayName, resolution: "fallback path")
            return true
        }

        debugLog("unavailable \(app.displayName) bundle=\(app.bundleIdentifier)")
        return false
    }

    @discardableResult
    static func openApp(bundleIdentifier: String) -> Bool {
        if let app = SupportedApp.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return open(app)
        }

        if let runningApplication = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            runningApplication.activate(options: [])
            debugLog("focused running app via \(bundleIdentifier)")
            return true
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            debugLog("unavailable app bundle=\(bundleIdentifier)")
            return false
        }
        openApplication(at: applicationURL, appName: bundleIdentifier, resolution: "bundle")
        return true
    }

    @discardableResult
    static func openShortcut(title: String, target: String) -> Bool {
        if let app = supportedApp(title: title, target: target) {
            return open(app)
        }

        if let url = URL(string: target), url.scheme != nil {
            NSWorkspace.shared.open(url)
            return true
        }

        let url = URL(fileURLWithPath: target)
        guard FileManager.default.fileExists(atPath: url.path) else {
            debugLog("shortcut unavailable title=\(title) target=\(target)")
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }

    @discardableResult
    static func openYouTube(preferredBrowserBundleIdentifier: String? = nil) -> Bool {
        if let preferredBrowserBundleIdentifier,
           SupportedApp.allCases.contains(where: { $0.bundleIdentifier == preferredBrowserBundleIdentifier }) {
            _ = openApp(bundleIdentifier: preferredBrowserBundleIdentifier)
        }

        guard let url = URL(string: "https://www.youtube.com") else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    private static func supportedApp(title: String, target: String) -> SupportedApp? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetURL = URL(fileURLWithPath: target)
        let normalizedPathName = targetURL.lastPathComponent.lowercased()

        return SupportedApp.allCases.first { app in
            normalizedTitle == app.displayName.lowercased() ||
                normalizedTitle == shortName(for: app) ||
                app.knownPathNames.contains(normalizedPathName)
        }
    }

    private static func shortName(for app: SupportedApp) -> String {
        switch app {
        case .music: "music"
        case .systemSettings: "settings"
        default: app.displayName.lowercased()
        }
    }

    private static func openApplication(at url: URL, appName: String, resolution: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        debugLog("opened \(appName) via \(resolution) path=\(url.path)")
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        debugPrint("DynamicIsland app launch", message)
        #endif
    }
}
