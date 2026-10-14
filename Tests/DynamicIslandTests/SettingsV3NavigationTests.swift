import XCTest
@testable import DynamicIsland

@MainActor
final class SettingsV3NavigationTests: XCTestCase {
    func testMultiAndHighAlertSamplesUseProductionGeometryWithoutPreferenceWrites() {
        let defaults = SettingsPreviewDefaults(); let settings = AppSettings(defaults: defaults)
        let before = defaults.dictionaryRepresentation() as NSDictionary
        for _ in 0..<20 {
            for mode in SettingsActivityPreviewMode.allCases {
                let presentation = LiveActivityLayoutSettingsPreview.presentation(settings: settings, scenario: mode.scenario)
                XCTAssertGreaterThan(presentation.geometry.collapsedFrame.width, 0)
                XCTAssertGreaterThan(presentation.canvasSize.height, 0)
                XCTAssertNotNil(presentation.resolution.primary)
            }
        }
        XCTAssertEqual(SettingsActivityPreviewMode.multi.scenario, .mediaBatteryTimer)
        XCTAssertEqual(SettingsActivityPreviewMode.highAlert.scenario, .permissionHover)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
    func testNotchChoicePersistsAndCannotStealProtectedOrExpandedInteractions() {
        let defaults = SettingsPreviewDefaults()
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.notchRightClickAction, .openSettings)
        settings.notchRightClickAction = .hide
        XCTAssertEqual(AppSettings(defaults: defaults).notchRightClickAction, .hide)
        XCTAssertTrue(NotchRightClickAction.permitted(collapsed: true, morphing: false, protected: false))
        XCTAssertFalse(NotchRightClickAction.permitted(collapsed: false, morphing: false, protected: false))
        XCTAssertFalse(NotchRightClickAction.permitted(collapsed: true, morphing: true, protected: false))
        XCTAssertFalse(NotchRightClickAction.permitted(collapsed: true, morphing: false, protected: true))
    }
    func testTransferReaderRejectsSymlinksDirectoriesAndOversizedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settings-transfer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sample.json")
        let data = Data("{}".utf8); try data.write(to: file)
        XCTAssertEqual(try SettingsDocumentFile.readJSON(file), data)
        let link = root.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try SettingsDocumentFile.readJSON(link))
        let directory = root.appendingPathComponent("folder.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        XCTAssertThrowsError(try SettingsDocumentFile.readJSON(directory))
        try Data(repeating: 32, count: 65_537).write(to: file)
        XCTAssertThrowsError(try SettingsDocumentFile.readJSON(file))
        XCTAssertThrowsError(try SettingsDocumentFile.readJSON(URL(string: "https://example.invalid/sample.json")!))
    }
    func testElevenReferencePagesAndEveryLegacyPaneHaveStableRestorableRoutes() {
        XCTAssertEqual(SettingsPage.sidebarGroups.flatMap { $0 }, SettingsPage.allCases)
        XCTAssertEqual(SettingsPage.allCases.map(\.rawValue), ["Account", "General", "Module Store", "Shelf", "Basket", "Clipboard", "Lock Screen", "Cloud / Sharing", "Shortcuts", "Live Activities", "About"])
        let routes = SettingsPage.allCases.map(SettingsRoute.page) + SettingsSection.allCases.map(SettingsRoute.section) + [.permissions]
        XCTAssertEqual(Set(routes.map(\.id)).count, routes.count)
        for route in routes { XCTAssertEqual(SettingsRoute(id: route.id), route) }
        XCTAssertNil(SettingsRoute(id: "unknown"))
    }
    func testHistoryBranchesWithoutDuplicatesAndRelaunchRestoresRouteAndSidebar() {
        let defaults = SettingsPreviewDefaults()
        let store = SettingsNavigationStore(defaults: defaults)
        store.navigate(.page(.shelf)); store.navigate(.page(.shelf)); store.navigate(.section(.media))
        XCTAssertEqual(store.backHistory, [.page(.general), .page(.shelf)])
        store.back(); XCTAssertEqual(store.route, .page(.shelf))
        store.forward(); XCTAssertEqual(store.route, .section(.media))
        store.back(); store.navigate(.page(.clipboard))
        XCTAssertTrue(store.forwardHistory.isEmpty)
        store.sidebarVisible = false
        let restored = SettingsNavigationStore(defaults: defaults)
        XCTAssertEqual(restored.route, .page(.clipboard)); XCTAssertFalse(restored.sidebarVisible)
        XCTAssertTrue(restored.backHistory.isEmpty)
    }
    func testInvalidStoredRouteRecoversAndHistoryIsBounded() {
        let defaults = SettingsPreviewDefaults(); defaults.set("script://arbitrary", forKey: "settings.route")
        let store = SettingsNavigationStore(defaults: defaults)
        XCTAssertEqual(store.route, .page(.general))
        for i in 0..<300 { store.navigate(.page(i.isMultiple(of: 2) ? .shelf : .about)) }
        XCTAssertEqual(store.backHistory.count, 128)
        store.scrollOrigins[.page(.shelf)] = CGPoint(x: 0, y: 170)
        XCTAssertNil(store.scrollOrigins[.page(.clipboard)])
    }
    func testShortcutStoreUsesInjectedPreferencesAndEditsPersist() {
        let defaults = SettingsPreviewDefaults()
        let store = ShortcutsStore(defaults: defaults)
        XCTAssertTrue(store.shortcuts.isEmpty)
        store.shortcuts = [.init(title: "Synthetic", target: "https://example.invalid", symbolName: "link")]
        XCTAssertEqual(ShortcutsStore(defaults: defaults).shortcuts, store.shortcuts)
        store.remove(store.shortcuts[0]); XCTAssertTrue(ShortcutsStore(defaults: defaults).shortcuts.isEmpty)
    }
}

