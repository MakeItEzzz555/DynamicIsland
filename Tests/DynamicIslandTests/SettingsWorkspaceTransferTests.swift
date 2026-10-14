import XCTest
@testable import DynamicIsland

@MainActor
final class SettingsWorkspaceTransferTests: XCTestCase {
    private func layout() -> WorkspaceConfiguration {
        var layout = WorkspaceConfiguration.initial
        layout.placements.append(.init(kind: .timer, surface: .media, order: 3, stacksBelowPrevious: true))
        layout.markCustomized(.media)
        layout.navigation.setVisible(.stats, visible: false)
        return layout.normalized()
    }

    func testReviewedWorkspaceImportIsInertUntilApplyAndPersistsVerticalLayout() throws {
        let source = AppSettings(defaults: SettingsPreviewDefaults()); source.shellOpacity = 0.7
        let data = try source.exportAppearanceTransfer(workspace: layout())
        let defaults = SettingsPreviewDefaults(); let target = AppSettings(defaults: defaults)
        let store = WorkspaceCustomizationStore(defaults: defaults)
        let document = try target.inspectAppearanceTransfer(data)
        XCTAssertEqual(target.shellOpacity, 1); XCTAssertEqual(store.persistenceWriteCount, 0)
        XCTAssertThrowsError(try target.applyAppearanceTransfer(document))
        XCTAssertThrowsError(try target.applySettingsTransfer(document, workspace: nil))
        try target.applySettingsTransfer(document, workspace: store)
        XCTAssertEqual(target.shellOpacity, 0.7)
        XCTAssertEqual(store.configuration, layout()); XCTAssertEqual(store.persistenceWriteCount, 1)
        XCTAssertEqual(WorkspaceCustomizationStore(defaults: defaults).configuration, layout())
        try target.applySettingsTransfer(document, workspace: store)
        XCTAssertEqual(store.persistenceWriteCount, 1)
    }

    func testWorkspaceTamperingFutureSchemaAndLossyRecoveryRejectWithoutWrites() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        let good = try settings.inspectAppearanceTransfer(settings.exportAppearanceTransfer(workspace: layout()))
        let defaults = SettingsPreviewDefaults(); let target = AppSettings(defaults: defaults)
        let store = WorkspaceCustomizationStore(defaults: defaults)
        let before = defaults.dictionaryRepresentation() as NSDictionary
        for mutate in 0..<4 {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: good.workspace!) as? [String: Any])
            switch mutate {
            case 0: object["schemaVersion"] = 999
            case 1: object["unknown"] = "do not silently drop"
            case 2:
                var placements = try XCTUnwrap(object["placements"] as? [[String: Any]])
                placements[0]["kind"] = "unknown-widget"; object["placements"] = placements
            default:
                var placements = try XCTUnwrap(object["placements"] as? [[String: Any]])
                placements.append(placements[0]); object["placements"] = placements
            }
            let workspace = try JSONSerialization.data(withJSONObject: object)
            let document = SettingsTransferDocument(version: 2, scope: "appearance-workspace", values: good.values,
                sha256: try SettingsTransferDocument.checksum(good.values, workspace: workspace), workspace: workspace)
            XCTAssertThrowsError(try target.applySettingsTransfer(document, workspace: store))
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
            XCTAssertEqual(store.persistenceWriteCount, 0)
        }
        var tampered = good; tampered.workspace = try JSONEncoder().encode(WorkspaceConfiguration.initial)
        XCTAssertThrowsError(try target.applySettingsTransfer(tampered, workspace: store))
    }

    func testLegacyAppearanceFileStillImportsWithoutReplacingWidgets() throws {
        let defaults = SettingsPreviewDefaults(); let settings = AppSettings(defaults: defaults)
        let store = WorkspaceCustomizationStore(defaults: defaults); store.commit(layout())
        let source = AppSettings(defaults: SettingsPreviewDefaults()); source.shellOpacity = 0.6
        let document = try settings.inspectAppearanceTransfer(source.exportAppearanceTransfer())
        try settings.applySettingsTransfer(document, workspace: store)
        XCTAssertEqual(settings.shellOpacity, 0.6); XCTAssertEqual(store.configuration, layout())
    }

    func testFailedWorkspacePersistenceRollsBackPreferencesAndLayout() throws {
        let suite = "SettingsRejectedTransfer.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RejectingWorkspaceDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults); settings.shellOpacity = 0.9
        let store = WorkspaceCustomizationStore(defaults: defaults)
        let source = AppSettings(defaults: SettingsPreviewDefaults()); source.shellOpacity = 0.5
        let document = try settings.inspectAppearanceTransfer(source.exportAppearanceTransfer(workspace: layout()))
        XCTAssertThrowsError(try settings.applySettingsTransfer(document, workspace: store))
        XCTAssertEqual(settings.shellOpacity, 0.9); XCTAssertEqual(store.configuration, .initial)
        XCTAssertEqual(AppSettings(defaults: defaults).shellOpacity, 0.9)
    }

    func testHardResetPreservesPrivacyAccessAndUnrelatedPersonalData() {
        let defaults = SettingsPreviewDefaults(); let settings = AppSettings(defaults: defaults)
        settings.shellOpacity = 0.7; settings.gesturesEnabled = true; settings.gestureInputSource = .camera
        settings.dockIconEnabled = true; settings.menuBarIconEnabled = false; settings.launchAtLoginEnabled = true
        settings.clipboardHistoryClearOnQuit = true; settings.clipboardHistoryRetentionDays = 7
        defaults.set("synthetic-test-token", forKey: "spotify.refreshToken")
        defaults.set(["fixture"], forKey: "clipboard-personal-data")
        settings.resetPreferencesPreservingAccess()
        XCTAssertEqual(settings.shellOpacity, 1); XCTAssertFalse(settings.gesturesEnabled)
        XCTAssertTrue(settings.launchAtLoginEnabled); XCTAssertTrue(settings.dockIconEnabled); XCTAssertFalse(settings.menuBarIconEnabled)
        XCTAssertTrue(settings.clipboardHistoryClearOnQuit); XCTAssertEqual(settings.clipboardHistoryRetentionDays, 7)
        XCTAssertEqual(defaults.string(forKey: "spotify.refreshToken"), "synthetic-test-token")
        XCTAssertEqual(defaults.stringArray(forKey: "clipboard-personal-data"), ["fixture"])
    }
}

private final class RejectingWorkspaceDefaults: UserDefaults, @unchecked Sendable {
    override func set(_ value: Any?, forKey key: String) {
        guard key != "workspaceCustomizationConfiguration" else { return }
        super.set(value, forKey: key)
    }
}
