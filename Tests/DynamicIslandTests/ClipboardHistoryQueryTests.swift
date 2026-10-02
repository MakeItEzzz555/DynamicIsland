import Foundation
import XCTest
@testable import DynamicIsland

final class ClipboardHistoryQueryTests: XCTestCase {
    func testSearchCoversTextURLFilenameSourceCustomTitleAndTag() {
        let tag = ClipboardTag(name: "Project", color: .purple)
        let entries = [
            entry(.text(.init(plainText: "Alpha body", rtfData: nil, htmlData: nil)), source: "VS Code"),
            entry(.url(URL(string: "https://example.com/path")!), title: "Docs"),
            entry(.files([URL(fileURLWithPath: "/tmp/report-final.pdf")])),
            ClipboardHistoryEntry(
                id: UUID(),
                createdAt: Date(),
                payload: .imagePNG(Data([1])),
                fingerprint: "image",
                sourceApplication: ClipboardSourceApplication(name: "Preview", bundleIdentifier: "com.apple.Preview"),
                tagIDs: [tag.id]
            )
        ]

        XCTAssertEqual(query("alpha").apply(entries: entries, tags: [tag]).count, 1)
        XCTAssertEqual(query("example.com").apply(entries: entries, tags: [tag]).count, 1)
        XCTAssertEqual(query("report-final").apply(entries: entries, tags: [tag]).count, 1)
        XCTAssertEqual(query("vs code").apply(entries: entries, tags: [tag]).count, 1)
        XCTAssertEqual(query("docs").apply(entries: entries, tags: [tag]).count, 1)
        XCTAssertEqual(query("project").apply(entries: entries, tags: [tag]).count, 1)
    }

    func testSearchIsCaseAndDiacriticInsensitive() {
        let item = entry(.text(.init(plainText: "Résumé ÉCLAIR", rtfData: nil, htmlData: nil)))
        XCTAssertEqual(query("resume eclair").apply(entries: [item], tags: []).map(\.id), [item.id])
    }

    func testFiltersAndTagIntersectionAreDeterministic() {
        let tag = ClipboardTag(name: "Keep", color: .green)
        let favorite = ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            payload: .url(URL(string: "https://openai.com")!),
            fingerprint: "fav",
            isFavorite: true,
            tagIDs: [tag.id]
        )
        let text = entry(.text(.init(plainText: "plain", rtfData: nil, htmlData: nil)))
        var q = ClipboardHistoryQuery(text: "", filter: .favorites, tagID: nil)
        XCTAssertEqual(q.apply(entries: [favorite, text], tags: [tag]).map(\.id), [favorite.id])
        q.filter = .links
        q.tagID = tag.id
        XCTAssertEqual(q.apply(entries: [favorite, text], tags: [tag]).map(\.id), [favorite.id])
        q.filter = .text
        XCTAssertTrue(q.apply(entries: [favorite, text], tags: [tag]).isEmpty)
    }

    func testUnknownTagFilterDoesNotHideHistory() {
        let item = entry(.text(.init(plainText: "kept", rtfData: nil, htmlData: nil)))
        let q = ClipboardHistoryQuery(text: "", filter: .all, tagID: UUID())
        XCTAssertEqual(q.apply(entries: [item], tags: []).map(\.id), [item.id])
    }

    private func query(_ text: String) -> ClipboardHistoryQuery {
        ClipboardHistoryQuery(text: text, filter: .all, tagID: nil)
    }

    private func entry(
        _ payload: ClipboardHistoryPayload,
        title: String? = nil,
        source: String? = nil
    ) -> ClipboardHistoryEntry {
        ClipboardHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            payload: payload,
            fingerprint: UUID().uuidString,
            sourceApplication: source.map {
                ClipboardSourceApplication(name: $0, bundleIdentifier: "test.\($0.replacingOccurrences(of: " ", with: "-"))")
            },
            customTitle: title
        )
    }
}
