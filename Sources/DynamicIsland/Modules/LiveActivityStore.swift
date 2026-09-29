import Foundation

enum DynamicIslandLiveActivityKind: String, Equatable, Sendable {
    case media
    case timer
    case fileTray
    case battery
    case system
    case agent
}

enum CollapsedLiveActivityPrioritySource: String, CaseIterable, Identifiable {
    case systemHUD
    case runningTimer
    case playingMedia
    case lowBattery
    case pausedTimer
    case recentFiles
    case pausedMedia
    case chargingBattery
    case fullBattery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemHUD:
            "System HUD"
        case .runningTimer:
            "Running Timer"
        case .playingMedia:
            "Playing Media"
        case .lowBattery:
            "Low Battery"
        case .pausedTimer:
            "Paused Timer"
        case .recentFiles:
            "Recent Files"
        case .pausedMedia:
            "Paused Media"
        case .chargingBattery:
            "Charging Battery"
        case .fullBattery:
            "Charged Battery"
        }
    }

    var defaultPriority: Int {
        switch self {
        case .systemHUD:
            200
        case .runningTimer:
            100
        case .playingMedia:
            90
        case .lowBattery:
            85
        case .pausedTimer:
            80
        case .recentFiles:
            60
        case .pausedMedia:
            50
        case .chargingBattery, .fullBattery:
            45
        }
    }

    var defaultRank: Int {
        switch self {
        case .systemHUD:
            0
        case .runningTimer:
            1
        case .playingMedia:
            2
        case .lowBattery:
            3
        case .pausedTimer:
            4
        case .recentFiles:
            5
        case .pausedMedia:
            6
        case .chargingBattery:
            7
        case .fullBattery:
            8
        }
    }
}

struct CollapsedLiveActivityPrioritySettings: Equatable {
    static let range = 0...200

    var runningTimer: Int
    var playingMedia: Int
    var pausedTimer: Int
    var recentFiles: Int
    var pausedMedia: Int

    static var defaults: CollapsedLiveActivityPrioritySettings {
        CollapsedLiveActivityPrioritySettings(
            runningTimer: CollapsedLiveActivityPrioritySource.runningTimer.defaultPriority,
            playingMedia: CollapsedLiveActivityPrioritySource.playingMedia.defaultPriority,
            pausedTimer: CollapsedLiveActivityPrioritySource.pausedTimer.defaultPriority,
            recentFiles: CollapsedLiveActivityPrioritySource.recentFiles.defaultPriority,
            pausedMedia: CollapsedLiveActivityPrioritySource.pausedMedia.defaultPriority
        )
    }

    func priority(for source: CollapsedLiveActivityPrioritySource) -> Int {
        let value: Int
        switch source {
        case .systemHUD:
            value = source.defaultPriority
        case .runningTimer:
            value = runningTimer
        case .playingMedia:
            value = playingMedia
        case .pausedTimer:
            value = pausedTimer
        case .recentFiles:
            value = recentFiles
        case .pausedMedia:
            value = pausedMedia
        case .lowBattery, .chargingBattery, .fullBattery:
            value = source.defaultPriority
        }
        return Self.clamped(value)
    }

