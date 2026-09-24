import Foundation

protocol CountdownClock: Sendable {
    var now: Duration { get }
    func sleep(for duration: Duration) async throws
}

struct SystemCountdownClock: CountdownClock {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    init() {
        origin = clock.now
    }

    var now: Duration {
        origin.duration(to: clock.now)
    }

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}

enum CountdownLifecycleEvent: Equatable {
    case scheduled(generation: UInt64, remaining: Duration)
    case cancelled(generation: UInt64)
    case completed(generation: UInt64)
}

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

    private let clock: any CountdownClock
    private let refreshInterval: Duration?
    private let onCompletion: @MainActor () -> Void
    private var lifecycleHandler: @MainActor (CountdownLifecycleEvent) -> Void = { _ in }
    private var task: Task<Void, Never>?
    private(set) var currentGeneration: UInt64 = 0
    private var activeGeneration: UInt64?
    private var deadline: Duration?
    private var preciseRemaining: Duration = .zero
    private var completionHandled = false

    init(
        clock: any CountdownClock = SystemCountdownClock(),
        refreshInterval: Duration? = .seconds(1),
        onCompletion: @escaping @MainActor () -> Void = {}
    ) {
        self.clock = clock
        self.refreshInterval = refreshInterval
        self.onCompletion = onCompletion
    }

    var displayText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func setLifecycleHandler(
        _ handler: @escaping @MainActor (CountdownLifecycleEvent) -> Void
    ) {
        lifecycleHandler = handler
    }

    func start(minutes: Int) {
        start(seconds: max(1, minutes * 60))
    }

    func start(seconds: Int) {
        invalidateCurrentRun()
        let duration = Duration.seconds(max(1, seconds))
        totalSeconds = Self.displaySeconds(for: duration)
        preciseRemaining = duration
        remainingSeconds = totalSeconds
        deadline = clock.now + duration
        completionHandled = false
        isRunning = true
        activeGeneration = currentGeneration
        lifecycleHandler(.scheduled(generation: currentGeneration, remaining: duration))
        runCountdown(generation: currentGeneration)
    }

    func pause() {
        guard isRunning else { return }
        refresh(generation: currentGeneration)
        guard isRunning else { return }
        invalidateCurrentRun()
        deadline = nil
        isRunning = false
    }

    func resume() {
        guard !isRunning, remainingSeconds > 0 else { return }
        invalidateCurrentRun()
        deadline = clock.now + preciseRemaining
        completionHandled = false
        isRunning = true
        activeGeneration = currentGeneration
        lifecycleHandler(.scheduled(generation: currentGeneration, remaining: preciseRemaining))
        runCountdown(generation: currentGeneration)
    }

    func reset() {
        invalidateCurrentRun()
        deadline = nil
        preciseRemaining = .seconds(totalSeconds)
        remainingSeconds = totalSeconds
        completionHandled = false
        isRunning = false
    }

    func stop() {
        invalidateCurrentRun()
        deadline = nil
        preciseRemaining = .zero
        remainingSeconds = 0
        completionHandled = false
        isRunning = false
    }

    func refresh() {
        refresh(generation: currentGeneration)
    }

    func refresh(generation: UInt64) {
        guard generation == currentGeneration,
              isRunning,
              let deadline else { return }
        let remaining = deadline - clock.now
        guard remaining > .zero else {
            complete(generation: generation)
            return
        }
        preciseRemaining = remaining
        remainingSeconds = Self.displaySeconds(for: remaining)
    }

    private func runCountdown(generation: UInt64) {
        guard let refreshInterval else { return }
        task = Task { [weak self, clock] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: refreshInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.refresh(generation: generation)
                guard self.isRunning, generation == self.currentGeneration else { return }
            }
        }
    }

    private func complete(generation: UInt64) {
        guard generation == currentGeneration, isRunning, !completionHandled else { return }
        completionHandled = true
        task?.cancel()
        task = nil
        deadline = nil
        preciseRemaining = .zero
        remainingSeconds = 0
        isRunning = false
        activeGeneration = nil
        lifecycleHandler(.completed(generation: generation))
        onCompletion()
    }

    private func invalidateCurrentRun() {
        task?.cancel()
        task = nil
        if let activeGeneration {
            lifecycleHandler(.cancelled(generation: activeGeneration))
            self.activeGeneration = nil
        }
        currentGeneration &+= 1
    }

    private static func displaySeconds(for duration: Duration) -> Int {
        let components = duration.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return max(0, Int(ceil(seconds)))
    }
}
