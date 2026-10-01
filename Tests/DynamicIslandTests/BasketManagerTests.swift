import XCTest
@testable import DynamicIsland

@MainActor
final class BasketManagerTests: XCTestCase {
    private var root: URL!
    private var userDir: URL!
    private var tempRoot: URL!
    private var suite: String!
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var ledger: TemporaryFileOwnershipLedger!
    private var shelf: FileShelfStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BasketManagerTests-\(UUID().uuidString)", isDirectory: true)
        userDir = root.appendingPathComponent("User", isDirectory: true)
        tempRoot = root.appendingPathComponent("Owned", isDirectory: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        suite = "BasketManagerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        settings = AppSettings(defaults: defaults)
        settings.persistFileShelfAcrossLaunches = false
        ledger = TemporaryFileOwnershipLedger(temporaryRoots: [tempRoot])
        shelf = FileShelfStore(settings: settings, defaults: defaults, ownership: ledger)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeManager(operations: BackgroundOperationController? = nil) -> BasketManager {
        BasketManager(settings: settings, shelf: shelf, ownership: ledger, operations: operations)
    }

    private func file(_ name: String, in dir: URL? = nil) -> URL {
        let directory = dir ?? userDir!
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 1, count: 10))
        return url.standardizedFileURL
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: State

    func testAddKeepsStableOrderDeduplicatesAndSkipsMissing() throws {
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        let a = file("a.txt"), b = file("b.txt")
        let missing = userDir.appendingPathComponent("missing.txt")

        XCTAssertEqual(manager.add([a, b, a, missing], to: basket.id), [a, b])
        XCTAssertEqual(manager.add([b], to: basket.id), [])
        XCTAssertEqual(basket.items.map(\.url), [a, b])
        XCTAssertEqual(basket.totalByteCount, 20)
        XCTAssertEqual(basket.titleText, "2 Documents", "Droppy BasketFileCountLabel: all text/pdf → Documents")
    }

    func testFinderLikeSelection() throws {
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        let urls = (0..<5).map { file("\($0).txt") }
        manager.add(urls, to: basket.id)
        let ids = basket.items.map(\.id)

        basket.select(ids[1])
        XCTAssertEqual(basket.selection, [ids[1]])
        basket.select(ids[3], range: true)
        XCTAssertEqual(basket.selection, Set(ids[1...3]))
        basket.select(ids[0], extend: true)
        XCTAssertEqual(basket.selection, Set(ids[0...3]))
        basket.select(ids[2], extend: true)
        XCTAssertEqual(basket.selection, [ids[0], ids[1], ids[3]])
        basket.selectAll()
        XCTAssertEqual(basket.selection, Set(ids))
        basket.clearSelection()
        XCTAssertTrue(basket.selection.isEmpty)
    }

    func testDragPayloadUsesSelectionOnlyWhenDraggedItemIsSelected() throws {
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        let urls = (0..<3).map { file("\($0).txt") }
        manager.add(urls, to: basket.id)
        let ids = basket.items.map(\.id)
        basket.select(ids[0])
        basket.select(ids[2], extend: true)

        XCTAssertEqual(basket.dragPayload(startingAt: ids[2]), [urls[0], urls[2]], "Basket order, not Set order")
        XCTAssertEqual(basket.dragPayload(startingAt: ids[1]), [urls[1]])
    }

    func testMultipleBasketsAreIndependentWithDistinctAccents() throws {
        let manager = makeManager()
        let first = try XCTUnwrap(manager.createBasket())
        let second = try XCTUnwrap(manager.createBasket())
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.accent, second.accent)

