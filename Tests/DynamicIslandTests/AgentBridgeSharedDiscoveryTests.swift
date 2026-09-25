import Darwin
import Foundation
import XCTest
@testable import AgentBridgeShared

final class AgentBridgeSharedDiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testDefaultPathIsApplicationSupportBridgeV1Record() throws {
        let reader = try AgentBridgeDiscoveryReader(now: { Date(timeIntervalSince1970: 2_000_000_000) })
        XCTAssertTrue(reader.recordURL.path.hasSuffix("/Library/Application Support/DynamicIsland/AgentBridge/bridge-v1.json"))
    }

    func testValidPrivateRecordProducesLoopbackProfile() async throws {
        let reader = try makeReader(snapshot: snapshot())
        let profile = try await reader.loadProfile()
        XCTAssertEqual(profile.host, "127.0.0.1")
        XCTAssertEqual(profile.port, 49_321)
        XCTAssertEqual(profile.producerID, "producer-1")
        XCTAssertEqual(profile.authenticationKey, Data(repeating: 0x24, count: 32))
    }

    func testRejectsSymlinkWrongOwnerAndUnsafePermissions() async throws {
        for expected in [
            snapshot(isSymbolicLink: true),
            snapshot(isRegularFile: false),
            snapshot(ownerID: geteuid() &+ 1),
            snapshot(permissions: 0o644)
        ] {
            let reader = try makeReader(snapshot: expected)
            do {
                _ = try await reader.loadProfile()
                XCTFail("Expected discovery rejection")
            } catch {
                XCTAssertTrue(error is AgentBridgeDiscoveryReadError)
            }
        }
    }

    func testRejectsNonLoopbackUnknownProtocolInvalidPortAndMalformedKey() async throws {
        let records = [
            record(host: "localhost"),
            record(protocolVersion: 2),
            record(port: 0),
            record(authenticationToken: Data(repeating: 1, count: 31).base64EncodedString())
        ]
        for record in records {
            let reader = try makeReader(snapshot: snapshot(data: encode(record)))
            await XCTAssertThrowsErrorAsync { _ = try await reader.loadProfile() }
        }
    }

    func testSystemReaderRejectsSymlinkAndOversizedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentBridgeSharedDiscovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("target.json")
        let link = directory.appendingPathComponent("bridge-v1.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(
            try SystemAgentBridgeDiscoveryFileReader().readSnapshot(at: link, maximumBytes: 100)
        ) { XCTAssertEqual($0 as? AgentBridgeDiscoveryReadError, .symbolicLink) }

        let large = directory.appendingPathComponent("large.json")
        try Data(repeating: 1, count: 101).write(to: large)
        XCTAssertThrowsError(
            try SystemAgentBridgeDiscoveryFileReader().readSnapshot(at: large, maximumBytes: 100)
        ) { XCTAssertEqual($0 as? AgentBridgeDiscoveryReadError, .oversized) }
    }

    private func makeReader(snapshot: AgentBridgeDiscoveryFileSnapshot) throws -> AgentBridgeDiscoveryReader {
        try AgentBridgeDiscoveryReader(
            recordURL: URL(fileURLWithPath: "/private/test/bridge-v1.json"),
            fileReader: FixedDiscoveryFileReader(snapshot: snapshot),
            effectiveUserID: geteuid(),
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )
    }

    private func snapshot(
        data: Data? = nil,
        isRegularFile: Bool = true,
        isSymbolicLink: Bool = false,
        ownerID: uid_t = geteuid(),
        permissions: mode_t = 0o600
    ) -> AgentBridgeDiscoveryFileSnapshot {
        AgentBridgeDiscoveryFileSnapshot(
            data: data ?? encode(record()),
            isRegularFile: isRegularFile,
            isSymbolicLink: isSymbolicLink,
            ownerID: ownerID,
            permissions: permissions,
            deviceID: 1,
            inode: 2
        )
    }

    private func record(
        protocolVersion: Int = 1,
        host: String = "127.0.0.1",
        port: UInt16 = 49_321,
        authenticationToken: String = Data(repeating: 0x24, count: 32).base64EncodedString()
    ) -> AgentBridgeDiscoveryRecord {
        AgentBridgeDiscoveryRecord(
            protocolVersion: protocolVersion,
            host: host,
            port: port,
            launchID: "launch-1",
            producerID: "producer-1",
            authenticationToken: authenticationToken,
            processID: 123,
            createdAt: now
        )
    }

    private func encode(_ record: AgentBridgeDiscoveryRecord) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try! encoder.encode(record)
    }
}

private struct FixedDiscoveryFileReader: AgentBridgeDiscoveryFileReading {
    let snapshot: AgentBridgeDiscoveryFileSnapshot
    func readSnapshot(at: URL, maximumBytes: Int) throws -> AgentBridgeDiscoveryFileSnapshot { snapshot }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
