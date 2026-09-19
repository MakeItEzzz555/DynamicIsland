import AppKit
import Combine
import Foundation
import XCTest
@testable import DynamicIsland

private final class MediaRemoteTestLock<Value>: @unchecked Sendable {
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

private final class ManualMediaRemoteDeadlineScheduler: @unchecked Sendable {
    private struct Entry {
        let action: @Sendable () -> Void
        var isCancelled = false
    }

    private let entries = MediaRemoteTestLock<[Entry]>([])
    private let onSchedule: @Sendable (Int) -> Void

    init(onSchedule: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.onSchedule = onSchedule
    }

    var scheduler: MediaRemoteDeadlineScheduler {
        MediaRemoteDeadlineScheduler { [weak self] _, action in
            guard let self else {
                return MediaRemoteDeadlineToken(cancel: {})
            }
            let index = entries.update { entries -> Int in
                entries.append(Entry(action: action))
                return entries.count - 1
            }
            onSchedule(index)
            return MediaRemoteDeadlineToken { [weak self] in
                self?.entries.update { entries in
                    guard entries.indices.contains(index) else { return }
                    entries[index].isCancelled = true
                }
            }
        }
    }

    var count: Int {
        entries.read().count
    }

    func isCancelled(_ index: Int) -> Bool {
        entries.read()[index].isCancelled
    }

    /// Intentionally fires cancelled entries so tests prove a losing deadline is inert.
    func fire(_ index: Int) {
        entries.read()[index].action()
    }
}

private final class ControlledMediaRemoteCallback<Value: Sendable>: @unchecked Sendable {
    private let callback = MediaRemoteTestLock<(@Sendable (Value?) -> Void)?>(nil)
    private let onStart: @Sendable () -> Void

    init(onStart: @escaping @Sendable () -> Void = {}) {
        self.onStart = onStart
    }

    func start(_ callback: @escaping @Sendable (Value?) -> Void) {
        self.callback.update { $0 = callback }
        onStart()
    }

    func complete(_ value: Value?) {
        callback.read()?(value)
    }
}

private struct SendableMediaRemoteDictionary: @unchecked Sendable {
    let value: NSDictionary
}

@MainActor
private final class ControlledMediaRemoteProvider: MediaRemoteProviding {
    let isAvailable = true
    let scheduler: ManualMediaRemoteDeadlineScheduler
    var onInfoRequest: @Sendable (Int) -> Void = { _ in }
    private(set) var infoCallbacks: [@Sendable (SendableMediaRemoteDictionary?) -> Void] = []

    init(scheduler: ManualMediaRemoteDeadlineScheduler) {
        self.scheduler = scheduler
    }

    func nowPlayingInfo() async -> NSDictionary? {
        let requestIndex = infoCallbacks.count
        let wrapped: SendableMediaRemoteDictionary? = await MediaRemoteCallbackBridge.wait(
            timeout: MediaRemoteClient.callbackTimeout,
            scheduler: scheduler.scheduler
        ) { [weak self] completion in
            self?.infoCallbacks.append(completion)
            self?.onInfoRequest(requestIndex)
        }
        return wrapped?.value
    }

    func nowPlayingApplicationDisplayName() async -> String? {
        nil
    }

    func completeInfo(_ index: Int, dictionary: NSDictionary?) {
        infoCallbacks[index](dictionary.map(SendableMediaRemoteDictionary.init))
    }
}

final class MediaRemoteCallbackBridgeTests: XCTestCase {
    @MainActor
    func testNormalCallbackReturnsExpectedValueAndCancelsDeadline() async {
        let scheduler = ManualMediaRemoteDeadlineScheduler()

        let result: String? = await MediaRemoteCallbackBridge.wait(
            timeout: 0.5,
            scheduler: scheduler.scheduler
        ) { completion in
            completion("expected")
        }

        XCTAssertEqual(result, "expected")
        XCTAssertEqual(scheduler.count, 1)
        XCTAssertTrue(scheduler.isCancelled(0))
    }

