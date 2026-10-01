import AppKit
import EventKit
import Foundation

enum CalendarAccessState: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess
}

struct CalendarEventDescriptor: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    /// sRGB components of the calendar color, when EventKit provides one.
    let calendarColor: [Double]?
    /// A link present on the event itself (URL field, or a link in the
    /// location/notes). Nil when the event carries no link.
    let meetingURL: URL?
}

@MainActor
protocol CalendarEventsProviding: AnyObject {
    var accessState: CalendarAccessState { get }
    func requestFullAccess() async throws -> CalendarAccessState
    func upcomingEvents(from start: Date, through end: Date) -> [CalendarEventDescriptor]
    var changeNotificationName: Notification.Name? { get }
}

@MainActor
final class EventKitCalendarProvider: CalendarEventsProviding {
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    var accessState: CalendarAccessState {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    var changeNotificationName: Notification.Name? { .EKEventStoreChanged }

    func requestFullAccess() async throws -> CalendarAccessState {
        _ = try await store.requestFullAccessToEvents()
        return accessState
    }

    func upcomingEvents(from start: Date, through end: Date) -> [CalendarEventDescriptor] {
        guard accessState == .fullAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard let id = event.eventIdentifier else { return nil }
            return CalendarEventDescriptor(
                id: id,
                title: event.title?.isEmpty == false ? event.title : "Untitled event",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar?.title ?? "",
                calendarColor: event.calendar?.color.flatMap(Self.components),
                meetingURL: CalendarMeetingLink.find(url: event.url, location: event.location, notes: event.notes)
            )
        }
    }

    static func map(_ status: EKAuthorizationStatus) -> CalendarAccessState {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess, .authorized: .fullAccess
        @unknown default: .denied
        }
    }

    private static func components(_ color: NSColor) -> [Double]? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return [Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)]
    }
}

/// Finds a link that is actually present on an event. Never invents one.
enum CalendarMeetingLink {
    static func find(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) { return url }
        for text in [location, notes].compactMap({ $0 }) {
            if let link = firstLink(in: text) { return link }
        }
        return nil
    }

    static func firstLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).lazy
            .compactMap(\.url)
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }
}

/// EventKit events for the Right Workspace. Publishes two views of the same
/// store: `events` (upcoming summary, next seven days) and `dayEvents` (the
/// whole local day the user selected). Access is requested only from an
/// explicit user action; both refresh on store changes while observed.
@MainActor
final class CalendarEventsController: ObservableObject {
    static let lookahead: TimeInterval = 7 * 24 * 60 * 60
    static let maximumEvents = 8
    static let maximumDayEvents = 40

    @Published private(set) var accessState: CalendarAccessState
    @Published private(set) var events: [CalendarEventDescriptor] = []
    /// Start of the selected local day.
    @Published private(set) var selectedDay: Date
    @Published private(set) var dayEvents: [CalendarEventDescriptor] = []
    @Published private(set) var lastError: String?

    private let provider: CalendarEventsProviding
    private let now: () -> Date
    private let calendar: Calendar
    private var observer: NSObjectProtocol?
    private var dayObservers: [NSObjectProtocol] = []
    private var lastObservedToday: Date

    init(
        provider: CalendarEventsProviding = EventKitCalendarProvider(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.provider = provider
        self.now = now
        self.calendar = calendar
        accessState = provider.accessState
        let today = calendar.startOfDay(for: now())
        selectedDay = today
        lastObservedToday = today
    }

    /// The local day containing `date`, from midnight to the next midnight
    /// (23 or 25 hours on DST transition days).
    nonisolated static func dayInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 60 * 60)
    }

    /// Events overlapping the interval (all-day, in-progress and events that
    /// cross midnight included; an event ending exactly at its start is not),
    /// all-day first, then chronological.
    nonisolated static func events(
        _ events: [CalendarEventDescriptor],
        overlapping interval: DateInterval
    ) -> [CalendarEventDescriptor] {
        events
            .filter { $0.endDate > interval.start && $0.startDate < interval.end }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                return $0.id < $1.id
            }
    }

    var isSelectedDayToday: Bool {
        calendar.isDate(selectedDay, inSameDayAs: now())
    }

    var dayStatusText: String {
        dayEvents.isEmpty ? "No events on this date" : "\(dayEvents.count) event\(dayEvents.count == 1 ? "" : "s")"
    }

    /// Never requests permission; reads only with full access.
    func selectDay(containing date: Date) {
        let day = calendar.startOfDay(for: date)
        if day != selectedDay { selectedDay = day }
        refreshSelectedDay()
    }

    func shiftSelectedDay(by days: Int) {
        guard let day = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
        selectDay(containing: day)
    }

    func selectToday() {
        selectDay(containing: now())
    }

    /// Midnight or time-zone change: a "today" selection follows the clock;
    /// an explicitly chosen other day is kept.
    func handleDayChange() {
        let today = calendar.startOfDay(for: now())
        if selectedDay == lastObservedToday { selectedDay = today }
        lastObservedToday = today
        refresh()
    }

    private func refreshSelectedDay() {
        guard accessState == .fullAccess else {
            if !dayEvents.isEmpty { dayEvents = [] }
            return
        }
        let interval = Self.dayInterval(containing: selectedDay, calendar: calendar)
        let next = Array(
            Self.events(provider.upcomingEvents(from: interval.start, through: interval.end), overlapping: interval)
                .prefix(Self.maximumDayEvents)
        )
        if next != dayEvents { dayEvents = next }
    }

    var statusText: String {
        switch accessState {
        case .notDetermined: "Calendar access not requested"
        case .denied: "Calendar access denied"
        case .restricted: "Calendar access restricted"
        case .writeOnly: "Calendar access is add-only; reading events needs full access"
        case .fullAccess: events.isEmpty ? "No upcoming events this week" : "\(events.count) upcoming"
        }
    }

    /// Explicit user action.
    func requestAccess() async {
        do {
            accessState = try await provider.requestFullAccess()
            lastError = nil
        } catch {
            accessState = provider.accessState
            lastError = "Calendar access could not be requested"
        }
        refresh()
    }

    /// Reads without prompting.
    func refresh() {
        accessState = provider.accessState
        guard accessState == .fullAccess else {
            events = []
            dayEvents = []
            return
        }
        refreshSelectedDay()
        let start = now()
        events = Array(
            provider.upcomingEvents(from: start, through: start.addingTimeInterval(Self.lookahead))
                .filter { $0.endDate > start }
                .sorted {
                    if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                    return $0.id < $1.id
                }
                .prefix(Self.maximumEvents)
        )
    }

    private var observingSurfaces = 0

    /// Reference-counted: each visible surface starts and stops once.
    func startObserving() {
        observingSurfaces += 1
        if dayObservers.isEmpty {
            dayObservers = [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange].map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handleDayChange() }
                }
            }
        }
        guard observer == nil, let name = provider.changeNotificationName else { return }
        observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopObserving() {
        observingSurfaces = max(0, observingSurfaces - 1)
        guard observingSurfaces == 0 else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        dayObservers.forEach(NotificationCenter.default.removeObserver)
        dayObservers = []
    }

    /// Opens the event's own link when present, otherwise Calendar.
    func open(_ event: CalendarEventDescriptor) {
        if let url = event.meetingURL {
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
