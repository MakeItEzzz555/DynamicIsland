import AppKit
import EventKit
import Foundation

enum ReminderAccessState: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess
    case unavailable(reason: String)
}

struct ReminderListDescriptor: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
}

struct ReminderDescriptor: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let listID: String
    let listTitle: String
    let dueDate: Date?
    let isCompleted: Bool
}

/// Boundary around EventKit so tests never touch real Reminders data or
/// trigger the system privacy prompt.
@MainActor
protocol RemindersProviding: AnyObject {
    var accessState: ReminderAccessState { get }
    /// Only called from an explicit user action; this is the single path
    /// that may present the system Reminders prompt.
    func requestFullAccess() async throws -> ReminderAccessState
    func fetchLists() throws -> [ReminderListDescriptor]
    func createReminder(title: String, listID: String, dueDate: Date?) throws -> ReminderDescriptor
    func completeReminder(id: String) throws
    func fetchUpcomingReminders(from start: Date, through end: Date) async throws -> [ReminderDescriptor]
    /// Posts whenever the underlying store changes outside the app.
    var changeNotificationName: Notification.Name? { get }
}

@MainActor
final class EventKitRemindersProvider: RemindersProviding {
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    var accessState: ReminderAccessState {
        Self.mapAuthorization(EKEventStore.authorizationStatus(for: .reminder))
    }

    var changeNotificationName: Notification.Name? { .EKEventStoreChanged }

    func requestFullAccess() async throws -> ReminderAccessState {
        if #available(macOS 14.0, *) {
            _ = try await store.requestFullAccessToReminders()
        } else {
            let _: Bool = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Bool, any Error>) in
                store.requestAccess(to: .reminder) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
        return accessState
    }

    func fetchLists() throws -> [ReminderListDescriptor] {
        RemindersController.sortedLists(
            store.calendars(for: .reminder)
                .map { ReminderListDescriptor(id: $0.calendarIdentifier, title: $0.title) }
        )
    }

    func createReminder(title: String, listID: String, dueDate: Date?) throws -> ReminderDescriptor {
        guard let calendar = store.calendar(withIdentifier: listID),
              calendar.allowsContentModifications else {
            throw RemindersControllerError.listUnavailable
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        reminder.dueDateComponents = dueDate.map { RemindersController.dueDateComponents(for: $0) }
        try store.save(reminder, commit: true)

        return Self.descriptor(reminder, calendar: calendar)
    }

    func completeReminder(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersControllerError.reminderUnavailable
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    func fetchUpcomingReminders(from start: Date, through end: Date) async throws -> [ReminderDescriptor] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: nil
        )

        // EKReminder is not Sendable; convert to value descriptors inside the
        // EventKit callback before crossing back to the main actor.
        return await withCheckedContinuation { (continuation: CheckedContinuation<[ReminderDescriptor], Never>) in
            store.fetchReminders(matching: predicate) { reminders in
                let descriptors = (reminders ?? []).compactMap { reminder -> ReminderDescriptor? in
                    guard let calendar = reminder.calendar else { return nil }
                    return Self.descriptor(reminder, calendar: calendar)
                }
                continuation.resume(returning: descriptors)
            }
        }
    }

    nonisolated static func mapAuthorization(_ status: EKAuthorizationStatus) -> ReminderAccessState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .writeOnly:
            return .writeOnly
        case .fullAccess:
            return .fullAccess
        @unknown default:
            return .unavailable(reason: "Unknown Reminders authorization state")
        }
    }

    nonisolated private static func descriptor(_ reminder: EKReminder, calendar: EKCalendar) -> ReminderDescriptor {
        ReminderDescriptor(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Reminder",
            listID: calendar.calendarIdentifier,
            listTitle: calendar.title,
            dueDate: reminder.dueDateComponents.flatMap(RemindersController.dueDate(from:)),
            isCompleted: reminder.isCompleted
        )
    }
}

enum RemindersControllerError: LocalizedError, Equatable {
    case permissionRequired
    case invalidTitle
    case listUnavailable
    case reminderUnavailable
    case disabled
    case unsupportedAction(IslandCapabilityAction)

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "Full Reminders access is required."
        case .invalidTitle:
            "Reminder title cannot be empty."
        case .listUnavailable:
            "The selected reminder list is no longer available."
        case .reminderUnavailable:
            "The reminder is no longer available."
        case .disabled:
            "Reminders integration is disabled."
        case .unsupportedAction(let action):
            "Reminders does not support \(action.rawValue) without additional context."
        }
    }
}

@MainActor
final class RemindersController: ObservableObject, IslandCapabilityAdapter {
    static let activityID = "reminder.upcoming"
    static let maximumTitleLength = 500

    let capabilityID: IslandCapabilityID = .reminders

