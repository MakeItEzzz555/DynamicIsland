import Foundation

enum DynamicIslandLiveActivityKind: String, Equatable {
    case media
    case timer
    case fileTray
    case system
}

enum CollapsedLiveActivityPrioritySource: String, CaseIterable, Identifiable {
    case runningTimer
    case playingMedia
    case pausedTimer
    case recentFiles
    case pausedMedia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .runningTimer:
            "Running Timer"
        case .playingMedia:
            "Playing Media"
        case .pausedTimer:
            "Paused Timer"
        case .recentFiles:
            "Recent Files"
        case .pausedMedia:
            "Paused Media"
        }
    }

    var defaultPriority: Int {
        switch self {
        case .runningTimer:
            100
        case .playingMedia:
            90
        case .pausedTimer:
            80
        case .recentFiles:
            60
        case .pausedMedia:
            50
        }
    }

    var defaultRank: Int {
        switch self {
        case .runningTimer:
            0
        case .playingMedia:
            1
        case .pausedTimer:
            2
        case .recentFiles:
            3
        case .pausedMedia:
            4
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
}

enum CollapsedIslandContentMode: Equatable {
    case inactive
    case media
    case timer(DynamicIslandLiveActivity)
    case fileTray(DynamicIslandLiveActivity)
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

struct DynamicIslandLiveActivity: Identifiable, Equatable {
    let id: String
    let kind: DynamicIslandLiveActivityKind
    let title: String
    let subtitle: String?
    let symbolName: String
    let priority: Int
    let isActive: Bool
    let progress: Double?
    let updatedAt: Date
}

enum CollapsedLiveActivitySelector {
    static func select(
        activities: [DynamicIslandLiveActivity],
        priorities: CollapsedLiveActivityPrioritySettings,
        toggles: CollapsedLiveActivitySourceToggles
    ) -> CollapsedIslandContentMode {
        guard toggles.liveActivitiesEnabled else { return .inactive }

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
        case .playingMedia, .pausedMedia:
            return .media
        case .runningTimer, .pausedTimer:
            return .timer(selected.activity)
        case .recentFiles:
            return .fileTray(selected.activity)
        }
    }

    static func previewActivities(
        activities: [DynamicIslandLiveActivity],
        priorities: CollapsedLiveActivityPrioritySettings,
        toggles: CollapsedLiveActivitySourceToggles,
        maxCount: Int = 3
    ) -> [DynamicIslandLiveActivity] {
        guard toggles.liveActivitiesEnabled, maxCount > 0 else { return [] }

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
        case .system:
            return nil
        }
    }

    private static func isSourceEnabled(
        _ source: CollapsedLiveActivityPrioritySource,
        toggles: CollapsedLiveActivitySourceToggles
    ) -> Bool {
        switch source {
        case .runningTimer, .pausedTimer:
            return toggles.timerEnabled
        case .playingMedia, .pausedMedia:
            return toggles.mediaEnabled
        case .recentFiles:
            return toggles.fileTrayEnabled
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
