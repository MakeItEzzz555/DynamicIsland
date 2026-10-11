import CoreGraphics

/// Intrinsic interaction requirements. Informational activity hover keeps its size.
enum CollapsedActivityHoverPolicy: Equatable {
    static let agentApprovalHeight: CGFloat = 68

    case none
    case peek
    case interactive(requiredHeight: CGFloat)

    static func resolve(kind: DynamicIslandLiveActivityKind?, exactMessageReply: Bool = false,
                        exactAgentApproval: Bool = false, authorizedCallControls: Bool = false) -> Self {
        if exactAgentApproval { return .interactive(requiredHeight: agentApprovalHeight) }
        switch kind {
        case .message: return exactMessageReply ? .interactive(requiredHeight: 128) : .peek
        case .call: return authorizedCallControls ? .interactive(requiredHeight: 68) : .none
        default: return .none
        }
    }

    func isActive(hoverVisible: Bool, interactionPinned: Bool, focused: Bool, sending: Bool) -> Bool {
        self != .none && (hoverVisible || (interactionPinned && (focused || sending)))
    }

    func frame(from base: CGRect) -> CGRect {
        let height: CGFloat
        switch self {
        case .none: return base
        case .peek: height = base.height + 92
        case .interactive(let requiredHeight): height = base.height + requiredHeight
        }
        let width = max(base.width, 320)
        return CGRect(x: base.midX - width / 2, y: base.maxY - height, width: width, height: height)
    }
}