    @Published private(set) var lists: [ReminderListDescriptor] = []
    @Published var selectedListID: String?
    @Published private(set) var upcomingReminders: [ReminderDescriptor] = []
    @Published private(set) var lastError: String?
    @Published private(set) var accessState: ReminderAccessState
    @Published private(set) var isEnabled = true

    private let provider: RemindersProviding
    private let liveActivities: LiveActivityStore
    private let capabilities: IslandCapabilityRegistry
    private let now: () -> Date
    private let upcomingWindow: TimeInterval
    private let activityLeadTime: TimeInterval
    private var healthOverride: IslandCapabilityHealth?
    nonisolated(unsafe) private var changeObserver: NSObjectProtocol?
    private var dueRefreshTask: Task<Void, Never>?

    init(
        liveActivities: LiveActivityStore,
        capabilities: IslandCapabilityRegistry,
        provider: RemindersProviding = EventKitRemindersProvider(),
        now: @escaping () -> Date = Date.init,
        upcomingWindow: TimeInterval = 7 * 24 * 60 * 60,
        activityLeadTime: TimeInterval = 60 * 60
    ) {
        self.liveActivities = liveActivities
        self.capabilities = capabilities
        self.provider = provider
        self.now = now
        self.upcomingWindow = upcomingWindow
        self.activityLeadTime = activityLeadTime
        self.accessState = provider.accessState
        if let name = provider.changeNotificationName {
            changeObserver = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
        }
        publishState()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        dueRefreshTask?.cancel()
    }

    var snapshot: IslandCapabilitySnapshot {
        let mapping = Self.capabilityMapping(for: accessState)
        return IslandCapabilitySnapshot(
            id: .reminders,
            isEnabled: isEnabled,
            permission: mapping.permission,
            availability: mapping.availability,
            health: healthOverride ?? .healthy,
            supportedActions: [.test, .openSettings],
            isActive: isEnabled && !upcomingReminders.isEmpty,
            statusText: statusText
        )
    }

    var statusText: String {
        guard isEnabled else { return "Disabled" }
        switch accessState {
        case .notDetermined: return "Permission not requested"
        case .denied: return "Permission denied"
        case .restricted: return "Access restricted"
        case .writeOnly: return "Full access required"
        case .fullAccess:
            return upcomingReminders.isEmpty ? "No upcoming reminders" : "\(upcomingReminders.count) upcoming"
        case .unavailable(let reason): return reason
        }
    }

    /// Maps EventKit authorization onto the shared capability model.
    static func capabilityMapping(
        for state: ReminderAccessState
    ) -> (permission: IslandCapabilityPermissionState, availability: IslandCapabilityAvailability) {
        switch state {
        case .notDetermined:
            return (.notDetermined, .available)
        case .denied:
            return (.denied, .available)
        case .restricted:
            return (.denied, .unsupported(reason: "Reminders access is restricted on this Mac."))
        case .writeOnly:
            return (.required, .temporarilyUnavailable(reason: "Full Reminders access is required to read upcoming reminders."))
        case .fullAccess:
            return (.granted, .available)
        case .unavailable(let reason):
            return (.required, .unsupported(reason: reason))
        }
    }

    /// Explicit user action only. Never called at launch.
    func requestAccess() async {
        guard isEnabled else { return }
        do {
            accessState = try await provider.requestFullAccess()
            healthOverride = nil
            lastError = nil
            await refresh()
        } catch {
            accessState = provider.accessState
            fail(with: error)
        }
    }

    /// Re-reads authoritative EventKit state. Reads authorization status
    /// without prompting.
    func refresh() async {
        accessState = provider.accessState
        guard isEnabled, accessState == .fullAccess else {
            lists = []
            upcomingReminders = []
            removeActivity()
            publishState()
            return
        }

        do {
            lists = try provider.fetchLists()
            if selectedListID == nil || !lists.contains(where: { $0.id == selectedListID }) {
                selectedListID = lists.first?.id
            }
            let start = now()
            let fetched = try await provider.fetchUpcomingReminders(
                from: start,
                through: start.addingTimeInterval(upcomingWindow)
            )
            upcomingReminders = Self.sortedUpcoming(fetched, now: start)
            healthOverride = nil
            lastError = nil
            publishActivity(at: start)
            scheduleDueRefresh(after: start)
            publishState()
        } catch {
            fail(with: error)
        }
    }

    @discardableResult
    func createReminder(title rawTitle: String, dueDate: Date?) async throws -> ReminderDescriptor {
        guard isEnabled else { throw RemindersControllerError.disabled }
        accessState = provider.accessState
        guard accessState == .fullAccess else {
            throw RemindersControllerError.permissionRequired
        }

        let title = try Self.validatedTitle(rawTitle)

        if lists.isEmpty {
            lists = try provider.fetchLists()
        }
        guard let listID = selectedListID ?? lists.first?.id,
              lists.contains(where: { $0.id == listID }) else {
            throw RemindersControllerError.listUnavailable
        }

        let reminder = try provider.createReminder(title: title, listID: listID, dueDate: dueDate)
        await refresh()
        return reminder
    }

