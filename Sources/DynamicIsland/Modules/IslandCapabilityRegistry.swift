import Foundation

enum IslandCapabilityID: String, CaseIterable, Codable, Hashable, Sendable {
    case keepAwake
    case windowSnap
    case terminal
    case reminders
    case voiceTranscribe
    case camera
    case backgroundRemoval
    case screenRecording
}

enum IslandCapabilityPermissionState: Equatable, Sendable {
    case notRequired
    case notDetermined
    case required
    case denied
    case granted
}

enum IslandCapabilityAvailability: Equatable, Sendable {
    case available
    case unsupported(reason: String)
    case temporarilyUnavailable(reason: String)
}

enum IslandCapabilityHealth: Equatable, Sendable {
    case healthy
    case degraded(message: String)
    case failed(message: String)
}

enum IslandCapabilityAction: String, CaseIterable, Hashable, Sendable {
    case start
    case stop
    case test
    case openSettings
    case configureShortcut
}

struct IslandCapabilitySnapshot: Equatable, Sendable, Identifiable {
    let id: IslandCapabilityID
    var isEnabled: Bool
    var permission: IslandCapabilityPermissionState
    var availability: IslandCapabilityAvailability
    var health: IslandCapabilityHealth
    var supportedActions: Set<IslandCapabilityAction>
    var isActive: Bool
    var progress: Double?
    var statusText: String?
    var shortcutIdentifier: String?

    init(
        id: IslandCapabilityID,
        isEnabled: Bool = true,
        permission: IslandCapabilityPermissionState = .notRequired,
        availability: IslandCapabilityAvailability = .available,
        health: IslandCapabilityHealth = .healthy,
        supportedActions: Set<IslandCapabilityAction> = [],
        isActive: Bool = false,
        progress: Double? = nil,
        statusText: String? = nil,
        shortcutIdentifier: String? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.permission = permission
        self.availability = availability
        self.health = health
        self.supportedActions = supportedActions
        self.isActive = isActive
        self.progress = Self.clampedProgress(progress)
        self.statusText = statusText
        self.shortcutIdentifier = shortcutIdentifier
    }

    var isOperational: Bool {
        guard isEnabled else { return false }
        guard permission == .notRequired || permission == .granted else { return false }
        guard case .available = availability else { return false }
        guard case .failed = health else { return true }
        return false
    }

    static func clampedProgress(_ progress: Double?) -> Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(max(progress, 0), 1)
    }
}

@MainActor
final class IslandCapabilityRegistry: ObservableObject {
    @Published private(set) var snapshots: [IslandCapabilityID: IslandCapabilitySnapshot] = [:]

    func update(_ snapshot: IslandCapabilitySnapshot) {
        snapshots[snapshot.id] = snapshot
    }

    func remove(_ id: IslandCapabilityID) {
        snapshots.removeValue(forKey: id)
    }

    func snapshot(for id: IslandCapabilityID) -> IslandCapabilitySnapshot? {
        snapshots[id]
    }
}

@MainActor
protocol IslandCapabilityAdapter: AnyObject {
    var capabilityID: IslandCapabilityID { get }
    var snapshot: IslandCapabilitySnapshot { get }

    func refresh() async
    func perform(_ action: IslandCapabilityAction) async throws
}
