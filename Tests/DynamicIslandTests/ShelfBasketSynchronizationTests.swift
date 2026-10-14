import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
final class ShelfBasketSynchronizationTests: XCTestCase {
    func testBidirectionalAdditionsPreserveSelectionAndNeverResurrectLocalRemoval() async throws {
        let f = try Fixture(); defer { f.close() }
        let basket = try XCTUnwrap(f.baskets.createBasket())
        f.sync.configure(enabled: true)
        f.shelf.add([f.a]); f.shelf.select(f.a)
        await settle()
        XCTAssertEqual(basket.urls, [f.a])
        XCTAssertEqual(f.shelf.selection, [f.a])
        let firstID = try XCTUnwrap(basket.items.first).id
        basket.select(firstID)
        f.baskets.add([f.b, f.b], to: basket.id)
        await settle()
        XCTAssertEqual(f.shelf.files, [f.a, f.b])
        XCTAssertEqual(basket.urls, [f.a, f.b])
        XCTAssertEqual(basket.selection, [firstID])
        f.shelf.remove(f.a)
        await settle()
        XCTAssertEqual(f.shelf.files, [f.b])
        XCTAssertEqual(basket.urls, [f.a, f.b])
        f.shelf.add([f.b]); await settle()
        XCTAssertEqual(f.shelf.files, [f.b])
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.a.path))
    }

    func testDisableCancelsQueuedSynchronizationAndOtherBasketsStayIndependent() async throws {
        let f = try Fixture(); defer { f.close() }
        let first = try XCTUnwrap(f.baskets.createBasket())
        let second = try XCTUnwrap(f.baskets.createBasket())
        f.sync.configure(enabled: true)
        f.shelf.add([f.a]); f.sync.configure(enabled: false)
        await settle()
        XCTAssertTrue(first.urls.isEmpty)
        f.sync.configure(enabled: true); await settle()
        XCTAssertEqual(first.urls, [f.a])
        XCTAssertTrue(second.urls.isEmpty)
        f.baskets.add([f.b], to: second.id); await settle()
        XCTAssertEqual(f.shelf.files, [f.a])
        f.sync.stop(); f.shelf.add([f.b]); await settle()
        XCTAssertEqual(first.urls, [f.a])
    }

    func testSynchronizationDoesNotCreateOrOpenBasketAndRespectsShelfCapacity() async throws {
        let f = try Fixture(); defer { f.close() }
        f.sync.configure(enabled: true); f.shelf.add([f.a]); await settle()
        XCTAssertTrue(f.baskets.baskets.isEmpty)
        let primary = try XCTUnwrap(f.baskets.createBasket()); await settle()
        XCTAssertEqual(primary.urls, [f.a])
        XCTAssertFalse(primary.isVisible)
        f.settings.maxShelfFiles = 1
        f.baskets.add([f.b], to: primary.id); await settle()
        XCTAssertEqual(f.shelf.files, [f.a])
        XCTAssertEqual(primary.urls, [f.a, f.b])
    }

    private func settle() async { for _ in 0..<5 { await Task.yield() } }

    @MainActor
    private final class Fixture {
        let root: URL, a: URL, b: URL
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        let shelf: FileShelfStore
        let baskets: BasketManager
        let sync: ShelfBasketSynchronization
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-sync-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            a = root.appendingPathComponent("a.txt"); b = root.appendingPathComponent("b.txt")
            try Data("Synthetic A".utf8).write(to: a); try Data("Synthetic B".utf8).write(to: b)
            let ledger = TemporaryFileOwnershipLedger(temporaryRoots: [])
            shelf = FileShelfStore(settings: settings, defaults: SettingsPreviewDefaults(), ownership: ledger)
            baskets = BasketManager(settings: settings, shelf: shelf, ownership: ledger, operations: nil)
            sync = ShelfBasketSynchronization(shelf: shelf, baskets: baskets)
        }
        func close() { sync.stop(); try? FileManager.default.removeItem(at: root) }
    }
}
