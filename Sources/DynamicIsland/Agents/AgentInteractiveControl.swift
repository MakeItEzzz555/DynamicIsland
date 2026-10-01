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


enum AgentInteractiveCapability: String, CaseIterable, Hashable, Sendable {
    case startSession
    case resumeSession
    case submitPrompt
    case interrupt
    case selectModel
    case resolveApprovals
    case accountUsage
    case contextUsage
    case streamMessages
    case streamToolActivity
    case loadHistory
}

struct AgentManagedModelDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let model: String
    let displayName: String
    let description: String?
    let isDefault: Bool
}

enum AgentModelSelectionScope: String, Equatable, Sendable {
    /// The selected model is sent as an authoritative provider override on the
    /// next turn request. Codex applies that override to this turn and
    /// subsequent turns in the same thread.
    case turnAndSubsequent
}

enum AgentManagedTranscriptRole: String, Equatable, Sendable {
    case user
    case agent
    case tool
    case command
    case plan
    case status
    case error
}

struct AgentManagedTranscriptEntry: Identifiable, Equatable, Sendable {
    static let maximumTextLength = 8_000

    let id: String
    let nativeSessionID: String
    let turnID: String?
    let role: AgentManagedTranscriptRole
    let text: String
    let timestamp: Date

    static func boundedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maximumTextLength { return trimmed }
        return String(trimmed.prefix(maximumTextLength - 1)) + "…"
    }
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
    case transcript(AgentManagedTranscriptEntry)
    case transcriptDelta(nativeSessionID: String, turnID: String, itemID: String, delta: String)
    case accountUsageChanged
    case normalized(AgentManagedNormalizedEvent)
    case approvalRequested(AgentManagedApprovalRequest)
    /// The provider withdrew one exact pending approval request (for example
    /// Claude Code `control_cancel_request`). It must never be answered.
    case approvalCancelled(nativeSessionID: String, requestID: String)
    /// The provider's own authoritative statement that one exact pending
    /// request (by its wire token) is resolved: Codex
    /// `serverRequest/resolved`, Claude Code `tool_result` for the answered
    /// tool use. The only evidence that may confirm a delivered decision.
    case approvalAcknowledged(nativeSessionID: String, requestToken: AgentInteractiveRequestToken)
    case transportClosed(String?)
}

struct AgentManagedNormalizedEvent: Equatable, Sendable {
    let nativeSessionID: String
    let turnID: String?
    let type: AgentEventType
    let correlationID: AgentCorrelationID?
    let payload: AgentEventPayload
}

enum AgentInteractiveRequestToken: Hashable, Sendable {
    case string(String)
    case integer(Int64)
}

struct AgentManagedApprovalRequest: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case command
        case fileChange
    }

    let requestToken: AgentInteractiveRequestToken
    /// Provider-authoritative identity for this exact approval callback. This
    /// is distinct from the tool item because one item can issue more than one
    /// approval request.
    let requestID: String
    let kind: Kind
    let threadID: String
    let turnID: String
    let itemID: String
    let summary: String
}

protocol AgentInteractiveProvider: Sendable {
    var provider: AgentProvider { get }
    var interactiveCapabilities: Set<AgentInteractiveCapability> { get }
    var modelSelectionScope: AgentModelSelectionScope? { get }

    func events() async -> AsyncStream<AgentInteractiveProviderEvent>
    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor]
    /// Resolves one exact provider-native session without relying on bounded
    /// discovery. Implementations must not create a replacement session.
    func inspectSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor?
    func readAccountUsage() async throws -> AgentUsage
    func readTranscript(nativeSessionID: String, limit: Int) async throws -> [AgentManagedTranscriptEntry]
    func listModels() async throws -> [AgentManagedModelDescriptor]
    func startSession(cwd: String?, model: String?) async throws -> AgentManagedSessionDescriptor
    func resumeSession(
        nativeSessionID: String,
        cwd: String?
    ) async throws -> AgentManagedSessionDescriptor
    func submit(
        prompt: String,
        nativeSessionID: String,
        model: String?
    ) async throws -> AgentManagedTurnDescriptor
    func interrupt(nativeSessionID: String, turnID: String) async throws
    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws
    func stop() async
    /// Configured agents/profiles the provider itself exposes. Empty when
    /// the provider has no such concept.
    func listAgents() async throws -> [AgentManagedAgentDescriptor]
    func startSession(cwd: String?, model: String?, agent: String?) async throws -> AgentManagedSessionDescriptor
}

extension AgentInteractiveProvider {
    func listAgents() async throws -> [AgentManagedAgentDescriptor] { [] }

    func startSession(cwd: String?, model: String?, agent: String?) async throws -> AgentManagedSessionDescriptor {
        guard agent == nil else { throw AgentManagedAgentSelectionError.unsupported }
        return try await startSession(cwd: cwd, model: model)
    }
}

enum AgentManagedAgentSelectionError: Error, Equatable {
    case unsupported
}

enum AgentManagedInteractionState: Equatable, Sendable {
    case observed
    case connecting
    case checkingAttachment
    case ready
    case submitting
    case working(canInterrupt: Bool)
    case stopping
    case failed(String)

    var allowsPromptSubmission: Bool {
        if case .ready = self { return true }
        return false
    }

    var canInterrupt: Bool {
        if case let .working(canInterrupt) = self { return canInterrupt }
        return false
    }
}

struct AgentManagedControlState: Equatable, Sendable {
    let nativeSessionID: String
    var activeTurnID: String?
    var isSubmitting: Bool
    var isInterrupting: Bool
    var lastError: String?
    var acceptsDirectInput: Bool

    var canInterrupt: Bool {
        activeTurnID != nil && !isInterrupting
    }

    var canSubmit: Bool {
        acceptsDirectInput &&
        activeTurnID == nil &&
        !isSubmitting &&
        !isInterrupting
    }
}
