import AgentBridgeShared
import XCTest
@testable import DynamicIsland

final class AgentBridgeDiscoveryTests: XCTestCase {
    private var directory: URL!
    private var recordURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland-AgentBridge-\(UUID().uuidString)", isDirectory: true)
        recordURL = directory.appendingPathComponent("bridge-v1.json")
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        recordURL = nil
    }

    func testDefaultPathUsesDynamicIslandApplicationSupportDirectory() throws {
        let publisher = try AgentBridgeDiscoveryPublisher()
        XCTAssertTrue(publisher.recordURL.path.hasSuffix("/DynamicIsland/AgentBridge/bridge-v1.json"))
        XCTAssertFalse(publisher.recordURL.path.hasPrefix("/tmp/"))
    }

    func testPublishCreatesValidRecordWithPrivatePermissions() throws {
        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        let expected = record(launchID: "launch-a")
        try publisher.publish(expected)

        XCTAssertEqual(try decode(), expected)
        let attributes = try FileManager.default.attributesOfItem(atPath: recordURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.uint16Value, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.uint16Value, 0o700)
    }

    func testPublishAtomicallyReplacesExistingRecord() throws {
        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        try publisher.publish(record(launchID: "launch-a"))
        try publisher.publish(record(launchID: "launch-b", port: 54321))

        XCTAssertEqual(try decode().launchID, "launch-b")
        XCTAssertEqual(try decode().port, 54321)
    }

    func testStaleAndMalformedRecordsAreReplacedOnPublish() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: recordURL)
        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        try publisher.publish(record(launchID: "fresh"))

        XCTAssertEqual(try decode().launchID, "fresh")
    }

    func testPublishRejectsSymlinkRecordWithoutTouchingTarget() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let target = directory.appendingPathComponent("target.json")
        let original = Data("do-not-touch".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: recordURL, withDestinationURL: target)

        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        XCTAssertThrowsError(try publisher.publish(record(launchID: "attacker"))) {
            XCTAssertEqual($0 as? AgentBridgeDiscoveryError, .insecurePermissions)
        }
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testShutdownDoesNotReadOrDeleteOversizedUnprovenRecord() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let oversized = Data(
            repeating: 0x41,
            count: AgentBridgeProtocol.maximumDiscoveryBytes + 1
        )
        try oversized.write(to: recordURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: recordURL.path
        )

        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        XCTAssertNoThrow(try publisher.removeIfOwned(launchID: "unknown"))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: recordURL.path)[.size] as? NSNumber,
            NSNumber(value: oversized.count)
        )
    }

    func testOwnedRecordIsRemovedOnCleanShutdown() throws {
        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        try publisher.publish(record(launchID: "owner"))
        try publisher.removeIfOwned(launchID: "owner")
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
    }

    func testOldGenerationCannotRemoveNewerDiscoveryRecord() throws {
        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        try publisher.publish(record(launchID: "new-owner"))
        try publisher.removeIfOwned(launchID: "old-owner")
        XCTAssertEqual(try decode().launchID, "new-owner")
    }

    func testMalformedRecordIsNotDeletedByUnprovenOwner() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("malformed".utf8).write(to: recordURL)
        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        try publisher.removeIfOwned(launchID: "unknown")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordURL.path))
    }

    func testDiscoveryContainsLaunchKeyButNeverInstallationSecret() throws {
        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        try publisher.publish(record(launchID: "launch"))
        let data = try Data(contentsOf: recordURL)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains(AgentBridgeTestSupport.launchKey.base64EncodedString()))
        XCTAssertFalse(text.contains(AgentBridgeTestSupport.secret.base64EncodedString()))
    }

    private func record(launchID: String, port: UInt16 = 12345) -> AgentBridgeDiscoveryRecord {
        AgentBridgeDiscoveryRecord(
            protocolVersion: 1,
            host: "127.0.0.1",
            port: port,
            launchID: launchID,
            producerID: launchID,
            authenticationToken: AgentBridgeTestSupport.launchKey.base64EncodedString(),
            processID: 123,
            createdAt: AgentBridgeTestSupport.now
        )
    }

    private func decode() throws -> AgentBridgeDiscoveryRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentBridgeDiscoveryRecord.self, from: Data(contentsOf: recordURL))
    }
}
