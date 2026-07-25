import Combine

enum IslandOverlayPresentation: Equatable {
    case clipboardHistory
}

enum IslandEscapeRoute: Equatable {
    case dismissPresentation
    case collapseIsland
    case passThrough
}

struct IslandEscapeRoutingPolicy {
    static func route(
        islandState: IslandPresentationState,
        topmostPresentation: IslandOverlayPresentation?
    ) -> IslandEscapeRoute {
        guard islandState == .expanded else {
            return .passThrough
        }
        return topmostPresentation == nil
            ? .collapseIsland
            : .dismissPresentation
    }
}

@MainActor
final class IslandEscapeRouter: ObservableObject {
    @Published private(set) var topmostPresentation: IslandOverlayPresentation?
    @Published private(set) var dismissalRequestGeneration = 0

    func setTopmostPresentation(_ presentation: IslandOverlayPresentation?) {
        guard presentation != topmostPresentation else { return }
        topmostPresentation = presentation
    }

    @discardableResult
    func requestDismissTopmost() -> Bool {
        guard topmostPresentation != nil else { return false }
        dismissalRequestGeneration += 1
        return true
    }
}