    @MainActor
    func testMissingCallbackResolvesThroughDeadline() async {
        let scheduled = expectation(description: "deadline scheduled")
        let started = expectation(description: "callback operation started")
        let scheduler = ManualMediaRemoteDeadlineScheduler { _ in scheduled.fulfill() }
        let callback = ControlledMediaRemoteCallback<String> { started.fulfill() }
        let task = Task { @MainActor in
            await MediaRemoteCallbackBridge.wait(
                timeout: 0.5,
                scheduler: scheduler.scheduler,
                start: callback.start
            )
        }

        await fulfillment(of: [scheduled, started], timeout: 1)
        scheduler.fire(0)

        let result = await task.value
        XCTAssertNil(result)
    }

    @MainActor
    func testLateCallbackAfterDeadlineIsInert() async {
        let started = expectation(description: "callback operation started")
        let scheduler = ManualMediaRemoteDeadlineScheduler()
        let callback = ControlledMediaRemoteCallback<String> { started.fulfill() }
        let task = Task { @MainActor in
            await MediaRemoteCallbackBridge.wait(
                timeout: 0.5,
                scheduler: scheduler.scheduler,
                start: callback.start
            )
        }

        await fulfillment(of: [started], timeout: 1)
        scheduler.fire(0)
        let result = await task.value
        XCTAssertNil(result)

        callback.complete("too late")
        scheduler.fire(0)
    }

    @MainActor
    func testCallbackWinsAndLaterDeadlineIsInert() async {
        let started = expectation(description: "callback operation started")
        let scheduler = ManualMediaRemoteDeadlineScheduler()
        let callback = ControlledMediaRemoteCallback<String> { started.fulfill() }
        let task = Task { @MainActor in
            await MediaRemoteCallbackBridge.wait(
                timeout: 0.5,
                scheduler: scheduler.scheduler,
                start: callback.start
            )
        }

        await fulfillment(of: [started], timeout: 1)
        callback.complete("callback")
        let result = await task.value
        XCTAssertEqual(result, "callback")
        XCTAssertTrue(scheduler.isCancelled(0))

        scheduler.fire(0)
        callback.complete("duplicate")
    }

    @MainActor
    func testConcurrentCallbackAndDeadlineResolveExactlyOnce() async {
        for _ in 0..<50 {
            let started = expectation(description: "callback operation started")
            let scheduler = ManualMediaRemoteDeadlineScheduler()
            let callback = ControlledMediaRemoteCallback<Int> { started.fulfill() }
            let task = Task { @MainActor in
                await MediaRemoteCallbackBridge.wait(
                    timeout: 0.5,
                    scheduler: scheduler.scheduler,
                    start: callback.start
                )
            }
            await fulfillment(of: [started], timeout: 1)

            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    callback.complete(42)
                } else {
                    scheduler.fire(0)
                }
            }

            let result = await task.value
            XCTAssertTrue(result == 42 || result == nil)
        }
    }

    @MainActor
    func testCancellationResolvesAndReleasesDeadlineOwnership() async {
        let started = expectation(description: "callback operation started")
        let scheduler = ManualMediaRemoteDeadlineScheduler()
        let callback = ControlledMediaRemoteCallback<String> { started.fulfill() }
        let task = Task { @MainActor in
            await MediaRemoteCallbackBridge.wait(
                timeout: 0.5,
                scheduler: scheduler.scheduler,
                start: callback.start
            )
        }

        await fulfillment(of: [started], timeout: 1)
        task.cancel()

        let result = await task.value
        XCTAssertNil(result)
        XCTAssertTrue(scheduler.isCancelled(0))
        callback.complete("too late")
        scheduler.fire(0)
    }
}

