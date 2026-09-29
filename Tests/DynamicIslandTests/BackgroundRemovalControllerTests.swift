import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DynamicIsland

private final class FakeBackgroundProcessor: BackgroundRemovalProcessing, @unchecked Sendable {
    enum Mode {
        case succeed
        case fail(Error)
        case waitForCancellation
    }

    private let lock = NSLock()
    private var _mode: Mode = .succeed
    private var _calls: [URL] = []
    private var _cancelled = false

    var mode: Mode {
        get { lock.withLock { _mode } }
        set { lock.withLock { _mode = newValue } }
    }

    var calls: [URL] { lock.withLock { _calls } }
    var observedCancellation: Bool { lock.withLock { _cancelled } }

    func removeBackground(from imageURL: URL) async throws -> BackgroundRemovalOutput {
        lock.withLock { _calls.append(imageURL) }
        switch mode {
        case .succeed:
            return BackgroundRemovalOutput(pngData: try makePNG(width: 4, height: 3), pixelWidth: 4, pixelHeight: 3)
        case .fail(let error):
            throw error
        case .waitForCancellation:
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            lock.withLock { _cancelled = true }
            throw CancellationError()
        }
    }
}

private func makePNG(width: Int, height: Int) throws -> Data {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "fixture", code: 1)
    }
    return data as Data
}