    func completeReminder(id: String) async throws {
        guard isEnabled else { throw RemindersControllerError.disabled }
        accessState = provider.accessState
        guard accessState == .fullAccess else {
            throw RemindersControllerError.permissionRequired
        }
        do {
            try provider.completeReminder(id: id)
        } catch {
            // Still refresh so presentation matches EventKit after a failure.
            await refresh()
            throw error
        }
        // No optimistic local removal: completion is reflected only after
        // EventKit re-reports the reminder set.
        await refresh()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            lists = []
            upcomingReminders = []
            dueRefreshTask?.cancel()
            dueRefreshTask = nil
            removeActivity()
        }
        publishState()
    }

    func perform(_ action: IslandCapabilityAction) async throws {
        switch action {
        case .test:
            await refresh()
        case .openSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                NSWorkspace.shared.open(url)
            }
        case .start, .stop, .configureShortcut:
            throw RemindersControllerError.unsupportedAction(action)
        }
    }

    static func validatedTitle(_ rawTitle: String) throws -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= maximumTitleLength else {
            throw RemindersControllerError.invalidTitle
        }
        return title
    }

    nonisolated static func dueDateComponents(
        for date: Date,
        calendar: Calendar = .current
    ) -> DateComponents {
        calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: date
        )
    }

    nonisolated static func dueDate(from components: DateComponents) -> Date? {
        let calendar = components.calendar ?? .current
        return calendar.date(from: components)
    }

    nonisolated static func sortedLists(_ lists: [ReminderListDescriptor]) -> [ReminderListDescriptor] {
        lists.sorted {
            let order = $0.title.localizedCaseInsensitiveCompare($1.title)
            if order == .orderedSame {
                return $0.id < $1.id
            }
            return order == .orderedAscending
        }
    }

    static func sortedUpcoming(_ reminders: [ReminderDescriptor], now: Date) -> [ReminderDescriptor] {
        reminders
            .filter { reminder in
                guard !reminder.isCompleted else { return false }
                guard let dueDate = reminder.dueDate else { return true }
                return dueDate >= now
            }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?):
                    if left != right { return left < right }
                    return lhs.id < rhs.id
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.id < rhs.id
                }
            }
    }

    /// The live activity only represents a reminder that is due soon; lists
    /// further out stay visible in the expanded/settings surfaces only.
    static func activityReminder(
        in upcoming: [ReminderDescriptor],
        now: Date,
        leadTime: TimeInterval
    ) -> ReminderDescriptor? {
        guard let first = upcoming.first,
              let dueDate = first.dueDate,
              !first.isCompleted,
              dueDate >= now,
              dueDate <= now.addingTimeInterval(leadTime) else {
            return nil
        }
        return first
    }

    private func fail(with error: Error) {
        lists = []
        upcomingReminders = []
        lastError = error.localizedDescription
        healthOverride = .failed(message: error.localizedDescription)
        removeActivity()
        publishState()
    }

    /// Re-reads EventKit when the next reminder enters the activity lead
    /// window or passes its due time, instead of mutating local state.
    private func scheduleDueRefresh(after date: Date) {
        dueRefreshTask?.cancel()
        dueRefreshTask = nil
        guard let nextDue = upcomingReminders.first?.dueDate else { return }
        let windowStart = nextDue.addingTimeInterval(-activityLeadTime)
        let fireDate = windowStart > date ? windowStart : nextDue
        let delay = max(fireDate.timeIntervalSince(date), 0) + 1
        dueRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func publishActivity(at date: Date) {
        guard let reminder = Self.activityReminder(
            in: upcomingReminders,
            now: date,
            leadTime: activityLeadTime
        ) else {
            removeActivity()
            return
        }

        let subtitle = reminder.dueDate.map { Self.activityDateFormatter.string(from: $0) } ?? reminder.listTitle

        liveActivities.update(
            DynamicIslandLiveActivity(
                id: Self.activityID,
                kind: .reminder,
                title: reminder.title,
                subtitle: subtitle,
                symbolName: "checklist",
                priority: 78,
                isActive: true,
                progress: nil,
                updatedAt: date,
                lifecycle: LiveActivityLifecycleMetadata(
                    authority: .eventKit,
                    startEvidence: "EventKit returned an authoritative incomplete reminder",
                    progressEvidence: nil,
                    completionEvidence: "EventKit reminder completion state",
                    dismissPolicy: .untilSourceEnds,
                    supportsCancellation: false
                )
            )
        )
    }

    private func removeActivity() {
        liveActivities.remove(id: Self.activityID)
    }

    private func publishState() {
        capabilities.update(snapshot)
    }

    private static let activityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
