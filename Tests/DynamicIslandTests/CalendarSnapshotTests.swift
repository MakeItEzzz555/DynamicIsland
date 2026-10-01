import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Review renders (DYNAMIC_ISLAND_CALENDAR_SNAPSHOT_DIR) of the production
/// Calendar section with synthetic test events and real display metrics.
/// Also asserts, without the env var, that nothing is clipped horizontally.
@MainActor
final class CalendarSnapshotTests: XCTestCase {
    private let calendar = Calendar.current

    private final class Provider: CalendarEventsProviding {
        var accessState: CalendarAccessState
        var events: [CalendarEventDescriptor] = []
        let changeNotificationName: Notification.Name? = nil
        init(_ state: CalendarAccessState) { accessState = state }
        func requestFullAccess() async throws -> CalendarAccessState { accessState }
        func upcomingEvents(from start: Date, through end: Date) -> [CalendarEventDescriptor] { events }
    }

    private func metrics(_ width: CGFloat, _ height: CGFloat, notch: Bool = true) -> ResolvedIslandMetrics {
        IslandDisplayMetricsResolver.resolve(IslandDisplaySnapshot(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            visibleFrame: CGRect(x: 0, y: 0, width: width, height: height - 25),
            safeAreaInsets: NSEdgeInsets(top: notch ? 32 : 0, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil,
            backingScaleFactor: 2, displayID: nil, isBuiltIn: notch,
            pixelSize: CGSize(width: width * 2, height: height * 2)
        ))
    }

    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: today)!
    }

    private func sampleEvents() -> [CalendarEventDescriptor] {
        func event(_ id: String, _ title: String, _ start: Date, _ end: Date, allDay: Bool = false, cal: String, rgb: [Double], link: Bool = false) -> CalendarEventDescriptor {
            CalendarEventDescriptor(id: id, title: title, startDate: start, endDate: end, isAllDay: allDay,
                                    calendarTitle: cal, calendarColor: rgb,
                                    meetingURL: link ? URL(string: "https://example.com/meet/synthetic") : nil)
        }
        return [
            event("a", "Synthetic holiday", at(0, 0), at(1, 0), allDay: true, cal: "Holidays", rgb: [0.2, 0.75, 0.4]),
            event("b", "Design review", at(0, 9, 30), at(0, 10, 30), cal: "Work", rgb: [0.95, 0.3, 0.3], link: true),
            event("c", "Lunch", at(0, 12), at(0, 13), cal: "Personal", rgb: [0.3, 0.55, 0.95]),
            event("d", "Planning (in progress now)", Date().addingTimeInterval(-600), Date().addingTimeInterval(1800), cal: "Work", rgb: [0.95, 0.3, 0.3]),
            event("e", "Late deploy window", at(0, 23), at(1, 1), cal: "Work", rgb: [0.95, 0.6, 0.2]),
            event("f", "Future offsite", at(3, 10), at(3, 15), cal: "Work", rgb: [0.95, 0.3, 0.3], link: true)
        ]
    }

    private func render(_ name: String, state: CalendarAccessState, events: [CalendarEventDescriptor] = [],
                        selectDayOffset: Int = 0, metrics: ResolvedIslandMetrics, size: CGSize = CGSize(width: 340, height: 230)) throws -> NSHostingView<AnyView> {
        let provider = Provider(state)
        provider.events = events
        let controller = CalendarEventsController(provider: provider)
        controller.refresh()
        if selectDayOffset != 0 { controller.selectDay(containing: at(selectDayOffset, 12)) }
        let view = AnyView(
            CalendarSectionView(controller: controller, layoutStore: nil)
                .environment(\.islandDisplayMetrics, metrics)
                .padding(10)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        )
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        if let dir = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_CALENDAR_SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try write(host, to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
        return host
    }

    private func write(_ host: NSView, to url: URL) throws {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return XCTFail("png") }
        try png.write(to: url)
    }

    func testCalendarStatesRenderWithinBounds() throws {
        let m14 = metrics(1512, 982)
        let m16 = metrics(1728, 1117)
        let views = [
            try render("cal-01-no-permission", state: .notDetermined, metrics: m14),
            try render("cal-02-denied", state: .denied, metrics: m14),
            try render("cal-03-today-events", state: .fullAccess, events: sampleEvents(), metrics: m14),
            try render("cal-04-future-date", state: .fullAccess, events: sampleEvents(), selectDayOffset: 3, metrics: m14),
            try render("cal-05-empty-date", state: .fullAccess, events: sampleEvents(), selectDayOffset: 9, metrics: m14),
            try render("cal-06-narrow", state: .fullAccess, events: sampleEvents(), metrics: metrics(1440, 900, notch: false), size: CGSize(width: 260, height: 210)),
            try render("cal-07-16in", state: .fullAccess, events: sampleEvents(), metrics: m16, size: CGSize(width: 380, height: 250)),
            try render("cal-08-1920", state: .fullAccess, events: sampleEvents(), metrics: metrics(1920, 1080, notch: false)),
            try render("cal-09-2560", state: .fullAccess, events: sampleEvents(), metrics: metrics(2560, 1440, notch: false), size: CGSize(width: 400, height: 260)),
            try render("cal-10-3840", state: .fullAccess, events: sampleEvents(), metrics: metrics(3840, 2160, notch: false), size: CGSize(width: 420, height: 270))
        ]
        for view in views {
            XCTAssertLessThanOrEqual(view.fittingSize.width, view.frame.width + 0.5, "content must not overflow horizontally")
        }

        // The popover content itself (rendered directly; popovers are separate windows).
        if let dir = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_CALENDAR_SNAPSHOT_DIR"] {
            let controller = CalendarEventsController(provider: Provider(.fullAccess))
            let host = NSHostingView(rootView: CalendarDatePickerPopover(controller: controller, isPresented: .constant(true))
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            try write(host, to: URL(fileURLWithPath: dir).appendingPathComponent("cal-12-date-picker-popover.png"))
        }
    }
}