final class MediaRemoteRefreshRecoveryTests: XCTestCase {
    @MainActor
    func testTimeoutRunsNewestPendingRefreshFallbackAndRejectsLateNativeResult() async {
        let firstNativeRequest = expectation(description: "first native request")
        let pendingNativeRequest = expectation(description: "pending native request")
        let laterNativeRequest = expectation(description: "later native request")
        let scheduler = ManualMediaRemoteDeadlineScheduler()
        let remote = ControlledMediaRemoteProvider(scheduler: scheduler)
        remote.onInfoRequest = { index in
            switch index {
            case 0: firstNativeRequest.fulfill()
            case 1: pendingNativeRequest.fulfill()
            case 2: laterNativeRequest.fulfill()
            default: break
            }
        }
        let fallbackAttempt = MediaRemoteTestLock(0)
        let executor = MediaAutomationExecutor(runner: { source, _ in
            guard source.contains("tell application \"Spotify\"") else {
                return MediaAutomationScriptResult(output: "", failure: nil)
            }
            let attempt = fallbackAttempt.update { value -> Int in
                value += 1
                return value
            }
            let title = attempt == 1 ? "Recovered" : "Subsequent"
            return MediaAutomationScriptResult(
                output: "\(title)||Artist||playing||Spotify||1||100||||50",
                failure: nil
            )
        })
        let provider = NowPlayingMediaProvider(mediaRemote: remote)
        let controller = MediaController(
            automationExecutor: executor,
            systemNowPlayingProvider: provider,
            startsAutomatically: false
        )
        let recovered = expectation(description: "fallback published")
        let subsequent = expectation(description: "subsequent fallback published")
        let subscription = controller.$title.sink { title in
            if title == "Recovered" { recovered.fulfill() }
            if title == "Subsequent" { subsequent.fulfill() }
        }

        controller.refresh()
        await fulfillment(of: [firstNativeRequest], timeout: 1)
        controller.refresh()
        scheduler.fire(0)
        await fulfillment(of: [pendingNativeRequest], timeout: 1)
        scheduler.fire(1)
        await fulfillment(of: [recovered], timeout: 2)

        remote.completeInfo(0, dictionary: Self.nativeInfo(title: "Stale Native"))
        await Task.yield()
        XCTAssertEqual(controller.title, "Recovered")
        XCTAssertEqual(fallbackAttempt.read(), 1)

        controller.refresh()
        await fulfillment(of: [laterNativeRequest], timeout: 1)
        scheduler.fire(2)
        await fulfillment(of: [subsequent], timeout: 2)

        XCTAssertEqual(controller.title, "Subsequent")
        XCTAssertEqual(fallbackAttempt.read(), 2)
        subscription.cancel()
    }

    @MainActor
    func testControllerTeardownDoesNotRetainTimedOutRefreshOrLateCallback() async {
        let nativeRequest = expectation(description: "native request")
        let scheduler = ManualMediaRemoteDeadlineScheduler()
        let remote = ControlledMediaRemoteProvider(scheduler: scheduler)
        remote.onInfoRequest = { _ in nativeRequest.fulfill() }
        var provider: NowPlayingMediaProvider? = NowPlayingMediaProvider(mediaRemote: remote)
        weak let weakProvider = provider
        var controller: MediaController? = MediaController(
            systemNowPlayingProvider: provider!,
            startsAutomatically: false
        )
        weak let weakController = controller

        controller?.refresh()
        await fulfillment(of: [nativeRequest], timeout: 1)
        provider = nil
        controller = nil

        XCTAssertNil(weakController)
        scheduler.fire(0)
        remote.completeInfo(0, dictionary: Self.nativeInfo(title: "Late"))
        for _ in 0..<10 where weakProvider != nil {
            await Task.yield()
        }
        XCTAssertNil(weakProvider)
    }

    private static func nativeInfo(title: String) -> NSDictionary {
        [
            "kMRMediaRemoteNowPlayingInfoTitle": title,
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1,
            "kMRMediaRemoteNowPlayingApplicationBundleIdentifier": "com.spotify.client"
        ] as NSDictionary
    }
}
