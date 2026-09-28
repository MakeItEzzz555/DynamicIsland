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

enum AgentApprovalDeliveryState: Equatable, Sendable {
    case awaitingDecision
    case submitting(AgentBridgePermissionDecision)
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
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func request(
        _ request: AgentApprovalControlRequest,
        maximumWait: Duration = .seconds(75)
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
                let remaining = max(0, request.expiresAt.timeIntervalSince(now()))
                let expiryWait = min(maximumWait, .milliseconds(Int64(remaining * 1_000)))
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
        guard let request = pendingRequests[key], request.expiresAt > now() else {
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
        if let decision = deliveryDecisions[key] { return .submitting(decision) }
        return pendingRequests[key] == nil ? nil : .awaitingDecision
    }

    func confirmDelivery(_ key: AgentApprovalControlKey) {
        deliveringRequests.removeValue(forKey: key)
        deliveryDecisions.removeValue(forKey: key)
    }

    func failDelivery(_ key: AgentApprovalControlKey) {
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
        continuations.removeValue(forKey: key)?.resume(returning: decision)
    }

    private func pruneCompletedRequests() {
        let current = now()
        completedRequests = completedRequests.filter { $0.value > current }
    }
}
