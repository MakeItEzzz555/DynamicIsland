import XCTest
@testable import DynamicIsland

private final class RecordingFileShelfDefaults: UserDefaults, @unchecked Sendable {
    var persistedBookmarksSetCount = 0
    var persistedBookmarksRemovalCount = 0

    override func set(_ value: Any?, forKey defaultName: String) {
        if defaultName == "fileShelfPersistedBookmarks" {
            persistedBookmarksSetCount += 1
        }
        super.set(value, forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) {
        if defaultName == "fileShelfPersistedBookmarks" {
            persistedBookmarksRemovalCount += 1
        }
        super.removeObject(forKey: defaultName)
    }
}

final class FileShelfStoreTests: XCTestCase {
    private var defaults: RecordingFileShelfDefaults!
    private var defaultsSuiteName: String!
    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "FileShelfStoreTests-\(UUID().uuidString)"
        defaults = RecordingFileShelfDefaults(suiteName: defaultsSuiteName)!
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
        defaults.persistedBookmarksRemovalCount = 0
        firstSettings.persistFileShelfAcrossLaunches = false

        XCTAssertEqual(defaults.persistedBookmarksRemovalCount, 1)

        let secondSettings = AppSettings(defaults: defaults)
        let secondStore = FileShelfStore(settings: secondSettings, defaults: defaults)

        XCTAssertTrue(secondStore.files.isEmpty)
    }

    @MainActor
    func testEnablingPersistenceImmediatelySavesExistingFiles() {
        let firstSettings = AppSettings(defaults: defaults)
        let firstStore = FileShelfStore(settings: firstSettings, defaults: defaults)
        let file = makeFile(named: "enabled-after-add.txt")
        firstStore.add([file])

        defaults.persistedBookmarksSetCount = 0
        firstSettings.persistFileShelfAcrossLaunches = true

        XCTAssertEqual(defaults.persistedBookmarksSetCount, 1)
        let secondSettings = AppSettings(defaults: defaults)
        let secondStore = FileShelfStore(settings: secondSettings, defaults: defaults)
        XCTAssertEqual(secondStore.files, [file.standardizedFileURL])
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

    @MainActor
    func testRemovingOwnedTemporaryFileDeletesMaterializedCopy() throws {
        let settings = AppSettings(defaults: defaults)
        let store = FileShelfStore(settings: settings, defaults: defaults)
        let source = makeFile(named: "provider-owned.txt")
        let ownedURL = try FileShelfTemporaryStorage.shared.copyIntoShelf(source)

        store.add([ownedURL])
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownedURL.path))

        store.remove(ownedURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: ownedURL.path))
        XCTAssertTrue(store.files.isEmpty)
    }

    @MainActor
    func testAddingOwnedTemporaryFileTwiceDoesNotDeleteShelfItem() throws {
        let settings = AppSettings(defaults: defaults)
        let store = FileShelfStore(settings: settings, defaults: defaults)
        let source = makeFile(named: "duplicate-provider-owned.txt")
        let ownedURL = try FileShelfTemporaryStorage.shared.copyIntoShelf(source)

        store.add([ownedURL, ownedURL])

        XCTAssertEqual(store.files, [ownedURL.standardizedFileURL])
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownedURL.path))
        store.clear()
    }


    @MainActor
    func testRangeSelectionUsesStableShelfOrderAndSelectAll() {
        let settings = AppSettings(defaults: defaults)
        let store = FileShelfStore(settings: settings, defaults: defaults)
        let a = makeFile(named: "a.txt")
        let b = makeFile(named: "b.txt")
        let c = makeFile(named: "c.txt")
        let d = makeFile(named: "d.txt")
        store.add([a, b, c, d])
        let files = store.files

        store.select(files[1])
        store.select(files[3], range: true)
        XCTAssertEqual(store.selection, Set([files[1], files[2], files[3]]))

        store.select(files[0], extend: true)
        XCTAssertEqual(store.selection, Set(files))
        store.clearSelection()
        store.selectAll()
        XCTAssertEqual(store.selection, Set(files))
    }

    @MainActor
    func testFoldersAreRealShelfItems() throws {
        let settings = AppSettings(defaults: defaults)
        let store = FileShelfStore(settings: settings, defaults: defaults)
        let folder = temporaryDirectory.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        store.add([folder])

        XCTAssertEqual(store.files, [folder.standardizedFileURL])
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.files[0].path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    @MainActor
    func testRenameUpdatesShelfSelectionAndDiskWithoutOverwriting() throws {
        let settings = AppSettings(defaults: defaults)
        let store = FileShelfStore(settings: settings, defaults: defaults)
        let original = makeFile(named: "before.txt")
        let occupied = makeFile(named: "taken.txt")
        store.add([original, occupied])
        store.select(original)

        let renamed = try store.rename(original, to: "after.txt")

        XCTAssertEqual(renamed.lastPathComponent, "after.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertTrue(store.selection.contains(renamed))
        XCTAssertFalse(store.selection.contains(original))

        XCTAssertThrowsError(try store.rename(renamed, to: "taken.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: occupied.path))
    }

    @MainActor
    func testRemovingStableFileFromShelfNeverDeletesOriginal() {
        let settings = AppSettings(defaults: defaults)
        let store = FileShelfStore(settings: settings, defaults: defaults)
        let file = makeFile(named: "keep-on-disk.txt")
        store.add([file])

        store.remove(file)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(store.files.isEmpty)
    }


    @MainActor
    func testRecordMoveRetargetsShelfAndSelectionAfterRealDiskMove() throws {
        let settings = AppSettings(defaults: defaults)
        let store = FileShelfStore(settings: settings, defaults: defaults)
        let source = makeFile(named: "move-me.txt")
        store.add([source])
        store.select(source)
        let destinationDirectory = temporaryDirectory.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.moveItem(at: source, to: destination)

        store.recordMove(from: source, to: destination)

        XCTAssertEqual(store.files, [destination.standardizedFileURL])
        XCTAssertEqual(store.selection, [destination.standardizedFileURL])
    }

    private func makeFile(named name: String) -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        _ = FileManager.default.createFile(atPath: url.path, contents: Data(name.utf8))
        return url
    }
}
