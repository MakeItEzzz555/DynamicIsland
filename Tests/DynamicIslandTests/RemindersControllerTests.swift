import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
private final class FakeRemindersProvider: RemindersProviding {
    static let changeName = Notification.Name("FakeRemindersProvider.changed")

    var accessState: ReminderAccessState = .notDetermined
    var requestCount = 0
    var createError: Error?
    var completeError: Error?
    var completionHidesReminder = true
    var changeNotificationName: Notification.Name? { Self.changeName }
    var requestedState: ReminderAccessState = .fullAccess
    var lists: [ReminderListDescriptor] = []
    var upcoming: [ReminderDescriptor] = []
    var created: [(title: String, listID: String, dueDate: Date?)] = []
    var completedIDs: [String] = []
    var requestError: Error?
    var fetchError: Error?

    func requestFullAccess() async throws -> ReminderAccessState {
        requestCount += 1
        if let requestError { throw requestError }
        accessState = requestedState
        return accessState
    }

    func fetchLists() throws -> [ReminderListDescriptor] {
        if let fetchError { throw fetchError }
        return lists
    }

    func createReminder(title: String, listID: String, dueDate: Date?) throws -> ReminderDescriptor {
        if let createError { throw createError }
        created.append((title, listID, dueDate))
        return ReminderDescriptor(
            id: "created-\(created.count)",
            title: title,
            listID: listID,
            listTitle: lists.first(where: { $0.id == listID })?.title ?? "List",
            dueDate: dueDate,
            isCompleted: false
        )
    }

    func completeReminder(id: String) throws {
        if let completeError { throw completeError }
        completedIDs.append(id)
        if completionHidesReminder {
            upcoming.removeAll { $0.id == id }
        }
    }

    func fetchUpcomingReminders(from start: Date, through end: Date) async throws -> [ReminderDescriptor] {
        if let fetchError { throw fetchError }
        return upcoming
    }
}

