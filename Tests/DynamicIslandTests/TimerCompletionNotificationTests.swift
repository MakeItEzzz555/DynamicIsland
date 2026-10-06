import XCTest
@testable import DynamicIsland

@MainActor
private final class MockTimerNotificationCenterClient: TimerNotificationCenterClient {
    enum TestError: Error {
        case schedulingFailed
    }

    var status: TimerNotificationAuthorizationStatus = .authorized
    var authorizationResult = true
    var addError: Error?
    var beforeAddReturns: (() -> Void)?
    private(set) var authorizationRequestCount = 0
    private(set) var addedRequests: [TimerCompletionNotificationRequest] = []
    private(set) var removedIdentifierBatches: [[String]] = []

    func authorizationStatus() async -> TimerNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return authorizationResult
    }

    func add(_ request: TimerCompletionNotificationRequest) async throws {
        beforeAddReturns?()
        if let addError {
            throw addError
        }
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifierBatches.append(identifiers)
    }
}

@MainActor
final class TimerCompletionNotificationTests: XCTestCase {
    private let enabledPreferences = TimerCompletionNotificationPreferences(
        notificationsEnabled: true,
        soundEnabled: true
    )

    func testStartSchedulesExactlyOneCompletionNotification() async {
        let (timer, _, coordinator, client) = makeSystem()

        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()

        XCTAssertEqual(client.addedRequests.count, 1)
        XCTAssertEqual(client.addedRequests[0].delay, 10, accuracy: 0.000_001)
    }

    func testPauseCancelsPendingCompletionNotification() async throws {
        let (timer, _, coordinator, client) = makeSystem()
        timer.start(seconds: 30)
        await coordinator.waitForPendingWork()
        let identifier = try XCTUnwrap(client.addedRequests.first?.identifier)

        timer.pause()

        XCTAssertEqual(client.removedIdentifierBatches, [[identifier]])
    }

    func testResumeSchedulesReplacementUsingFrozenRemainingTime() async {
        let (timer, clock, coordinator, client) = makeSystem()
        timer.start(seconds: 30)
        await coordinator.waitForPendingWork()
        clock.advance(by: .seconds(8))
        timer.pause()
        clock.advance(by: .seconds(100))

        timer.resume()
        await coordinator.waitForPendingWork()

        XCTAssertEqual(client.addedRequests.count, 2)
        XCTAssertEqual(client.addedRequests[1].delay, 22, accuracy: 0.000_001)
        XCTAssertNotEqual(client.addedRequests[0].identifier, client.addedRequests[1].identifier)
    }

    func testResetRemovesPendingCompletionNotification() async throws {
        let (timer, _, coordinator, client) = makeSystem()
        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()
        let identifier = try XCTUnwrap(client.addedRequests.first?.identifier)

        timer.reset()

        XCTAssertEqual(client.removedIdentifierBatches, [[identifier]])
        XCTAssertEqual(timer.remainingSeconds, 10)
        XCTAssertFalse(timer.isRunning)
    }

    func testStopRemovesPendingCompletionNotification() async throws {
        let (timer, _, coordinator, client) = makeSystem()
        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()
        let identifier = try XCTUnwrap(client.addedRequests.first?.identifier)

        timer.stop()

        XCTAssertEqual(client.removedIdentifierBatches, [[identifier]])
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertFalse(timer.isRunning)
    }

    func testReplacementCancelsOnlyStaleTimerOwnedNotification() async throws {
        let (timer, _, coordinator, client) = makeSystem()
        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()
        let firstIdentifier = try XCTUnwrap(client.addedRequests.first?.identifier)

        timer.start(seconds: 20)
        await coordinator.waitForPendingWork()

        XCTAssertEqual(client.addedRequests.count, 2)
        XCTAssertEqual(client.removedIdentifierBatches, [[firstIdentifier]])
        XCTAssertNotEqual(firstIdentifier, client.addedRequests[1].identifier)
    }

    func testPauseDuringSchedulingRemovesLateStaleRequest() async throws {
        let client = MockTimerNotificationCenterClient()
        let (timer, _, coordinator, _) = makeSystem(client: client)
        client.beforeAddReturns = { [weak timer] in
            timer?.pause()
        }

        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()

        let identifier = try XCTUnwrap(client.addedRequests.first?.identifier)
        XCTAssertEqual(client.removedIdentifierBatches, [[identifier], [identifier]])
        XCTAssertFalse(timer.isRunning)
    }

    func testDeniedAuthorizationDoesNotBreakTimerOperation() async {
        let client = MockTimerNotificationCenterClient()
        client.status = .denied
        let (timer, clock, coordinator, _) = makeSystem(client: client)

        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()
        clock.advance(by: .seconds(10))
        timer.refresh()

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertFalse(timer.isRunning)
    }

    func testSchedulingFailureDoesNotCorruptTimerState() async {
        let client = MockTimerNotificationCenterClient()
        client.addError = MockTimerNotificationCenterClient.TestError.schedulingFailed
        let (timer, clock, coordinator, _) = makeSystem(client: client)

        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()
        clock.advance(by: .seconds(1))
        timer.refresh()

        XCTAssertEqual(timer.remainingSeconds, 9)
        XCTAssertTrue(timer.isRunning)
    }