@MainActor
final class SettingsV3ModuleImportTests: XCTestCase {
    private var valid: SettingsLocalModule {
        .init(schemaVersion: 1, id: "local.media", title: "Media shortcut", summary: "Open media settings",
            destination: SettingsSection.media.rawValue, capabilities: ["settings-navigation"])
    }
    func testSchemaOnlyAcceptsExistingSettingsNavigationAndRejectsExecutableFields() throws {
        let bytes = try JSONEncoder().encode(valid)
        XCTAssertEqual(try SettingsLocalModule.validate(bytes), valid)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for (key, value) in [("schemaVersion", 2 as Any), ("destination", "../../script" as Any), ("capabilities", ["shell"] as Any), ("id", "../escape" as Any)] {
            var bad = object; bad[key] = value
            XCTAssertThrowsError(try SettingsLocalModule.validate(JSONSerialization.data(withJSONObject: bad)))
        }
        object["script"] = "do not execute"
        XCTAssertThrowsError(try SettingsLocalModule.validate(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try SettingsLocalModule.validate(Data(repeating: 0, count: 65_537)))
    }
    func testChooseAndDropShareReviewAcceptancePersistenceDuplicateAndRemoval() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("module.json")
        try JSONEncoder().encode(valid).write(to: file)
        let defaults = SettingsPreviewDefaults(); let store = SettingsModuleImportStore(defaults: defaults)
        await store.inspect(file)
        XCTAssertTrue(store.receipts.isEmpty, "Inspection is not approval")
        XCTAssertEqual(store.candidate?.module, valid); XCTAssertEqual(store.candidate?.sha256.count, 64)
        store.cancel(); XCTAssertNil(store.candidate)
        await store.inspect(file); store.accept(); store.accept()
        XCTAssertEqual(store.receipts.count, 1)
        XCTAssertEqual(SettingsModuleImportStore(defaults: defaults).receipts, store.receipts)
        await store.inspect(file); XCTAssertNil(store.candidate); XCTAssertNotNil(store.message)
        store.remove(valid.id); XCTAssertTrue(SettingsModuleImportStore(defaults: defaults).receipts.isEmpty)
    }
    func testSymlinkDirectoryRemoteMalformedAndUnknownPluginAreRejectedWithoutReceipt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("bad.json"); try Data("{}".utf8).write(to: file)
        let link = directory.appendingPathComponent("link.json"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let store = SettingsModuleImportStore(defaults: SettingsPreviewDefaults())
        for url in [file, link, directory, URL(string: "https://example.invalid/plugin.json")!, directory.appendingPathComponent("script.droplet")] {
            await store.inspect(url); XCTAssertNil(store.candidate); XCTAssertNotNil(store.message)
            XCTAssertTrue(store.receipts.isEmpty); XCTAssertFalse(store.isValidating)
        }
        XCTAssertEqual(try Data(contentsOf: file), Data("{}".utf8))
    }
}

