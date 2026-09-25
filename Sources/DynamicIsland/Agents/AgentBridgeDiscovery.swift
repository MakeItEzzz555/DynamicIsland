import AgentBridgeShared
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
        try validatePrivateDirectory(directory)

        var existing = stat()
        if lstat(recordURL.path, &existing) == 0 {
            guard (existing.st_mode & S_IFMT) == S_IFREG,
                  existing.st_uid == geteuid() else {
                throw AgentBridgeDiscoveryError.insecurePermissions
            }
        } else if errno != ENOENT {
            throw AgentBridgeDiscoveryError.invalidRecord
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        guard data.count <= AgentBridgeProtocol.maximumDiscoveryBytes else {
            throw AgentBridgeDiscoveryError.invalidRecord
        }
        try data.write(to: recordURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)

        var written = stat()
        guard lstat(recordURL.path, &written) == 0,
              (written.st_mode & S_IFMT) == S_IFREG,
              written.st_uid == geteuid(),
              written.st_mode & 0o7777 == 0o600 else {
            throw AgentBridgeDiscoveryError.insecurePermissions
        }
    }

    func removeIfOwned(launchID: String) throws {
        let snapshot: AgentBridgeDiscoveryFileSnapshot
        do {
            snapshot = try SystemAgentBridgeDiscoveryFileReader().readSnapshot(
                at: recordURL,
                maximumBytes: AgentBridgeProtocol.maximumDiscoveryBytes
            )
        } catch AgentBridgeDiscoveryReadError.unavailable {
            return
        } catch {
            // Ownership is not proven for malformed, oversized, symlinked or
            // otherwise unsafe records. Leave them untouched.
            return
        }
        guard snapshot.ownerID == geteuid(),
              snapshot.permissions & 0o7777 == 0o600 else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(AgentBridgeDiscoveryRecord.self, from: snapshot.data),
              record.launchID == launchID else {
            return
        }

        var current = stat()
        guard lstat(recordURL.path, &current) == 0,
              (current.st_mode & S_IFMT) == S_IFREG,
              current.st_uid == geteuid(),
              current.st_dev == snapshot.deviceID,
              current.st_ino == snapshot.inode else {
            return
        }
        guard unlink(recordURL.path) == 0 || errno == ENOENT else {
            throw AgentBridgeDiscoveryError.invalidRecord
        }
    }

    private func validatePrivateDirectory(_ directory: URL) throws {
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0 else {
            throw AgentBridgeDiscoveryError.insecurePermissions
        }
    }
}
