import Foundation

public enum IslandPresentationState: String, Equatable {
    case collapsed
    case peek
    case expanded
    case dragReceiving
    case pinned
}

@MainActor
public final class IslandStateStore: ObservableObject {
    @Published public private(set) var state: IslandPresentationState = .collapsed
    private var collapseTask: Task<Void, Never>?

    public init() {}

    public var isExpandedSurfaceVisible: Bool {
        state == .expanded || state == .dragReceiving || state == .pinned
    }

    public func hoverEntered(delay: TimeInterval) {
        guard state == .collapsed else { return }
        collapseTask?.cancel()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await MainActor.run {
                if self?.state == .collapsed {
                    self?.state = .peek
                }
            }
        }
    }

    public func hoverExited(autoCollapseDelay: TimeInterval) {
        guard state == .peek || state == .expanded else { return }
        scheduleCollapse(after: autoCollapseDelay)
    }

    public func toggleExpanded() {
        collapseTask?.cancel()
        switch state {
        case .collapsed, .peek:
            state = .expanded
        case .expanded:
            state = .pinned
        case .pinned, .dragReceiving:
            state = .collapsed
        }
    }

    public func collapseFromOutsideClick() {
        guard state != .pinned else { return }
        state = .collapsed
    }

    public func dragEntered() {
        collapseTask?.cancel()
        state = .dragReceiving
    }

    public func dragEnded() {
        state = .expanded
    }

    public func pin() {
        collapseTask?.cancel()
        state = .pinned
    }

    public func collapse() {
        collapseTask?.cancel()
        state = .collapsed
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await MainActor.run {
                guard let self, self.state != .pinned else { return }
                self.state = .collapsed
            }
        }
    }
}
