import EventKit
import XCTest
@testable import DynamicIsland

@MainActor
private final class FakeCalendarProvider: CalendarEventsProviding {
    var accessState: CalendarAccessState = .notDetermined
    var grant: CalendarAccessState = .fullAccess
    var events: [CalendarEventDescriptor] = []
    var requestCount = 0
    var queriedRanges: [(Date, Date)] = []
    let changeNotificationName: Notification.Name? = Notification.Name("FakeCalendarChanged")

    func requestFullAccess() async throws -> CalendarAccessState {
        requestCount += 1
        accessState = grant
        return grant
    }

    func upcomingEvents(from start: Date, through end: Date) -> [CalendarEventDescriptor] {
        queriedRanges.append((start, end))
        return events
    }
}

@MainActor
final class CalendarEventsControllerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testNothingIsReadOrRequestedWithoutExplicitAccess() {
        let provider = FakeCalendarProvider()
        let controller = CalendarEventsController(provider: provider, now: { self.now })
        controller.refresh()
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertTrue(provider.queriedRanges.isEmpty)
        XCTAssertTrue(controller.events.isEmpty)
        XCTAssertEqual(controller.statusText, "Calendar access not requested")
    }

    func testExplicitRequestThenUpcomingSortedBoundedAndEndedEventsDropped() async {
        let provider = FakeCalendarProvider()
        provider.events = (0..<12).map { event(id: "e\($0)", start: Double(12 - $0) * 600) } + [
            event(id: "ended", start: -7200, duration: 600)
        ]
        let controller = CalendarEventsController(provider: provider, now: { self.now })

        await controller.requestAccess()

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(controller.accessState, .fullAccess)
        XCTAssertEqual(controller.events.count, CalendarEventsController.maximumEvents)
        XCTAssertEqual(controller.events.first?.id, "e11")
        XCTAssertFalse(controller.events.contains { $0.id == "ended" })
        let range = try? XCTUnwrap(provider.queriedRanges.last)
        XCTAssertEqual(range?.1.timeIntervalSince(range?.0 ?? now), CalendarEventsController.lookahead)
    }

    func testDeniedAndWriteOnlyAreTruthful() async {
        let provider = FakeCalendarProvider()
        provider.grant = .writeOnly
        let controller = CalendarEventsController(provider: provider, now: { self.now })
        await controller.requestAccess()
        XCTAssertTrue(controller.events.isEmpty)
        XCTAssertTrue(controller.statusText.contains("full access"))
        XCTAssertTrue(provider.queriedRanges.isEmpty)
    }

    func testStoreChangeRefreshes() async {
        let provider = FakeCalendarProvider()
        provider.accessState = .fullAccess
        let controller = CalendarEventsController(provider: provider, now: { self.now })
        controller.startObserving()
        defer { controller.stopObserving() }
        provider.events = [event(id: "new", start: 60)]
        NotificationCenter.default.post(name: provider.changeNotificationName!, object: nil)
        XCTAssertEqual(controller.events.map(\.id), ["new"])
    }

    func testObservationIsReferenceCounted() {
        let provider = FakeCalendarProvider()
        provider.accessState = .fullAccess
        let controller = CalendarEventsController(provider: provider, now: { self.now })
        controller.startObserving()
        controller.startObserving()
        controller.stopObserving()
        provider.events = [event(id: "still-observed", start: 60)]
        NotificationCenter.default.post(name: provider.changeNotificationName!, object: nil)
        XCTAssertEqual(controller.events.map(\.id), ["still-observed"])
        controller.stopObserving()
        provider.events = []
        NotificationCenter.default.post(name: provider.changeNotificationName!, object: nil)
        XCTAssertEqual(controller.events.map(\.id), ["still-observed"], "no refresh after the last surface stopped")
    }

    func testMeetingLinkIsOnlyTakenFromTheEvent() {
        XCTAssertEqual(
            CalendarMeetingLink.find(url: nil, location: "Room 4", notes: "Join https://meet.example.com/abc now"),
            URL(string: "https://meet.example.com/abc")
        )
        XCTAssertEqual(
            CalendarMeetingLink.find(url: URL(string: "https://zoom.us/j/1"), location: nil, notes: nil),
            URL(string: "https://zoom.us/j/1")
        )
        XCTAssertNil(CalendarMeetingLink.find(url: URL(string: "file:///etc/hosts"), location: "Office", notes: "No link"))
    }

    func testAuthorizationMapping() {
        XCTAssertEqual(EventKitCalendarProvider.map(.fullAccess), .fullAccess)
        XCTAssertEqual(EventKitCalendarProvider.map(.writeOnly), .writeOnly)
        XCTAssertEqual(EventKitCalendarProvider.map(.denied), .denied)
        XCTAssertEqual(EventKitCalendarProvider.map(.notDetermined), .notDetermined)
    }

    private func event(id: String, start: TimeInterval, duration: TimeInterval = 1800) -> CalendarEventDescriptor {
        CalendarEventDescriptor(
            id: id,
            title: id,
            startDate: now.addingTimeInterval(start),
            endDate: now.addingTimeInterval(start + duration),
            isAllDay: false,
            calendarTitle: "Work",
            calendarColor: [0.2, 0.4, 0.9],
            meetingURL: nil
        )
    }
}

