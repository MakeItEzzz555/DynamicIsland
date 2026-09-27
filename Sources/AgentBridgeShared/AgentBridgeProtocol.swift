import Foundation

package enum AgentBridgeProtocol {
    package static let version = 1
    package static let eventsRoute = "/v1/events"
    package static let codexHookEventsRoute = "/v1/events/codex-hook"
    package static let codexPermissionRoute = "/v1/control/codex-permission"
    package static let claudeHookEventsRoute = "/v1/events/claude-hook"
    package static let healthRoute = "/v1/health"

    package static let maximumSingleEventBodyBytes = 64 * 1_024
    package static let maximumRequestBodyBytes = 1_024 * 1_024
    package static let maximumBatchEvents = 100
    package static let maximumDiscoveryBytes = 16 * 1_024
    package static let maximumResponseBytes = 16 * 1_024
    package static let maximumIdentifierBytes = 256
    package static let launchKeyBytes = 32

    package static let protocolHeader = "x-dynamicisland-protocol"
    package static let timestampHeader = "x-dynamicisland-timestamp"
    package static let nonceHeader = "x-dynamicisland-nonce"
    package static let signatureHeader = "x-dynamicisland-signature"
}

package struct AgentBridgeDiscoveryRecord: Codable, Equatable, Sendable {
    package let protocolVersion: Int
    package let host: String
    package let port: UInt16
    package let launchID: String
    package let producerID: String
    package let authenticationToken: String
    package let eventsRoute: String?
    package let processID: Int32
    package let createdAt: Date

    package init(
        protocolVersion: Int,
        host: String,
        port: UInt16,
        launchID: String,
        producerID: String,
        authenticationToken: String,
        eventsRoute: String? = nil,
        processID: Int32,
        createdAt: Date
    ) {
        self.protocolVersion = protocolVersion
        self.host = host
        self.port = port
        self.launchID = launchID
        self.producerID = producerID
        self.authenticationToken = authenticationToken
        self.eventsRoute = eventsRoute
        self.processID = processID
        self.createdAt = createdAt
    }
}

/// A validated, per-launch client credential. It never contains the persistent
/// installation secret and must not be rendered in logs or diagnostics.
package struct AgentBridgeClientProfile: Equatable, Sendable {
    package let host: String
    package let port: UInt16
    package let protocolVersion: Int
    package let launchID: String
    package let producerID: String
    package let authenticationKey: Data
    package let eventsRoute: String

    package init(
        host: String,
        port: UInt16,
        protocolVersion: Int,
        launchID: String,
        producerID: String,
        authenticationKey: Data,
        eventsRoute: String = AgentBridgeProtocol.eventsRoute
    ) {
        self.host = host
        self.port = port
        self.protocolVersion = protocolVersion
        self.launchID = launchID
        self.producerID = producerID
        self.authenticationKey = authenticationKey
        self.eventsRoute = eventsRoute
    }
}

package struct AgentBridgeClientRequest: Equatable, Sendable {
    package let method: String
    package let route: String
    package let headers: [String: String]
    package let body: Data

    package init(method: String, route: String, headers: [String: String], body: Data) {
        self.method = method
        self.route = route
        self.headers = headers
        self.body = body
    }
}

package struct AgentBridgeClientResponse: Equatable, Sendable {
    package let statusCode: Int
    package let code: String
    package let permissionDecision: AgentBridgePermissionDecision?

    package init(
        statusCode: Int,
        code: String,
        permissionDecision: AgentBridgePermissionDecision? = nil
    ) {
        self.statusCode = statusCode
        self.code = String(code.unicodeScalars.filter {
            $0.isASCII && !CharacterSet.controlCharacters.contains($0)
        }.prefix(96))
        self.permissionDecision = permissionDecision
    }
}

package enum AgentBridgePermissionDecision: String, Codable, Equatable, Sendable {
    case allow
    case deny
}
