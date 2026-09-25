import Darwin
import Foundation

package enum AgentBridgeDiscoveryReadError: Error, Equatable, Sendable {
    case unavailable
    case notRegularFile
    case symbolicLink
    case wrongOwner
    case unsafePermissions
    case oversized
    case changedDuringRead
    case malformed
    case unsupportedProtocol
    case invalidHost
    case invalidPort
    case invalidIdentifier
    case invalidAuthentication
    case invalidProcess
    case invalidTimestamp
}

package struct AgentBridgeDiscoveryFileSnapshot: Equatable, Sendable {
    package let data: Data
    package let isRegularFile: Bool
    package let isSymbolicLink: Bool
    package let ownerID: uid_t
    package let permissions: mode_t
    package let deviceID: dev_t
    package let inode: ino_t

    package init(
        data: Data,
        isRegularFile: Bool,
        isSymbolicLink: Bool,
        ownerID: uid_t,
        permissions: mode_t,
        deviceID: dev_t,
        inode: ino_t
    ) {
        self.data = data
        self.isRegularFile = isRegularFile
        self.isSymbolicLink = isSymbolicLink
        self.ownerID = ownerID
        self.permissions = permissions
        self.deviceID = deviceID
        self.inode = inode
    }
}

package protocol AgentBridgeDiscoveryFileReading: Sendable {
    func readSnapshot(at url: URL, maximumBytes: Int) throws -> AgentBridgeDiscoveryFileSnapshot
}

package struct SystemAgentBridgeDiscoveryFileReader: AgentBridgeDiscoveryFileReading {
    package init() {}

    package func readSnapshot(
        at url: URL,
        maximumBytes: Int
    ) throws -> AgentBridgeDiscoveryFileSnapshot {
        var pathStatus = stat()
        guard lstat(url.path, &pathStatus) == 0 else { throw AgentBridgeDiscoveryReadError.unavailable }
        guard (pathStatus.st_mode & S_IFMT) != S_IFLNK else {
            throw AgentBridgeDiscoveryReadError.symbolicLink
        }

        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw errno == ELOOP ? AgentBridgeDiscoveryReadError.symbolicLink : .unavailable
        }
        defer { close(descriptor) }

        var openedStatus = stat()
        guard fstat(descriptor, &openedStatus) == 0 else { throw AgentBridgeDiscoveryReadError.unavailable }
        guard pathStatus.st_dev == openedStatus.st_dev,
              pathStatus.st_ino == openedStatus.st_ino else {
            throw AgentBridgeDiscoveryReadError.changedDuringRead
        }
        guard (openedStatus.st_mode & S_IFMT) == S_IFREG else {
            throw AgentBridgeDiscoveryReadError.notRegularFile
        }
        guard openedStatus.st_size >= 0,
              openedStatus.st_size <= maximumBytes else {
            throw AgentBridgeDiscoveryReadError.oversized
        }

        var data = Data()
        data.reserveCapacity(Int(openedStatus.st_size))
        var buffer = [UInt8](repeating: 0, count: min(4_096, maximumBytes + 1))
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw AgentBridgeDiscoveryReadError.unavailable
            }
            guard data.count <= maximumBytes - count else {
                throw AgentBridgeDiscoveryReadError.oversized
            }
            data.append(contentsOf: buffer.prefix(count))
        }

        var finalStatus = stat()
        guard fstat(descriptor, &finalStatus) == 0,
              finalStatus.st_dev == openedStatus.st_dev,
              finalStatus.st_ino == openedStatus.st_ino,
              finalStatus.st_size == openedStatus.st_size,
              data.count == Int(openedStatus.st_size) else {
            throw AgentBridgeDiscoveryReadError.changedDuringRead
        }

        return AgentBridgeDiscoveryFileSnapshot(
            data: data,
            isRegularFile: true,
            isSymbolicLink: false,
            ownerID: openedStatus.st_uid,
            permissions: openedStatus.st_mode & 0o7777,
            deviceID: openedStatus.st_dev,
            inode: openedStatus.st_ino
        )
    }
}