// MARK: - Selected-day browsing (Phase 6)

@MainActor
final class CalendarSelectedDayTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false, link: URL? = nil) -> CalendarEventDescriptor {
        CalendarEventDescriptor(
            id: id, title: id, startDate: start, endDate: end, isAllDay: allDay,
            calendarTitle: "Work", calendarColor: [0.9, 0.2, 0.2], meetingURL: link
        )
    }

    private func makeController(now: Date, access: CalendarAccessState = .fullAccess) -> (CalendarEventsController, FakeCalendarProvider) {
        let provider = FakeCalendarProvider()
        provider.accessState = access
        let controller = CalendarEventsController(provider: provider, now: { now }, calendar: calendar)
        return (controller, provider)
    }

    func testDayIntervalUsesLocalMidnightsIncludingDSTDays() {
        let normal = CalendarEventsController.dayInterval(containing: date(2026, 10, 1, 15), calendar: calendar)
        XCTAssertEqual(normal.start, date(2026, 10, 1))
        XCTAssertEqual(normal.end, date(2026, 10, 2))
        XCTAssertEqual(normal.duration, 24 * 3600)

        let springForward = CalendarEventsController.dayInterval(containing: date(2026, 3, 8, 12), calendar: calendar)
        XCTAssertEqual(springForward.duration, 23 * 3600, "DST start day is 23 hours")
        let fallBack = CalendarEventsController.dayInterval(containing: date(2026, 11, 1, 12), calendar: calendar)
        XCTAssertEqual(fallBack.duration, 25 * 3600, "DST end day is 25 hours")
    }

    func testInitialSelectionIsTodayAndChangingItNeverRequestsPermission() {
        let (controller, provider) = makeController(now: date(2026, 10, 1, 9), access: .notDetermined)
        XCTAssertEqual(controller.selectedDay, date(2026, 10, 1))
        XCTAssertTrue(controller.isSelectedDayToday)
        controller.selectDay(containing: date(2026, 10, 5, 18))
        XCTAssertEqual(controller.selectedDay, date(2026, 10, 5))
        XCTAssertFalse(controller.isSelectedDayToday)
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertTrue(provider.queriedRanges.isEmpty, "no access: nothing is read")
        XCTAssertTrue(controller.dayEvents.isEmpty)
    }

    func testSelectedDayShowsOverlappingEventsAllDayFirstThenChronological() {
        let now = date(2026, 10, 1, 9)
        let (controller, provider) = makeController(now: now)
        provider.events = [
            event("late", date(2026, 10, 5, 16), date(2026, 10, 5, 17)),
            event("early", date(2026, 10, 5, 8), date(2026, 10, 5, 9), link: URL(string: "https://example.com/meet")),
            event("overnight-in", date(2026, 10, 4, 22), date(2026, 10, 5, 2)),
            event("overnight-out", date(2026, 10, 5, 23), date(2026, 10, 6, 1)),
            event("holiday", date(2026, 10, 5), date(2026, 10, 6), allDay: true),
            event("yesterday", date(2026, 10, 4, 9), date(2026, 10, 4, 10)),
            event("ends-at-midnight", date(2026, 10, 4, 23), date(2026, 10, 5)),
            event("tomorrow", date(2026, 10, 6, 9), date(2026, 10, 6, 10))
        ]
        controller.selectDay(containing: date(2026, 10, 5, 12))
        XCTAssertEqual(controller.dayEvents.map(\.id), ["holiday", "overnight-in", "early", "late", "overnight-out"])
        let range = provider.queriedRanges.last!
        XCTAssertEqual(range.0, date(2026, 10, 5))
        XCTAssertEqual(range.1, date(2026, 10, 6))
        XCTAssertNotNil(controller.dayEvents.first { $0.id == "early" }?.meetingURL)
    }

    func testTodayIncludesInProgressAndEarlierEventsOfTheDay() {
        let (controller, provider) = makeController(now: date(2026, 10, 1, 13))
        provider.events = [
            event("morning", date(2026, 10, 1, 8), date(2026, 10, 1, 9)),
            event("now", date(2026, 10, 1, 12, 30), date(2026, 10, 1, 13, 30))
        ]
        controller.refresh()
        XCTAssertEqual(controller.dayEvents.map(\.id), ["morning", "now"],
                       "the selected-day view shows the whole local day, not just what's left")
        XCTAssertEqual(controller.events.map(\.id), ["now"], "upcoming summary keeps its existing semantics")
    }

    func testEmptySelectedDayIsTruthfulAndNeverFallsBackToOtherEvents() {
        let (controller, provider) = makeController(now: date(2026, 10, 1, 9))
        provider.events = [event("other", date(2026, 10, 2, 9), date(2026, 10, 2, 10))]
        controller.selectDay(containing: date(2026, 10, 9))
        XCTAssertTrue(controller.dayEvents.isEmpty)
        XCTAssertEqual(controller.dayStatusText, "No events on this date")
    }

    func testShiftAndTodayReset() {
        let (controller, _) = makeController(now: date(2026, 10, 1, 9))
        controller.shiftSelectedDay(by: 1)
        XCTAssertEqual(controller.selectedDay, date(2026, 10, 2))
        controller.shiftSelectedDay(by: -3)
        XCTAssertEqual(controller.selectedDay, date(2026, 9, 29))
        controller.selectToday()
        XCTAssertEqual(controller.selectedDay, date(2026, 10, 1))
        XCTAssertTrue(controller.isSelectedDayToday)
    }

    func testStoreChangeRefreshesTheSelectedDay() {
        let (controller, provider) = makeController(now: date(2026, 10, 1, 9))
        controller.selectDay(containing: date(2026, 10, 3))
        controller.startObserving()
        defer { controller.stopObserving() }
        provider.events = [event("added", date(2026, 10, 3, 10), date(2026, 10, 3, 11))]
        NotificationCenter.default.post(name: provider.changeNotificationName!, object: nil)
        XCTAssertEqual(controller.dayEvents.map(\.id), ["added"])
    }

    func testDeniedAccessExposesNoDayEvents() {
        let (controller, provider) = makeController(now: date(2026, 10, 1, 9), access: .denied)
        provider.events = [event("secret", date(2026, 10, 1, 10), date(2026, 10, 1, 11))]
        controller.refresh()
        controller.selectDay(containing: date(2026, 10, 1))
        XCTAssertTrue(controller.dayEvents.isEmpty)
        XCTAssertTrue(provider.queriedRanges.isEmpty)
    }

    func testDayRolloverMovesTodayButKeepsAnExplicitOtherDay() {
        var now = date(2026, 10, 1, 23, 59)
        let provider = FakeCalendarProvider()
        provider.accessState = .fullAccess
        let controller = CalendarEventsController(provider: provider, now: { now }, calendar: calendar)
        now = date(2026, 10, 2, 0, 1)
        controller.handleDayChange()
        XCTAssertEqual(controller.selectedDay, date(2026, 10, 2), "a 'today' selection follows the clock")
        controller.selectDay(containing: date(2026, 10, 20))
        now = date(2026, 10, 3, 0, 1)
        controller.handleDayChange()
        XCTAssertEqual(controller.selectedDay, date(2026, 10, 20), "an explicit other day is kept")
    }
}

