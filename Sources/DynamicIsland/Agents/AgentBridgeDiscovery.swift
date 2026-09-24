import Darwin
import Foundation

protocol AgentBridgeDiscoveryPublishing: Sendable {
    var recordURL: URL { get }
    func publish(_ record: AgentBridgeDiscoveryRecord) throws
    func removeIfOwned(launchID: String) throws
}

enum AgentBridgeDiscoveryError: Error, Equatable {
    case unavailableDirectory
    case invalidRecord
    case insecurePermissions
}

struct AgentBridgeDiscoveryPublisher: AgentBridgeDiscoveryPublishing {
    let recordURL: URL

    init(recordURL: URL? = nil, fileManager: FileManager = .default) throws {
        if let recordURL {
            self.recordURL = recordURL
        } else {
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw AgentBridgeDiscoveryError.unavailableDirectory
            }
            self.recordURL = applicationSupport
                .appendingPathComponent("DynamicIsland", isDirectory: true)
                .appendingPathComponent("AgentBridge", isDirectory: true)
                .appendingPathComponent("bridge-v1.json")
        }
    }

    func publish(_ record: AgentBridgeDiscoveryRecord) throws {
        let directory = recordURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: recordURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)

        let attributes = try FileManager.default.attributesOfItem(atPath: recordURL.path)
        guard (attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o600 else {
            throw AgentBridgeDiscoveryError.insecurePermissions
        }
    }

    func removeIfOwned(launchID: String) throws {
        guard FileManager.default.fileExists(atPath: recordURL.path) else { return }
        let data = try Data(contentsOf: recordURL, options: [.mappedIfSafe])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(AgentBridgeDiscoveryRecord.self, from: data) else {
            // A malformed stale record is safe to replace during startup, but an
            // owner cannot prove it created this file during shutdown.
            return
        }
        guard record.launchID == launchID else { return }
        try FileManager.default.removeItem(at: recordURL)
    }
}
