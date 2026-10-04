import AgentBridgeShared
import Foundation

struct AgentApprovalControlKey: Hashable, Sendable {
    let session: AgentSessionInstanceID
    let requestID: AgentCorrelationID
}

struct AgentApprovalControlRequest: Identifiable, Equatable, Sendable {
    let key: AgentApprovalControlKey
    let summary: String
    let expiresAt: Date

    var id: AgentApprovalControlKey { key }
}

enum AgentApprovalControlResult: Equatable, Sendable {
    case accepted
    case missing
}

/// awaitingDecision -> submitting -> (provider-confirmed: removed; the
/// normalized store records Approved/Denied) or failed. Clicking never
/// produces "Approved" on its own.
enum AgentApprovalDeliveryState: Equatable, Sendable {
    case awaitingDecision
    case submitting(AgentBridgePermissionDecision)
    /// The decision was not confirmed by the provider. Provider responses are
    /// single-use (Codex JSON-RPC id, Claude control_response), so a failed
    /// delivery is never re-sent; the row stays visible until dismissed.
    case failed(AgentBridgePermissionDecision, reason: String)
}

@MainActor
final class AgentApprovalController: ObservableObject {
    @Published private(set) var pendingRequests: [AgentApprovalControlKey: AgentApprovalControlRequest] = [:]
    @Published private(set) var deliveringRequests: [AgentApprovalControlKey: AgentApprovalControlRequest] = [:]
    @Published private(set) var approvalPolicies: [AgentApprovalPolicyKey: AgentApprovalPolicyState] = [:]

    private var continuations: [AgentApprovalControlKey: CheckedContinuation<AgentBridgePermissionDecision?, Never>] = [:]
    private var expirationTasks: [AgentApprovalControlKey: Task<Void, Never>] = [:]
    private var completedRequests: [AgentApprovalControlKey: Date] = [:]
    private var deliveryDecisions: [AgentApprovalControlKey: AgentBridgePermissionDecision] = [:]
    private var deliveryFailures: [AgentApprovalControlKey: String] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    /// `maximumWait: nil` is for managed provider requests: the provider
    /// keeps waiting, so the request lives until the user decides or the
    /// provider/turn/transport withdraws it. Never answered by a timer.
    func request(
        _ request: AgentApprovalControlRequest,
        maximumWait: Duration? = .seconds(75)
    ) async -> AgentBridgePermissionDecision? {
        pruneCompletedRequests()
        guard request.expiresAt > now(),
              continuations[request.key] == nil,
              completedRequests[request.key] == nil else { return nil }
        if automaticallyApproves(request) {
            completedRequests[request.key] = request.expiresAt
            deliveringRequests[request.key] = request
            deliveryDecisions[request.key] = .allow
            return .allow
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                continuations[request.key] = continuation
                pendingRequests[request.key] = request
                guard let maximumWait else { return }
                let remaining = max(0, request.expiresAt.timeIntervalSince(now()))
                let expiryWait = min(maximumWait, .milliseconds(Int64(min(remaining, 86_400) * 1_000)))
                expirationTasks[request.key] = Task { [weak self] in
                    try? await Task.sleep(for: expiryWait)
                    guard !Task.isCancelled else { return }
                    self?.finish(request.key, decision: nil)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(request.key, decision: nil)
            }
        }
    }

    @discardableResult
    func resolve(
        session: AgentSessionInstanceID,
        requestID: AgentCorrelationID,
        decision: AgentBridgePermissionDecision
    ) -> AgentApprovalControlResult {
        let key = AgentApprovalControlKey(session: session, requestID: requestID)
        guard let request = pendingRequests[key] else { return .missing }
        guard request.expiresAt > now() else {
            finish(key, decision: nil)
            return .missing
        }
        expirationTasks.removeValue(forKey: key)?.cancel()
        pendingRequests.removeValue(forKey: key)
        deliveringRequests[key] = request
        deliveryDecisions[key] = decision
        completedRequests[key] = request.expiresAt
        continuations.removeValue(forKey: key)?.resume(returning: decision)
        return .accepted
    }

    /// Withdraws one exact request that is still awaiting a decision with
    /// **no decision** (the waiting caller receives `nil`). Used when the
    /// provider cancels the request, its turn ends, or its transport dies —
    /// never presented as a user Allow/Deny. Stays one-shot: the key is
    /// recorded as handled.
    @discardableResult
    func withdraw(
        session: AgentSessionInstanceID,
        requestID: AgentCorrelationID
    ) -> AgentApprovalControlResult {
        let key = AgentApprovalControlKey(session: session, requestID: requestID)
        guard pendingRequests[key] != nil else { return .missing }
        finish(key, decision: nil)
        return .accepted
    }