@MainActor
final class CalendarEventPresentationTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func event(_ start: Date, _ end: Date, allDay: Bool = false, link: URL? = nil) -> CalendarEventDescriptor {
        CalendarEventDescriptor(id: "e", title: "Standup", startDate: start, endDate: end, isAllDay: allDay,
                                calendarTitle: "Work", calendarColor: nil, meetingURL: link)
    }

    func testSameDayTimesHaveNoDayPrefix() {
        let text = CalendarEventPresentation.timeText(event(at(5, 9), at(5, 10)), selectedDay: at(5, 0), calendar: calendar)
        XCTAssertFalse(text.contains(at(5, 0).formatted(.dateTime.weekday(.abbreviated))), text)
        XCTAssertTrue(text.hasSuffix(" · Work"))
    }

    func testCrossMidnightShowsTheOtherDay() {
        let text = CalendarEventPresentation.timeText(event(at(4, 22), at(5, 2)), selectedDay: at(5, 0), calendar: calendar)
        XCTAssertTrue(text.hasPrefix(at(4, 0).formatted(.dateTime.weekday(.abbreviated))), text)
    }

    func testAllDayAndAccessibility() {
        XCTAssertEqual(CalendarEventPresentation.timeText(event(at(5, 0), at(6, 0), allDay: true), selectedDay: at(5, 0), calendar: calendar), "All day · Work")
        let label = CalendarEventPresentation.accessibilityText(
            event(at(5, 9), at(5, 10), link: URL(string: "https://example.com")), selectedDay: at(5, 0), isOngoing: true)
        XCTAssertTrue(label.contains("Standup"))
        XCTAssertTrue(label.contains("in progress"))
        XCTAssertTrue(label.contains("has a meeting link"))
        XCTAssertFalse(CalendarEventPresentation.accessibilityText(event(at(5, 9), at(5, 10)), selectedDay: at(5, 0), isOngoing: false)
            .contains("meeting link"), "no link is never presented as joinable")
    }
}
