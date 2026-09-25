import AppKit
import Foundation

enum MediaAutomationTarget: Hashable, Sendable {
    case spotify
    case music
    case browser(bundleIdentifier: String)

    var debugName: String {
        switch self {
        case .spotify:
            "Spotify"
        case .music:
            "Music"
        case .browser(let bundleIdentifier):
            bundleIdentifier
        }
    }
}

enum MediaAutomationFailure: Equatable, Sendable {
    case timedOut
    case execution(String)
    case backedOff
    case cancelled
    case queueFull
}

struct MediaAutomationScriptResult: Equatable, Sendable {
    let output: String
    let failure: MediaAutomationFailure?

    var errorDescription: String? {
        switch failure {
        case nil:
            nil
        case .timedOut:
            "AppleScript timed out"
        case .execution(let description):
            description
        case .backedOff:
            "Temporarily backed off after an automation failure"
        case .cancelled:
            "Automation request was cancelled or superseded"
        case .queueFull:
            "Automation command queue is full"
        }
    }
}

struct MediaAutomationOperation: Sendable {
    let target: MediaAutomationTarget
    let source: String
}

struct MediaAutomationBrowserOperation: Sendable {
    let applicationName: String
    let bundleIdentifier: String
    let source: String

    var operation: MediaAutomationOperation {
        MediaAutomationOperation(
            target: .browser(bundleIdentifier: bundleIdentifier),
            source: source
        )
    }
}

struct MediaAutomationDetectionRequest: Sendable {
    let spotify: MediaAutomationOperation
    let music: MediaAutomationOperation
    let browsers: [MediaAutomationBrowserOperation]
    let cancellation: MediaAutomationCancellation
}

struct MediaAutomationBrowserResult: Sendable {
    let applicationName: String
    let bundleIdentifier: String
    let result: MediaAutomationScriptResult
}

struct MediaAutomationDetectionResult: Sendable {
    let spotify: MediaAutomationScriptResult
    let music: MediaAutomationScriptResult
    let browsers: [MediaAutomationBrowserResult]
}

final class MediaAutomationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

struct MediaAutomationBackoff: Sendable {
    struct Entry: Sendable {
        var consecutiveFailures: Int
        var retryAfter: TimeInterval
    }

    private(set) var entries: [MediaAutomationTarget: Entry] = [:]
    let initialDelay: TimeInterval
    let maximumDelay: TimeInterval

    init(initialDelay: TimeInterval = 1.5, maximumDelay: TimeInterval = 12) {
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
    }

    func permits(_ target: MediaAutomationTarget, at time: TimeInterval) -> Bool {
        guard let entry = entries[target] else { return true }
        return time >= entry.retryAfter
    }

    mutating func record(_ result: MediaAutomationScriptResult, for target: MediaAutomationTarget, at time: TimeInterval) {
        switch result.failure {
        case nil:
            entries[target] = nil
        case .timedOut, .execution:
            let failures = (entries[target]?.consecutiveFailures ?? 0) + 1
            let multiplier = pow(2.0, Double(max(0, failures - 1)))
            entries[target] = Entry(
                consecutiveFailures: failures,
                retryAfter: time + min(maximumDelay, initialDelay * multiplier)
            )
        case .backedOff, .cancelled, .queueFull:
            break
        }
    }
}

/// Runs every AppleScript on one private serial worker. The native Apple Event
/// timeout is deliberately short: a target gets one second to respond, after
/// which the request becomes a normal failure and later queued work can run.
final class MediaAutomationExecutor: @unchecked Sendable {
    typealias ScriptRunner = @Sendable (_ source: String, _ timeoutSeconds: Int) -> MediaAutomationScriptResult
    typealias Clock = @Sendable () -> TimeInterval

    private enum Work {
        case detection(
            MediaAutomationDetectionRequest,
            @Sendable (MediaAutomationDetectionResult) -> Void
        )
        case command(
            MediaAutomationOperation,
            isVolume: Bool,
            @Sendable (MediaAutomationScriptResult) -> Void
        )

        var isVolume: Bool {
            if case .command(_, let isVolume, _) = self { return isVolume }
            return false
        }

        var target: MediaAutomationTarget? {
            if case .command(let operation, _, _) = self { return operation.target }
            return nil
        }

        var isCommand: Bool {
            if case .command = self { return true }
            return false
        }

