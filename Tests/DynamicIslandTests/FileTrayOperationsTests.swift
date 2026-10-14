import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DynamicIsland

/// File Tray operations against real temporary files: originals are never
/// changed, outputs are new and collision-safe, and they join the Tray.
@MainActor
final class FileTrayOperationsTests: XCTestCase {
    private var directory: URL!
    private var settings: AppSettings!
    private var shelf: FileShelfStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("tray-ops-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settings = AppSettings(defaults: SettingsPreviewDefaults())
        shelf = FileShelfStore(settings: settings, defaults: SettingsPreviewDefaults(), ownership: TemporaryFileOwnershipLedger(temporaryRoots: []))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makePNG(_ name: String, text: String? = nil) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let size = NSSize(width: 360, height: 120)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            if let text {
                (text as NSString).draw(at: NSPoint(x: 16, y: 36), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor.black,
                ])
            }
            return true
        }
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func settled(timeout: TimeInterval = 20) async throws -> FileTrayOperationStatus {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = shelf.operationStatus, case .working = status {} else if let status = shelf.operationStatus { return status }
            try await Task.sleep(for: .milliseconds(20))
        }
        struct NotSettled: Error {}
        XCTFail("operation did not settle: \(String(describing: shelf.operationStatus))")
        throw NotSettled()
    }

    func testConvertKeepsOriginalAddsSelectedOutputAndReportsSuccess() async throws {
        let png = try makePNG("photo.png")
        let original = try Data(contentsOf: png)
        shelf.add([png])
        shelf.convertImages([png], to: .jpeg)
        guard case .succeeded = try await settled() else { return XCTFail("\(String(describing: shelf.operationStatus))") }
        let output = directory.appendingPathComponent("photo.jpg").standardizedFileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: png), original, "Original must be untouched")
        XCTAssertEqual(shelf.files, [png.standardizedFileURL, output])
        XCTAssertEqual(shelf.selection, [output])
    }

    func testPartialBatchFailureReportsExactCountsAndPreservesEverything() async throws {
        let good = try makePNG("good.png")
        let bad = directory.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: bad)
        shelf.add([good, bad])
        shelf.convertImages([good, bad], to: .jpeg)
        guard case .failed(let message) = try await settled() else { return XCTFail("partial failure must not report success") }
        XCTAssertTrue(message.contains("Added 1; 1 failed"), message)
        XCTAssertEqual(try Data(contentsOf: bad), Data("not an image".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("good.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("broken.jpg").path))
    }

    func testDuplicateNamesNeverOverwrite() async throws {
        let png = try makePNG("dup.png")
        try Data("existing".utf8).write(to: directory.appendingPathComponent("dup.jpg"))
        shelf.add([png])
        shelf.convertImages([png], to: .jpeg)
        guard case .succeeded = try await settled() else { return XCTFail() }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("dup.jpg")), Data("existing".utf8))
        XCTAssertTrue(shelf.files.contains(directory.appendingPathComponent("dup 2.jpg").standardizedFileURL))
    }

    func testFolderWithCopiesKeepsOriginalsAndIsCollisionSafe() throws {
        let a = directory.appendingPathComponent("a.txt"); try Data("A".utf8).write(to: a)
        let b = directory.appendingPathComponent("b.txt"); try Data("B".utf8).write(to: b)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("New Folder"), withIntermediateDirectories: false)
        let folder = try FileShelfStore.createFolder(withCopiesOf: [a, b], in: directory)
        XCTAssertEqual(folder.lastPathComponent, "New Folder 2")
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["a.txt", "b.txt"])
        XCTAssertEqual(try Data(contentsOf: a), Data("A".utf8))
        XCTAssertEqual(try Data(contentsOf: b), Data("B".utf8))
    }

    func testFolderFailureRemovesOnlyItsOwnFolderAndLeavesSourcesIntact() throws {
        let a = directory.appendingPathComponent("a.txt"); try Data("A".utf8).write(to: a)
        let missing = directory.appendingPathComponent("gone.txt")
        XCTAssertThrowsError(try FileShelfStore.createFolder(withCopiesOf: [a, missing], in: directory))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["a.txt"])
        XCTAssertEqual(try Data(contentsOf: a), Data("A".utf8))
    }

    func testFolderInUnwritableLocationFailsWithoutSideEffects() throws {
        let locked = directory.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        let a = locked.appendingPathComponent("a.txt"); try Data("A".utf8).write(to: a)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertThrowsError(try FileShelfStore.createFolder(withCopiesOf: [a], in: locked))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: locked.path), ["a.txt"])
    }

    func testZIPJoinsTheTrayOnlyAfterTheArchiveExists() async throws {
        let a = directory.appendingPathComponent("notes.txt"); try Data("hello".utf8).write(to: a)
        shelf.add([a])
        let operations = BackgroundOperationController(liveActivities: LiveActivityStore())
        shelf.createZIP([a], using: operations)
        guard case .working = try XCTUnwrap(shelf.operationStatus) else { return XCTFail("must not claim success before the archive exists") }
        guard case .succeeded = try await settled(timeout: 30) else { return XCTFail("\(String(describing: shelf.operationStatus))") }
        let zip = try XCTUnwrap(shelf.files.first { $0.pathExtension == "zip" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
        XCTAssertTrue(shelf.files.contains(a.standardizedFileURL), "source stays in the Tray")
        XCTAssertEqual(try Data(contentsOf: a), Data("hello".utf8))
        XCTAssertEqual(shelf.selection, [zip])
    }

    func testZIPFailureLeavesNoWorkingStatusOrFabricatedOutput() async throws {
        let missing = directory.appendingPathComponent("missing.txt")
        let operations = BackgroundOperationController(liveActivities: LiveActivityStore())
        shelf.createZIP([missing], using: operations)
        guard case .failed(let message) = try await settled() else { return XCTFail("must report the failed archive") }
        XCTAssertTrue(message.contains("ZIP not created"))
        XCTAssertTrue(shelf.files.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testFullTrayIsReportedInsteadOfClaimingTheOutputWasAdded() async throws {
        settings.maxShelfFiles = 1
        let png = try makePNG("full.png")
        shelf.add([png])
        shelf.convertImages([png], to: .jpeg)
        guard case .failed(let message) = try await settled() else { return XCTFail() }
        XCTAssertTrue(message.contains("Tray is full"), message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("full.jpg").path))
    }

    func testUnsupportedConversionIsRefusedWithoutWriting() {
        let text = directory.appendingPathComponent("readme.txt")
        try? Data("x".utf8).write(to: text)
        shelf.convertImages([text], to: .png)
        guard case .failed = shelf.operationStatus else { return XCTFail() }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["readme.txt"])
    }

    func testOnDeviceTextRecognitionReadsRenderedText() throws {
        let image = try makePNG("text.png", text: "TRAY 42")
        let text = try FileShelfStore.recognizedText(in: image)
        XCTAssertTrue(text.uppercased().contains("TRAY"), "recognized: \(text)")
    }
}
