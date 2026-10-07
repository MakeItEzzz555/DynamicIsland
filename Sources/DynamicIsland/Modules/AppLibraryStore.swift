import AppKit
import Foundation

/// One launchable installed application.
struct InstalledApp: Identifiable, Equatable, Hashable, Sendable {
    let bundleIdentifier: String
    let name: String
    let url: URL

    var id: String { bundleIdentifier }
}

/// Discovers installed, user-launchable applications from the standard
/// application folders using only public Foundation/AppKit APIs. Runs off
/// the main actor; never evaluated during SwiftUI body computation.
enum InstalledAppScanner {
    static var standardDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true)
        ]
    }

    /// Finder lives outside the application folders but is user-facing.
    static let extraApplications = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)]

    /// Earlier directories win for duplicate bundle identifiers.
    static func scan(
        directories: [URL] = standardDirectories,
        extras: [URL] = extraApplications,
        maximumDepth: Int = 3,
        fileManager: FileManager = .default
    ) -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        let scanned = directories.flatMap { bundles(in: $0, maximumDepth: maximumDepth, fileManager: fileManager) }
        let candidates = scanned.map { ($0, true) } + extras.map { ($0, false) }
        for (url, requiresApplicationType) in candidates {
            guard let app = app(at: url, requiresApplicationType: requiresApplicationType, fileManager: fileManager),
                  seen.insert(app.bundleIdentifier.lowercased()).inserted else { continue }
            apps.append(app)
        }
        return apps.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.bundleIdentifier < $1.bundleIdentifier : order == .orderedAscending
        }
    }

    static func bundles(in directory: URL, maximumDepth: Int, fileManager: FileManager = .default) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app" {
                result.append(url)
                enumerator.skipDescendants()
            } else if enumerator.level >= maximumDepth {
                enumerator.skipDescendants()
            } else if (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true {
                enumerator.skipDescendants()
            }
        }
        return result
    }

    /// Nil for helpers, agents and background-only bundles.
    static func app(
        at url: URL,
        requiresApplicationType: Bool = true,
        fileManager: FileManager = .default
    ) -> InstalledApp? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String, !identifier.isEmpty,
              info["CFBundleExecutable"] != nil else { return nil }
        if isTrue(info["LSUIElement"]) || isTrue(info["LSBackgroundOnly"]) { return nil }
        if requiresApplicationType, let type = info["CFBundlePackageType"] as? String, type != "APPL" { return nil }
        var name = fileManager.displayName(atPath: url.path)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        return InstalledApp(bundleIdentifier: identifier, name: name, url: url)
    }

    private static func isTrue(_ value: Any?) -> Bool {
        switch value {
        case let value as Bool: value
        case let value as NSNumber: value.boolValue
        case let value as String: ["1", "true", "yes"].contains(value.lowercased())
        default: false
        }
    }
}

/// Cached installed-app catalog with favorites and recents.
@MainActor
final class AppLibraryStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    static let recentsKey = "appLibrary.recentBundleIdentifiers"
    static let favoritesKey = "appLibrary.favoriteBundleIdentifiers"
    static let maximumRecents = 8
    static let cacheLifetime: TimeInterval = 5 * 60

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var recentIDs: [String]
    @Published private(set) var favoriteIDs: [String]
    @Published private(set) var lastLaunchError: String?

    private let defaults: UserDefaults
    private let scan: @Sendable () -> [InstalledApp]
    private var loadedAt: Date?
    private var loadTask: Task<Void, Never>?
    private let iconCache = NSCache<NSString, NSImage>()

    init(
        defaults: UserDefaults = .standard,
        scan: @escaping @Sendable () -> [InstalledApp] = { InstalledAppScanner.scan() }
    ) {
        self.defaults = defaults
        self.scan = scan
        recentIDs = defaults.stringArray(forKey: Self.recentsKey) ?? []
        favoriteIDs = defaults.stringArray(forKey: Self.favoritesKey) ?? []
        iconCache.countLimit = 256
    }

    /// Scans in the background unless a fresh catalog is cached.
    func refreshIfNeeded(now: Date = Date()) {
        if let loadedAt, now.timeIntervalSince(loadedAt) < Self.cacheLifetime, !apps.isEmpty { return }
        reload()
    }

    func reload() {
        guard loadTask == nil else { return }
        state = apps.isEmpty ? .loading : state
        let scan = scan
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { scan() }.value
            guard let self else { return }
            self.apps = result
            self.loadedAt = Date()
            self.state = .loaded
            self.loadTask = nil
        }
    }

    func waitForLoad() async {
        await loadTask?.value
    }

    func filtered(_ query: String) -> [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.bundleIdentifier.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var favorites: [InstalledApp] { resolve(favoriteIDs) }
    var recents: [InstalledApp] { resolve(recentIDs) }

    func isFavorite(_ app: InstalledApp) -> Bool { favoriteIDs.contains(app.bundleIdentifier) }

    func toggleFavorite(_ app: InstalledApp) {
        if let index = favoriteIDs.firstIndex(of: app.bundleIdentifier) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.append(app.bundleIdentifier)
        }
        defaults.set(favoriteIDs, forKey: Self.favoritesKey)
    }

    func icon(for app: InstalledApp) -> NSImage {
        let key = app.url.path as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        iconCache.setObject(image, forKey: key)
        return image
    }

    /// Launches the real application and records it as recent on success.
    @discardableResult
    func launch(_ app: InstalledApp) async -> Bool {
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: app.url,
                configuration: NSWorkspace.OpenConfiguration()
            )
            recordRecent(app.bundleIdentifier)
            lastLaunchError = nil
            return true
        } catch {
            lastLaunchError = "\(app.name) could not be opened"
            return false
        }
    }

    func recordRecent(_ bundleIdentifier: String) {
        recentIDs.removeAll { $0 == bundleIdentifier }
        recentIDs.insert(bundleIdentifier, at: 0)
        if recentIDs.count > Self.maximumRecents { recentIDs.removeLast(recentIDs.count - Self.maximumRecents) }
        defaults.set(recentIDs, forKey: Self.recentsKey)
    }

    private func resolve(_ ids: [String]) -> [InstalledApp] {
        let byID = Dictionary(apps.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }
}