@MainActor
final class SettingsV3PreferenceTransferTests: XCTestCase {
    func testVisibilityCannotLoseBothRecoveryIconsAndPersistsWithoutTouchingOtherSettings() {
        let defaults = SettingsPreviewDefaults(); let settings = AppSettings(defaults: defaults)
        settings.timerPreset1Minutes = 31
        settings.menuBarIconEnabled = false; XCTAssertTrue(settings.menuBarIconEnabled)
        settings.dockIconEnabled = true; settings.menuBarIconEnabled = false
        XCTAssertFalse(settings.menuBarIconEnabled)
        settings.dockIconEnabled = false; XCTAssertTrue(settings.menuBarIconEnabled)
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.menuBarIconEnabled); XCTAssertFalse(reloaded.dockIconEnabled)
        XCTAssertEqual(reloaded.timerPreset1Minutes, 31)
    }
    func testAppearanceExportImportIsDryRunUntilApplyAndExcludesPrivateDataAndActivation() throws {
        let sourceDefaults = SettingsPreviewDefaults(); let source = AppSettings(defaults: sourceDefaults)
        source.shellOpacity = 0.68; source.animationPreset = .slow
        sourceDefaults.set("secret", forKey: "spotify.refreshToken")
        sourceDefaults.set(["private.file"], forKey: "files")
        sourceDefaults.set(true, forKey: "gesturesEnabled")
        let data = try source.exportAppearanceTransfer()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("secret")); XCTAssertFalse(text.contains("private.file")); XCTAssertFalse(text.contains("gesturesEnabled"))
        let target = AppSettings(defaults: SettingsPreviewDefaults())
        let document = try target.inspectAppearanceTransfer(data)
        XCTAssertEqual(target.shellOpacity, 1)
        XCTAssertTrue(target.appearanceTransferChanges(document).contains("shellOpacity"))
        try target.applyAppearanceTransfer(document)
        XCTAssertEqual(target.shellOpacity, 0.68); XCTAssertEqual(target.animationPreset, .slow)
        XCTAssertFalse(target.gesturesEnabled)
    }
    func testTamperedWrongTypeUnknownKeysVersionAndRangesRejectWithoutWrites() throws {
        let defaults = SettingsPreviewDefaults(); let settings = AppSettings(defaults: defaults)
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let candidates: [[String: SettingsTransferValue]] = [
            ["shellOpacity": .number(9)], ["shellOpacity": .text("0.5")],
            ["showMediaTitle": .number(1)], ["showMediaTitle": .text("true")],
            ["launchAtLoginEnabled": .boolean(true)], ["shellOpacity": .number(0.5), "private.path": .text("sensitive")]]
        for values in candidates {
            let candidate = SettingsTransferDocument(version: 1, scope: "appearance", values: values,
                sha256: try SettingsTransferDocument.checksum(values))
            XCTAssertThrowsError(try settings.applyAppearanceTransfer(candidate))
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        }
        let data = try settings.exportAppearanceTransfer()
        let document = try JSONDecoder().decode(SettingsTransferDocument.self, from: data)
        XCTAssertThrowsError(try settings.applyAppearanceTransfer(.init(version: 2, scope: "appearance", values: document.values, sha256: document.sha256)))
        XCTAssertThrowsError(try settings.applyAppearanceTransfer(.init(version: 1, scope: "appearance", values: ["shellOpacity": .number(0.5)], sha256: "tampered")))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }
}

@MainActor
final class SettingsV3ClipboardPreviewTests: XCTestCase {
    func testInteractivePreviewUsesOnlySyntheticEntriesAndCopiesIntoItsOwnMemory() throws {
        let preview = SettingsClipboardPreviewModel()
        XCTAssertEqual(preview.store.entries.count, 3)
        XCTAssertEqual(Set(preview.store.entries.map { $0.payload.kind }), [.text, .url, .image])
        XCTAssertFalse(preview.store.isMonitoring)
        XCTAssertFalse(preview.settings.clipboardHistoryPersistenceEnabled)
        preview.settings.clipboardHistoryCopyAndFavorite = true
        let entry = try XCTUnwrap(preview.store.entries.first)
        XCTAssertTrue(preview.store.copyEntryToPasteboard(id: entry.id))
        XCTAssertEqual(preview.pasteboard.value, entry.payload)
        XCTAssertTrue(preview.store.entries.first(where: { $0.id == entry.id })?.isFavorite == true)
        preview.store.toggleFavorite(id: entry.id)
        XCTAssertTrue(preview.store.entries.first(where: { $0.id == entry.id })?.isFavorite == false)
        preview.store.removeEntry(id: entry.id)
        XCTAssertEqual(preview.store.entries.count, 2)
        XCTAssertEqual(SettingsClipboardPreviewModel().store.entries.count, 3)
    }
}