    static func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct CollapsedLiveActivitySourceToggles: Equatable {
    var liveActivitiesEnabled: Bool
    var timerEnabled: Bool
    var mediaEnabled: Bool
    var fileTrayEnabled: Bool
    var batteryEnabled: Bool
    var systemHUDEnabled: Bool = false
}

enum CollapsedIslandContentMode: Equatable {
    case inactive
    case media
    case agent(DynamicIslandLiveActivity)
    case system(DynamicIslandLiveActivity)
    case timer(DynamicIslandLiveActivity)
    case fileTray(DynamicIslandLiveActivity)
    case battery(DynamicIslandLiveActivity)
}

enum BatteryLiveActivityState: String, Equatable {
    case low
    case charging
    case pluggedIn
    case full
}

enum LiveActivityTimeFormatting {
    static func remainingTime(_ seconds: Int) -> String {
        let clampedSeconds = max(seconds, 0)
        let hours = clampedSeconds / 3600
        let minutes = (clampedSeconds % 3600) / 60
        let seconds = clampedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct DynamicIslandLiveActivity: Identifiable, Equatable, Sendable {
    let id: String
    let kind: DynamicIslandLiveActivityKind
    let title: String
    let subtitle: String?
    let symbolName: String
    let priority: Int
    let isActive: Bool
    let progress: Double?
    let updatedAt: Date
    let batteryState: BatteryLiveActivityState?

    init(
        id: String,
        kind: DynamicIslandLiveActivityKind,
        title: String,
        subtitle: String?,
        symbolName: String,
        priority: Int,
        isActive: Bool,
        progress: Double?,
        updatedAt: Date,
        batteryState: BatteryLiveActivityState? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.priority = priority
        self.isActive = isActive
        self.progress = progress
        self.updatedAt = updatedAt
        self.batteryState = batteryState
    }
}

enum CollapsedLiveActivitySelector {
    static func select(
        activities: [DynamicIslandLiveActivity],
        priorities: CollapsedLiveActivityPrioritySettings,
        toggles: CollapsedLiveActivitySourceToggles
    ) -> CollapsedIslandContentMode {
        guard toggles.liveActivitiesEnabled || toggles.systemHUDEnabled else { return .inactive }

        guard let selected = candidates(
            activities: activities,
            priorities: priorities,
            toggles: toggles
        )
        .sorted(by: candidateSort)
        .first else {
            return .inactive
        }

        switch selected.source {
        case .systemHUD:
            return .system(selected.activity)
        case .playingMedia, .pausedMedia:
            return .media
        case .runningTimer, .pausedTimer:
            return .timer(selected.activity)
        case .recentFiles:
            return .fileTray(selected.activity)
        case .lowBattery, .chargingBattery, .fullBattery:
            return .battery(selected.activity)
        }
    }

    static func previewActivities(
        activities: [DynamicIslandLiveActivity],
        priorities: CollapsedLiveActivityPrioritySettings,
        toggles: CollapsedLiveActivitySourceToggles,
        maxCount: Int = 3
    ) -> [DynamicIslandLiveActivity] {
        guard (toggles.liveActivitiesEnabled || toggles.systemHUDEnabled), maxCount > 0 else { return [] }

        return candidates(
            activities: activities,
            priorities: priorities,
            toggles: toggles
        )
        .sorted(by: candidateSort)
        .prefix(maxCount)
        .map(\.activity)
    }

    private struct Candidate {
        let activity: DynamicIslandLiveActivity
        let source: CollapsedLiveActivityPrioritySource
        let priority: Int
    }

    private static func candidates(
        activities: [DynamicIslandLiveActivity],
        priorities: CollapsedLiveActivityPrioritySettings,
        toggles: CollapsedLiveActivitySourceToggles
    ) -> [Candidate] {
        activities.compactMap { activity -> Candidate? in
            guard let source = source(for: activity) else { return nil }
            guard isSourceEnabled(source, toggles: toggles) else { return nil }
            return Candidate(
                activity: activity,
                source: source,
                priority: priorities.priority(for: source)
            )
        }
    }

    private static func source(for activity: DynamicIslandLiveActivity) -> CollapsedLiveActivityPrioritySource? {
        switch activity.kind {
        case .timer:
            return activity.isActive ? .runningTimer : .pausedTimer
        case .media:
            return activity.isActive ? .playingMedia : .pausedMedia
        case .fileTray:
            return .recentFiles
        case .battery:
            switch activity.batteryState {
            case .low:
                return .lowBattery
            case .charging, .pluggedIn:
                return .chargingBattery
            case .full:
                return .fullBattery
            case nil:
                return nil
            }
        case .system:
            return .systemHUD
        case .agent:
            return nil
        }
    }

    private static func isSourceEnabled(
        _ source: CollapsedLiveActivityPrioritySource,
        toggles: CollapsedLiveActivitySourceToggles
    ) -> Bool {
        switch source {
        case .systemHUD:
            return toggles.systemHUDEnabled
        case .runningTimer, .pausedTimer:
            return toggles.liveActivitiesEnabled && toggles.timerEnabled
        case .playingMedia, .pausedMedia:
            return toggles.liveActivitiesEnabled && toggles.mediaEnabled
        case .recentFiles:
            return toggles.liveActivitiesEnabled && toggles.fileTrayEnabled
        case .lowBattery, .chargingBattery, .fullBattery:
            return toggles.liveActivitiesEnabled && toggles.batteryEnabled
        }
    }

    private static func candidateSort(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        if lhs.source.defaultRank != rhs.source.defaultRank {
            return lhs.source.defaultRank < rhs.source.defaultRank
        }
        if lhs.activity.updatedAt != rhs.activity.updatedAt {
            return lhs.activity.updatedAt > rhs.activity.updatedAt
        }
        return lhs.activity.title.localizedCaseInsensitiveCompare(rhs.activity.title) == .orderedAscending
    }
}

@MainActor
final class LiveActivityStore: ObservableObject {
    static let timerActivityID = "timer"
    static let mediaActivityID = "media"
    static let fileTrayActivityID = "fileTray"
    static let systemHUDActivityID = "systemHUD"
    nonisolated static let batteryActivityID = "battery"

    @Published private(set) var activities: [DynamicIslandLiveActivity] = []

    var primaryActivity: DynamicIslandLiveActivity? {
        activities.first
    }

    func update(_ activity: DynamicIslandLiveActivity) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
        activities = Self.sorted(activities)
    }

    func remove(id: String) {
        activities.removeAll { $0.id == id }
    }

    func removeAll() {
        activities.removeAll()
    }

    static func clampedProgress(_ progress: Double?) -> Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(max(progress, 0), 1)
    }

    private static func sorted(_ activities: [DynamicIslandLiveActivity]) -> [DynamicIslandLiveActivity] {
        activities.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
