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
