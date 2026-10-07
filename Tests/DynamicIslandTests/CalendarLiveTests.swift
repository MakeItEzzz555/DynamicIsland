import EventKit
import XCTest
@testable import DynamicIsland

/// Opt-in real EventKit read (DYNAMIC_ISLAND_LIVE_CALENDAR=1). Never prompts,
/// never prints event content: only counts, ranges and access state.
@MainActor
final class CalendarLiveTests: XCTestCase {
    func testRealEventKitSelectedDayBrowsing() throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_CALENDAR"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_CALENDAR=1 for a real EventKit read.")
        }
        let provider = EventKitCalendarProvider()
        print("LIVE-CALENDAR access=\(provider.accessState)")
        guard provider.accessState == .fullAccess else {
            throw XCTSkip("IMPLEMENTED BUT REAL VALIDATION BLOCKED BY CALENDAR PERMISSION (\(provider.accessState)).")
        }
        let controller = CalendarEventsController(provider: provider)
        controller.refresh()
        var perDay: [Int] = []
        for offset in 0..<14 {
            controller.selectToday()
            controller.shiftSelectedDay(by: offset)
            perDay.append(controller.dayEvents.count)
            for event in controller.dayEvents {
                let interval = CalendarEventsController.dayInterval(containing: controller.selectedDay, calendar: .current)
                XCTAssertTrue(event.endDate > interval.start && event.startDate < interval.end, "event outside selected day")
            }
        }
        let calendars = EKEventStore().calendars(for: .event).count
        print("LIVE-CALENDAR calendars=\(calendars) upcoming=\(controller.events.count) dayCounts(next14)=\(perDay)")
    }
}