@MainActor
final class SettingsV3SearchTests: XCTestCase {
    func testControlSearchNavigatesToRealGroupAndHistoryClearsItsHighlight() throws {
        let navigation = SettingsNavigationStore(defaults: SettingsPreviewDefaults())
        let result = try XCTUnwrap(SettingsSearchResult.matching("retention pinned").first)
        XCTAssertEqual(result.route, .page(.clipboard))
        navigation.open(result)
        XCTAssertEqual(navigation.requestedAnchor, "Clipboard History")
        XCTAssertEqual(navigation.route, .page(.clipboard))
        navigation.back()
        XCTAssertEqual(navigation.route, .page(.general))
        XCTAssertNil(navigation.requestedAnchor)
        XCTAssertTrue(SettingsSearchResult.matching("   ").isEmpty)
        XCTAssertTrue(SettingsSearchResult.matching("fabricatedmodule").isEmpty)
        XCTAssertEqual(SettingsSearchResult.entries.count, Set(SettingsSearchResult.entries.map(\.id)).count)
    }
}

@MainActor
final class SettingsV3ShortcutReorderTests: XCTestCase {
    func testNativeDropReordersDraftOnlyAndRejectsOtherPayloads() {
        let defaults = SettingsPreviewDefaults()
        let store = ShortcutsStore(defaults: defaults)
        store.shortcuts = [.init(title: "First", target: "https://example.invalid/1", symbolName: "link"),
                           .init(title: "Second", target: "https://example.invalid/2", symbolName: "folder")]
        let original = store.shortcuts
        var draft = original
        guard original.count >= 2 else { return XCTFail("Fixture needs at least two shortcuts") }
        XCTAssertTrue(SettingsShortcutReorder.move("dynamicisland-shortcut:" + original[1].id.uuidString, before: original[0].id, in: &draft))
        XCTAssertEqual(draft[0], original[1])
        XCTAssertEqual(store.shortcuts, original, "Drag remains reversible until Apply")
        let reordered = draft
        XCTAssertFalse(SettingsShortcutReorder.move("arbitrary external text", before: draft[0].id, in: &draft))
        XCTAssertFalse(SettingsShortcutReorder.move("dynamicisland-shortcut:" + UUID().uuidString, before: draft[0].id, in: &draft))
        XCTAssertEqual(draft, reordered)
        store.shortcuts = draft
        XCTAssertEqual(ShortcutsStore(defaults: defaults).shortcuts, reordered)
    }
}

@MainActor
final class SettingsV3LockSoundTests: XCTestCase {
    func testIndependentSoundSelectionsPersistAndOnlySystemFilesAreOffered() {
        let defaults = SettingsPreviewDefaults()
        let model = SettingsLockSoundModel(defaults: defaults)
        XCTAssertEqual(SettingsLockSoundModel.names, ["Default", "None", "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"])
        model.lock = "None"
        model.unlock = "Glass"
        let restored = SettingsLockSoundModel(defaults: defaults)
        XCTAssertEqual(restored.lock, "None")
        XCTAssertEqual(restored.unlock, "Glass")
        XCTAssertNil(model.message, "Changing selection must never play a sound")
        for name in SettingsLockSoundModel.availableNames where name != "Default" && name != "None" {
            XCTAssertTrue(FileManager.default.fileExists(atPath: SettingsLockSoundModel.soundURL(name).path))
        }
        defaults.set("../../private", forKey: "settings.lockPreview.lockSound")
        XCTAssertEqual(SettingsLockSoundModel(defaults: defaults).lock, "Default")
    }
}

@MainActor
final class SettingsV3InteractiveMediaPreviewTests: XCTestCase {
    func testProductionMediaPreviewRespondsLocallyWithoutOpeningOrSendingToApps() {
        let media = MediaController.settingsPreview()
        XCTAssertTrue(media.isPlaying)
        media.playPause(); XCTAssertFalse(media.isPlaying)
        media.playPause(); XCTAssertTrue(media.isPlaying)
        media.setScrubbing(true)
        media.updateScrubPosition(112)
        media.setScrubbing(false)
        XCTAssertEqual(media.playbackPosition, 112)
        media.seek(to: 50); XCTAssertEqual(media.playbackPosition, 50)
        media.setVolume(0.2); XCTAssertEqual(media.volume, 0.2)
        media.nextTrack(); XCTAssertEqual(media.title, "Preview Track 2")
        XCTAssertEqual(media.playbackPosition, 0)
        media.previousTrack(); XCTAssertEqual(media.title, "Preview Track")
        XCTAssertFalse(media.openActiveMediaSource())
        XCTAssertTrue(media.isSettingsPreview)
        XCTAssertNil(media.artworkFlipRequest)
    }
}