@MainActor
final class RemindersControllerTests: XCTestCase {
    func testNotDeterminedPermissionDoesNotPromptOrFabricateActivity() async {
        let fixture = makeFixture()
        await fixture.controller.refresh()

        XCTAssertEqual(fixture.controller.accessState, .notDetermined)
        XCTAssertEqual(fixture.registry.snapshot(for: .reminders)?.permission, .notDetermined)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testDeniedPermissionFailsClosed() async {
        let fixture = makeFixture()
        fixture.provider.accessState = .denied

        await fixture.controller.refresh()

        XCTAssertEqual(fixture.registry.snapshot(for: .reminders)?.permission, .denied)
        XCTAssertTrue(fixture.controller.lists.isEmpty)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testExplicitAccessRequestRefreshesAuthorizedLists() async {
        let fixture = makeFixture()
        fixture.provider.requestedState = .fullAccess
        fixture.provider.lists = [
            ReminderListDescriptor(id: "work", title: "Work"),
            ReminderListDescriptor(id: "home", title: "Home")
        ]

        await fixture.controller.requestAccess()

        XCTAssertEqual(fixture.controller.accessState, .fullAccess)
        XCTAssertEqual(fixture.registry.snapshot(for: .reminders)?.permission, .granted)
        XCTAssertEqual(fixture.controller.selectedListID, "work")
    }

    func testCreateReminderUsesSelectedListAndDueDate() async throws {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [
            ReminderListDescriptor(id: "work", title: "Work"),
            ReminderListDescriptor(id: "home", title: "Home")
        ]
        await fixture.controller.refresh()
        fixture.controller.selectedListID = "home"
        let due = Date(timeIntervalSince1970: 2_000)

        let created = try await fixture.controller.createReminder(title: "Submit report", dueDate: due)

        XCTAssertEqual(created.title, "Submit report")
        XCTAssertEqual(fixture.provider.created.first?.listID, "home")
        XCTAssertEqual(fixture.provider.created.first?.dueDate, due)
    }

    func testCompleteReminderDelegatesToProviderAndRefreshes() async throws {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        fixture.provider.upcoming = [
            reminder(id: "r1", due: Date(timeIntervalSince1970: 1_100))
        ]
        await fixture.controller.refresh()

        try await fixture.controller.completeReminder(id: "r1")

        XCTAssertEqual(fixture.provider.completedIDs, ["r1"])
        XCTAssertTrue(fixture.controller.upcomingReminders.isEmpty)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testUpcomingRemindersOrderDueDatesFirstAndFilterCompletedOrPast() {
        let now = Date(timeIntervalSince1970: 1_000)
        let values = [
            reminder(id: "none", due: nil),
            reminder(id: "later", due: Date(timeIntervalSince1970: 1_300)),
            reminder(id: "soon", due: Date(timeIntervalSince1970: 1_100)),
            reminder(id: "past", due: Date(timeIntervalSince1970: 900)),
            reminder(id: "done", due: Date(timeIntervalSince1970: 1_050), completed: true)
        ]

        XCTAssertEqual(
            RemindersController.sortedUpcoming(values, now: now).map(\.id),
            ["soon", "later", "none"]
        )
    }

    func testAuthorizedRefreshPublishesTruthfulEventKitLiveActivity() async {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        fixture.provider.upcoming = [
            reminder(id: "r1", due: Date(timeIntervalSince1970: 1_100))
        ]

        await fixture.controller.refresh()

        let activity = fixture.activities.activities.first
        XCTAssertEqual(activity?.kind, .reminder)
        XCTAssertEqual(activity?.lifecycle.authority, .eventKit)
        XCTAssertNil(activity?.progress)
        XCTAssertEqual(activity?.lifecycle.dismissPolicy, .untilSourceEnds)
        XCTAssertFalse(activity?.lifecycle.supportsCancellation ?? true)
    }

    func testWriteOnlyIsNotTreatedAsReadableFullAccess() async {
        let fixture = makeFixture()
        fixture.provider.accessState = .writeOnly

        await fixture.controller.refresh()

        XCTAssertEqual(fixture.registry.snapshot(for: .reminders)?.permission, .required)
        guard case .temporarilyUnavailable = fixture.registry.snapshot(for: .reminders)?.availability else {
            return XCTFail("Expected full-access requirement to be explicit")
        }
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testLaunchConstructionNeverRequestsPermission() async {
        let fixture = makeFixture()
        await fixture.controller.refresh()
        try? await fixture.controller.perform(.test)

        XCTAssertEqual(fixture.provider.requestCount, 0)
    }

    func testAuthorizationMappingCoversEveryEventKitState() {
        XCTAssertEqual(EventKitRemindersProvider.mapAuthorization(.notDetermined), .notDetermined)
        XCTAssertEqual(EventKitRemindersProvider.mapAuthorization(.denied), .denied)
        XCTAssertEqual(EventKitRemindersProvider.mapAuthorization(.restricted), .restricted)
        XCTAssertEqual(EventKitRemindersProvider.mapAuthorization(.writeOnly), .writeOnly)
        XCTAssertEqual(EventKitRemindersProvider.mapAuthorization(.fullAccess), .fullAccess)
    }

    func testCapabilityMappingIsTruthful() {
        XCTAssertEqual(RemindersController.capabilityMapping(for: .notDetermined).permission, .notDetermined)
        XCTAssertEqual(RemindersController.capabilityMapping(for: .denied).permission, .denied)
        XCTAssertEqual(RemindersController.capabilityMapping(for: .fullAccess).permission, .granted)
        XCTAssertEqual(RemindersController.capabilityMapping(for: .fullAccess).availability, .available)

        let restricted = RemindersController.capabilityMapping(for: .restricted)
        XCTAssertEqual(restricted.permission, .denied)
        guard case .unsupported = restricted.availability else {
            return XCTFail("Restricted access must not look available")
        }

        let unavailable = RemindersController.capabilityMapping(for: .unavailable(reason: "x"))
        XCTAssertEqual(unavailable.availability, .unsupported(reason: "x"))
    }

    func testDeniedRequestFailsClosedWithoutActivity() async {
        let fixture = makeFixture()
        fixture.provider.requestedState = .denied

        await fixture.controller.requestAccess()

        XCTAssertEqual(fixture.provider.requestCount, 1)
        XCTAssertEqual(fixture.registry.snapshot(for: .reminders)?.permission, .denied)
        XCTAssertFalse(fixture.registry.snapshot(for: .reminders)?.isOperational ?? true)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testRequestFailureMapsToFailedHealth() async {
        let fixture = makeFixture()
        fixture.provider.requestError = RemindersControllerError.listUnavailable

        await fixture.controller.requestAccess()

        guard case .failed = fixture.registry.snapshot(for: .reminders)?.health else {
            return XCTFail("Expected failed health")
        }
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testFetchFailureClearsStateAndActivity() async {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        fixture.provider.upcoming = [reminder(id: "r1", due: Date(timeIntervalSince1970: 1_100))]
        await fixture.controller.refresh()
        XCTAssertFalse(fixture.activities.activities.isEmpty)

        fixture.provider.fetchError = RemindersControllerError.reminderUnavailable
        await fixture.controller.refresh()

        XCTAssertTrue(fixture.controller.upcomingReminders.isEmpty)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        guard case .failed = fixture.registry.snapshot(for: .reminders)?.health else {
            return XCTFail("Expected failed health")
        }
    }

    func testListOrderingIsDeterministic() {
        let lists = [
            ReminderListDescriptor(id: "b", title: "work"),
            ReminderListDescriptor(id: "a", title: "Work"),
            ReminderListDescriptor(id: "c", title: "Errands")
        ]
        XCTAssertEqual(RemindersController.sortedLists(lists).map(\.id), ["c", "a", "b"])
    }

    func testStaleSelectedListFallsBackToFirstAvailableList() async {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        fixture.controller.selectedListID = "deleted"

        await fixture.controller.refresh()

        XCTAssertEqual(fixture.controller.selectedListID, "work")
    }

    func testCreateRejectsEmptyAndOverlongTitles() async {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        await fixture.controller.refresh()

        for title in ["", "   \n ", String(repeating: "x", count: RemindersController.maximumTitleLength + 1)] {
            do {
                _ = try await fixture.controller.createReminder(title: title, dueDate: nil)
                XCTFail("Expected invalid title")
            } catch {
                XCTAssertEqual(error as? RemindersControllerError, .invalidTitle)
            }
        }
        XCTAssertTrue(fixture.provider.created.isEmpty)
    }

    func testCreateTrimsTitleAndAllowsMissingDueDate() async throws {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        await fixture.controller.refresh()

        _ = try await fixture.controller.createReminder(title: "  Call  ", dueDate: nil)

        XCTAssertEqual(fixture.provider.created.first?.title, "Call")
        XCTAssertNil(fixture.provider.created.first?.dueDate ?? nil)
    }

    func testCreateWithoutFullAccessThrowsPermissionRequired() async {
        let fixture = makeFixture()
        fixture.provider.accessState = .writeOnly

        do {
            _ = try await fixture.controller.createReminder(title: "Title", dueDate: nil)
            XCTFail("Expected permission error")
        } catch {
            XCTAssertEqual(error as? RemindersControllerError, .permissionRequired)
        }
        XCTAssertTrue(fixture.provider.created.isEmpty)
    }

    func testDueDateComponentsRoundTripToMinute() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Athens")!
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let components = RemindersController.dueDateComponents(for: date, calendar: calendar)

        XCTAssertNotNil(components.hour)
        XCTAssertNotNil(components.minute)
        XCTAssertEqual(components.timeZone, calendar.timeZone)
        XCTAssertEqual(RemindersController.dueDate(from: components), date)
    }

    func testCompletionIsNotOptimistic() async throws {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        fixture.provider.upcoming = [reminder(id: "r1", due: Date(timeIntervalSince1970: 1_100))]
        fixture.provider.completionHidesReminder = false
        await fixture.controller.refresh()

        try await fixture.controller.completeReminder(id: "r1")

        XCTAssertEqual(fixture.controller.upcomingReminders.map(\.id), ["r1"])
        XCTAssertEqual(fixture.activities.activities.first?.id, RemindersController.activityID)
    }

    func testCompletionFailureRethrowsAndKeepsEventKitState() async {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        fixture.provider.upcoming = [reminder(id: "r1", due: Date(timeIntervalSince1970: 1_100))]
        fixture.provider.completeError = RemindersControllerError.reminderUnavailable
        await fixture.controller.refresh()

        do {
            try await fixture.controller.completeReminder(id: "r1")
            XCTFail("Expected completion error")
        } catch {
            XCTAssertEqual(error as? RemindersControllerError, .reminderUnavailable)
        }
        XCTAssertEqual(fixture.controller.upcomingReminders.map(\.id), ["r1"])
    }

    func testNoActivityForRemindersOutsideLeadWindowOrWithoutDueDate() async {
        let fixture = makeFixture(leadTime: 60)
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        fixture.provider.upcoming = [
            reminder(id: "far", due: Date(timeIntervalSince1970: 5_000)),
            reminder(id: "undated", due: nil)
        ]

        await fixture.controller.refresh()

        XCTAssertEqual(fixture.controller.upcomingReminders.map(\.id), ["far", "undated"])
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testDisablingRemovesActivity() async {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        fixture.provider.upcoming = [reminder(id: "r1", due: Date(timeIntervalSince1970: 1_100))]
        await fixture.controller.refresh()

        fixture.controller.setEnabled(false)

        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertFalse(fixture.registry.snapshot(for: .reminders)?.isOperational ?? true)
    }

    func testStoreChangeNotificationTriggersAuthoritativeRefresh() async {
        let fixture = makeFixture()
        fixture.provider.accessState = .fullAccess
        fixture.provider.lists = [ReminderListDescriptor(id: "work", title: "Work")]
        await fixture.controller.refresh()
        XCTAssertTrue(fixture.activities.activities.isEmpty)

        fixture.provider.upcoming = [reminder(id: "r1", due: Date(timeIntervalSince1970: 1_100))]
        NotificationCenter.default.post(name: FakeRemindersProvider.changeName, object: nil)

        for _ in 0..<50 where fixture.activities.activities.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(fixture.activities.activities.first?.kind, .reminder)
    }

    private func makeFixture(leadTime: TimeInterval = 10_000) -> (
        controller: RemindersController,
        provider: FakeRemindersProvider,
        activities: LiveActivityStore,
        registry: IslandCapabilityRegistry
    ) {
        let provider = FakeRemindersProvider()
        let activities = LiveActivityStore()
        let registry = IslandCapabilityRegistry()
        let controller = RemindersController(
            liveActivities: activities,
            capabilities: registry,
            provider: provider,
            now: { Date(timeIntervalSince1970: 1_000) },
            upcomingWindow: 10_000,
            activityLeadTime: leadTime
        )
        return (controller, provider, activities, registry)
    }

    private func reminder(
        id: String,
        due: Date?,
        completed: Bool = false
    ) -> ReminderDescriptor {
        ReminderDescriptor(
            id: id,
            title: id,
            listID: "work",
            listTitle: "Work",
            dueDate: due,
            isCompleted: completed
        )
    }
}
