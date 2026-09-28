import Foundation

enum AgentApprovalPolicyChoice: String, CaseIterable, Equatable, Sendable {
    case askEveryTime
    case autoApprove
}

enum AgentApprovalPolicyMode: Equatable, Sendable {
    case askEveryTime
    case autoApprove

    var displayName: String {
        switch self {
        case .askEveryTime: "Ask every time"
        case .autoApprove: "Auto approve"
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
