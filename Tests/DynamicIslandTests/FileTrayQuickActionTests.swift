import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DynamicIsland

final class FileTrayQuickActionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTrayQuickActionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Targets

    func testTargetsUseExplicitSelectionOrSingleFileOnly() {
        let a = URL(fileURLWithPath: "/tmp/a.png")
        let b = URL(fileURLWithPath: "/tmp/b.png")

        XCTAssertEqual(FileTrayActionTargets.resolve(files: [a], selection: []).urls, [a])
        XCTAssertEqual(FileTrayActionTargets.resolve(files: [a, b], selection: []).urls, [])
        XCTAssertEqual(FileTrayActionTargets.resolve(files: [a, b], selection: [b]).urls, [b])
        // Order follows the Tray, not the selection set.
        XCTAssertEqual(FileTrayActionTargets.resolve(files: [a, b], selection: [b, a]).urls, [a, b])
        // Stale selection for a removed file is ignored.
        XCTAssertEqual(FileTrayActionTargets.resolve(files: [a, b], selection: [URL(fileURLWithPath: "/tmp/gone.png")]).urls, [])
    }

    func testAvailabilityIsTruthfulPerAction() throws {
        let image = try makePNG(named: "photo.png")
        let text = directory.appendingPathComponent("notes.txt")
        try Data("hi".utf8).write(to: text)

        let none = FileTrayActionTargets(urls: [])
        XCTAssertFalse(none.availability(of: .removeBackground).isAvailable)
        XCTAssertFalse(none.availability(of: .convert).isAvailable)
        XCTAssertFalse(none.availability(of: .share).isAvailable)

        let single = FileTrayActionTargets(urls: [image])
        XCTAssertTrue(single.availability(of: .removeBackground).isAvailable)
        XCTAssertTrue(single.availability(of: .convert).isAvailable)
        XCTAssertTrue(single.availability(of: .share).isAvailable)

        let nonImage = FileTrayActionTargets(urls: [text])
        XCTAssertFalse(nonImage.availability(of: .removeBackground).isAvailable)
        XCTAssertFalse(nonImage.availability(of: .convert).isAvailable)
        XCTAssertTrue(nonImage.availability(of: .share).isAvailable)

        let multiple = FileTrayActionTargets(urls: [image, text])
        XCTAssertFalse(multiple.availability(of: .removeBackground).isAvailable)
        XCTAssertFalse(multiple.availability(of: .convert).isAvailable)
        XCTAssertTrue(multiple.availability(of: .share).isAvailable)
    }

    func testActionOrderIsRemoveBackgroundConvertShare() {
        XCTAssertEqual(FileTrayQuickAction.allCases, [.removeBackground, .convert, .share])
    }

    // MARK: Selection

    @MainActor
    func testShelfSelectionTogglesExtendsAndPrunesOnRemoval() throws {
        let suite = "FileTrayQuickActionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.persistFileShelfAcrossLaunches = false
        let store = FileShelfStore(settings: settings, defaults: defaults)
        let a = try makePNG(named: "a.png")
        let b = try makePNG(named: "b.png")
        store.add([a, b])
        let files = store.files

        store.select(files[0])
        XCTAssertEqual(store.selection, [files[0]])
        store.select(files[1], extend: true)
        XCTAssertEqual(store.selection, Set(files))
        XCTAssertEqual(store.quickActionTargets.urls, files)
        store.select(files[1], extend: true)
        XCTAssertEqual(store.selection, [files[0]])
        store.select(files[0])
        XCTAssertEqual(store.selection, [])

        store.select(files[1])
        store.remove(files[1])
        XCTAssertEqual(store.selection, [])
        // One file left and nothing selected: it is the implicit target.
        XCTAssertEqual(store.quickActionTargets.urls, [files[0]])
    }

    // MARK: Conversion

    func testOutputURLIsCollisionSafeAndNeverTheSource() {
        let source = URL(fileURLWithPath: "/tmp/x/photo.png")
        var existing: Set<String> = ["/tmp/x/photo.jpg", "/tmp/x/photo 2.jpg"]
        XCTAssertEqual(
            FileConversionController.outputURL(for: source, format: .jpeg) { existing.contains($0.path) }.path,
            "/tmp/x/photo 3.jpg"
        )
        existing = []
        XCTAssertEqual(
            FileConversionController.outputURL(for: source, format: .png) { existing.contains($0.path) }.path,
            "/tmp/x/photo 2.png"
        )
    }

    func testTargetFormatsExcludeCurrentFormatAndNonImages() throws {
        let png = try makePNG(named: "p.png")
        let formats = FileConversionController.targetFormats(for: png)
        XCTAssertFalse(formats.contains(.png))
        XCTAssertTrue(formats.contains(.jpeg))
        XCTAssertTrue(Set(formats).isSubset(of: Set(FileConversionController.availableFormats)))

        let text = directory.appendingPathComponent("n.txt")
        try Data("x".utf8).write(to: text)
        XCTAssertEqual(FileConversionController.targetFormats(for: text), [])
    }

    func testConvertWritesValidNewFileAndLeavesOriginalUntouched() async throws {
        let png = try makePNG(named: "shot.png")
        let originalData = try Data(contentsOf: png)
        // Occupy the obvious name to prove no overwrite.
        let occupied = directory.appendingPathComponent("shot.jpg")
        try Data("keep".utf8).write(to: occupied)

        let output = try await FileConversionController.convert(png, to: .jpeg)

        XCTAssertEqual(output.lastPathComponent, "shot 2.jpg")
        XCTAssertEqual(try Data(contentsOf: png), originalData)
        XCTAssertEqual(try Data(contentsOf: occupied), Data("keep".utf8))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testUnsupportedConversionFailsWithoutWriting() async throws {
        let png = try makePNG(named: "same.png")
        do {
            _ = try await FileConversionController.convert(png, to: .png)
            XCTFail("Converting to the same format must be rejected")
        } catch let error as FileConversionError {
            XCTAssertEqual(error, .unsupported)
        }
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(contents, ["same.png"])
    }

    // MARK: Hover geometry

    func testAccessoryRegionKeepsExpandedAndBridgesGapWithoutClaimingSides() {
        let shell = CGRect(x: 0, y: 56, width: 860, height: 286)
        let circles = CGRect(x: 367, y: 12, width: 128, height: 36)

        func decide(_ point: CGPoint) -> ExpandedHoverContainment.Decision {
            ExpandedHoverContainment.decide(pointer: point, shellFrame: shell, accessoryFrames: [circles], holds: [])
        }

        XCTAssertEqual(decide(CGPoint(x: 430, y: 30)), .keepExpanded)   // on a circle
        XCTAssertEqual(decide(CGPoint(x: 430, y: 52)), .keepExpanded)   // gap between shell and circles
        XCTAssertEqual(decide(CGPoint(x: 100, y: 30)), .collapse)       // beside circles
        XCTAssertEqual(decide(CGPoint(x: 430, y: 2)), .collapse)        // below circles
        XCTAssertEqual(
            ExpandedHoverContainment.decide(pointer: CGPoint(x: 430, y: 30), shellFrame: shell, holds: []),
            .collapse,
            "Without accessories the area below the shell is not claimed"
        )
    }

    // MARK: Helpers

    private func makePNG(named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
