import AppKit
import XCTest
@testable import DynamicIsland

/// The four Tray drop zones ride on the existing shelf drop transaction.
@MainActor
final class FileDropZoneTests: XCTestCase {
    func testZoneRegionKeepsTheSessionWhileTheShelfTargetUnderneathLeaves() async throws {
        let session = FileDragSessionController(exitGraceNanoseconds: 20_000_000)
        session.setSourceTargeted(true, region: .trayShelf)
        // Pointer moves onto a zone: the zone claims before the shelf target clears.
        session.setSourceTargeted(true, region: .trayDropZone)
        session.setSourceTargeted(false, region: .trayShelf)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(session.isActive, "moving onto a zone must not end the drag")
        session.setSourceTargeted(false, region: .trayDropZone)
        // The grace Task needs the main actor after its sleep; a loaded CI host
        // can delay that hop past any fixed sleep, so wait for the outcome.
        let deadline = ContinuousClock.now + .seconds(2)
        while session.isActive, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(session.isActive)
    }

    func testKeepAddsWithoutOpeningFileActionsAndContextConversionStillCan() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        let shelf = FileShelfStore(settings: settings, defaults: SettingsPreviewDefaults(), ownership: TemporaryFileOwnershipLedger(temporaryRoots: []))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("zone-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let session = FileDragSessionController()

        let keep = try XCTUnwrap(session.claimShelfDrop())
        XCTAssertEqual(session.completeShelfDrop(keep, urls: [file], shelf: shelf, allowed: true, requestActions: false),
                       [file.standardizedFileURL])
        XCTAssertNil(shelf.fileActionRequest, "Keep must not open the File Actions panel")

        let convert = try XCTUnwrap(session.claimShelfDrop())
        _ = session.completeShelfDrop(convert, urls: [file], shelf: shelf, allowed: true)
        XCTAssertEqual(shelf.fileActionRequest?.urls, [file.standardizedFileURL])
    }

    func testOnlyOneZoneCanClaimADropAndAStaleClaimAddsNothing() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        let shelf = FileShelfStore(settings: settings, defaults: SettingsPreviewDefaults(), ownership: TemporaryFileOwnershipLedger(temporaryRoots: []))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("zone-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let session = FileDragSessionController()
        let claim = try XCTUnwrap(session.claimShelfDrop())
        XCTAssertNil(session.claimShelfDrop(), "a second zone cannot claim the same drop")
        session.cancel()
        XCTAssertNil(session.completeShelfDrop(claim, urls: [file], shelf: shelf, allowed: true, requestActions: false))
        XCTAssertTrue(shelf.files.isEmpty)
    }

    func testZonesHaveDistinctLabelsAndOriginalsAreDescribedAsKept() {
        XCTAssertEqual(FileDropZone.allCases.map(\.title), ["Keep in Tray", "Messages", "Share", "Create ZIP"])
        XCTAssertTrue(FileDropZone.messages.detail.contains("you choose Send"))
        XCTAssertTrue(FileDropZone.zip.detail.contains("originals kept"))
    }
    func testOnlyAcceptedFilesReachMessagesAndPartialAcceptanceIsVisible() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults()); settings.maxShelfFiles = 1
        let shelf = FileShelfStore(settings: settings, defaults: SettingsPreviewDefaults(), ownership: TemporaryFileOwnershipLedger(temporaryRoots: []))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [root.appendingPathComponent("a.txt"), root.appendingPathComponent("b.txt")]
        for file in files { try Data("fixture".utf8).write(to: file) }
        let session = FileDragSessionController()
        let claim = try XCTUnwrap(session.claimShelfDrop())
        let accepted = try XCTUnwrap(session.completeShelfDrop(claim, urls: files, shelf: shelf, allowed: true, requestActions: false))
        var calls = 0
        let executor = FileDragActionExecutor { action, urls, _ in
            calls += 1; XCTAssertEqual(action, .messages); XCTAssertEqual(urls, accepted)
            return .handedOff
        }
        shelf.performDropZone(.messages, accepted: accepted, attemptedCount: 2,
            operations: BackgroundOperationController(liveActivities: LiveActivityStore()), executor: executor, anchor: nil, layoutStore: IslandLayoutStore())
        XCTAssertEqual(calls, 1); XCTAssertEqual(shelf.selection, Set(accepted)); XCTAssertEqual(accepted.count, 1)
        XCTAssertTrue(shelf.operationStatus?.message.contains("1 of 2") == true)
        XCTAssertTrue(shelf.operationStatus?.message.contains("nothing has been sent") == true)
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path)) }
        XCTAssertNil(shelf.fileActionRequest)
    }

    func testSharingOwnsOnlyItsHoldAndDismissalIsIdempotent() {
        let layout = IslandLayoutStore(); layout.setTransientInteraction(true, owner: .nativeMenu)
        let session = NativeFileSharingSession(layoutStore: layout, anchor: nil)
        XCTAssertTrue(layout.transientInteractionOwners.contains(.fileSharing(session.id)))
        session.sharingServicePicker(NSSharingServicePicker(items: []), didChoose: nil)
        session.cancel(); session.finish()
        XCTAssertTrue(session.finished)
        XCTAssertEqual(layout.transientInteractionOwners, [.nativeMenu])
    }

    func testInvalidOrUnownedShareAnchorFailsWithoutAcquiringAHold() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let layout = IslandLayoutStore()
        guard case .failed = FileDragActionExecutor.production.perform(.share, urls: [file], anchor: NSView(), layoutStore: layout) else { return XCTFail() }
        XCTAssertTrue(layout.transientInteractionOwners.isEmpty)
    }

}
