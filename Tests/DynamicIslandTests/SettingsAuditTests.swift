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
        XCTAssertEqual(published.count, 189)
        let audited = SettingsAuditCatalog.appSettingsKeys
        XCTAssertEqual(audited.count, Set(audited).count, "duplicate audit entries")
        XCTAssertEqual(Set(audited), Set(published),
                       "missing: \(Set(published).subtracting(audited).sorted()) extra: \(Set(audited).subtracting(published).sorted())")
    }

    func testEveryUserFacingVisualSettingHasALivePreview() {
        XCTAssertFalse(
            SettingsAuditCatalog.entries.contains { $0.classification == .visualWithoutPreview },
            "Every user-facing visual setting must have a live production-component preview"
        )
        for entry in SettingsAuditCatalog.entries where entry.classification == .visual {
            XCTAssertNotNil(entry.preview, "\(entry.key) is visual but has no preview")
        }
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
            "collapsedPriorityRunningTimer", "collapsedPriorityPlayingMedia", "collapsedPriorityPausedTimer",
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
