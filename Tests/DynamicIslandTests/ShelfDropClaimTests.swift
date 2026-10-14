import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
final class ShelfDropClaimTests: XCTestCase {
    func testOneClaimCompletesOnceAndAutoOpenKeepsExactRequestIdentity() throws {
        let f = try Fixture(); defer { f.close() }
        let drag = FileDragSessionController()
        let claim = try XCTUnwrap(drag.claimShelfDrop())
        XCTAssertNil(drag.claimShelfDrop()); XCTAssertNil(drag.claimDrop(.mail))
        XCTAssertEqual(drag.completeShelfDrop(claim, urls: [f.file, f.file], shelf: f.shelf, allowed: true, openAfterDrop: true), [f.file])
        let request = try XCTUnwrap(f.shelf.fileActionRequest)
        XCTAssertTrue(request.openShelfAfterDrop)
        XCTAssertNil(drag.completeShelfDrop(claim, urls: [f.file], shelf: f.shelf, allowed: true, openAfterDrop: true))
        XCTAssertEqual(f.shelf.fileActionRequest?.id, request.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.file.path))
        f.shelf.consumeAutoOpenRequest(UUID())
        XCTAssertTrue(try XCTUnwrap(f.shelf.fileActionRequest).openShelfAfterDrop)
        f.shelf.consumeAutoOpenRequest(request.id)
        XCTAssertFalse(try XCTUnwrap(f.shelf.fileActionRequest).openShelfAfterDrop)
        XCTAssertEqual(f.shelf.files, [f.file])
        XCTAssertFalse(drag.isActive)
    }

    func testCancelledLateDropCannotPublishOrDeleteAnExistingOwner() throws {
        let f = try Fixture(owned: true); defer { f.close() }
        f.shelf.add([f.file])
        let drag = FileDragSessionController()
        let old = try XCTUnwrap(drag.claimShelfDrop())
        drag.cancel()
        let current = try XCTUnwrap(drag.claimShelfDrop())
        XCTAssertNil(drag.completeShelfDrop(old, urls: [f.file], shelf: f.shelf, allowed: true))
        XCTAssertTrue(drag.isDropInFlight)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.file.path))
        XCTAssertNil(f.shelf.fileActionRequest)
        XCTAssertEqual(drag.completeShelfDrop(current, urls: [f.file], shelf: f.shelf, allowed: false), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.file.path))
        XCTAssertFalse(drag.isActive)
    }

    func testDisabledIntakeCleansOnlyUnownedMaterializedFiles() throws {
        let f = try Fixture(owned: true); defer { f.close() }
        let drag = FileDragSessionController()
        let claim = try XCTUnwrap(drag.claimShelfDrop())
        XCTAssertEqual(drag.completeShelfDrop(claim, urls: [f.file], shelf: f.shelf, allowed: false), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.file.path))
        XCTAssertTrue(f.shelf.files.isEmpty)
        let borrowed = try Fixture(); defer { borrowed.close() }
        let next = try XCTUnwrap(drag.claimShelfDrop())
        _ = drag.completeShelfDrop(next, urls: [borrowed.file], shelf: borrowed.shelf, allowed: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: borrowed.file.path))
    }

    @MainActor
    private final class Fixture {
        let root: URL, file: URL
        let shelf: FileShelfStore
        init(owned: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-claim-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            file = root.appendingPathComponent("synthetic.txt")
            try Data("Synthetic intake".utf8).write(to: file)
            let ledger = TemporaryFileOwnershipLedger(temporaryRoots: owned ? [root] : [])
            shelf = FileShelfStore(settings: AppSettings(defaults: SettingsPreviewDefaults()), defaults: SettingsPreviewDefaults(), ownership: ledger)
        }
        func close() { try? FileManager.default.removeItem(at: root) }
    }
}
