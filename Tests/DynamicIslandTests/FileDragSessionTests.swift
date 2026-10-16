import AppKit
import Combine
import XCTest
@testable import DynamicIsland

@MainActor
final class FileDragSessionTests: XCTestCase {
    func testSessionStartsTargetsAndEndsAfterAllRegionsLeave() async throws {
        let controller = FileDragSessionController(exitGraceNanoseconds: 20_000_000)

        controller.setSourceTargeted(true)
        XCTAssertTrue(controller.isActive)
        let generation = controller.generation

        controller.setActionTargeted(.airDrop, true)
        XCTAssertEqual(controller.targetedAction, .airDrop)
        controller.setSourceTargeted(false)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(controller.isActive, "action target owns the drag after the shell region exits")

        await expectSessionEnd(controller) {
            controller.setActionTargeted(.airDrop, false)
        }
        XCTAssertGreaterThan(controller.generation, generation)
    }

    func testBridgeKeepsSessionAliveAcrossButtonGaps() async throws {
        let controller = FileDragSessionController(exitGraceNanoseconds: 20_000_000)
        controller.setSourceTargeted(true)
        controller.setSourceTargeted(false)
        controller.setBridgeTargeted(true)

        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertTrue(controller.isActive)

        await expectSessionEnd(controller) {
            controller.setBridgeTargeted(false)
        }
    }

    func testExactlyOneDropMayBeClaimedPerGeneration() {
        let controller = FileDragSessionController()
        controller.setSourceTargeted(true)

        let first = controller.claimDrop(.messages)
        XCTAssertNotNil(first)
        XCTAssertNil(controller.claimDrop(.mail))
        XCTAssertEqual(controller.phase, .materializing(.messages))
    }

    func testStaleMaterializationCannotExecuteForNewerDrag() {
        let controller = FileDragSessionController()
        controller.setSourceTargeted(true)
        let stale = try! XCTUnwrap(controller.claimDrop(.messages))
        controller.cancel()
        controller.setSourceTargeted(true)

        var received: [URL] = []
        let executor = FileDragActionExecutor { _, urls, _ in
            received = urls
            return .handedOff
        }
        let url = URL(fileURLWithPath: "/tmp/stale.txt")
        let outcome = controller.completeDrop(
            claim: stale,
            action: .messages,
            urls: [url],
            anchor: nil,
            executor: executor
        )

        XCTAssertNil(outcome)
        XCTAssertTrue(received.isEmpty)
        XCTAssertTrue(controller.isActive)
    }

    func testExecutorReceivesExactExternalPayloadNotShelfSelection() throws {
        let controller = FileDragSessionController()
        controller.setSourceTargeted(true)
        let claim = try XCTUnwrap(controller.claimDrop(.mail))
        let dragged = [
            URL(fileURLWithPath: "/tmp/drag-a.txt"),
            URL(fileURLWithPath: "/tmp/drag-b.txt")
        ]
        let unrelatedShelf = URL(fileURLWithPath: "/tmp/shelf-only.txt")
        var executedAction: FileDragQuickAction?
        var executedURLs: [URL] = [unrelatedShelf]
        let executor = FileDragActionExecutor { action, urls, _ in
            executedAction = action
            executedURLs = urls
            return .handedOff
        }

        let outcome = controller.completeDrop(
            claim: claim,
            action: .mail,
            urls: dragged,
            anchor: nil,
            executor: executor
        )

        XCTAssertEqual(outcome, .handedOff)
        XCTAssertEqual(executedAction, .mail)
        XCTAssertEqual(executedURLs, dragged)
        XCTAssertFalse(executedURLs.contains(unrelatedShelf))
    }

    func testEmptyMaterializationPreservesFailureForUserFeedback() throws {
        let controller = FileDragSessionController()
        controller.setSourceTargeted(true)
        let claim = try XCTUnwrap(controller.claimDrop(.messages))

        let outcome = controller.completeDrop(
            claim: claim,
            action: .messages,
            urls: [],
            anchor: nil,
            executor: FileDragActionExecutor { _, _, _ in
                XCTFail("An empty materialization must never execute the system action")
                return .handedOff
            }
        )

        XCTAssertEqual(outcome, .failed("No files were materialized"))
        XCTAssertEqual(controller.lastOutcome, .failed("No files were materialized"))
        XCTAssertEqual(controller.outcomeMessage, "No files were materialized")
        XCTAssertFalse(controller.isActive)
    }

    func testFailureDoesNotClaimSuccess() throws {
        let controller = FileDragSessionController()
        controller.setSourceTargeted(true)
        let claim = try XCTUnwrap(controller.claimDrop(.airDrop))
        let executor = FileDragActionExecutor { _, _, _ in .unavailable("No service") }

        XCTAssertEqual(
            controller.completeDrop(
                claim: claim,
                action: .airDrop,
                urls: [URL(fileURLWithPath: "/tmp/a.txt")],
                anchor: nil,
                executor: executor
            ),
            .unavailable("No service")
        )
        XCTAssertEqual(controller.lastOutcome, .unavailable("No service"))
        XCTAssertEqual(controller.outcomeMessage, "No service")
    }

    func testQuickActionOrderingMatchesSourceBackedOrbitAndNoQuicksharePlaceholder() {
        XCTAssertEqual(FileDragQuickAction.shareActions, [.airDrop, .messages, .mail, .share])
        XCTAssertEqual(FileDragQuickAction.allCases, [.airDrop, .messages, .mail, .share, .addToBasket, .compress])
    }

