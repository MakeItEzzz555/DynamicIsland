import AppKit
import Combine

/// Raw session/display signals. None of them is a documented security
/// contract; the reducer treats them as hints and fails closed.
enum LockSignal: Equatable, Sendable {
    case screenLocked          // com.apple.screenIsLocked (distributed)
    case screenUnlocked        // com.apple.screenIsUnlocked (distributed)
    case sessionResigned       // NSWorkspace.sessionDidResignActive (user switching)
    case sessionBecameActive   // NSWorkspace.sessionDidBecomeActive
    case screensSlept          // NSWorkspace.screensDidSleep
    case screensWoke           // NSWorkspace.screensDidWake
    case screensaverStarted    // com.apple.screensaver.didstart (distributed)
    case screensaverStopped    // com.apple.screensaver.didstop (distributed)
}

/// `locked` and `screensaver(locked: true)` are the only states in which a
/// lock-screen surface may be shown. Everything uncertain is `unknown`.
enum LockState: Equatable, Sendable {
    case unknown
    case unlocked
    case locked
    case screensaver(locked: Bool)
    case sleeping(locked: Bool)
    /// Another user's session owns the console (fast user switching).
    case sessionInactive

    var isConfirmedLocked: Bool {
        switch self {
        case .locked, .screensaver(locked: true): true
        default: false
        }
    }
}

enum LockStateReducer {
    /// Pure transition. A wake never implies unlock, and session activation
    /// alone never proves the secure screen is gone: only `screenUnlocked` does.
    static func reduce(_ state: LockState, _ signal: LockSignal) -> LockState {
        switch signal {
        case .screenLocked:
            return .locked
        case .screenUnlocked:
            return .unlocked
        case .sessionResigned:
            return .sessionInactive
        case .sessionBecameActive:
            // Returning from another session passes through loginwindow; stay
            // unproven until an explicit lock or unlock signal arrives.
            return state == .sessionInactive ? .unknown : state
        case .screensSlept:
            switch state {
            case .locked, .screensaver(locked: true): return .sleeping(locked: true)
            case .unlocked, .screensaver(locked: false): return .sleeping(locked: false)
            default: return state
            }
        case .screensWoke:
            switch state {
            case .sleeping(locked: true): return .locked
            // Sleep may have engaged the lock with its signal still in flight.
            case .sleeping(locked: false): return .unknown
            default: return state
            }
        case .screensaverStarted:
            switch state {
            case .locked: return .screensaver(locked: true)
            case .unlocked: return .screensaver(locked: false)
            default: return state
            }
        case .screensaverStopped:
            switch state {
            case .screensaver(locked: true): return .locked
            // The saver may have required a password; unproven until a signal.
            case .screensaver(locked: false): return .unknown
            default: return state
            }
        }
    }
}

@MainActor
protocol LockSignalSource: AnyObject {
    func start(_ handler: @escaping @MainActor (LockSignal) -> Void)
    func stop()
}

/// Publishes the reduced lock state. `generation` changes only on a real
/// transition so animations started for an older state can ignore themselves.
@MainActor
final class LockStateMonitor: ObservableObject {
    @Published private(set) var state: LockState = .unknown
    private(set) var generation: UInt64 = 0
    private let source: LockSignalSource
    private var running = false

    init(source: LockSignalSource = SystemLockSignalSource()) { self.source = source }

    func start() {
        guard !running else { return }
        running = true
        source.start { [weak self] signal in self?.receive(signal) }
    }

    func stop() {
        guard running else { return }
        running = false
        source.stop()
        state = .unknown
        generation &+= 1
    }

    func receive(_ signal: LockSignal) {
        let next = LockStateReducer.reduce(state, signal)
        guard next != state else { return }
        state = next
        generation &+= 1
    }
}

/// Distributed lock/screensaver notifications plus NSWorkspace session/display events.
@MainActor
final class SystemLockSignalSource: LockSignalSource {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func start(_ handler: @escaping @MainActor (LockSignal) -> Void) {
        stop()
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        let routes: [(NotificationCenter, Notification.Name, LockSignal)] = [
            (distributed, .init("com.apple.screenIsLocked"), .screenLocked),
            (distributed, .init("com.apple.screenIsUnlocked"), .screenUnlocked),
            (distributed, .init("com.apple.screensaver.didstart"), .screensaverStarted),
            (distributed, .init("com.apple.screensaver.didstop"), .screensaverStopped),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionResigned),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive),
            (workspace, NSWorkspace.screensDidSleepNotification, .screensSlept),
            (workspace, NSWorkspace.screensDidWakeNotification, .screensWoke)
        ]
        for (center, name, signal) in routes {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(signal) }
            }
            tokens.append((center, token))
        }
    }

    func stop() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }
}