        var cancellation: MediaAutomationCancellation? {
            if case .detection(let request, _) = self { return request.cancellation }
            return nil
        }

        func completeAsCancelled(_ failure: MediaAutomationFailure = .cancelled) {
            switch self {
            case .command(_, _, let completion):
                completion(MediaAutomationScriptResult(output: "", failure: failure))
            case .detection(_, let completion):
                let result = MediaAutomationScriptResult(output: "", failure: failure)
                completion(MediaAutomationDetectionResult(
                    spotify: result,
                    music: result,
                    browsers: []
                ))
            }
        }
    }

    private let timeoutSeconds: Int
    private let maximumPendingCommands: Int
    private let runner: ScriptRunner
    private let clock: Clock
    private let workerQueue = DispatchQueue(label: "DynamicIsland.MediaAutomation")
    private let stateLock = NSLock()
    private var pending: [Work] = []
    private var workerIsRunning = false
    private var isInvalidated = false
    private var activeDetectionCancellation: MediaAutomationCancellation?
    private var backoff: MediaAutomationBackoff

    init(
        timeoutSeconds: Int = 1,
        maximumPendingCommands: Int = 64,
        backoff: MediaAutomationBackoff = MediaAutomationBackoff(),
        clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime },
        runner: @escaping ScriptRunner = MediaAutomationExecutor.runNativeAppleScript
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.maximumPendingCommands = max(1, maximumPendingCommands)
        self.backoff = backoff
        self.clock = clock
        self.runner = runner
    }

    func submitDetection(
        _ request: MediaAutomationDetectionRequest,
        completion: @escaping @Sendable (MediaAutomationDetectionResult) -> Void
    ) {
        enqueue(.detection(request, completion))
    }

    func submitCommand(
        _ operation: MediaAutomationOperation,
        isVolume: Bool = false,
        completion: @escaping @Sendable (MediaAutomationScriptResult) -> Void = { _ in }
    ) {
        enqueue(.command(operation, isVolume: isVolume, completion))
    }

    func invalidate() {
        let cancelled = stateLock.withLock { () -> [Work] in
            guard !isInvalidated else { return [] }
            isInvalidated = true
            activeDetectionCancellation?.cancel()
            let work = pending
            pending.removeAll(keepingCapacity: false)
            return work
        }
        cancelled.forEach { $0.completeAsCancelled() }
    }

    /// Invalidates queued work and waits until the serial worker has returned
    /// from any in-flight native call. This provides a deterministic lifecycle
    /// boundary for owners that must not outlive executor callbacks.
    func invalidateAndWaitForIdle() async {
        invalidate()
        await withCheckedContinuation { continuation in
            workerQueue.async {
                continuation.resume()
            }
        }
    }

    private func enqueue(_ work: Work) {
        var replaced: Work?
        var rejection: MediaAutomationFailure?
        let shouldStart = stateLock.withLock { () -> Bool in
            guard !isInvalidated else {
                rejection = .cancelled
                return false
            }
            if work.isVolume,
               let last = pending.last,
               last.isVolume,
               last.target == work.target {
                replaced = pending.removeLast()
            }
            if work.isCommand,
               pending.lazy.filter(\.isCommand).count >= maximumPendingCommands {
                rejection = .queueFull
                return false
            }
            pending.append(work)
            guard !workerIsRunning else { return false }
            workerIsRunning = true
            return true
        }

        replaced?.completeAsCancelled()
        if let rejection {
            work.completeAsCancelled(rejection)
            return
        }
        guard shouldStart else { return }
        workerQueue.async { [self] in drain() }
    }

    private func drain() {
        while let work = nextWork() {
            switch work {
            case .detection(let request, let completion):
                completion(executeDetection(request))
                stateLock.withLock { activeDetectionCancellation = nil }
            case .command(let operation, _, let completion):
                completion(execute(operation, observesBackoff: false))
            }
        }
    }

    private func nextWork() -> Work? {
        stateLock.withLock {
            guard !pending.isEmpty else {
                workerIsRunning = false
                return nil
            }
            let index = pending.firstIndex(where: \.isCommand) ?? pending.startIndex
            let work = pending.remove(at: index)
            activeDetectionCancellation = work.cancellation
            return work
        }
    }

    private func executeDetection(_ request: MediaAutomationDetectionRequest) -> MediaAutomationDetectionResult {
        let spotify = executeUnlessCancelled(request.spotify, cancellation: request.cancellation)
        let music = executeUnlessCancelled(request.music, cancellation: request.cancellation)
        var browserResults: [MediaAutomationBrowserResult] = []

        for browser in request.browsers {
            let result = executeUnlessCancelled(browser.operation, cancellation: request.cancellation)
            browserResults.append(MediaAutomationBrowserResult(
                applicationName: browser.applicationName,
                bundleIdentifier: browser.bundleIdentifier,
                result: result
            ))
            if result.output.hasPrefix("media||") || request.cancellation.isCancelled {
                break
            }
        }

        return MediaAutomationDetectionResult(
            spotify: spotify,
            music: music,
            browsers: browserResults
        )
    }

    private func executeUnlessCancelled(
        _ operation: MediaAutomationOperation,
        cancellation: MediaAutomationCancellation
    ) -> MediaAutomationScriptResult {
        guard !cancellation.isCancelled else {
            return MediaAutomationScriptResult(output: "", failure: .cancelled)
        }
        return execute(operation, observesBackoff: true)
    }

    private func execute(
        _ operation: MediaAutomationOperation,
        observesBackoff: Bool
    ) -> MediaAutomationScriptResult {
        let now = clock()
        if observesBackoff, !backoff.permits(operation.target, at: now) {
            return MediaAutomationScriptResult(output: "", failure: .backedOff)
        }

        let result = runner(operation.source, timeoutSeconds)
        backoff.record(result, for: operation.target, at: clock())
        return result
    }

    static func boundedSource(_ source: String, timeoutSeconds: Int) -> String {
        """
        with timeout of \(max(1, timeoutSeconds)) seconds
        \(source)
        end timeout
        """
    }

    private static func runNativeAppleScript(
        source: String,
        timeoutSeconds: Int
    ) -> MediaAutomationScriptResult {
        var error: NSDictionary?
        guard let script = NSAppleScript(
            source: boundedSource(source, timeoutSeconds: timeoutSeconds)
        ) else {
            return MediaAutomationScriptResult(
                output: "",
                failure: .execution("Unable to compile AppleScript")
            )
        }

        let output = script.executeAndReturnError(&error)
        guard let error else {
            return MediaAutomationScriptResult(output: output.stringValue ?? "", failure: nil)
        }

        let number = error[NSAppleScript.errorNumber] as? NSNumber
        if number?.intValue == -1712 {
            return MediaAutomationScriptResult(output: "", failure: .timedOut)
        }

        let message = error[NSAppleScript.errorMessage] as? String
        let description: String
        if let message, let number {
            description = "\(message) (\(number))"
        } else if let message {
            description = message
        } else {
            description = error.description
        }
        return MediaAutomationScriptResult(output: output.stringValue ?? "", failure: .execution(description))
    }
}

