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

@MainActor
final class AgentApprovalController: ObservableObject {
    @Published private(set) var pendingRequests: [AgentApprovalControlKey: AgentApprovalControlRequest] = [:]

    private var continuations: [AgentApprovalControlKey: CheckedContinuation<AgentBridgePermissionDecision?, Never>] = [:]
    private var expirationTasks: [AgentApprovalControlKey: Task<Void, Never>] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func request(
        _ request: AgentApprovalControlRequest,
        maximumWait: Duration = .seconds(75)
    ) async -> AgentBridgePermissionDecision? {
        guard request.expiresAt > now(), continuations[request.key] == nil else { return nil }
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
        finish(key, decision: decision)
        return .accepted
    }

    func pendingRequest(for session: AgentSessionInstanceID) -> AgentApprovalControlRequest? {
        pendingRequests.values
            .filter { $0.key.session == session && $0.expiresAt > now() }
            .sorted { $0.expiresAt < $1.expiresAt }
            .first
    }

    func cancelAll() {
        for key in Array(continuations.keys) {
            finish(key, decision: nil)
        }
    }

    private func finish(
        _ key: AgentApprovalControlKey,
        decision: AgentBridgePermissionDecision?
    ) {
        expirationTasks.removeValue(forKey: key)?.cancel()
        pendingRequests.removeValue(forKey: key)
        continuations.removeValue(forKey: key)?.resume(returning: decision)
    }
}
