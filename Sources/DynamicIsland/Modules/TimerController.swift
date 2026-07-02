import Foundation

@MainActor
final class TimerController: ObservableObject {
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var isRunning = false

    private var task: Task<Void, Never>?

    var displayText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func start(minutes: Int) {
        task?.cancel()
        remainingSeconds = max(1, minutes * 60)
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    guard let self, self.isRunning else { return }
                    self.remainingSeconds -= 1
                    if self.remainingSeconds <= 0 {
                        self.stop()
                    }
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        remainingSeconds = 0
        isRunning = false
    }
}