struct MediaRefreshCoordinator {
    struct Start: Sendable {
        let generation: Int
        let cancellation: MediaAutomationCancellation
    }

    private(set) var generation = 0
    private(set) var isRunning = false
    private(set) var hasPendingRefresh = false
    private(set) var isInvalidated = false
    private var activeGeneration: Int?
    private var activeCancellation: MediaAutomationCancellation?

    mutating func request() -> Start? {
        guard !isInvalidated else { return nil }
        generation &+= 1
        guard !isRunning else {
            hasPendingRefresh = true
            activeCancellation?.cancel()
            return nil
        }
        return startCurrentGeneration()
    }

    func accepts(_ completedGeneration: Int) -> Bool {
        !isInvalidated && completedGeneration == generation
    }

    mutating func complete(_ completedGeneration: Int) -> Start? {
        guard isRunning, activeGeneration == completedGeneration else { return nil }
        isRunning = false
        activeGeneration = nil
        activeCancellation = nil
        guard !isInvalidated, hasPendingRefresh else {
            hasPendingRefresh = false
            return nil
        }
        hasPendingRefresh = false
        return startCurrentGeneration()
    }

    mutating func invalidate() {
        isInvalidated = true
        generation &+= 1
        hasPendingRefresh = false
        activeCancellation?.cancel()
        activeGeneration = nil
        activeCancellation = nil
        isRunning = false
    }

    private mutating func startCurrentGeneration() -> Start {
        let cancellation = MediaAutomationCancellation()
        activeGeneration = generation
        activeCancellation = cancellation
        isRunning = true
        return Start(generation: generation, cancellation: cancellation)
    }
}
