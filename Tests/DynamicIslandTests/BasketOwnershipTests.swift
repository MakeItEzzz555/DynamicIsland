import XCTest
@testable import DynamicIsland

/// Temporary-file ownership is the safety contract for Basket ↔ Shelf ↔
/// Basket transfers: stable user files are never deleted, and DynamicIsland
/// temp files are deleted only when the last surface releases them.
@MainActor
final class BasketOwnershipTests: XCTestCase {
    private var root: URL!
    private var tempRoot: URL!
    private var userDir: URL!
    private var ledger: TemporaryFileOwnershipLedger!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BasketOwnershipTests-\(UUID().uuidString)", isDirectory: true)
        tempRoot = root.appendingPathComponent("Owned", isDirectory: true)
        userDir = root.appendingPathComponent("User", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        ledger = TemporaryFileOwnershipLedger(temporaryRoots: [tempRoot])
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ name: String, in dir: URL) -> URL {
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url.standardizedFileURL
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testClassifiesStableAndTemporaryURLs() {
        XCTAssertTrue(ledger.isTemporary(file("a.png", in: tempRoot)))
        XCTAssertFalse(ledger.isTemporary(file("b.png", in: userDir)))
        XCTAssertFalse(ledger.isTemporary(tempRoot), "the root itself is never a deletable item")
    }

    func testReleasingStableURLNeverDeletesOriginal() {
        let original = file("original.txt", in: userDir)
        let basket = FileSurfaceOwner.basket(UUID())
        ledger.retain([original], by: basket)
        let deleted = ledger.release([original], by: basket)
        XCTAssertEqual(deleted, [])
        XCTAssertTrue(exists(original))
        XCTAssertTrue(ledger.owners(of: original).isEmpty)
    }

    func testTemporaryFileDeletedOnlyWhenLastOwnerReleases() {
        let promised = file("photo.heic", in: tempRoot.appendingPathComponent("drop1"))
        let basket = FileSurfaceOwner.basket(UUID())
        ledger.retain([promised], by: basket)
        ledger.retain([promised], by: .shelf)

        XCTAssertEqual(ledger.release([promised], by: basket), [])
        XCTAssertTrue(exists(promised), "Shelf still owns it")

        XCTAssertEqual(ledger.release([promised], by: .shelf), [promised])
        XCTAssertFalse(exists(promised))
        XCTAssertFalse(exists(promised.deletingLastPathComponent()), "empty drop directory is pruned")
        XCTAssertTrue(exists(tempRoot), "the owned root is never removed")
    }

    func testReleasingOnePromisedSiblingKeepsTheOthers() {
        let dir = tempRoot.appendingPathComponent("drop2")
        let first = file("1.heic", in: dir)
        let second = file("2.heic", in: dir)
        let basket = FileSurfaceOwner.basket(UUID())
        ledger.retain([first, second], by: basket)

        XCTAssertEqual(ledger.release([first], by: basket), [first])
        XCTAssertTrue(exists(second), "deleting one promise result must not delete its sibling's directory")
        XCTAssertTrue(exists(dir))
    }

    func testTransferMovesOwnershipWithoutCleanup() {
        let promised = file("p.png", in: tempRoot.appendingPathComponent("drop3"))
        let a = FileSurfaceOwner.basket(UUID())
        let b = FileSurfaceOwner.basket(UUID())
        ledger.retain([promised], by: a)

        ledger.transfer([promised], from: a, to: b)
        XCTAssertTrue(exists(promised))
        XCTAssertEqual(ledger.owners(of: promised), [b])

        ledger.transfer([promised], from: b, to: .shelf)
        XCTAssertTrue(exists(promised))
        XCTAssertEqual(ledger.owners(of: promised), [.shelf])
    }

    func testReleaseByNonOwnerIsIgnored() {
        let promised = file("q.png", in: tempRoot.appendingPathComponent("drop4"))
        ledger.retain([promised], by: .shelf)
        XCTAssertEqual(ledger.release([promised], by: .basket(UUID())), [])
        XCTAssertTrue(exists(promised))
    }

    func testDiscardIfUnownedOnlyRemovesOrphanedTemporaryFiles() {
        let orphan = file("o.png", in: tempRoot.appendingPathComponent("drop5"))
        let owned = file("w.png", in: tempRoot.appendingPathComponent("drop6"))
        let stable = file("s.png", in: userDir)
        ledger.retain([owned], by: .shelf)

        let deleted = ledger.discardIfUnowned([orphan, owned, stable])
        XCTAssertEqual(deleted, [orphan])
        XCTAssertTrue(exists(owned))
        XCTAssertTrue(exists(stable))
    }

    func testDragOutRetentionOutlivesBasketRemoval() {
        let promised = file("d.png", in: tempRoot.appendingPathComponent("drop7"))
        let basket = FileSurfaceOwner.basket(UUID())
        let drag = FileSurfaceOwner.dragOut(UUID())
        ledger.retain([promised], by: basket)
        ledger.retain([promised], by: drag)

        ledger.release([promised], by: basket)
        XCTAssertTrue(exists(promised), "a drag session in flight still needs the file")
        ledger.release([promised], by: drag)
        XCTAssertFalse(exists(promised))
    }
}