package protocol AgentBridgeClientProfileProviding: Sendable {
    func loadProfile() async throws -> AgentBridgeClientProfile
}

package struct AgentBridgeDiscoveryReader: AgentBridgeClientProfileProviding {
    package let recordURL: URL
    private let fileReader: any AgentBridgeDiscoveryFileReading
    private let effectiveUserID: uid_t
    private let now: @Sendable () -> Date

    package init(
        recordURL: URL? = nil,
        fileReader: any AgentBridgeDiscoveryFileReading = SystemAgentBridgeDiscoveryFileReader(),
        effectiveUserID: uid_t = geteuid(),
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        if let recordURL {
            self.recordURL = recordURL
        } else {
            guard let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw AgentBridgeDiscoveryReadError.unavailable
            }
            self.recordURL = applicationSupport
                .appendingPathComponent("DynamicIsland", isDirectory: true)
                .appendingPathComponent("AgentBridge", isDirectory: true)
                .appendingPathComponent("bridge-v1.json")
        }
        self.fileReader = fileReader
        self.effectiveUserID = effectiveUserID
        self.now = now
    }

    package func loadProfile() async throws -> AgentBridgeClientProfile {
        let snapshot = try fileReader.readSnapshot(
            at: recordURL,
            maximumBytes: AgentBridgeProtocol.maximumDiscoveryBytes
        )
        guard !snapshot.isSymbolicLink else { throw AgentBridgeDiscoveryReadError.symbolicLink }
        guard snapshot.isRegularFile else { throw AgentBridgeDiscoveryReadError.notRegularFile }
        guard snapshot.ownerID == effectiveUserID else { throw AgentBridgeDiscoveryReadError.wrongOwner }
        let permissions = snapshot.permissions & 0o7777
        guard permissions & 0o077 == 0,
              permissions & 0o400 != 0,
              permissions & 0o7000 == 0 else {
            throw AgentBridgeDiscoveryReadError.unsafePermissions
        }
        guard !snapshot.data.isEmpty,
              snapshot.data.count <= AgentBridgeProtocol.maximumDiscoveryBytes else {
            throw AgentBridgeDiscoveryReadError.oversized
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(AgentBridgeDiscoveryRecord.self, from: snapshot.data) else {
            throw AgentBridgeDiscoveryReadError.malformed
        }
        guard record.protocolVersion == AgentBridgeProtocol.version else {
            throw AgentBridgeDiscoveryReadError.unsupportedProtocol
        }
        guard record.host == "127.0.0.1" else { throw AgentBridgeDiscoveryReadError.invalidHost }
        guard record.port != 0 else { throw AgentBridgeDiscoveryReadError.invalidPort }
        guard Self.validIdentifier(record.launchID), Self.validIdentifier(record.producerID) else {
            throw AgentBridgeDiscoveryReadError.invalidIdentifier
        }
        guard let key = Data(base64Encoded: record.authenticationToken),
              key.count == AgentBridgeProtocol.launchKeyBytes else {
            throw AgentBridgeDiscoveryReadError.invalidAuthentication
        }
        guard record.processID > 0 else { throw AgentBridgeDiscoveryReadError.invalidProcess }
        let current = now()
        guard record.createdAt.timeIntervalSince1970 >= 1_577_836_800,
              record.createdAt <= current.addingTimeInterval(60) else {
            throw AgentBridgeDiscoveryReadError.invalidTimestamp
        }
        return AgentBridgeClientProfile(
            host: "127.0.0.1",
            port: record.port,
            protocolVersion: record.protocolVersion,
            launchID: record.launchID,
            producerID: record.producerID,
            authenticationKey: key
        )
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= AgentBridgeProtocol.maximumIdentifierBytes &&
            value.unicodeScalars.allSatisfy {
                $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0))
            }
    }
}