@MainActor
final class BackgroundRemovalControllerTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackgroundRemovalControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDecodeAcceptsValidImageFixture() throws {
        let url = try writeFixtureImage(named: "photo.png")
        let image = try VisionBackgroundRemovalProcessor.decode(url)
        XCTAssertEqual(image.width, 8)
        XCTAssertEqual(image.height, 6)
    }

    func testDecodeRejectsNonImageFile() throws {
        let url = directory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: url)
        XCTAssertThrowsError(try VisionBackgroundRemovalProcessor.decode(url)) {
            XCTAssertEqual($0 as? BackgroundRemovalError, .unsupportedInput)
        }
    }

    func testDecodeRejectsCorruptImage() throws {
        let url = directory.appendingPathComponent("broken.png")
        try Data("not really a png".utf8).write(to: url)
        XCTAssertThrowsError(try VisionBackgroundRemovalProcessor.decode(url)) {
            XCTAssertEqual($0 as? BackgroundRemovalError, .decodeFailed)
        }
    }

    func testDecodeRejectsMissingFileAndDirectories() {
        XCTAssertThrowsError(try VisionBackgroundRemovalProcessor.decode(directory.appendingPathComponent("missing.png")))
        XCTAssertThrowsError(try VisionBackgroundRemovalProcessor.decode(directory))
    }

    func testProcessingLifecyclePublishesActivityWithoutProgressAndCompletesWithValidOutput() async throws {
        let fixture = makeFixture()
        let source = try writeFixtureImage(named: "photo.png")
        let originalData = try Data(contentsOf: source)

        try fixture.controller.process(imageURL: source)

        let activity = fixture.activities.activities.first
        XCTAssertEqual(activity?.kind, .backgroundRemoval)
        XCTAssertEqual(activity?.lifecycle.authority, .vision)
        XCTAssertNil(activity?.progress)
        XCTAssertTrue(fixture.controller.isProcessing)

        await fixture.controller.waitForCompletion()

        let result = try XCTUnwrap(fixture.controller.result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.previewURL.path))
        XCTAssertEqual(result.pixelWidth, 4)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), originalData)
        XCTAssertNil(fixture.registry.snapshot(for: .backgroundRemoval)?.progress)
    }

    func testFailureStateIsExplicitAndActivityRemoved() async throws {
        let fixture = makeFixture()
        fixture.processor.mode = .fail(BackgroundRemovalError.noForegroundFound)
        let source = try writeFixtureImage(named: "photo.png")

        try fixture.controller.process(imageURL: source)
        await fixture.controller.waitForCompletion()

        XCTAssertEqual(fixture.controller.phase, .failed(BackgroundRemovalError.noForegroundFound.localizedDescription))
        XCTAssertNil(fixture.controller.result)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        guard case .failed = fixture.registry.snapshot(for: .backgroundRemoval)?.health else {
            return XCTFail("Expected failed health")
        }
    }

    func testCancellationStopsWorkAndReturnsToIdle() async throws {
        let fixture = makeFixture()
        fixture.processor.mode = .waitForCancellation
        let source = try writeFixtureImage(named: "photo.png")

        try fixture.controller.process(imageURL: source)
        for _ in 0..<100 where fixture.processor.calls.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        fixture.controller.cancel()
        fixture.controller.cancel()
        for _ in 0..<200 where !fixture.processor.observedCancellation {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertTrue(fixture.processor.observedCancellation)
        XCTAssertEqual(fixture.controller.phase, .idle)
        XCTAssertNil(fixture.controller.result)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testBusyRejectsSecondJob() throws {
        let fixture = makeFixture()
        fixture.processor.mode = .waitForCancellation
        let source = try writeFixtureImage(named: "photo.png")

        try fixture.controller.process(imageURL: source)
        XCTAssertThrowsError(try fixture.controller.process(imageURL: source)) {
            XCTAssertEqual($0 as? BackgroundRemovalError, .busy)
        }
        fixture.controller.cancel()
    }

    func testDestinationNamingAndCollisions() {
        let source = URL(fileURLWithPath: "/tmp/Portrait.jpeg")
        let directory = URL(fileURLWithPath: "/tmp/out")
        var existing: Set<String> = []

        let first = BackgroundRemovalController.availableDestination(for: source, in: directory) { existing.contains($0.path) }
        XCTAssertEqual(first.lastPathComponent, "Portrait (background removed).png")

        existing.insert(first.path)
        let second = BackgroundRemovalController.availableDestination(for: source, in: directory) { existing.contains($0.path) }
        XCTAssertEqual(second.lastPathComponent, "Portrait (background removed) 2.png")
    }

    func testExportWritesCollisionSafeFileAndPreservesOriginal() async throws {
        let fixture = makeFixture()
        let source = try writeFixtureImage(named: "photo.png")
        let originalData = try Data(contentsOf: source)
        try fixture.controller.process(imageURL: source)
        await fixture.controller.waitForCompletion()

        let first = try fixture.controller.export()
        let second = try fixture.controller.export()

        XCTAssertEqual(first.lastPathComponent, "photo (background removed).png")
        XCTAssertEqual(second.lastPathComponent, "photo (background removed) 2.png")
        XCTAssertNotNil(try VisionBackgroundRemovalProcessor.decode(first))
        XCTAssertEqual(try Data(contentsOf: source), originalData)
        XCTAssertEqual(fixture.controller.lastExportURL, second)
    }

    func testExportFailureIsReported() async throws {
        let fixture = makeFixture()
        let source = try writeFixtureImage(named: "photo.png")
        try fixture.controller.process(imageURL: source)
        await fixture.controller.waitForCompletion()

        let missingDirectory = directory.appendingPathComponent("does/not/exist", isDirectory: true)
        XCTAssertThrowsError(try fixture.controller.export(toDirectory: missingDirectory)) {
            guard case .exportFailed = $0 as? BackgroundRemovalError else {
                return XCTFail("Expected export failure, got \($0)")
            }
        }
    }

    func testShelfHandoffUsesShelfOwnedCopy() async throws {
        let fixture = makeFixture()
        let source = try writeFixtureImage(named: "photo.png")
        try fixture.controller.process(imageURL: source)
        await fixture.controller.waitForCompletion()

        let shelfURL = try fixture.controller.addResultToShelf()

        XCTAssertEqual(fixture.shelf.urls, [shelfURL])
        XCTAssertTrue(fixture.shelfStorage.isOwned(shelfURL))
        XCTAssertTrue(shelfURL.lastPathComponent.hasSuffix("photo (background removed).png"))
    }

    func testOutputsRequireResult() {
        let fixture = makeFixture()
        XCTAssertThrowsError(try fixture.controller.export())
        XCTAssertThrowsError(try fixture.controller.addResultToShelf())
    }

    func testDisableCancelsAndDiscardsPreview() async throws {
        let fixture = makeFixture()
        let source = try writeFixtureImage(named: "photo.png")
        try fixture.controller.process(imageURL: source)
        await fixture.controller.waitForCompletion()
        let previewURL = try XCTUnwrap(fixture.controller.result?.previewURL)

        fixture.controller.setEnabled(false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertNil(fixture.controller.result)
        XCTAssertThrowsError(try fixture.controller.process(imageURL: source)) {
            XCTAssertEqual($0 as? BackgroundRemovalError, .disabled)
        }
    }

    // MARK: Fixture

    private final class ShelfSink {
        var urls: [URL] = []
    }

    private struct Fixture {
        let controller: BackgroundRemovalController
        let processor: FakeBackgroundProcessor
        let activities: LiveActivityStore
        let registry: IslandCapabilityRegistry
        let shelf: ShelfSink
        let shelfStorage: FileShelfTemporaryStorage
    }

    private func makeFixture() -> Fixture {
        let processor = FakeBackgroundProcessor()
        let activities = LiveActivityStore()
        let registry = IslandCapabilityRegistry()
        let shelf = ShelfSink()
        let shelfStorage = FileShelfTemporaryStorage(
            rootURL: directory.appendingPathComponent("Shelf", isDirectory: true),
            providerTemporaryRootURL: directory.appendingPathComponent("Provider", isDirectory: true)
        )
        let controller = BackgroundRemovalController(
            liveActivities: activities,
            capabilities: registry,
            processor: processor,
            shelfStorage: shelfStorage,
            addToShelf: { shelf.urls.append(contentsOf: $0) },
            workingDirectory: directory.appendingPathComponent("Work", isDirectory: true),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        return Fixture(
            controller: controller,
            processor: processor,
            activities: activities,
            registry: registry,
            shelf: shelf,
            shelfStorage: shelfStorage
        )
    }

    private func writeFixtureImage(named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try makePNG(width: 8, height: 6).write(to: url)
        return url
    }
}
