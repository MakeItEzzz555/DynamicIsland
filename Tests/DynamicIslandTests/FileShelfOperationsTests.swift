import XCTest
@testable import DynamicIsland

final class FileShelfOperationsTests: XCTestCase {
    private var root: URL!
    private var sourceDirectory: URL!
    private var destinationDirectory: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileShelfOperationsTests-\(UUID().uuidString)", isDirectory: true)
        sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        destinationDirectory = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCollisionSafeDestinationNeverOverwrites() throws {
        let source = sourceDirectory.appendingPathComponent("photo.png")
        try Data("source".utf8).write(to: source)
        try Data("occupied".utf8).write(to: destinationDirectory.appendingPathComponent("photo.png"))
        try Data("occupied2".utf8).write(to: destinationDirectory.appendingPathComponent("photo 2.png"))

        XCTAssertEqual(
            FileShelfDiskOperations.collisionSafeDestination(for: source, in: destinationDirectory).lastPathComponent,
            "photo 3.png"
        )
    }

    func testCopyLeavesSourceAndUsesCollisionSafeName() throws {
        let source = sourceDirectory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: source)
        try Data("keep".utf8).write(to: destinationDirectory.appendingPathComponent("notes.txt"))

        let outputs = try FileShelfDiskOperations.copy([source], to: destinationDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(outputs.first?.lastPathComponent, "notes 2.txt")
        XCTAssertEqual(try Data(contentsOf: outputs[0]), Data("hello".utf8))
        XCTAssertEqual(try Data(contentsOf: destinationDirectory.appendingPathComponent("notes.txt")), Data("keep".utf8))
    }

    func testMoveMovesSourceAndReportsOldAndNewURL() throws {
        let source = sourceDirectory.appendingPathComponent("move.txt")
        try Data("move".utf8).write(to: source)

        let pairs = try FileShelfDiskOperations.move([source], to: destinationDirectory)

        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].from, source.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pairs[0].to.path))
    }
}