        let a = file("a.txt")
        manager.add([a], to: first.id)
        manager.add([a], to: second.id)
        first.selectAll()
        first.layout = .list
        XCTAssertTrue(second.selection.isEmpty)
        XCTAssertEqual(second.layout, .grid)
        XCTAssertEqual(manager.baskets.count, 2)
    }

    func testAccentAllocationReusesFreedAccentAndHidesForSingleBasket() throws {
        let manager = makeManager()
        let first = try XCTUnwrap(manager.createBasket())
        let second = try XCTUnwrap(manager.createBasket())
        manager.setVisible(first.id, true)
        manager.setVisible(second.id, true)
        XCTAssertTrue(manager.showsAccentIdentity)
        manager.close(first.id)
        XCTAssertFalse(manager.showsAccentIdentity, "one visible basket shows no accent noise")
        let third = try XCTUnwrap(manager.createBasket())
        XCTAssertEqual(third.accent, first.accent, "lowest free accent is reused")
    }

    func testSingleBasketModeNeverCreatesASecondBasket() throws {
        settings.basketMultipleEnabled = false
        let manager = makeManager()
        let first = try XCTUnwrap(manager.createBasket())
        XCTAssertEqual(manager.createBasket()?.id, first.id)
        XCTAssertEqual(manager.baskets.count, 1)
    }

    func testDisabledFeatureCreatesNothing() {
        settings.floatingBasketEnabled = false
        XCTAssertNil(makeManager().createBasket())
    }

    // MARK: Ownership

    func testRemoveFromBasketNeverDeletesStableOriginal() throws {
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        let original = file("keep.txt")
        manager.add([original], to: basket.id)
        manager.remove(Set(basket.items.map(\.id)), from: basket.id)
        XCTAssertTrue(basket.items.isEmpty)
        XCTAssertTrue(exists(original))
        manager.add([original], to: basket.id)
        manager.close(basket.id)
        XCTAssertTrue(exists(original))
    }

    func testRemovingLastOwnerDeletesPromisedTemporaryFile() throws {
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        let promised = file("photo.heic", in: tempRoot.appendingPathComponent("drop"))
        manager.add([promised], to: basket.id)
        manager.remove(Set(basket.items.map(\.id)), from: basket.id)
        XCTAssertFalse(exists(promised))
    }

    func testBasketToShelfTransfersOwnershipWithoutCleanup() throws {
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        let promised = file("p.png", in: tempRoot.appendingPathComponent("drop"))
        let stable = file("s.txt")
        manager.add([promised, stable], to: basket.id)

        let moved = manager.moveToShelf(Set(basket.items.map(\.id)), from: basket.id)
        XCTAssertEqual(Set(moved), [promised, stable])
        XCTAssertTrue(basket.items.isEmpty)
        XCTAssertEqual(shelf.files, [promised, stable])
        XCTAssertTrue(exists(promised), "moving between surfaces never triggers cleanup")
        XCTAssertEqual(ledger.owners(of: promised), [.shelf])
        XCTAssertTrue(shelf.selection.isEmpty, "Shelf selection is not mutated by a transfer")

        shelf.remove(promised)
        XCTAssertFalse(exists(promised), "Shelf is now the last owner")
        XCTAssertTrue(exists(stable))
    }

    func testBasketToShelfKeepsItemsTheShelfRejects() throws {
        settings.maxShelfFiles = 1
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        let a = file("a.txt"), b = file("b.txt")
        manager.add([a, b], to: basket.id)
        let moved = manager.moveToShelf(Set(basket.items.map(\.id)), from: basket.id)
        XCTAssertEqual(moved, [a])
        XCTAssertEqual(basket.items.map(\.url), [b], "zero lost URLs")
    }

    func testShelfToBasketTransfersOwnership() throws {
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        let promised = file("p.png", in: tempRoot.appendingPathComponent("drop"))
        shelf.add([promised])
        shelf.select(promised)

        XCTAssertEqual(manager.moveFromShelf([promised], to: basket.id), [promised])
        XCTAssertEqual(shelf.files, [])
        XCTAssertTrue(shelf.selection.isEmpty)
        XCTAssertEqual(basket.items.map(\.url), [promised])
        XCTAssertTrue(exists(promised))
        XCTAssertEqual(ledger.owners(of: promised), [.basket(basket.id)])
    }

    func testBasketToBasketTransfer() throws {
        let manager = makeManager()
        let source = try XCTUnwrap(manager.createBasket())
        let target = try XCTUnwrap(manager.createBasket())
        let promised = file("p.png", in: tempRoot.appendingPathComponent("drop"))
        manager.add([promised], to: source.id)
        source.selectAll()

        XCTAssertEqual(manager.transfer(source.selection, from: source.id, to: target.id), [promised])
        XCTAssertTrue(source.items.isEmpty)
        XCTAssertTrue(source.selection.isEmpty)
        XCTAssertEqual(target.items.map(\.url), [promised])
        XCTAssertTrue(exists(promised))
        XCTAssertEqual(ledger.owners(of: promised), [.basket(target.id)])
    }

    func testRenameMovesOnDiskKeepsIdentityAndRejectsUnsafeNames() throws {
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        let original = file("old.txt")
        manager.add([original], to: basket.id)
        let id = try XCTUnwrap(basket.items.first?.id)
        basket.select(id)

        XCTAssertThrowsError(try manager.rename(id, in: basket.id, to: "a/b.txt"))
        XCTAssertThrowsError(try manager.rename(id, in: basket.id, to: "  "))
        _ = file("taken.txt")
        XCTAssertThrowsError(try manager.rename(id, in: basket.id, to: "taken.txt"))

        let renamed = try manager.rename(id, in: basket.id, to: "new.txt")
        XCTAssertEqual(renamed.lastPathComponent, "new.txt")
        XCTAssertFalse(exists(original))
        XCTAssertTrue(exists(renamed))
        XCTAssertEqual(basket.items.map(\.id), [id])
        XCTAssertEqual(basket.items.first?.url, renamed)
        XCTAssertEqual(basket.selection, [id])
        XCTAssertEqual(ledger.owners(of: renamed), [.basket(basket.id)])
    }

    // MARK: Drops

    func testDropClaimTargetsExactBasketAndStaleCompletionIsDiscarded() throws {
        let manager = makeManager()
        let first = try XCTUnwrap(manager.createBasket())
        let second = try XCTUnwrap(manager.createBasket())
        let claim = try XCTUnwrap(manager.claimDrop(into: second.id))
        let a = file("a.txt")
        XCTAssertEqual(manager.completeDrop(claim, urls: [a]), [a])
        XCTAssertTrue(first.items.isEmpty)
        XCTAssertEqual(second.items.map(\.url), [a])
        XCTAssertEqual(manager.completeDrop(claim, urls: [a]), [], "a claim executes at most once")

        let staleClaim = try XCTUnwrap(manager.claimDrop(into: first.id))
        manager.close(first.id)
        let promised = file("late.heic", in: tempRoot.appendingPathComponent("late"))
        XCTAssertEqual(manager.completeDrop(staleClaim, urls: [promised]), [])
        XCTAssertFalse(exists(promised), "late promise result for a closed basket is cleaned up")
    }

    // MARK: Jiggle decisions (Droppy FloatingBasketWindowController.onJiggleDetected)

    func testJiggleDecisionMatrix() throws {
        let manager = makeManager()
        guard case .show(let primary) = manager.resolveJiggle() else { return XCTFail("first jiggle shows a basket") }
        manager.setVisible(primary.id, true)

        guard case .show(let spawned) = manager.resolveJiggle() else { return XCTFail("one visible → spawn") }
        XCTAssertNotEqual(spawned.id, primary.id)
        manager.setVisible(spawned.id, true)

        guard case .switcher(let listed) = manager.resolveJiggle() else { return XCTFail("two visible → switcher") }
        XCTAssertEqual(listed.map(\.id), [primary.id, spawned.id])
        XCTAssertEqual(manager.baskets.count, 2, "switcher never creates a duplicate basket")
    }

    func testJiggleRevealsHiddenBasketsWithItemsBeforeCreating() throws {
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        manager.add([file("a.txt")], to: basket.id)
        manager.setVisible(basket.id, false)
        guard case .reveal(let hidden, _) = manager.resolveJiggle() else { return XCTFail() }
        XCTAssertEqual(hidden.map(\.id), [basket.id])
        XCTAssertEqual(manager.baskets.count, 1)
    }

    func testSingleModeJiggleWithVisibleBasketDoesNothing() throws {
        settings.basketMultipleEnabled = false
        let manager = makeManager()
        let basket = try XCTUnwrap(manager.createBasket())
        manager.setVisible(basket.id, true)
        XCTAssertEqual(manager.resolveJiggle(), .none)
    }

    // MARK: Operations

    func testCompressUsesBackgroundOperationAndReturnsResultToExactBasket() async throws {
        let operations = BackgroundOperationController(liveActivities: LiveActivityStore())
        let manager = makeManager(operations: operations)
        let source = try XCTUnwrap(manager.createBasket())
        let other = try XCTUnwrap(manager.createBasket())
        let a = file("a.txt"), b = file("b.txt")
        manager.add([a, b], to: source.id)

        let id = try XCTUnwrap(manager.compress(Set(source.items.map(\.id)), in: source.id))
        XCTAssertEqual(operations.operation(id)?.sources, [a, b])
        XCTAssertEqual(ledger.owners(of: a), [.basket(source.id), .operation(id)])

        for _ in 0..<200 where operations.operation(id)?.state.isTerminal != true {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let output = try XCTUnwrap(operations.operation(id)?.result?.outputURL)
        XCTAssertEqual(source.items.last?.url, output.standardizedFileURL)
        XCTAssertTrue(other.items.isEmpty)
        XCTAssertEqual(ledger.owners(of: a), [.basket(source.id)], "operation released its hold")
        try? FileManager.default.removeItem(at: output)
    }
}

