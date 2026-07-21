import Foundation

enum TimerProgressColorStage: Equatable {
    case high
    case mid
    case low
}

enum TimerProgressFormatting {
    static func progress(remainingSeconds: Int, totalSeconds: Int) -> Double {
        guard totalSeconds > 0 else { return 1 }
        return min(max(Double(remainingSeconds) / Double(totalSeconds), 0), 1)
    }

    static func colorStage(progress: Double) -> TimerProgressColorStage {
        let clampedProgress = min(max(progress, 0), 1)
        if clampedProgress > 0.5 {
            return .high
        }
        if clampedProgress > 0.18 {
            return .mid
        }
        return .low
    }
}

@MainActor
final class TimerController: ObservableObject {
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var totalSeconds = 0
    @Published private(set) var isRunning = false

    private var task: Task<Void, Never>?

    var displayText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func start(minutes: Int) {
        task?.cancel()
        totalSeconds = max(1, minutes * 60)
        remainingSeconds = totalSeconds
        isRunning = true
        runCountdown()
    }

    func pause() {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        isRunning = false
    }

    func resume() {
        guard !isRunning, remainingSeconds > 0 else { return }
        isRunning = true
        runCountdown()
    }

    func reset() {
        task?.cancel()
        task = nil
        remainingSeconds = totalSeconds
        isRunning = false
    }

    func stop() {
        task?.cancel()
        task = nil
        remainingSeconds = 0
        isRunning = false
    }

    private func runCountdown() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
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
}
