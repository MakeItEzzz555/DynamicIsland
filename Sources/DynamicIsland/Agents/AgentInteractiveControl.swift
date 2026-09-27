import Foundation

struct AgentManagedSessionDescriptor: Equatable, Sendable {
    let provider: AgentProvider
    let nativeSessionID: String
    let cwd: String?
    let model: String?
    let acceptsDirectInput: Bool

    var sessionID: AgentSessionID {
        AgentSessionID(provider: provider, nativeID: nativeSessionID)
    }
}

struct AgentManagedTurnDescriptor: Equatable, Sendable {
    let nativeSessionID: String
    let turnID: String
}

enum AgentDiscoveredSessionRuntimeState: String, Equatable, Sendable {
    case active
    case idle
    case notLoaded
    case systemError
}

struct AgentDiscoveredSessionDescriptor: Equatable, Sendable {
    let session: AgentManagedSessionDescriptor
    let runtimeState: AgentDiscoveredSessionRuntimeState
    let updatedAt: Date
}


enum AgentInteractiveProviderEvent: Equatable, Sendable {
    case threadAvailable(AgentManagedSessionDescriptor)
    case turnStarted(AgentManagedTurnDescriptor)
    case turnCompleted(AgentManagedTurnDescriptor, state: AgentState, summary: String?)
    case providerFailure(nativeSessionID: String?, summary: String?)
    case accountUsageChanged
    case normalized(AgentManagedNormalizedEvent)
    case approvalRequested(AgentManagedApprovalRequest)
    case transportClosed(String?)
}

struct AgentManagedNormalizedEvent: Equatable, Sendable {
    let nativeSessionID: String
    let turnID: String?
    let type: AgentEventType
    let correlationID: AgentCorrelationID?
    let payload: AgentEventPayload
}

enum AgentInteractiveRequestToken: Equatable, Sendable {
    case string(String)
    case integer(Int64)
}

struct AgentManagedApprovalRequest: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case command
        case fileChange
    }

    let requestToken: AgentInteractiveRequestToken
    let kind: Kind
    let threadID: String
    let turnID: String
    let itemID: String
    let summary: String
}

protocol AgentInteractiveProvider: Sendable {
    var provider: AgentProvider { get }

    func events() async -> AsyncStream<AgentInteractiveProviderEvent>
    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor]
    func readAccountUsage() async throws -> AgentUsage
    func startSession(cwd: String?) async throws -> AgentManagedSessionDescriptor
    func resumeSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor
    func submit(prompt: String, nativeSessionID: String) async throws -> AgentManagedTurnDescriptor
    func interrupt(nativeSessionID: String, turnID: String) async throws
    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws
    func stop() async
}

struct AgentManagedControlState: Equatable, Sendable {
    let nativeSessionID: String
    var activeTurnID: String?
    var isSubmitting: Bool
    var lastError: String?
    var acceptsDirectInput: Bool

    var canInterrupt: Bool {
        activeTurnID != nil
    }
}