final class BasketPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let external = CGRect(x: 1512, y: 0, width: 1920, height: 1055)
    private let size = CGSize(width: 248, height: 356)

    func testCentersOnPointer() {
        let frame = BasketPlacement.frame(centeredAt: CGPoint(x: 700, y: 500), size: size, screens: [screen])
        XCTAssertEqual(frame.midX, 700)
        XCTAssertEqual(frame.midY, 500)
    }

    func testNeverSpawnsOffScreen() {
        for pointer in [CGPoint(x: 2, y: 2), CGPoint(x: 1510, y: 940), CGPoint(x: -400, y: 300)] {
            let frame = BasketPlacement.frame(centeredAt: pointer, size: size, screens: [screen])
            XCTAssertTrue(screen.contains(frame), "\(pointer) → \(frame)")
        }
    }

    func testUsesPointerScreenOnMultiDisplay() {
        let frame = BasketPlacement.frame(centeredAt: CGPoint(x: 3420, y: 1050), size: size, screens: [screen, external])
        XCTAssertTrue(external.contains(frame))
    }

    func testRestoresPositionOnlyWhileItsDisplayExists() {
        let origin = CGPoint(x: 2000, y: 300)
        XCTAssertEqual(BasketPlacement.restoredFrame(origin: origin, size: size, screens: [screen, external])?.origin, origin)
        XCTAssertNil(BasketPlacement.restoredFrame(origin: origin, size: size, screens: [screen]), "display removed")
        XCTAssertNil(BasketPlacement.restoredFrame(origin: nil, size: size, screens: [screen]))
    }

    func testResizeKeepsTopCenterAndStaysOnScreen() {
        let current = CGRect(x: 100, y: 500, width: 248, height: 356)
        let grown = BasketPlacement.resized(current, to: CGSize(width: 408, height: 500), screens: [screen])
        XCTAssertEqual(grown.midX, current.midX)
        XCTAssertEqual(grown.maxY, current.maxY)
        let edge = BasketPlacement.resized(CGRect(x: 0, y: 0, width: 248, height: 356), to: CGSize(width: 408, height: 500), screens: [screen])
        XCTAssertTrue(screen.contains(edge))
    }
}

