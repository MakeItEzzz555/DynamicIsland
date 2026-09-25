import CryptoKit
import Foundation
import Security

package enum AgentBridgeRequestAuthentication {
    package static func bodyDigest(_ body: Data) -> String {
        SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    }

    /// Canonical v1 bytes, with no trailing newline:
    /// METHOD\nroute\nprotocolVersion\ntimestamp\nnonce\nsha256(body)
    package static func canonicalMessage(
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

    package static func signature(
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

    package static func validateSignature(
        _ signature: String,
        keyData: Data,
        method: String,
        route: String,
        protocolVersion: Int,
        timestamp: Int64,
        nonce: String,
        body: Data
    ) -> Bool {
        guard let code = Data(agentBridgeHex: signature), code.count == SHA256.byteCount else {
            return false
        }
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

    package static func randomNonce(byteCount: Int = 16) throws -> String {
        guard byteCount > 0, byteCount <= 64 else { throw AgentBridgeSharedError.invalidNonce }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AgentBridgeSharedError.randomUnavailable
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    init?(agentBridgeHex: String) {
        guard agentBridgeHex.utf8.count.isMultiple(of: 2) else { return nil }
        var result = Data(capacity: agentBridgeHex.utf8.count / 2)
        var index = agentBridgeHex.startIndex
        while index < agentBridgeHex.endIndex {
            let next = agentBridgeHex.index(index, offsetBy: 2)
            guard let byte = UInt8(agentBridgeHex[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        self = result
    }
}

package enum AgentBridgeSharedError: Error, Equatable, Sendable {
    case invalidNonce
    case randomUnavailable
}
