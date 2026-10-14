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
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(session.isActive)
    }

    func testKeepZoneAddsWithoutOpeningFileActionsConvertOpensThem() throws {
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
        XCTAssertEqual(FileDropZone.allCases.map(\.title), ["Keep in Tray", "Convert", "Share", "Create ZIP"])
        XCTAssertTrue(FileDropZone.convert.detail.contains("originals kept"))
        XCTAssertTrue(FileDropZone.zip.detail.contains("originals kept"))
    }
}
