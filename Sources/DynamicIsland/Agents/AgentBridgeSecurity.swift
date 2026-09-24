import CryptoKit
import Foundation
import Security

protocol AgentBridgeCredentialStore: Sendable {
    func installationSecret() throws -> Data
}

enum AgentBridgeCredentialError: Error, Equatable {
    case keychain(OSStatus)
    case invalidStoredSecret
    case randomGeneration(OSStatus)
}

struct SystemAgentBridgeCredentialStore: AgentBridgeCredentialStore {
    static let service = "com.local.dynamicisland.agent-bridge"
    static let account = "installation-secret-v1"

    func installationSecret() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data,
                  data.count == AgentBridgeLimits.installationSecretBytes else {
                throw AgentBridgeCredentialError.invalidStoredSecret
            }
            return data
        }
        guard status == errSecItemNotFound else {
            throw AgentBridgeCredentialError.keychain(status)
        }

        let generated = try AgentBridgeCrypto.randomBytes(count: AgentBridgeLimits.installationSecretBytes)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: generated
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecSuccess { return generated }
        if addStatus == errSecDuplicateItem {
            var retryResult: CFTypeRef?
            let retryStatus = SecItemCopyMatching(query as CFDictionary, &retryResult)
            guard retryStatus == errSecSuccess,
                  let data = retryResult as? Data,
                  data.count == AgentBridgeLimits.installationSecretBytes else {
                throw AgentBridgeCredentialError.keychain(retryStatus)
            }
            return data
        }
        throw AgentBridgeCredentialError.keychain(addStatus)
    }
}

enum AgentBridgeCrypto {
    static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AgentBridgeCredentialError.randomGeneration(status)
        }
        return Data(bytes)
    }

    static func launchKey(
        installationSecret: Data,
        launchID: String,
        launchNonce: Data
    ) -> Data {
        let key = SymmetricKey(data: installationSecret)
        let message = Data("DynamicIsland.AgentBridge.v1\n\(launchID)\n".utf8) + launchNonce
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    static func bodyDigest(_ body: Data) -> String {
        SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    }

    static func canonicalMessage(
        method: String,
        route: String,
        protocolVersion: Int,
        timestamp: Int64,
        nonce: String,
        body: Data
    ) -> Data {
        Data([
            method.uppercased(),
            route,
            String(protocolVersion),
            String(timestamp),
            nonce,
            bodyDigest(body)
        ].joined(separator: "\n").utf8)
    }

    static func signature(
        keyData: Data,
        method: String,
        route: String,
        protocolVersion: Int,
        timestamp: Int64,
        nonce: String,
        body: Data
    ) -> String {
        let message = canonicalMessage(
            method: method,
            route: route,
            protocolVersion: protocolVersion,
            timestamp: timestamp,
            nonce: nonce,
            body: body
        )
        return HMAC<SHA256>.authenticationCode(
            for: message,
            using: SymmetricKey(data: keyData)
        ).map { String(format: "%02x", $0) }.joined()
    }

    static func validateSignature(
        _ signature: String,
        keyData: Data,
        method: String,
        route: String,
        protocolVersion: Int,
        timestamp: Int64,
        nonce: String,
        body: Data
    ) -> Bool {
        guard let code = Data(hex: signature), code.count == SHA256.byteCount else { return false }
        let message = canonicalMessage(
            method: method,
            route: route,
            protocolVersion: protocolVersion,
            timestamp: timestamp,
            nonce: nonce,
            body: body
        )
        return HMAC<SHA256>.isValidAuthenticationCode(
            code,
            authenticating: message,
            using: SymmetricKey(data: keyData)
        )
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.utf8.count.isMultiple(of: 2) else { return nil }
        var result = Data(capacity: hex.utf8.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        self = result
    }
}

enum AgentBridgeAuthenticationError: Error, Equatable, Sendable {
    case missingHeaders
    case unsupportedProtocol
    case invalidTimestamp
    case timestampOutsideWindow
    case invalidNonce
    case invalidSignature
    case replay
    case replayCacheFull
}

actor AgentBridgeAuthenticator {
    private struct NonceEntry: Sendable {
        let nonce: String
        let expiresAt: Date
    }

    private let keyData: Data
    private let now: @Sendable () -> Date
    private var nonceEntries: [NonceEntry] = []
    private var nonceSet: Set<String> = []

    init(keyData: Data, now: @escaping @Sendable () -> Date = Date.init) {
        self.keyData = keyData
        self.now = now
    }

    var rememberedNonceCount: Int { nonceEntries.count }

    func authenticate(
        _ request: AgentBridgeHTTPRequest,
        at currentDate: Date? = nil
    ) -> AgentBridgeAuthenticationError? {
        guard let protocolText = request.headers["x-dynamicisland-protocol"],
              let timestampText = request.headers["x-dynamicisland-timestamp"],
              let nonce = request.headers["x-dynamicisland-nonce"],
              let signature = request.headers["x-dynamicisland-signature"] else {
            return .missingHeaders
        }
        guard protocolText == String(AgentBridgeLimits.protocolVersion) else {
            return .unsupportedProtocol
        }
        guard let timestamp = Int64(timestampText) else { return .invalidTimestamp }
        guard Self.validToken(nonce, maximumBytes: AgentBridgeLimits.maximumNonceBytes) else {
            return .invalidNonce
        }
        guard Self.validToken(signature, maximumBytes: AgentBridgeLimits.maximumSignatureBytes) else {
            return .invalidSignature
        }

        let current = currentDate ?? now()
        let requestDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
        guard abs(current.timeIntervalSince(requestDate)) <= AgentBridgeLimits.acceptedClockSkew else {
            return .timestampOutsideWindow
        }
        guard AgentBridgeCrypto.validateSignature(
            signature,
            keyData: keyData,
            method: request.method,
            route: request.route,
            protocolVersion: AgentBridgeLimits.protocolVersion,
            timestamp: timestamp,
            nonce: nonce,
            body: request.body
        ) else {
            return .invalidSignature
        }

        purgeExpired(at: current)
        guard !nonceSet.contains(nonce) else { return .replay }
        guard nonceEntries.count < AgentBridgeLimits.maximumRememberedNonces else {
            return .replayCacheFull
        }
        nonceEntries.append(NonceEntry(
            nonce: nonce,
            expiresAt: current.addingTimeInterval(AgentBridgeLimits.nonceRetention)
        ))
        nonceSet.insert(nonce)
        return nil
    }

    func invalidate() {
        nonceEntries.removeAll(keepingCapacity: false)
        nonceSet.removeAll(keepingCapacity: false)
    }

    private func purgeExpired(at date: Date) {
        // Do not assume wall-clock samples are monotonic. Filtering the bounded
        // cache keeps expiry correct even if the system clock moves backward.
        let expired = nonceEntries.lazy.filter { $0.expiresAt <= date }.map(\.nonce)
        for nonce in expired { nonceSet.remove(nonce) }
        nonceEntries.removeAll { $0.expiresAt <= date }
    }

    private static func validToken(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes && value.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0))
        }
    }
}
