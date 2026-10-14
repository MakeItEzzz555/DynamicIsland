import CoreGraphics

/// Intrinsic interaction requirements. Informational activity hover keeps its size.
enum CollapsedActivityHoverPolicy: Equatable {
    static let agentApprovalHeight: CGFloat = 68

    case none
    case peek
    case interactive(requiredHeight: CGFloat)
    /// Read-only activity preview (media, battery, timer, agent) that grows
    /// the shell downward by exactly its content height.
    case activityPreview(height: CGFloat)

    static func resolve(kind: DynamicIslandLiveActivityKind?, exactMessageReply: Bool = false,
                        exactAgentApproval: Bool = false, authorizedCallControls: Bool = false,
                        activityPreview: CollapsedActivityPreview? = nil) -> Self {
        if exactAgentApproval { return .interactive(requiredHeight: agentApprovalHeight) }
        switch kind {
        case .message: return exactMessageReply ? .interactive(requiredHeight: 128) : .peek
        case .call: return authorizedCallControls ? .interactive(requiredHeight: 68) : .none
        default: return activityPreview.map { .activityPreview(height: $0.height) } ?? .none
        }
    }

    func isActive(hoverVisible: Bool, interactionPinned: Bool, focused: Bool, sending: Bool) -> Bool {
        self != .none && (hoverVisible || (interactionPinned && (focused || sending)))
    }

    func allowsAutomaticExpansion(enabled: Bool) -> Bool {
        enabled && self == .none
    }

    func frame(from base: CGRect) -> CGRect {
        let height: CGFloat
        switch self {
        case .none: return base
        case .peek: height = base.height + 92
        case .interactive(let requiredHeight): height = base.height + requiredHeight
        case .activityPreview(let previewHeight): height = base.height + previewHeight
        }
        let width = max(base.width, 300)
        return CGRect(x: base.midX - width / 2, y: base.maxY - height, width: width, height: height)
    }
}
