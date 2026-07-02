import Foundation

public enum IslandPresentationState: String, Equatable, Sendable {
    case collapsed
    case expanded
}

@MainActor
public final class IslandStateStore: ObservableObject {
    @Published public private(set) var state: IslandPresentationState = .collapsed

    public init() {}

    public var isExpandedSurfaceVisible: Bool {
        state == .expanded
    }

    public func toggleExpanded() {
        switch state {
        case .collapsed:
            state = .expanded
        case .expanded:
            state = .collapsed
        }
    }

    public func collapseFromOutsideClick() {
        state = .collapsed
    }

    public func collapse() {
        state = .collapsed
    }
}
