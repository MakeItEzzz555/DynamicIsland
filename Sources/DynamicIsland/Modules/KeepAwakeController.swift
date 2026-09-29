import Foundation
import IOKit.pwr_mgt

enum KeepAwakePreset: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .fifteenMinutes: "15 min"
        case .thirtyMinutes: "30 min"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        }
    }

    var duration: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

enum KeepAwakeControllerError: LocalizedError, Equatable {
    case assertionCreationFailed(Int32)
    case invalidDuration
    case unsupportedAction(IslandCapabilityAction)

    var errorDescription: String? {
        switch self {
        case .assertionCreationFailed(let code):
            "Unable to create macOS power assertion (IOReturn \(code))."
        case .invalidDuration:
            "Keep Awake duration must be greater than zero."
        case .unsupportedAction(let action):
            "Keep Awake does not support \(action.rawValue)."
        }
    }
}

final class KeepAwakeAssertionLease {
    private var releaseHandler: (() -> Void)?

    init(releaseHandler: @escaping () -> Void) {
        self.releaseHandler = releaseHandler
    }

    func invalidate() {
        let release = releaseHandler
        releaseHandler = nil
        release?()
    }

    deinit {
        invalidate()
    }
}

protocol KeepAwakeAssertionProviding {
    func acquire(reason: String) throws -> KeepAwakeAssertionLease
}

struct SystemKeepAwakeAssertionProvider: KeepAwakeAssertionProviding {
    func acquire(reason: String) throws -> KeepAwakeAssertionLease {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            throw KeepAwakeControllerError.assertionCreationFailed(result)
        }

        return KeepAwakeAssertionLease {
            IOPMAssertionRelease(assertionID)
        }
    }
}

@MainActor
final class KeepAwakeController: ObservableObject, IslandCapabilityAdapter {
    static let activityID = "keepAwake"

    @Published private(set) var isActive = false
    @Published private(set) var expiresAt: Date?
    @Published private(set) var startedAt: Date?
    @Published private(set) var configuredDuration: TimeInterval?
    @Published private(set) var lastError: String?

    let capabilityID: IslandCapabilityID = .keepAwake

    private let assertionProvider: KeepAwakeAssertionProviding
    private let liveActivities: LiveActivityStore
    private let capabilities: IslandCapabilityRegistry
    private let now: () -> Date
    private var assertionLease: KeepAwakeAssertionLease?
    private var timer: Timer?
    private var isEnabled = true

    init(
        liveActivities: LiveActivityStore,
        capabilities: IslandCapabilityRegistry,
        assertionProvider: KeepAwakeAssertionProviding = SystemKeepAwakeAssertionProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.liveActivities = liveActivities
        self.capabilities = capabilities
        self.assertionProvider = assertionProvider
        self.now = now
        publishState()
    }

    var snapshot: IslandCapabilitySnapshot {
        IslandCapabilitySnapshot(
            id: .keepAwake,
            isEnabled: isEnabled,
            permission: .notRequired,
            availability: .available,
            health: lastError.map { .degraded(message: $0) } ?? .healthy,
            supportedActions: [.start, .stop, .test],
            isActive: isActive,
            progress: progress(at: now()),
            statusText: statusText(at: now())
        )
    }

    func startIndefinite() throws {
        try start(duration: nil)
    }

    func start(preset: KeepAwakePreset) throws {
        try start(duration: preset.duration)
    }

    func start(customDuration: TimeInterval) throws {
        guard customDuration.isFinite, customDuration > 0 else {
            throw KeepAwakeControllerError.invalidDuration
        }
        try start(duration: customDuration)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        assertionLease?.invalidate()
        assertionLease = nil
        isActive = false
        startedAt = nil
        expiresAt = nil
        configuredDuration = nil
        lastError = nil
        liveActivities.remove(id: Self.activityID)
        publishState()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled, isActive {
            stop()
            isEnabled = false
        }
        publishState()
    }

    func refresh() async {
        tick()
    }

    func perform(_ action: IslandCapabilityAction) async throws {
        switch action {
        case .start:
            try startIndefinite()
        case .stop:
            stop()
        case .test:
            try start(customDuration: 5)
        case .openSettings, .configureShortcut:
            throw KeepAwakeControllerError.unsupportedAction(action)
        }
    }

    func tick(at date: Date? = nil) {
        let current = date ?? now()
        if let expiresAt, current >= expiresAt {
            stop()
            return
        }
        publishActivity(at: current)
        publishState()
    }

    private func start(duration: TimeInterval?) throws {
        guard isEnabled else { return }
        let acquired: KeepAwakeAssertionLease
        do {
            acquired = try assertionProvider.acquire(reason: "DynamicIsland Keep Awake")
        } catch {
            lastError = error.localizedDescription
            publishState(failed: true)
            throw error
        }

        assertionLease?.invalidate()
        assertionLease = acquired

        let current = now()
        startedAt = current
        configuredDuration = duration
        expiresAt = duration.map { current.addingTimeInterval($0) }
        isActive = true
        lastError = nil

        scheduleTimer()
        publishActivity(at: current)
        publishState()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func publishActivity(at date: Date) {
        guard isActive else {
            liveActivities.remove(id: Self.activityID)
            return
        }

        liveActivities.update(
            DynamicIslandLiveActivity(
                id: Self.activityID,
                kind: .keepAwake,
                title: "Keep Awake",
                subtitle: statusText(at: date),
                symbolName: "cup.and.saucer.fill",
                priority: 72,
                isActive: true,
                progress: progress(at: date),
                updatedAt: date,
                lifecycle: LiveActivityLifecycleMetadata(
                    authority: .systemAPI,
                    startEvidence: "IOPM power assertion acquired",
                    progressEvidence: configuredDuration == nil ? nil : "authoritative elapsed duration",
                    completionEvidence: "power assertion released",
                    dismissPolicy: .untilSourceEnds,
                    supportsCancellation: true
                )
            )
        )
    }

    private func publishState(failed: Bool = false) {
        var value = snapshot
        if failed, let lastError {
            value.health = .failed(message: lastError)
        }
        capabilities.update(value)
    }

    private func progress(at date: Date) -> Double? {
        guard isActive,
              let configuredDuration,
              configuredDuration > 0,
              let startedAt else {
            return nil
        }
        let elapsed = max(date.timeIntervalSince(startedAt), 0)
        return IslandCapabilitySnapshot.clampedProgress(elapsed / configuredDuration)
    }

    private func statusText(at date: Date) -> String {
        guard isActive else { return "Off" }
        guard let expiresAt else { return "Indefinite" }
        let remaining = max(Int(ceil(expiresAt.timeIntervalSince(date))), 0)
        return LiveActivityTimeFormatting.remainingTime(remaining)
    }
}
