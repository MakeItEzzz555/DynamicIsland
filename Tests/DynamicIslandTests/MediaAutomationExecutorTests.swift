import AppKit
import Combine
import XCTest
@testable import DynamicIsland

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func read() -> Value {
        lock.withLock { value }
    }

    @discardableResult
    func update<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&value) }
    }
}

@MainActor
private final class EmptyMediaDetectionProvider: MediaDetectionProvider {
    let name = "Test"

    func snapshot() async -> MediaSnapshot? { nil }
}

@MainActor
private final class SequenceMediaDetectionProvider: MediaDetectionProvider {
    let name = "Test"
    private var snapshots: [MediaSnapshot]
    private var index = 0

    init(_ snapshots: [MediaSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() async -> MediaSnapshot? {
        guard !snapshots.isEmpty else { return nil }
        let snapshot = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return snapshot
    }
}

final class MediaAutomationExecutorTests: XCTestCase {
    @MainActor
    func testDelayedAutomationDoesNotBlockMainActor() async {
        let started = expectation(description: "automation started")
        let finished = expectation(description: "automation finished")
        let release = DispatchSemaphore(value: 0)
        let executor = MediaAutomationExecutor(runner: { _, _ in
            started.fulfill()
            release.wait()
            return Self.success()
        })

        executor.submitCommand(Self.operation("held")) { _ in
            finished.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)

        var mainActorAdvanced = false
        await Task { @MainActor in
            mainActorAdvanced = true
        }.value
        XCTAssertTrue(mainActorAdvanced)

        release.signal()
        await fulfillment(of: [finished], timeout: 2)
    }

    func testTransportCommandsExecuteInSubmissionOrder() async {
        let finished = expectation(description: "all commands finished")
        finished.expectedFulfillmentCount = 3
        let executed = LockedValues<[String]>([])
        let executor = MediaAutomationExecutor(runner: { source, _ in
            executed.update { $0.append(source) }
            return Self.success()
        })

        for command in ["next", "next", "previous"] {
            executor.submitCommand(Self.operation(command)) { _ in
                finished.fulfill()
            }
        }

        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(executed.read(), ["next", "next", "previous"])
    }

    func testCommandsRunBeforeQueuedDetectionWork() async {
        let blockerStarted = expectation(description: "blocker started")
        let finished = expectation(description: "work finished")
        finished.expectedFulfillmentCount = 2
        let release = DispatchSemaphore(value: 0)
        let executed = LockedValues<[String]>([])
        let executor = MediaAutomationExecutor(runner: { source, _ in
            executed.update { $0.append(source) }
            if source == "blocker" {
                blockerStarted.fulfill()
                release.wait()
            }
            return Self.success()
        })

        executor.submitCommand(Self.operation("blocker"))
        await fulfillment(of: [blockerStarted], timeout: 2)
        executor.submitDetection(Self.detectionRequest()) { _ in finished.fulfill() }
        executor.submitCommand(Self.operation("urgent")) { _ in finished.fulfill() }
        release.signal()

        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(executed.read(), ["blocker", "urgent", "spotify", "music"])
    }

    func testCommandQueueRejectsWorkBeyondConfiguredBound() async {
        let blockerStarted = expectation(description: "blocker started")
        let acceptedFinished = expectation(description: "accepted commands finished")
        acceptedFinished.expectedFulfillmentCount = 2
        let rejected = expectation(description: "overflow rejected")
        let release = DispatchSemaphore(value: 0)
        let executor = MediaAutomationExecutor(
            maximumPendingCommands: 2,
            runner: { source, _ in
                if source == "blocker" {
                    blockerStarted.fulfill()
                    release.wait()
                }
                return Self.success()
            }
        )

        executor.submitCommand(Self.operation("blocker"))
        await fulfillment(of: [blockerStarted], timeout: 2)
        executor.submitCommand(Self.operation("one")) { _ in acceptedFinished.fulfill() }
        executor.submitCommand(Self.operation("two")) { _ in acceptedFinished.fulfill() }
        executor.submitCommand(Self.operation("three")) { result in
            XCTAssertEqual(result.failure, .queueFull)
            rejected.fulfill()
        }

        await fulfillment(of: [rejected], timeout: 2)
        release.signal()
        await fulfillment(of: [acceptedFinished], timeout: 2)
    }

    func testTimeoutIsFailureAndFollowingCommandRecovers() async {
        let finished = expectation(description: "both commands finished")
        finished.expectedFulfillmentCount = 2
        let results = LockedValues<[MediaAutomationScriptResult]>([])
        let executor = MediaAutomationExecutor(runner: { source, _ in
            source == "timeout"
                ? MediaAutomationScriptResult(output: "", failure: .timedOut)
                : Self.success(output: "healthy")
        })

        executor.submitCommand(Self.operation("timeout")) { result in
            results.update { $0.append(result) }
            finished.fulfill()
        }
        executor.submitCommand(Self.operation("healthy")) { result in
            results.update { $0.append(result) }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(results.read(), [
            MediaAutomationScriptResult(output: "", failure: .timedOut),
            Self.success(output: "healthy")
        ])
    }

    func testDetectionBackoffIsPerTargetAndResetsAfterSuccess() async {
        let time = LockedValues<TimeInterval>(0)
        let spotifyAttempts = LockedValues(0)
        let musicAttempts = LockedValues(0)
        let executor = MediaAutomationExecutor(
            backoff: MediaAutomationBackoff(initialDelay: 2, maximumDelay: 8),
            clock: { time.read() },
            runner: { source, _ in
                if source == "spotify" {
                    let attempt = spotifyAttempts.update { value -> Int in
                        value += 1
                        return value
                    }
                    return attempt == 1
                        ? MediaAutomationScriptResult(output: "", failure: .timedOut)
                        : Self.success(output: "spotify-ok")
                }
                musicAttempts.update { $0 += 1 }
                return Self.success(output: "music-ok")
            }
        )

        let first = await detection(using: executor)
        let second = await detection(using: executor)
        time.update { $0 = 2 }
        let third = await detection(using: executor)
        let fourth = await detection(using: executor)

        XCTAssertEqual(first.spotify.failure, .timedOut)
        XCTAssertEqual(second.spotify.failure, .backedOff)
        XCTAssertEqual(third.spotify.output, "spotify-ok")
        XCTAssertNil(fourth.spotify.failure)
        XCTAssertEqual(spotifyAttempts.read(), 3)
        XCTAssertEqual(musicAttempts.read(), 4, "Spotify backoff must not suppress a healthy provider")
    }

    func testDetectionStopsAfterFirstBrowserMediaMatch() async {
        let executed = LockedValues<[String]>([])
        let executor = MediaAutomationExecutor(runner: { source, _ in
            executed.update { $0.append(source) }
            if source == "browser-one" {
                return Self.success(output: "media||Track||Browser||||||playing||url")
            }
            return Self.success()
        })
        let result = await withCheckedContinuation { continuation in
            executor.submitDetection(MediaAutomationDetectionRequest(
                spotify: Self.operation("spotify", target: .spotify),
                music: Self.operation("music", target: .music),
                browsers: [
                    Self.browser("browser-one", bundle: "one"),
                    Self.browser("browser-two", bundle: "two")
                ],
                cancellation: MediaAutomationCancellation()
            )) { continuation.resume(returning: $0) }
        }

        XCTAssertEqual(result.browsers.count, 1)
        XCTAssertEqual(executed.read(), ["spotify", "music", "browser-one"])
    }

    func testRapidVolumeChangesKeepOnlyNewestPendingValue() async {
        let blockerStarted = expectation(description: "blocker started")
        let latestFinished = expectation(description: "latest volume finished")
        let release = DispatchSemaphore(value: 0)
        let executed = LockedValues<[String]>([])
        let executor = MediaAutomationExecutor(runner: { source, _ in
            executed.update { $0.append(source) }
            if source == "blocker" {
                blockerStarted.fulfill()
                release.wait()
            }
            return Self.success()
        })

        executor.submitCommand(Self.operation("blocker"))
        await fulfillment(of: [blockerStarted], timeout: 2)

        for value in 21...49 {
            executor.submitCommand(Self.operation("volume-\(value)"), isVolume: true) { result in
                if value == 49, result.failure == nil {
                    latestFinished.fulfill()
                }
            }
        }
        release.signal()

        await fulfillment(of: [latestFinished], timeout: 2)
        XCTAssertEqual(executed.read(), ["blocker", "volume-49"])
    }

    func testNativeSourceIsWrappedInBoundedAppleEventTimeout() {
        let source = MediaAutomationExecutor.boundedSource(
            "tell application \"Music\" to next track",
            timeoutSeconds: 1
        )

        XCTAssertTrue(source.contains("with timeout of 1 seconds"))
        XCTAssertTrue(source.contains("tell application \"Music\" to next track"))
        XCTAssertTrue(source.contains("end timeout"))
    }

    func testInvalidationCancelsQueuedCommands() async {
        let blockerStarted = expectation(description: "blocker started")
        let pendingCancelled = expectation(description: "pending cancelled")
        let blockerFinished = expectation(description: "blocker finished")
        let release = DispatchSemaphore(value: 0)
        let executed = LockedValues<[String]>([])
        let executor = MediaAutomationExecutor(runner: { source, _ in
            executed.update { $0.append(source) }
            if source == "blocker" {
                blockerStarted.fulfill()
                release.wait()
            }
            return Self.success()
        })

        executor.submitCommand(Self.operation("blocker")) { _ in blockerFinished.fulfill() }
        await fulfillment(of: [blockerStarted], timeout: 2)
        executor.submitCommand(Self.operation("pending")) { result in
            XCTAssertEqual(result.failure, .cancelled)
            pendingCancelled.fulfill()
        }
        executor.invalidate()

        await fulfillment(of: [pendingCancelled], timeout: 2)
        release.signal()
        await fulfillment(of: [blockerFinished], timeout: 2)
        XCTAssertEqual(executed.read(), ["blocker"])
    }

    private func detection(using executor: MediaAutomationExecutor) async -> MediaAutomationDetectionResult {
        await withCheckedContinuation { continuation in
            executor.submitDetection(MediaAutomationDetectionRequest(
                spotify: Self.operation("spotify", target: .spotify),
                music: Self.operation("music", target: .music),
                browsers: [],
                cancellation: MediaAutomationCancellation()
            )) { continuation.resume(returning: $0) }
        }
    }

    private static func operation(
        _ source: String,
        target: MediaAutomationTarget = .music
    ) -> MediaAutomationOperation {
        MediaAutomationOperation(target: target, source: source)
    }

    private static func browser(_ source: String, bundle: String) -> MediaAutomationBrowserOperation {
        MediaAutomationBrowserOperation(
            applicationName: bundle,
            bundleIdentifier: bundle,
            source: source
        )
    }

    private static func detectionRequest() -> MediaAutomationDetectionRequest {
        MediaAutomationDetectionRequest(
            spotify: operation("spotify", target: .spotify),
            music: operation("music", target: .music),
            browsers: [],
            cancellation: MediaAutomationCancellation()
        )
    }

    private static func success(output: String = "") -> MediaAutomationScriptResult {
        MediaAutomationScriptResult(output: output, failure: nil)
    }
}

final class MediaControllerAutomationIntegrationTests: XCTestCase {
    @MainActor
    func testSuccessfulTransportCommandRefreshesImmediatelyAfterExecutorCompletion() async {
        let commandSucceeded = expectation(description: "transport command succeeded")
        let postCommandDetectionStarted = expectation(description: "post-command detection started")
        let executed = LockedValues<[String]>([])
        let commandSeen = LockedValues(false)
        let executor = MediaAutomationExecutor(runner: { source, _ in
            executed.update { $0.append(source) }
            if source.contains("next track") {
                commandSeen.update { $0 = true }
                commandSucceeded.fulfill()
            } else if source.contains("tell application \"Spotify\"") && commandSeen.read() {
                postCommandDetectionStarted.fulfill()
            }
            return Self.scriptSuccess("")
        })
        let provider = SequenceMediaDetectionProvider([
            Self.snapshot(title: "Old", imageSize: 10),
            Self.snapshot(title: "New", imageSize: 20)
        ])
        let controller = MediaController(
            automationExecutor: executor,
            systemNowPlayingProvider: provider,
            startsAutomatically: false
        )
        let oldPublished = expectation(description: "old track published")
        let newPublished = expectation(description: "new track published")
        let subscription = controller.$title.sink { title in
            if title == "Old" { oldPublished.fulfill() }
            if title == "New" { newPublished.fulfill() }
        }

        controller.refresh()
        await fulfillment(of: [oldPublished], timeout: 2)
        controller.nextTrack()
        await fulfillment(
            of: [commandSucceeded, newPublished, postCommandDetectionStarted],
            timeout: 2
        )

        let sources = executed.read()
        let commandIndex = try? XCTUnwrap(sources.firstIndex(where: { $0.contains("next track") }))
        let followingDetectionIndex = sources.indices.first { index in
            guard let commandIndex, index > commandIndex else { return false }
            return sources[index].contains("tell application \"Spotify\"")
        }
        XCTAssertNotNil(commandIndex)
        XCTAssertNotNil(followingDetectionIndex)
        subscription.cancel()
    }

    @MainActor
    func testSameSourceSystemArtworkPublishesBeforeAutomationBatchCompletes() async {
        let secondDetectionStarted = expectation(description: "second automation batch started")
        let releaseSecondDetection = DispatchSemaphore(value: 0)
        let spotifyAttempts = LockedValues(0)
        let executor = MediaAutomationExecutor(runner: { source, _ in
            if source.contains("tell application \"Spotify\"") {
                let attempt = spotifyAttempts.update { value -> Int in
                    value += 1
                    return value
                }
                if attempt == 2 {
                    secondDetectionStarted.fulfill()
                    releaseSecondDetection.wait()
                }
            }
            return Self.scriptSuccess("")
        })
        let provider = SequenceMediaDetectionProvider([
            Self.snapshot(title: "Old", imageSize: 10),
            Self.snapshot(title: "New", imageSize: 20)
        ])
        let controller = MediaController(
            automationExecutor: executor,
            systemNowPlayingProvider: provider,
            startsAutomatically: false
        )
        let oldPublished = expectation(description: "old track published")
        let newPublished = expectation(description: "new system track published")
        let firstHalfStarted = expectation(description: "new artwork flip started")
        let subscription = controller.$title.sink { title in
            if title == "Old" { oldPublished.fulfill() }
            if title == "New" { newPublished.fulfill() }
        }
        let artworkSubscription = controller.artworkPresentation.$state.sink { state in
            if state.phase == .firstHalf {
                firstHalfStarted.fulfill()
            }
        }

        controller.refresh()
        await fulfillment(of: [oldPublished], timeout: 2)
        controller.refresh()
        await fulfillment(
            of: [newPublished, firstHalfStarted, secondDetectionStarted],
            timeout: 2
        )

        XCTAssertEqual(controller.title, "New")
        releaseSecondDetection.signal()
        artworkSubscription.cancel()
        subscription.cancel()
    }

    @MainActor
    func testSupersededSpotifyResultCannotPublishOverNewerMusicResult() async {
        let firstSpotifyStarted = expectation(description: "first Spotify query started")
        let musicPublished = expectation(description: "newer Music result published")
        let releaseFirstSpotify = DispatchSemaphore(value: 0)
        let spotifyAttempts = LockedValues(0)
        let executor = MediaAutomationExecutor(runner: { source, _ in
            if source.contains("tell application \"Spotify\"") {
                let attempt = spotifyAttempts.update { value -> Int in
                    value += 1
                    return value
                }
                if attempt == 1 {
                    firstSpotifyStarted.fulfill()
                    releaseFirstSpotify.wait()
                    return Self.scriptSuccess("Old||Artist||playing||Spotify||1||100||||50")
                }
                return Self.scriptSuccess("")
            }
            if source.contains("tell application \"Music\"") {
                return Self.scriptSuccess("New||Artist||playing||Music||2||100||||50")
            }
            return Self.scriptSuccess("")
        })
        let controller = MediaController(
            automationExecutor: executor,
            systemNowPlayingProvider: EmptyMediaDetectionProvider(),
            startsAutomatically: false
        )
        var publishedSources: [String] = []
        let subscription = controller.$sourceName.sink { source in
            publishedSources.append(source)
            if source == "Music" { musicPublished.fulfill() }
        }

        controller.refresh()
        await fulfillment(of: [firstSpotifyStarted], timeout: 2)
        controller.refresh()
        releaseFirstSpotify.signal()
        await fulfillment(of: [musicPublished], timeout: 2)

        XCTAssertEqual(controller.sourceName, "Music")
        XCTAssertEqual(controller.title, "New")
        XCTAssertFalse(publishedSources.contains("Spotify"))
        subscription.cancel()
    }

    @MainActor
    func testControllerDeinitCancelsAutomationLifecycleWithoutRetention() async {
        let queryStarted = expectation(description: "query started")
        let queryReleased = expectation(description: "query released")
        let release = DispatchSemaphore(value: 0)
        let executor = MediaAutomationExecutor(runner: { _, _ in
            queryStarted.fulfill()
            release.wait()
            queryReleased.fulfill()
            return Self.scriptSuccess("")
        })
        var controller: MediaController? = MediaController(
            automationExecutor: executor,
            systemNowPlayingProvider: EmptyMediaDetectionProvider(),
            startsAutomatically: true
        )
        weak var weakController = controller

        await fulfillment(of: [queryStarted], timeout: 2)
        controller = nil
        XCTAssertNil(weakController)

        release.signal()
        await fulfillment(of: [queryReleased], timeout: 2)
    }

    private static func scriptSuccess(_ output: String) -> MediaAutomationScriptResult {
        MediaAutomationScriptResult(output: output, failure: nil)
    }

    private static func snapshot(title: String, imageSize: CGFloat) -> MediaSnapshot {
        MediaSnapshot(
            sourceKind: .spotify,
            sourceName: "Spotify",
            bundleIdentifier: "com.spotify.client",
            title: title,
            artist: "Artist",
            album: "Album",
            artwork: NSImage(size: CGSize(width: imageSize, height: imageSize)),
            isPlaying: true,
            duration: 180,
            elapsedTime: 1,
            transportAvailable: true,
            seekAvailable: true,
            volumeAvailable: true
        )
    }
}

final class MediaRefreshCoordinatorTests: XCTestCase {
    func testRapidCommandRefreshRequestsKeepOnlyNewestPendingGeneration() throws {
        var coordinator = MediaRefreshCoordinator()
        let active = try XCTUnwrap(coordinator.request())

        for _ in 0..<64 {
            XCTAssertNil(coordinator.request())
        }

        XCTAssertTrue(active.cancellation.isCancelled)
        XCTAssertTrue(coordinator.hasPendingRefresh)
        let newest = try XCTUnwrap(coordinator.complete(active.generation))
        XCTAssertEqual(newest.generation, 65)
        XCTAssertFalse(coordinator.hasPendingRefresh)
    }

    func testRefreshRequestsCoalesceToCurrentAndNewestPendingGeneration() throws {
        var coordinator = MediaRefreshCoordinator()
        let first = try XCTUnwrap(coordinator.request())

        XCTAssertNil(coordinator.request())
        XCTAssertNil(coordinator.request())
        XCTAssertTrue(first.cancellation.isCancelled)
        XCTAssertTrue(coordinator.hasPendingRefresh)
        XCTAssertFalse(coordinator.accepts(first.generation))

        let newest = try XCTUnwrap(coordinator.complete(first.generation))
        XCTAssertEqual(newest.generation, 3)
        XCTAssertFalse(coordinator.hasPendingRefresh)
        XCTAssertTrue(coordinator.accepts(newest.generation))
        XCTAssertNil(coordinator.complete(first.generation))
        XCTAssertTrue(coordinator.isRunning)
    }

    func testLateRefreshCannotReplaceNewerSource() throws {
        var coordinator = MediaRefreshCoordinator()
        let spotify = try XCTUnwrap(coordinator.request())
        XCTAssertNil(coordinator.request())

        var publishedSource: String?
        if coordinator.accepts(spotify.generation) {
            publishedSource = "Spotify"
        }
        XCTAssertNil(publishedSource)

        let browser = try XCTUnwrap(coordinator.complete(spotify.generation))
        if coordinator.accepts(browser.generation) {
            publishedSource = "Browser"
        }
        XCTAssertEqual(publishedSource, "Browser")
        XCTAssertFalse(coordinator.accepts(spotify.generation))
    }

    func testInvalidationRejectsLateResultAndCancelsActiveWork() throws {
        var coordinator = MediaRefreshCoordinator()
        let active = try XCTUnwrap(coordinator.request())

        coordinator.invalidate()

        XCTAssertTrue(active.cancellation.isCancelled)
        XCTAssertFalse(coordinator.accepts(active.generation))
        XCTAssertNil(coordinator.complete(active.generation))
        XCTAssertNil(coordinator.request())
    }
}