    /// Forgets one-shot history for a session once a *different* provider
    /// turn becomes authoritative. Provider request ids are only unique per
    /// transport (Codex JSON-RPC ids restart at 0 after a reconnect), so a
    /// reused id in a new turn is a new request. Replays from the previous
    /// turn are still refused by the managed turn binding.
    func forgetHandledRequests(for sessionID: AgentSessionID) {
        completedRequests = completedRequests.filter { $0.key.session.sessionID != sessionID }
    }

    func pendingRequest(for session: AgentSessionInstanceID) -> AgentApprovalControlRequest? {
        pendingRequests.values
            .filter { $0.key.session == session && $0.expiresAt > now() }
            .sorted { $0.expiresAt < $1.expiresAt }
            .first
    }

    func presentedRequest(for session: AgentSessionInstanceID) -> AgentApprovalControlRequest? {
        (Array(pendingRequests.values) + Array(deliveringRequests.values))
            .filter { $0.key.session == session && $0.expiresAt > now() }
            .sorted { $0.expiresAt < $1.expiresAt }
            .first
    }

    func deliveryState(for key: AgentApprovalControlKey) -> AgentApprovalDeliveryState? {
        if let decision = deliveryDecisions[key] {
            if let reason = deliveryFailures[key] { return .failed(decision, reason: reason) }
            return .submitting(decision)
        }
        return pendingRequests[key] == nil ? nil : .awaitingDecision
    }

    /// The provider acknowledged this exact decision.
    func confirmDelivery(_ key: AgentApprovalControlKey) {
        deliveringRequests.removeValue(forKey: key)
        deliveryDecisions.removeValue(forKey: key)
        deliveryFailures.removeValue(forKey: key)
    }

    /// The decision could not be confirmed. Kept presented (no buttons) so
    /// the user sees the failure instead of a silent disappearance.
    func failDelivery(_ key: AgentApprovalControlKey, reason: String) {
        guard deliveringRequests[key] != nil, deliveryDecisions[key] != nil else { return }
        deliveryFailures[key] = reason
        objectWillChange.send()
    }

    func dismissFailedDelivery(_ key: AgentApprovalControlKey) {
        guard deliveryFailures[key] != nil else { return }
        confirmDelivery(key)
    }

    func nextPendingRequest() -> AgentApprovalControlRequest? {
        pendingRequests.values
            .filter { $0.expiresAt > now() }
            .sorted { lhs, rhs in
                if lhs.expiresAt != rhs.expiresAt { return lhs.expiresAt < rhs.expiresAt }
                return lhs.key.requestID.rawValue < rhs.key.requestID.rawValue
            }
            .first
    }

    func approvalPolicy(for session: AgentSessionInstanceID) -> AgentApprovalPolicyMode {
        approvalPolicies[AgentApprovalPolicyKey(session: session)]?.mode ?? .askEveryTime
    }

    func setAutoApprove(_ enabled: Bool, for session: AgentSessionInstanceID) {
        let key = AgentApprovalPolicyKey(session: session)
        if enabled {
            approvalPolicies[key] = AgentApprovalPolicyState(key: key, mode: .autoApprove)
        } else {
            approvalPolicies.removeValue(forKey: key)
        }
        // Deliberately do not resolve existing pending requests. Policy changes
        // apply only to requests registered after this point.
    }

    func automaticallyApproves(_ request: AgentApprovalControlRequest) -> Bool {
        approvalPolicy(for: request.key.session) == .autoApprove
    }

    func hasHandled(_ key: AgentApprovalControlKey) -> Bool {
        pruneCompletedRequests()
        return completedRequests[key] != nil
    }

    func retainPolicies(for sessions: Set<AgentSessionInstanceID>) {
        approvalPolicies = approvalPolicies.filter { sessions.contains($0.key.session) }
    }

    func clearPolicies() {
        approvalPolicies.removeAll()
    }

    func clearPolicies(for provider: AgentProvider) {
        approvalPolicies = approvalPolicies.filter {
            $0.key.session.sessionID.provider != provider
        }
    }

    func cancelAll() {
        for key in Array(continuations.keys) {
            finish(key, decision: nil)
        }
        deliveringRequests.removeAll()
        deliveryDecisions.removeAll()
        deliveryFailures.removeAll()
    }

    private func finish(
        _ key: AgentApprovalControlKey,
        decision: AgentBridgePermissionDecision?
    ) {
        if let request = pendingRequests[key] {
            completedRequests[key] = request.expiresAt
        }
        expirationTasks.removeValue(forKey: key)?.cancel()
        pendingRequests.removeValue(forKey: key)
        deliveringRequests.removeValue(forKey: key)
        deliveryDecisions.removeValue(forKey: key)
        deliveryFailures.removeValue(forKey: key)
        continuations.removeValue(forKey: key)?.resume(returning: decision)
    }

    private func pruneCompletedRequests() {
        let current = now()
        completedRequests = completedRequests.filter { $0.value > current }
    }
}