final class BasketAutoHidePolicyTests: XCTestCase {
    private func decide(empty: Bool = false, visible: Bool = true, holds: Set<BasketHold> = [],
                        enabled: Bool = true, dragActive: Bool = false) -> BasketAutoHideDecision {
        BasketAutoHidePolicy.decide(isEmpty: empty, isVisible: visible, holds: holds,
                                    autoHideEnabled: enabled, delay: 2, externalDragActive: dragActive)
    }

    func testIdleBasketWithItemsHidesAfterDelayWhenEnabled() {
        XCTAssertEqual(decide(), .hide(after: 2))
        XCTAssertEqual(decide(enabled: false), .keep)
    }

    func testEmptyBasketClosesEvenWithoutAutoHide() {
        XCTAssertEqual(decide(empty: true, enabled: false), .close)
    }

    func testEveryHoldKeepsTheBasket() {
        for hold in BasketHold.allCases {
            XCTAssertEqual(decide(holds: [hold]), .keep, "\(hold)")
            XCTAssertEqual(decide(empty: true, holds: [hold]), .keep, "\(hold)")
        }
    }

    func testExternalDragKeepsBasketAvailable() {
        XCTAssertEqual(decide(dragActive: true), .keep)
        XCTAssertEqual(decide(empty: true, dragActive: true), .keep)
    }

    func testHiddenBasketIsLeftAlone() {
        XCTAssertEqual(decide(visible: false), .keep)
    }

    @MainActor
    func testHoldsAreOwnerScopedAndHidingKeepsItems() throws {
        let state = BasketState(accent: .teal)
        state.setHold(.nativeMenu, true)
        state.setHold(.pointer, true)
        state.setHold(.pointer, false)
        XCTAssertEqual(state.holds, [.nativeMenu], "releasing one hold never clears another")
        state.setHold(.nativeMenu, false)
        state.setHold(.nativeMenu, false)
        XCTAssertTrue(state.holds.isEmpty)
    }
}
