import Foundation
import Security
@testable import DynamicIsland

struct FixedAgentBridgeCredentialStore: AgentBridgeCredentialStore {
    let secret: Data?

    func installationSecret() throws -> Data {
        guard let secret else { throw AgentBridgeCredentialError.keychain(errSecInteractionNotAllowed) }
        return secret
    }
}

enum AgentBridgeTestSupport {
    static let secret = Data(repeating: 0x42, count: AgentBridgeLimits.installationSecretBytes)
    static let launchKey = Data(repeating: 0x24, count: AgentBridgeLimits.launchKeyBytes)
    static let now = Date(timeIntervalSince1970: 2_000_000_000)

    static func event(
        id: String = "event-1",
        provider: String = "unverified",
        nativeSessionID: String = "session-1",
        generation: UInt64? = nil,
        type: String = "sessionStarted",
        correlationID: String? = nil,
        authority: String = "localStructuredRecord",
        source: String = "unknown",
        payload: [String: Any] = ["sessionMetadata": [:]]
    ) -> [String: Any] {
        var value: [String: Any] = [
            "schemaVersion": 1,
            "eventID": id,
            "provider": provider,
            "source": source,
            "nativeSessionID": nativeSessionID,
            "eventType": type,
            "authority": authority,
            "payload": payload
        ]
        if let generation { value["sessionGeneration"] = generation }
        if let correlationID { value["correlationID"] = correlationID }
        return value
    }

    static func body(
        producerID: String = "producer-1",
        event: [String: Any]
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocolVersion": AgentBridgeLimits.protocolVersion,
            "producerID": producerID,
            "event": event
        ], options: [.sortedKeys])
    }

    static func batchBody(
        producerID: String = "producer-1",
        events: [[String: Any]]
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocolVersion": AgentBridgeLimits.protocolVersion,
            "producerID": producerID,
            "events": events
        ], options: [.sortedKeys])
    }

    static func signedRequest(
        body: Data,
        key: Data = launchKey,
        method: String = "POST",
        route: String = "/v1/events",
        timestamp: Int64 = Int64(now.timeIntervalSince1970),
        nonce: String = "nonce-1",
        contentType: String = "application/json"
    ) -> AgentBridgeHTTPRequest {
        let signature = AgentBridgeCrypto.signature(
            keyData: key,
            method: method,
            route: route,
            protocolVersion: AgentBridgeLimits.protocolVersion,
            timestamp: timestamp,
            nonce: nonce,
            body: body
        )
        return AgentBridgeHTTPRequest(
            method: method,
            route: route,
            headers: [
                "content-type": contentType,
                "x-dynamicisland-protocol": String(AgentBridgeLimits.protocolVersion),
                "x-dynamicisland-timestamp": String(timestamp),
                "x-dynamicisland-nonce": nonce,
                "x-dynamicisland-signature": signature
            ],
            body: body
        )
    }

    static func rawRequest(
        method: String = "POST",
        route: String = "/v1/events",
        headers: [(String, String)] = [("Content-Type", "application/json")],
        body: Data = Data()
    ) -> Data {
        var headerLines = ["\(method) \(route) HTTP/1.1"]
        headerLines.append(contentsOf: headers.map { "\($0.0): \($0.1)" })
        if !headers.contains(where: { $0.0.lowercased() == "content-length" }) {
            headerLines.append("Content-Length: \(body.count)")
        }
        return Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
    }
}
