import Foundation
import XCTest
@testable import DynamicIsland

final class ManualCountdownClock: CountdownClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero

    var now: Duration {
        lock.withLock { current }
    }

    func advance(by duration: Duration) {
        lock.withLock { current += duration }
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
    }
}

final class TimerControllerTests: XCTestCase {
    @MainActor
    func testNormalProgressionUsesElapsedTime() {
        let (timer, clock) = makeTimer()
        timer.start(seconds: 10)

        clock.advance(by: .seconds(1))
        timer.refresh()

        XCTAssertEqual(timer.remainingSeconds, 9)
        XCTAssertTrue(timer.isRunning)
    }

    @MainActor
    func testDelayedRefreshCatchesUpImmediately() {
        let (timer, clock) = makeTimer()
        timer.start(seconds: 10)

        clock.advance(by: .milliseconds(4_250))
        timer.refresh()

        XCTAssertEqual(timer.remainingSeconds, 6)
    }

    @MainActor
    func testRefreshAfterDeadlineCompletesImmediately() {
        var completions = 0
        let (timer, clock) = makeTimer { completions += 1 }
        timer.start(seconds: 10)

        clock.advance(by: .seconds(15))
        timer.refresh()

        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testPauseFreezesPreciseRemainingDuration() {
        let (timer, clock) = makeTimer()
        timer.start(seconds: 30)
        clock.advance(by: .seconds(8))

        timer.pause()
        clock.advance(by: .seconds(100))
        timer.refresh()

        XCTAssertEqual(timer.remainingSeconds, 22)
        XCTAssertFalse(timer.isRunning)
    }

    @MainActor
    func testResumeEstablishesNewDeadlineFromPausedRemainder() {
        let (timer, clock) = makeTimer()
        timer.start(seconds: 30)
        clock.advance(by: .seconds(8))
        timer.pause()
        clock.advance(by: .seconds(100))

        timer.resume()
        clock.advance(by: .seconds(2))
        timer.refresh()

        XCTAssertEqual(timer.remainingSeconds, 20)
        XCTAssertTrue(timer.isRunning)
    }

    @MainActor
    func testCompletionOccursExactlyOnce() {
        var completions = 0
        let (timer, clock) = makeTimer { completions += 1 }
        timer.start(seconds: 2)
        clock.advance(by: .seconds(3))

        timer.refresh()
        timer.refresh()
        timer.refresh()

        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testRestartRejectsStaleGenerationRefresh() {
        let (timer, clock) = makeTimer()
        timer.start(seconds: 10)
        let staleGeneration = timer.currentGeneration
        timer.start(seconds: 20)
        clock.advance(by: .seconds(2))

        timer.refresh(generation: staleGeneration)

        XCTAssertEqual(timer.remainingSeconds, 20)
        timer.refresh()
        XCTAssertEqual(timer.remainingSeconds, 18)
    }

    @MainActor
    func testResetRejectsStaleGenerationCompletion() {
        var completions = 0
        let (timer, clock) = makeTimer { completions += 1 }
        timer.start(seconds: 10)
        let staleGeneration = timer.currentGeneration
        timer.reset()
        clock.advance(by: .seconds(20))

        timer.refresh(generation: staleGeneration)

        XCTAssertEqual(timer.remainingSeconds, 10)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(completions, 0)
    }

    @MainActor
    func testPositiveFractionRoundsUpUntilDeadline() {
        var completions = 0
        let (timer, clock) = makeTimer { completions += 1 }
        timer.start(seconds: 1)

        clock.advance(by: .milliseconds(999))
        timer.refresh()
        XCTAssertEqual(timer.remainingSeconds, 1)
        XCTAssertTrue(timer.isRunning)

        clock.advance(by: .milliseconds(1))
        timer.refresh()
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    private func makeTimer(
        onCompletion: @escaping @MainActor () -> Void = {}
    ) -> (TimerController, ManualCountdownClock) {
        let clock = ManualCountdownClock()
        let timer = TimerController(
            clock: clock,
            refreshInterval: nil,
            onCompletion: onCompletion
        )
        return (timer, clock)
    }
}
