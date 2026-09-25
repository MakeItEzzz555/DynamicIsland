import Foundation

enum AgentBridgeLimits {
    static let protocolVersion = 1
    static let maximumSingleEventBodyBytes = 64 * 1_024
    static let maximumRequestBodyBytes = 1_024 * 1_024
    static let maximumBatchEvents = 100
    static let maximumHeaderBytes = 16 * 1_024
    static let maximumHeaderValueBytes = 4 * 1_024
    static let maximumJSONDepth = 12
    static let maximumConcurrentConnections = 16
    static let maximumNonceBytes = 128
    static let maximumSignatureBytes = 128
    static let maximumRememberedNonces = 2_048
    static let acceptedClockSkew: TimeInterval = 60
    static let nonceRetention: TimeInterval = 120
    static let installationSecretBytes = 32
    static let launchKeyBytes = 32
}

enum AgentBridgeState: String, Equatable, Sendable {
    case stopped
    case starting
    case running
    case degraded
    case failed
}

struct AgentBridgeHealth: Equatable, Sendable {
    var state: AgentBridgeState = .stopped
    var port: UInt16?
    var protocolVersion = AgentBridgeLimits.protocolVersion
    var lastSafeError: String?
    var acceptedRequestCount: UInt64 = 0
    var rejectedRequestCount: UInt64 = 0
}

struct AgentBridgeDiscoveryRecord: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let host: String
    let port: UInt16
    let launchID: String
    /// Identity bound by the server to this per-launch credential. HMAC proves
    /// possession of that credential, not OS process identity or provider truth;
    /// server-side producer policy constrains all semantic claims.
    let producerID: String
    /// A derived per-launch key. The persistent installation secret never leaves Keychain.
    let authenticationToken: String
    let processID: Int32
    let createdAt: Date
}

struct AgentBridgeWireRequest: Decodable, Sendable {
    let protocolVersion: Int
    let producerID: String
    let event: AgentBridgeWireEvent?
    let events: [AgentBridgeWireEvent]?

    var eventBatch: [AgentBridgeWireEvent]? {
        switch (event, events) {
        case (.some(let event), nil): [event]
        case (nil, .some(let events)): events
        default: nil
        }
    }
}

struct AgentBridgeWireEvent: Decodable, Sendable {
    let schemaVersion: Int
    let eventID: String
    let provider: String
    let source: String
    let nativeSessionID: String
    let sessionGeneration: UInt64?
    let eventType: String
    let providerTimestamp: String?
    let correlationID: String?
    let sequence: UInt64?
    let authority: String
    let payload: AgentBridgeWirePayload?
}

struct AgentBridgeWirePayload: Decodable, Sendable {
    let sessionMetadata: AgentSessionMetadata?
    let activity: AgentActivityDescriptor?
    let plan: AgentPlanEvent?
    let tool: AgentToolEvent?
    let command: AgentCommandEvent?
    let approvalRequest: AgentApprovalRequest?
    let approvalResolution: AgentApprovalResolution?
    let userInput: AgentUserInputEvent?
    let usage: [AgentBridgeWireUsageSample]?
    let capabilities: [AgentBridgeWireCapability]?
    let projectContext: AgentProjectContext?
    let terminal: AgentTerminalEvent?
    let subagent: AgentSubagentEvent?

    var populatedFieldCount: Int {
        [
            sessionMetadata != nil, activity != nil, plan != nil, tool != nil,
            command != nil, approvalRequest != nil, approvalResolution != nil,
            userInput != nil, usage != nil, capabilities != nil,
            projectContext != nil, terminal != nil, subagent != nil
        ].filter { $0 }.count
    }
}

struct AgentBridgeWireUsageSample: Decodable, Sendable {
    let metric: String
    let value: Double
    let limit: Double?
    let unit: String
    let scope: String
    let source: String
    let observedAt: String
}

struct AgentBridgeWireCapability: Decodable, Sendable {
    let name: String
    let authority: String
    let source: String
    let observedAt: String
}

enum AgentBridgeEnvelopeError: String, Error, Equatable, Sendable {
    case malformedEnvelope
    case unsupportedProtocol
    case emptyBatch
    case tooManyEvents
    case eventTooLarge
    case invalidProducer
    case invalidProvider
    case invalidSource
    case invalidEventType
    case invalidAuthority
    case invalidTimestamp
    case invalidPayload
    case invalidCapability
    case invalidUsage
    case policyViolation
    case generationConflict
    case semanticValidation
    case storeRejected
}

struct AgentBridgeIngestionResult: Equatable, Sendable {
    let acceptedEvents: Int
    let applications: [AgentEventApplication]
}

enum AgentBridgeHTTPStatus: Int, Equatable, Sendable {
    case ok = 200
    case accepted = 202
    case badRequest = 400
    case unauthorized = 401
    case notFound = 404
    case methodNotAllowed = 405
    case conflict = 409
    case payloadTooLarge = 413
    case unsupportedMediaType = 415
    case unprocessableContent = 422
    case tooManyRequests = 429
    case internalServerError = 500

    var reason: String {
        switch self {
        case .ok: "OK"
        case .accepted: "Accepted"
        case .badRequest: "Bad Request"
        case .unauthorized: "Unauthorized"
        case .notFound: "Not Found"
        case .methodNotAllowed: "Method Not Allowed"
        case .conflict: "Conflict"
        case .payloadTooLarge: "Payload Too Large"
        case .unsupportedMediaType: "Unsupported Media Type"
        case .unprocessableContent: "Unprocessable Content"
        case .tooManyRequests: "Too Many Requests"
        case .internalServerError: "Internal Server Error"
        }
    }
}

struct AgentBridgeHTTPResponse: Sendable {
    let status: AgentBridgeHTTPStatus
    let code: String

    var data: Data {
        let safeCode = code
            .unicodeScalars
            .filter { $0.isASCII && !CharacterSet.controlCharacters.contains($0) }
            .prefix(96)
        let body = Data("{\"status\":\"\(status.rawValue < 400 ? "accepted" : "rejected")\",\"code\":\"\(String(safeCode))\"}".utf8)
        let header = "HTTP/1.1 \(status.rawValue) \(status.reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        return Data(header.utf8) + body
    }
}
