import XCTest
import Combine
@testable import DynamicIsland

@MainActor
final class WorkspaceCustomizationModelTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "WorkspaceCustomizationModelTests-\(UUID().uuidString)")!
    }

    func testDefaultsStableIDsAndLegacyTimerTypesRemainCompatible() {
        let config = WorkspaceConfiguration.initial.normalized()
        XCTAssertEqual(config.widgets(on: .media).map(\.kind), [.media, .files, .clipboard])
        XCTAssertEqual(config.widgets(on: .agents).map(\.kind), [.chat, .feed])
        XCTAssertEqual(config, config.normalized())
        XCTAssertEqual(config.placements.map(\.id), WorkspaceConfiguration.initial.placements.map(\.id))
        XCTAssertTrue(config.customizedSurfaces.isEmpty)
        XCTAssertEqual(IslandWidgetLayout.initial.stored, "media,files,clipboard")
    }

    func testPersistenceWritesOnlyOnMeaningfulCommitAndNoOpPublishesNothing() {
        let preferences = defaults()
        let store = WorkspaceCustomizationStore(defaults: preferences)
        var publications = 0
        let observation = store.objectWillChange.sink { publications += 1 }
        var draft = store.configuration
        draft.add(.timer, on: .media)
        draft.move(draft.placement(kind: .timer, on: .media)!.id,
                   before: draft.placement(kind: .media, on: .media)!.id, on: .media)
        XCTAssertEqual(store.persistenceWriteCount, 0)
        XCTAssertEqual(publications, 0, "Drag previews are local values")
        draft.markCustomized(.media)
        store.commit(draft)
        XCTAssertEqual(store.persistenceWriteCount, 1)
        XCTAssertEqual(publications, 1)
        store.commit(draft)
        XCTAssertEqual(store.persistenceWriteCount, 1)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(WorkspaceCustomizationStore(defaults: preferences).configuration, draft.normalized())
        withExtendedLifetime(observation) {}
    }

    func testIndependentTabAndWidgetVisibility() {
        var config = WorkspaceConfiguration.initial
        config.navigation.setVisible(.timer, visible: false)
        config.add(.timer, on: .media)
        config.add(.timer, on: .agents)
        XCTAssertTrue(config.navigation.hidden.contains(.timer))
        XCTAssertTrue(config.widgets(on: .media).contains { $0.kind == .timer })
        XCTAssertTrue(config.widgets(on: .agents).contains { $0.kind == .timer })
        config.remove(config.placement(kind: .timer, on: .agents)!.id)
        XCTAssertTrue(config.widgets(on: .media).contains { $0.kind == .timer })
        XCTAssertTrue(config.navigation.hidden.contains(.timer))
    }

    func testLegacyMigrationOnlyWhenEnabledAndResetDoesNotRestoreLegacy() {
        let preferences = defaults()
        preferences.set("timer,calendar,timer,unknown", forKey: "islandWidgetLayout")
        XCTAssertEqual(WorkspaceCustomizationStore(defaults: preferences).configuration, .initial)
        preferences.set(true, forKey: "islandWidgetLayoutEnabled")
        let store = WorkspaceCustomizationStore(defaults: preferences)
        XCTAssertEqual(store.configuration.widgets(on: .media).map(\.kind), [.timer, .calendar])
        XCTAssertEqual(store.configuration.customizedSurfaces, [.media])
        XCTAssertEqual(store.configuration.widgets(on: .agents).map(\.kind), [.chat, .feed])
        store.reset()
        XCTAssertEqual(store.configuration, .initial)
        XCTAssertEqual(WorkspaceCustomizationStore(defaults: preferences).configuration, .initial)
    }

    func testCorruptedDataFutureSchemaAndVersionZeroMigrationRecoverSafely() throws {
        XCTAssertEqual(WorkspaceConfiguration.decoded(Data("not JSON".utf8)), .initial)
        var future = WorkspaceConfiguration.initial
        future.schemaVersion = 99
        XCTAssertEqual(WorkspaceConfiguration.decoded(try JSONEncoder().encode(future)), .initial)
        var old = WorkspaceConfiguration.initial
        old.schemaVersion = 0
        old.navigation.setVisible(.timer, visible: false)
        let migrated = WorkspaceConfiguration.decoded(try JSONEncoder().encode(old))
        XCTAssertEqual(migrated.schemaVersion, 1)
        XCTAssertTrue(migrated.navigation.hidden.contains(.timer))
    }

    func testUnknownItemDoesNotDiscardKnownSavedPlacement() throws {
        var config = WorkspaceConfiguration.initial
        config.add(.timer, on: .media)
        let data = try JSONEncoder().encode(config)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var placements = try XCTUnwrap(json["placements"] as? [[String: Any]])
        var unknown = try XCTUnwrap(placements.first)
        unknown["kind"] = "deprecated-widget"
        placements.insert(unknown, at: 0)
        placements.append(["kind": "terminal", "surface": "unknown-surface"])
        placements.append(["malformed": true])
        json["placements"] = placements
        json["navigation"] = ["order": ["tools", "unknown-tab", "timer", "tools"], "hidden": ["island", "timer", "unknown-tab"]]
        let decoded = WorkspaceConfiguration.decoded(try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.widgets(on: .media).map(\.kind), [.media, .files, .clipboard, .timer])
        XCTAssertEqual(decoded.navigation.order.prefix(2), [.tools, .timer])
        XCTAssertEqual(decoded.navigation.hidden, [.timer])
    }

    func testNormalizationRejectsDuplicatesAndRestoresRequiredPrimary() {
        let duplicateID = WidgetID("same")
        let config = WorkspaceConfiguration(placements: [
            .init(id: duplicateID, kind: .timer, surface: .media, order: 5),
            .init(id: duplicateID, kind: .files, surface: .media, order: 9),
            .init(kind: .timer, surface: .media, order: 12),
            .init(kind: .terminal, surface: .media, order: 0),
            .init(kind: .chat, surface: .agents, order: 8, isVisible: false)
        ]).normalized()
        XCTAssertEqual(config.widgets(on: .media).map(\.kind), [.timer])
        XCTAssertEqual(config.widgets(on: .agents).map(\.kind), [.chat])
        XCTAssertEqual(Set(config.placements.map(\.id)).count, config.placements.count)
        XCTAssertEqual(config, config.normalized())
        let empty = WorkspaceConfiguration(placements: []).normalized()
        XCTAssertEqual(empty.widgets(on: .media).map(\.kind), [.media])
        XCTAssertEqual(empty.widgets(on: .agents).map(\.kind), [.chat])
    }

    func testAddRemoveRestoreReorderAndSingletonIDs() {
        var config = WorkspaceConfiguration.initial
        config.add(.timer, on: .media)
        let timer = config.placement(kind: .timer, on: .media)!.id
        for _ in 0..<10 { config.add(.timer, on: .media) }
        XCTAssertEqual(config.widgets(on: .media).filter { $0.kind == .timer }.count, 1)
        config.shift(timer, by: -100)
        XCTAssertEqual(config.widgets(on: .media).first?.kind, .timer)
        config.shift(timer, by: 100)
        XCTAssertEqual(config.widgets(on: .media).last?.kind, .timer)
        config.remove(timer)
        XCTAssertFalse(config.widgets(on: .media).contains { $0.kind == .timer })
        config.add(.timer, on: .media)
        XCTAssertEqual(config.placement(kind: .timer, on: .media)?.id, timer)
        config.remove(config.placement(kind: .chat, on: .agents)!.id)
        XCTAssertTrue(config.widgets(on: .agents).contains { $0.kind == .chat })
    }

    func testStackCombineMoveSeparatePreservesMemberIDsAndOrder() throws {
        var config = WorkspaceConfiguration.initial
        config.add(.terminal, on: .agents)
        let chatID = config.placement(kind: .chat, on: .agents)!.id
        let terminalID = config.placement(kind: .terminal, on: .agents)!.id
        config.combineTerminalWithChat()
        let stack = try XCTUnwrap(config.regions(on: .agents).first { $0.isStack })
        XCTAssertEqual(stack.widgets.map(\.id), [chatID, terminalID])
        XCTAssertEqual(config.groups.count, 1)
        config.combineTerminalWithChat()
        XCTAssertEqual(config.groups.count, 1)
        config.shift(stack.id, by: 1)
        XCTAssertEqual(config.regions(on: .agents).last?.id, stack.id)
        XCTAssertEqual(config.placement(kind: .terminal, on: .agents)?.id, terminalID)
        let decoded = WorkspaceConfiguration.decoded(try JSONEncoder().encode(config))
        XCTAssertEqual(decoded.groups, config.groups)
        config.separateStack(stack.id)
        XCTAssertTrue(config.groups.isEmpty)
        XCTAssertEqual(config.placement(kind: .chat, on: .agents)?.id, chatID)
        XCTAssertEqual(config.placement(kind: .terminal, on: .agents)?.id, terminalID)
        config.remove(terminalID)
        config.add(.terminal, on: .agents)
        XCTAssertEqual(config.placement(kind: .terminal, on: .agents)?.id, terminalID)
    }

    func testInvalidGroupsDiscardedWithoutRemovingMemberWidgets() {
        var config = WorkspaceConfiguration.initial
        config.add(.terminal, on: .agents)
        let chat = config.placement(kind: .chat, on: .agents)!.id
        let terminal = config.placement(kind: .terminal, on: .agents)!.id
        config.groups = [.init(id: WidgetID("broken"), surface: .media, members: [chat, terminal]),
                         .init(id: WidgetID("missing"), surface: .agents, members: [chat, WidgetID("absent")])]
        let normalized = config.normalized()
        XCTAssertTrue(normalized.groups.isEmpty)
        XCTAssertTrue(normalized.widgets(on: .agents).contains { $0.kind == .terminal })
    }

    func testRepeatedEditDraftCyclesBoundPersistentState() {
        let store = WorkspaceCustomizationStore(defaults: defaults())
        for _ in 0..<100 {
            var draft = store.configuration
            draft.add(.terminal, on: .agents)
            draft.combineTerminalWithChat()
            if let group = draft.groups.first { draft.separateStack(group.id) }
            draft.remove(draft.placement(kind: .terminal, on: .agents)!.id)
            draft.markCustomized(.agents)
            store.commit(draft)
        }
        XCTAssertEqual(store.configuration.placements.filter { $0.kind == .terminal }.count, 1)
        XCTAssertTrue(store.configuration.groups.isEmpty)
        XCTAssertEqual(store.persistenceWriteCount, 1, "Identical repeated edits must not write preferences")
    }
    func testSurfaceResetPreservesNavigationAndOtherWorkspace() {
        var config = WorkspaceConfiguration.initial
        config.add(.timer, on: .media)
        config.add(.terminal, on: .agents)
        config.combineTerminalWithChat()
        config.navigation.setVisible(.timer, visible: false)
        config.navigation.move(.tools, before: .island)
        let navigation = config.navigation
        let media = config.widgets(on: .media)
        config.resetWidgets(on: .agents)
        XCTAssertEqual(config.navigation, navigation)
        XCTAssertEqual(config.widgets(on: .media), media)
        XCTAssertEqual(config.widgets(on: .agents).map(\.kind), [.chat, .feed])
        XCTAssertTrue(config.groups.isEmpty)
        XCTAssertTrue(config.customizedSurfaces.contains(.agents))
        config.add(.terminal, on: .agents)
        config.combineTerminalWithChat()
        let agents = config.widgets(on: .agents)
        let groups = config.groups
        config.resetWidgets(on: .media)
        XCTAssertEqual(config.widgets(on: .agents), agents)
        XCTAssertEqual(config.groups, groups)
        XCTAssertEqual(config.navigation, navigation)
        XCTAssertEqual(config.widgets(on: .media).map(\.kind), [.media, .files, .clipboard])
    }

}
