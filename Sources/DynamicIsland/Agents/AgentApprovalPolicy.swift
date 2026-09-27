import Foundation

enum AgentApprovalPolicyChoice: String, CaseIterable, Equatable, Sendable {
    case askEveryTime
    case allowTurn
    case allowSession
}

enum AgentApprovalPolicyMode: Equatable, Sendable {
    case askEveryTime
    case allowTurn(turnID: String)
    case allowSession

    var displayName: String {
        switch self {
        case .askEveryTime: "Ask every time"
        case .allowTurn: "Allow this turn"
        case .allowSession: "Allow this session"
        }
    }

    var isAutomatic: Bool {
        self != .askEveryTime
    }
}

struct AgentApprovalPolicyKey: Hashable, Sendable {
    let session: AgentSessionInstanceID
}

struct AgentApprovalPolicyState: Equatable, Sendable {
    let key: AgentApprovalPolicyKey
    var mode: AgentApprovalPolicyMode
}

enum AgentApprovalPolicyDecision: Equatable, Sendable {
    case manual
    case allowAutomatically
}

enum AgentApprovalPolicyEvaluator {
    static func decision(
        policy: AgentApprovalPolicyState?,
        provider: AgentProvider,
        session: AgentSessionInstanceID,
        turnID: String,
        supportsApprovalControl: Bool,
        requestIsCurrent: Bool
    ) -> AgentApprovalPolicyDecision {
        guard supportsApprovalControl,
              requestIsCurrent,
              session.sessionID.provider == provider,
              let policy,
              policy.key.session == session else {
            return .manual
        }

        switch policy.mode {
        case .askEveryTime:
            return .manual
        case .allowTurn(let allowedTurnID):
            return allowedTurnID == turnID ? .allowAutomatically : .manual
        case .allowSession:
            return .allowAutomatically
        }
    }
}
