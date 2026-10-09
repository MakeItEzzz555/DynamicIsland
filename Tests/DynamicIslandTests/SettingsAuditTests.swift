import Foundation
import XCTest
@testable import DynamicIsland

final class SettingsAuditTests: XCTestCase {
    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DynamicIsland", isDirectory: true)
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: sourcesRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    private func allSources() throws -> [(name: String, text: String)] {
        let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)
        var result: [(String, String)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            result.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return result
    }

    private func publishedSettings() throws -> [String] {
        let text = try source("State/AppSettings.swift")
        let regex = try NSRegularExpression(pattern: #"@Published public var ([A-Za-z0-9]+):"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    func testEveryAppSettingIsAuditedExactlyOnce() throws {
        let published = try publishedSettings()
        XCTAssertEqual(published.count, 202)
        let audited = SettingsAuditCatalog.appSettingsKeys
        XCTAssertEqual(audited.count, Set(audited).count, "duplicate audit entries")
        XCTAssertEqual(Set(audited), Set(published),
                       "missing: \(Set(published).subtracting(audited).sorted()) extra: \(Set(audited).subtracting(published).sorted())")
    }

    func testEveryUserFacingVisualSettingHasALivePreview() {
        // Only the pinned, documented gaps may lack a production-component
        // preview; the set may shrink but never grow.
        let withoutPreview = Set(SettingsAuditCatalog.entries
            .filter { $0.classification == .visualWithoutPreview }
            .map(\.key))
        XCTAssertEqual(withoutPreview, SettingsAuditCatalog.knownPreviewGaps,
                       "Every user-facing visual setting must have a live production-component preview")
        XCTAssertLessThanOrEqual(SettingsAuditCatalog.knownPreviewGaps.count, 6)
        for entry in SettingsAuditCatalog.entries where entry.classification == .visual {
            XCTAssertNotNil(entry.preview, "\(entry.key) is visual but has no preview")
        }
    }

    /// Workspace personalization and messaging preferences live outside
    /// AppSettings; every stored field must be audited and have a reader.
    func testWorkspaceAndMessagingPreferencesAreAuditedWithProductionReaders() throws {
        let workspaceFields = Set(Mirror(reflecting: RightWorkspaceConfiguration.default).children.compactMap(\.label))
        let messagingFields = Set(Mirror(reflecting: MessagingController.Preferences()).children.compactMap(\.label))
        let audited = Set(SettingsAuditCatalog.entries.map(\.key))
        XCTAssertEqual(
            Set(audited.filter { $0.hasPrefix("rightWorkspace.") }.map { String($0.dropFirst("rightWorkspace.".count)) }),
            workspaceFields
        )
        XCTAssertEqual(
            Set(audited.filter { $0.hasPrefix("messaging.") }.map { String($0.dropFirst("messaging.".count)) }),
            messagingFields
        )

        // Production reader token per workspace field, searched outside
        // Settings files and the store/model file itself.
        let readers: [String: String] = [
            "pageOrder": "visiblePages", "hiddenPages": "visiblePages",
            "defaultPage": "defaultPage", "indicatorStyle": "indicatorStyle", "swipeEnabled": "swipeEnabled",
            "toolOrder": "visibleTools", "hiddenTools": "visibleTools",
            "sectionOrder": "visibleSections", "hiddenSections": "visibleSections"
        ]
        XCTAssertEqual(Set(readers.keys), workspaceFields)
        let excluded: Set<String> = ["SettingsView.swift", "SettingsAudit.swift", "SettingsPreviews.swift",
                                     "RightWorkspaceSettingsView.swift"]
        var production = try allSources().filter { !excluded.contains($0.name) }
        // defaultPage is applied by the store itself (launch + on change).
        let storeText = try source("State/RightWorkspace.swift")
        XCTAssertTrue(storeText.contains("currentPage = configuration.defaultPage"))
        production.removeAll { $0.name == "RightWorkspace.swift" }
        for (field, token) in readers where field != "defaultPage" {
            XCTAssertTrue(production.contains { $0.text.contains(".\(token)") }, "\(field) has no production reader (\(token))")
        }
        let messagingSource = try source("Messaging/MessagingController.swift")
        for field in messagingFields {
            XCTAssertTrue(messagingSource.contains("preferences.\(field)"), "messaging \(field) has no production reader")
        }
    }

    @MainActor
    func testLiveActivityLayoutPreviewAppliesPerSourceSwitches() {
        let all = [LiveActivityPreviewCatalog.media, LiveActivityPreviewCatalog.timer, LiveActivityPreviewCatalog.battery]
        func kinds(_ snapshot: LiveActivitySettingsSnapshot) -> [DynamicIslandLiveActivityKind] {
            LiveActivityLayoutSettingsPreview.publishedActivities(all, settings: snapshot).map(\.kind)
        }
        XCTAssertEqual(kinds(.init(liveActivitiesEnabled: true, showMusicLiveActivity: true, showTimerLiveActivity: true,
                                   showFileDropLiveActivity: true, showBatteryLiveActivity: true)),
                       [.media, .timer, .battery])
        XCTAssertEqual(kinds(.init(liveActivitiesEnabled: true, showMusicLiveActivity: false, showTimerLiveActivity: true,
                                   showFileDropLiveActivity: true, showBatteryLiveActivity: false)),
                       [.timer])
        XCTAssertEqual(kinds(.init(liveActivitiesEnabled: false, showMusicLiveActivity: true, showTimerLiveActivity: true,
                                   showFileDropLiveActivity: true, showBatteryLiveActivity: true)),
                       [])
    }

    @MainActor
    func testRightWorkspacePreviewShowsNewDefaultPageImmediately() {
        var config = RightWorkspaceConfiguration.default
        config.defaultPage = .appsMedia
        XCTAssertEqual(RightWorkspaceSettingsPreview.previewPage(current: .productivity, previousDefault: .overview,
                                                                 configuration: config), .appsMedia)
        XCTAssertEqual(RightWorkspaceSettingsPreview.previewPage(current: .productivity, previousDefault: .appsMedia,
                                                                 configuration: config), .productivity,
                       "an unrelated change keeps the page picked in the preview")
        config.hiddenPages = [.productivity]
        XCTAssertEqual(RightWorkspaceSettingsPreview.previewPage(current: .productivity, previousDefault: .appsMedia,
                                                                 configuration: config), .appsMedia)
    }

    /// Keeps the "no production reader" finding truthful, and makes sure a
    /// setting without an external reader is never presented as working.
    func testNoProductionReaderClassificationMatchesTheSources() throws {
        let excluded: Set<String> = ["AppSettings.swift", "SettingsView.swift", "SettingsAudit.swift"]
        var identifiers = Set<Substring>()
        for file in try allSources() where !excluded.contains(file.name) {
            identifiers.formUnion(file.text.split { !($0.isLetter || $0.isNumber || $0 == "_") })
        }
        func hasExternalReader(_ key: String) -> Bool {
            identifiers.contains(Substring(key))
        }
        // Read only through AppSettings computed properties.
        let indirect: Set<String> = [
            "collapsedWidth", "expandedWidth", "autoCollapseDelayPreset", "autoCollapseGraceSeconds", "showIslandTab",
            "collapsedPriorityAgent", "collapsedPriorityRunningTimer", "collapsedPriorityPlayingMedia", "collapsedPriorityPausedTimer",
            "collapsedPriorityRecentFiles", "collapsedPriorityPausedMedia"
        ]
        let settingsView = try source("Views/SettingsView.swift")
        XCTAssertFalse(
            SettingsAuditCatalog.entries.contains { $0.classification == .noProductionReader },
            "User-facing settings with no production reader are forbidden"
        )

        for entry in SettingsAuditCatalog.entries where !entry.key.contains(".") {
            let external = hasExternalReader(entry.key)
            switch entry.classification {
            case .noProductionReader:
                XCTFail("\(entry.key) is a forbidden user-facing dead setting")
            case .deprecatedHidden:
                XCTAssertFalse(external, "\(entry.key) gained a production reader; reclassify it")
                XCTAssertFalse(
                    settingsView.contains(entry.key),
                    "\(entry.key) is deprecated/hidden but is still exposed in SettingsView"
                )
            default:
                if !external {
                    XCTAssertTrue(indirect.contains(entry.key), "\(entry.key) has no production reader but is classified \(entry.classification)")
                }
            }
        }
    }

    /// Preview-only fixtures must never be referenced by production views.
    func testPreviewFixturesDoNotLeakIntoProductionCode() throws {
        let allowed: Set<String> = ["SettingsPreviews.swift", "DynamicIslandApp.swift", "MediaController.swift"]
        for file in try allSources() where !allowed.contains(file.name) {
            XCTAssertFalse(file.text.contains("SettingsPreviewFixtures"), "\(file.name) references SettingsPreviewFixtures")
            XCTAssertFalse(file.text.contains(".settingsPreview()"), "\(file.name) creates a preview media controller")
        }
        let app = try source("App/DynamicIslandApp.swift")
        let previewUses = app.components(separatedBy: "MediaController.settingsPreview()").count - 1
        XCTAssertEqual(previewUses, 1, "only the Settings preview dependencies build a preview controller")
    }

    @MainActor
    func testSettingsPreviewMediaControllerIsInert() {
        let media = MediaController.settingsPreview()
        XCTAssertTrue(media.isSettingsPreview)
        XCTAssertEqual(media.title, "Preview Track")
        media.playPause()
        media.nextTrack()
        XCTAssertFalse(media.playSpotifyURI("spotify:track:4iV5W9uYEdYUVa79Axb7Rh") == false,
                       "valid URI is accepted but the send is a no-op for the preview role")
        XCTAssertFalse(MediaController(startsAutomatically: false).isSettingsPreview)
    }

    /// Writes research/SETTINGS_PREVIEW_AUDIT.md when requested.
    func testWriteAuditReportWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_WRITE_SETTINGS_AUDIT"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_WRITE_SETTINGS_AUDIT=<file> to write the audit report.")
        }
        try SettingsAuditCatalog.markdownReport().write(toFile: path, atomically: true, encoding: .utf8)
    }
}
