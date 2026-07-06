import XCTest
@testable import DynamicIsland

final class FileShelfStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "FileShelfStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileShelfStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        temporaryDirectory = nil
        super.tearDown()
    }

    @MainActor
    func testAddRespectsMaxShelfFilesAndDeduplicates() {
        let settings = AppSettings(defaults: defaults)
        settings.maxShelfFiles = 2
        let store = FileShelfStore(settings: settings, defaults: defaults)
        let first = makeFile(named: "first.txt")
        let second = makeFile(named: "second.txt")
        let third = makeFile(named: "third.txt")

        store.add([first, second, first, third])

        XCTAssertEqual(store.files, [first.standardizedFileURL, second.standardizedFileURL])
    }

    @MainActor
    func testPersistenceRestoresExistingFilesWhenEnabled() {
        let firstSettings = AppSettings(defaults: defaults)
        firstSettings.persistFileShelfAcrossLaunches = true
        let firstStore = FileShelfStore(settings: firstSettings, defaults: defaults)
        let file = makeFile(named: "persisted.txt")

        firstStore.add([file])

        let secondSettings = AppSettings(defaults: defaults)
        secondSettings.persistFileShelfAcrossLaunches = true
        let secondStore = FileShelfStore(settings: secondSettings, defaults: defaults)

        XCTAssertEqual(secondStore.files, [file.standardizedFileURL])
    }

    @MainActor
    func testPersistenceDisabledDoesNotRestoreFiles() {
        let firstSettings = AppSettings(defaults: defaults)
        firstSettings.persistFileShelfAcrossLaunches = true
        let firstStore = FileShelfStore(settings: firstSettings, defaults: defaults)
        let file = makeFile(named: "runtime-only.txt")

        firstStore.add([file])
        firstSettings.persistFileShelfAcrossLaunches = false

        let secondSettings = AppSettings(defaults: defaults)
        let secondStore = FileShelfStore(settings: secondSettings, defaults: defaults)

        XCTAssertTrue(secondStore.files.isEmpty)
    }

    @MainActor
    func testMissingPersistedFilesAreDroppedOnRestore() {
        let firstSettings = AppSettings(defaults: defaults)
        firstSettings.persistFileShelfAcrossLaunches = true
        let firstStore = FileShelfStore(settings: firstSettings, defaults: defaults)
        let keptFile = makeFile(named: "kept.txt")
        let missingFile = makeFile(named: "missing.txt")

        firstStore.add([keptFile, missingFile])
        try? FileManager.default.removeItem(at: missingFile)

        let secondSettings = AppSettings(defaults: defaults)
        secondSettings.persistFileShelfAcrossLaunches = true
        let secondStore = FileShelfStore(settings: secondSettings, defaults: defaults)

        XCTAssertEqual(secondStore.files, [keptFile.standardizedFileURL])
    }

    private func makeFile(named name: String) -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        _ = FileManager.default.createFile(atPath: url.path, contents: Data(name.utf8))
        return url
    }
}