    private func entry(_ available: Bool, _ ran: @escaping ([URL]) -> Void) -> FileDragLocalActions.Entry {
        .init(isAvailable: { available }, run: { ran($0); return .handedOff })
    }

    func testUnavailableLocalServicesHideTheirTargets() {
        XCTAssertEqual(FileDragQuickAction.orbitActions(local: .none), FileDragQuickAction.shareActions)
        let basketOnly = FileDragLocalActions(addToBasket: entry(true) { _ in })
        XCTAssertEqual(FileDragQuickAction.orbitActions(local: basketOnly), FileDragQuickAction.shareActions + [.addToBasket])
        let disabled = FileDragLocalActions(addToBasket: entry(false) { _ in }, compress: entry(true) { _ in })
        XCTAssertEqual(FileDragQuickAction.orbitActions(local: disabled), FileDragQuickAction.shareActions + [.compress])
    }

    func testOneDropRunsExactlyOneLocalActionAndNothingElse() throws {
        var basketRuns: [[URL]] = [], zipRuns: [[URL]] = []
        let controller = FileDragSessionController()
        controller.localActions = FileDragLocalActions(
            addToBasket: entry(true) { basketRuns.append($0) },
            compress: entry(true) { zipRuns.append($0) })
        XCTAssertEqual(controller.orbitActions.suffix(2), [.addToBasket, .compress])
        let urls = [URL(fileURLWithPath: "/tmp/drag-a.txt")]
        for action in [FileDragQuickAction.addToBasket, .compress] {
            controller.setSourceTargeted(true)
            let claim = try XCTUnwrap(controller.claimDrop(action))
            XCTAssertNil(controller.claimDrop(.share), "second claim in one drop is rejected")
            XCTAssertEqual(controller.completeDrop(claim: claim, action: action, urls: urls, anchor: nil), .handedOff)
            XCTAssertNil(controller.completeDrop(claim: claim, action: action, urls: urls, anchor: nil), "claim is one-shot")
        }
        XCTAssertEqual(basketRuns, [urls])
        XCTAssertEqual(zipRuns, [urls])
    }

    func testLocalActionWithoutExecutableServiceIsUnavailableNotRun() throws {
        let controller = FileDragSessionController()
        controller.localActions = FileDragLocalActions(compress: entry(false) { _ in XCTFail("must not run") })
        controller.setSourceTargeted(true)
        let claim = try XCTUnwrap(controller.claimDrop(.compress))
        let outcome = controller.completeDrop(claim: claim, action: .compress,
                                              urls: [URL(fileURLWithPath: "/tmp/a.txt")], anchor: nil)
        XCTAssertEqual(outcome, .unavailable("Compress is unavailable"))
    }

    func testNativePasteboardNSURLMaterializesAsDirectFileURL() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("FileDragSessionTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("drag-\(UUID().uuidString).txt")
        try Data("drag".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(pasteboard.writeObjects([url as NSURL]))

        XCTAssertEqual(FilePromiseDropNSView.directFileURLs(from: pasteboard), [url.standardizedFileURL])
    }

    func testPromiseStorageOwnsOnlyItsMaterializedFilesAndCleansThem() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileDragPromiseStorageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = FileDragPromiseStorage(rootURL: root)
        let directory = try storage.makeDropDirectory()
        let promised = directory.appendingPathComponent("photo.heic")
        try Data("image".utf8).write(to: promised)
        let external = FileManager.default.temporaryDirectory.appendingPathComponent("external.txt")

        XCTAssertTrue(storage.isOwned(promised))
        XCTAssertFalse(storage.isOwned(external))
        storage.removeIfOwned([promised, external], ownership: TemporaryFileOwnershipLedger(temporaryRoots: [root]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }


    func testMultipleSourceRegionsDoNotCancelEachOther() async throws {
        let controller = FileDragSessionController(exitGraceNanoseconds: 20_000_000)
        controller.setSourceTargeted(true, region: .trayShelf)
        controller.setSourceTargeted(true, region: .trayAirDrop)
        controller.setSourceTargeted(false, region: .trayShelf)
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertTrue(controller.isActive)

        await expectSessionEnd(controller) {
            controller.setSourceTargeted(false, region: .trayAirDrop)
        }
    }

    private func expectSessionEnd(_ controller: FileDragSessionController, releaseFinalOwner: () -> Void) async {
        let ended = expectation(description: "Unowned drag reaches idle after its exit task finishes")
        let observation = controller.$phase
            .dropFirst()
            .first(where: { $0 == .idle })
            .sink { _ in ended.fulfill() }
        defer { observation.cancel() }
        releaseFinalOwner()
        await fulfillment(of: [ended], timeout: 1)
        XCTAssertFalse(controller.isActive)
    }


    func testFourDestinationsNeedNoExternalOrbitReservation() {
        XCTAssertEqual(FileDropZone.allCases.count, 4)
        XCTAssertEqual(ExpandedPresentationProfile.resolve(for: .tray).accessoryHeight, 0)
    }

    func testMaterializationFailureResetsEvenAfterPointerLeavesTarget() throws {
        let controller = FileDragSessionController()
        controller.setSourceTargeted(true)
        controller.setActionTargeted(.messages, true)
        let claim = try XCTUnwrap(controller.claimDrop(.messages))
        controller.setActionTargeted(.messages, false)

        controller.materializationFailed(claim: claim, message: "Promise failed")

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.lastOutcome, .failed("Promise failed"))
    }

}
