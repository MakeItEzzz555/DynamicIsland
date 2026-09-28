import Combine
import Foundation

@MainActor
final class AgentActivityGlowCoordinator: ObservableObject {
    @Published private(set) var provider: AgentProvider?

    private let lingerDuration: TimeInterval
    private var clearTask: Task<Void, Never>?

    init(lingerDuration: TimeInterval = 4.0) {
        self.lingerDuration = max(0, lingerDuration)
    }

    func update(activeProvider: AgentProvider?) {
        clearTask?.cancel()
        clearTask = nil

        if let activeProvider {
            provider = activeProvider
            return
        }

        guard provider != nil else { return }
        clearTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(lingerDuration))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.provider = nil
                self.clearTask = nil
            }
        }
    }

    func stop() {
        clearTask?.cancel()
        clearTask = nil
        provider = nil
    }
}
