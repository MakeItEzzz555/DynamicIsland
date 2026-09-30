import XCTest
@testable import DynamicIsland

final class AppLibraryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppLibraryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testScannerKeepsLaunchableAppsAndSkipsAgentsHelpersAndDuplicates() throws {
        let first = root.appendingPathComponent("A", isDirectory: true)
        let second = root.appendingPathComponent("B", isDirectory: true)
        try makeApp("Notes Pro", id: "com.example.notes", in: first)
        try makeApp("Menu Agent", id: "com.example.agent", in: first, extra: ["LSUIElement": true])
        try makeApp("Daemon", id: "com.example.daemon", in: first, extra: ["LSBackgroundOnly": "1"])
        try makeApp("Nested", id: "com.example.nested", in: first.appendingPathComponent("Utilities"))
        try makeApp("Notes Copy", id: "com.example.notes", in: second)
        try makeApp("Broken", id: "", in: second)
        // An app inside another app bundle is not listed separately.
        try makeApp("Helper", id: "com.example.helper",
                    in: first.appendingPathComponent("Notes Pro.app/Contents/Library"))

        let apps = InstalledAppScanner.scan(directories: [first, second], extras: [])

        XCTAssertEqual(apps.map(\.bundleIdentifier), ["com.example.nested", "com.example.notes"])
        XCTAssertEqual(apps.first { $0.bundleIdentifier == "com.example.notes" }?.name, "Notes Pro",
                       "the earlier directory wins for duplicates")
    }

    /// Real system data: the macOS catalog includes built-in apps with icons.
    func testRealSystemCatalogIncludesBuiltInApplications() {
        let apps = InstalledAppScanner.scan()
        let ids = Set(apps.map(\.bundleIdentifier))
        XCTAssertTrue(ids.contains("com.apple.calculator"), "Calculator should be discovered")
        XCTAssertTrue(ids.contains("com.apple.finder"), "Finder should be discovered")
        XCTAssertFalse(ids.contains("com.apple.dock"), "Dock is not a user app")
        XCTAssertEqual(ids.count, apps.count, "no duplicate bundle identifiers")
    }

    @MainActor
    func testStoreCachesSearchesAndPersistsFavoritesAndRecents() async throws {
        let suite = "AppLibraryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = [
            InstalledApp(bundleIdentifier: "com.example.a", name: "Alpha", url: root),
            InstalledApp(bundleIdentifier: "com.example.b", name: "Beta", url: root)
        ]
        let scans = ScanCounter()
        let store = AppLibraryStore(defaults: defaults, scan: { scans.increment(); return catalog })

        store.refreshIfNeeded()
        await store.waitForLoad()
        store.refreshIfNeeded()
        await store.waitForLoad()
        XCTAssertEqual(store.apps, catalog)
        XCTAssertEqual(scans.value, 1, "fresh cache is reused")
        XCTAssertEqual(store.filtered("bet").map(\.name), ["Beta"])

        store.toggleFavorite(catalog[1])
        store.recordRecent("com.example.a")
        store.recordRecent("com.example.b")
        store.recordRecent("com.example.a")
        let reloaded = AppLibraryStore(defaults: defaults, scan: { catalog })
        reloaded.reload()
        await reloaded.waitForLoad()
        XCTAssertEqual(reloaded.favorites.map(\.name), ["Beta"])
        XCTAssertEqual(reloaded.recents.map(\.name), ["Alpha", "Beta"])
    }

    private func makeApp(_ name: String, id: String, in directory: URL, extra: [String: Any] = [:]) throws {
        let contents = directory.appendingPathComponent("\(name).app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleExecutable": name, "CFBundlePackageType": "APPL"]
        if !id.isEmpty { info["CFBundleIdentifier"] = id }
        info.merge(extra) { $1 }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}

private final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