    func testCompletionNotificationUsesSystemSoundConfiguration() async {
        let (timer, _, coordinator, client) = makeSystem()

        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()

        XCTAssertEqual(client.addedRequests.first?.title, "Timer Finished")
        XCTAssertEqual(client.addedRequests.first?.body, "Your timer has finished.")
        XCTAssertEqual(client.addedRequests.first?.includesSound, true)
    }

    func testRepeatedRefreshesDoNotScheduleDuplicateNotifications() async {
        let (timer, clock, coordinator, client) = makeSystem()
        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()

        clock.advance(by: .seconds(1))
        timer.refresh()
        timer.refresh()
        timer.refresh()
        await coordinator.waitForPendingWork()

        XCTAssertEqual(client.addedRequests.count, 1)
    }

    func testNotDeterminedAuthorizationIsRequestedOnceForOneSchedule() async {
        let client = MockTimerNotificationCenterClient()
        client.status = .notDetermined
        let (timer, _, coordinator, _) = makeSystem(client: client)

        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()

        XCTAssertEqual(client.authorizationRequestCount, 1)
        XCTAssertEqual(client.addedRequests.count, 1)
    }

    func testDisabledNotificationsDoNotRequestAuthorizationOrSchedule() async {
        let client = MockTimerNotificationCenterClient()
        client.status = .notDetermined
        let clock = ManualCountdownClock()
        let timer = TimerController(clock: clock, refreshInterval: nil)
        let coordinator = TimerCompletionNotificationCoordinator(
            client: client,
            sessionIdentifier: "test-session"
        )
        timer.setLifecycleHandler { [weak coordinator] event in
            coordinator?.handle(
                event,
                preferences: TimerCompletionNotificationPreferences(
                    notificationsEnabled: false,
                    soundEnabled: true
                )
            )
        }

        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()

        XCTAssertEqual(client.authorizationRequestCount, 0)
        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertTrue(timer.isRunning)
    }

    func testSoundCanBeDisabledForNativeNotification() async {
        let client = MockTimerNotificationCenterClient()
        let clock = ManualCountdownClock()
        let timer = TimerController(clock: clock, refreshInterval: nil)
        let coordinator = TimerCompletionNotificationCoordinator(
            client: client,
            sessionIdentifier: "test-session"
        )
        timer.setLifecycleHandler { [weak coordinator] event in
            coordinator?.handle(
                event,
                preferences: TimerCompletionNotificationPreferences(
                    notificationsEnabled: true,
                    soundEnabled: false
                )
            )
        }

        timer.start(seconds: 10)
        await coordinator.waitForPendingWork()

        XCTAssertEqual(client.addedRequests.first?.includesSound, false)
    }

    private var localChimes = 0

    private func makeSystem(
        client: MockTimerNotificationCenterClient = MockTimerNotificationCenterClient(),
        preferences: TimerCompletionNotificationPreferences? = nil
    ) -> (
        timer: TimerController,
        clock: ManualCountdownClock,
        coordinator: TimerCompletionNotificationCoordinator,
        client: MockTimerNotificationCenterClient
    ) {
        let clock = ManualCountdownClock()
        let timer = TimerController(clock: clock, refreshInterval: nil)
        localChimes = 0
        let coordinator = TimerCompletionNotificationCoordinator(
            client: client,
            sessionIdentifier: "test-session",
            playLocalChime: { [weak self] in self?.localChimes += 1 }
        )
        let preferences = preferences ?? enabledPreferences
        timer.setLifecycleHandler { [weak coordinator] event in
            coordinator?.handle(event, preferences: preferences)
        }
        return (timer, clock, coordinator, client)
    }

    // MARK: Exactly one completion sound

    private func runToCompletion(_ system: (timer: TimerController, clock: ManualCountdownClock,
                                            coordinator: TimerCompletionNotificationCoordinator,
                                            client: MockTimerNotificationCenterClient)) async {
        system.timer.start(seconds: 5)
        await system.coordinator.waitForPendingWork()
        system.clock.advance(by: .seconds(5))
        system.timer.refresh()
    }

    func testScheduledNotificationOwnsTheSoundSoNoLocalChime() async {
        let system = makeSystem()
        await runToCompletion(system)
        XCTAssertEqual(system.client.addedRequests.map(\.includesSound), [true])
        XCTAssertEqual(localChimes, 0, "no double sound")
    }

    func testSoundWithoutNotificationsPlaysOneLocalChime() async {
        let system = makeSystem(preferences: .init(notificationsEnabled: false, soundEnabled: true))
        await runToCompletion(system)
        XCTAssertTrue(system.client.addedRequests.isEmpty, "no banner, no permission needed")
        XCTAssertEqual(localChimes, 1)
    }

    func testDeniedNotificationsStillChimeOnce() async {
        let client = MockTimerNotificationCenterClient()
        client.status = .denied
        let system = makeSystem(client: client)
        await runToCompletion(system)
        XCTAssertEqual(localChimes, 1)
    }

    func testSoundOffIsSilentAndCancelledTimersNeverChime() async {
        let system = makeSystem(preferences: .init(notificationsEnabled: false, soundEnabled: false))
        await runToCompletion(system)
        XCTAssertEqual(localChimes, 0)
        let other = makeSystem(preferences: .init(notificationsEnabled: false, soundEnabled: true))
        other.timer.start(seconds: 5)
        other.timer.pause()
        other.clock.advance(by: .seconds(10))
        other.timer.refresh()
        XCTAssertEqual(localChimes, 0)
        XCTAssertEqual(TimerCompletionNotificationCoordinator.localChimeName, "Glass")
    }
}
