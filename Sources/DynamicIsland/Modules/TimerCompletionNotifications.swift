import Foundation
@preconcurrency import UserNotifications

enum TimerNotificationAuthorizationStatus: Equatable {
    case authorized
    case denied
    case notDetermined
}

struct TimerCompletionNotificationRequest: Equatable {
    let identifier: String
    let title: String
    let body: String
    let delay: TimeInterval
    let includesSound: Bool
}

@MainActor
protocol TimerNotificationCenterClient: AnyObject {
    func authorizationStatus() async -> TimerNotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: TimerCompletionNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

@MainActor
final class SystemTimerNotificationCenterClient: NSObject, TimerNotificationCenterClient,
    UNUserNotificationCenterDelegate
{
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func authorizationStatus() async -> TimerNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: TimerCompletionNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        if request.includesSound {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(request.delay, 0.1),
            repeats: false
        )
        try await center.add(
            UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: trigger
            )
        )
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

struct TimerCompletionNotificationPreferences: Equatable {
    let notificationsEnabled: Bool
    let soundEnabled: Bool
}

/// Timer completion audio: exactly one sound per completed countdown.
/// - The notification toggle controls the banner/list entry.
/// - The sound toggle controls audibility. When a notification with sound was
///   actually scheduled for this countdown, the system notification plays it
///   (`UNNotificationSound.default`, Apple-managed). Otherwise - notifications
///   off, permission denied/unanswered - an in-process system chime plays at
///   completion, so sound never requires notification permission.
/// macOS exposes no public Clock/Timer tone (only the private ToneLibrary
/// framework), so none is used or copied.
@MainActor
final class TimerCompletionNotificationCoordinator {
    static let localChimeName = "Glass"

    private let client: any TimerNotificationCenterClient
    private let sessionIdentifier: String
    private let playLocalChime: @MainActor () -> Void
    private var active: (generation: UInt64, identifier: String)?
    /// The countdown whose notification was scheduled with sound.
    private var notificationSoundGeneration: UInt64?
    private var pendingWork: Task<Void, Never>?

    init(
        client: any TimerNotificationCenterClient = SystemTimerNotificationCenterClient(),
        sessionIdentifier: String = UUID().uuidString,
        playLocalChime: @escaping @MainActor () -> Void = {
            SystemNotificationSoundPlayer.play(named: TimerCompletionNotificationCoordinator.localChimeName, volume: 0.8)
        }
    ) {
        self.client = client
        self.sessionIdentifier = sessionIdentifier
        self.playLocalChime = playLocalChime
    }

    func handle(
        _ event: CountdownLifecycleEvent,
        preferences: TimerCompletionNotificationPreferences
    ) {
        switch event {
        case let .scheduled(generation, remaining):
            schedule(generation: generation, remaining: remaining, preferences: preferences)
        case let .cancelled(generation):
            cancel(generation: generation)
        case let .completed(generation):
            complete(generation: generation, soundEnabled: preferences.soundEnabled)
        }
    }

    func waitForPendingWork() async {
        await pendingWork?.value
    }

    private func schedule(
        generation: UInt64,
        remaining: Duration,
        preferences: TimerCompletionNotificationPreferences
    ) {
        cancelActiveRequest()
        guard preferences.notificationsEnabled else { return }

        let identifier = "dynamic-island.timer.\(sessionIdentifier).\(generation)"
        active = (generation, identifier)
        let request = TimerCompletionNotificationRequest(
            identifier: identifier,
            title: "Timer Finished",
            body: "Your timer has finished.",
            delay: Self.timeInterval(for: remaining),
            includesSound: preferences.soundEnabled
        )

        pendingWork = Task { [weak self, client] in
            do {
                let status = await client.authorizationStatus()
                let authorized: Bool
                switch status {
                case .authorized:
                    authorized = true
                case .denied:
                    authorized = false
                case .notDetermined:
                    authorized = try await client.requestAuthorization()
                }

                guard authorized,
                      !Task.isCancelled,
                      self?.active?.identifier == identifier else { return }
                try await client.add(request)
                guard !Task.isCancelled,
                      self?.active?.identifier == identifier else {
                    client.removePendingNotificationRequests(withIdentifiers: [identifier])
                    return
                }
                if request.includesSound { self?.notificationSoundGeneration = generation }
            } catch {
                #if DEBUG
                print("[TimerNotification] scheduling failed: \(error)")
                #endif
            }
        }
    }

    private func cancel(generation: UInt64) {
        guard active?.generation == generation else { return }
        cancelActiveRequest()
    }

    private func complete(generation: UInt64, soundEnabled: Bool) {
        let notificationPlaysSound = notificationSoundGeneration == generation
        notificationSoundGeneration = nil
        if active?.generation == generation {
            pendingWork?.cancel()
            pendingWork = nil
            active = nil
        }
        if soundEnabled && !notificationPlaysSound { playLocalChime() }
    }

    private func cancelActiveRequest() {
        pendingWork?.cancel()
        pendingWork = nil
        notificationSoundGeneration = nil
        if let identifier = active?.identifier {
            client.removePendingNotificationRequests(withIdentifiers: [identifier])
        }
        active = nil
    }

    private static func timeInterval(for duration: Duration) -> TimeInterval {
        let components = duration.components
        return max(
            0,
            Double(components.seconds)
                + Double(components.attoseconds) / 1_000_000_000_000_000_000
        )
    }
}
