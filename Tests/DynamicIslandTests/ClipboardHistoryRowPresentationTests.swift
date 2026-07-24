import Foundation
import XCTest
@testable import DynamicIsland

final class ClipboardHistoryRowPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    func testTextPresentationNormalizesWhitespace() {
        let result = presentation(.text(.init(plainText: "Hello\n  world", rtfData: nil, htmlData: nil)))
        XCTAssertEqual(result.iconName, "text.alignleft")
        XCTAssertEqual(result.title, "Hello world")
        XCTAssertEqual(result.detail, "13 characters")
    }

    func testURLPresentationUsesHostAndFullURLDetail() {
        let result = presentation(.url(URL(string: "https://example.com/a?q=1")!))
        XCTAssertEqual(result.title, "example.com")
        XCTAssertEqual(result.detail, "https://example.com/a?q=1")
    }

    func testFilePresentationDoesNotExposeParentPath() {
        let result = presentation(.files([
            URL(fileURLWithPath: "/Users/private/Documents/report.pdf"),
            URL(fileURLWithPath: "/Volumes/Secret/photo.jpg")
        ]))
        XCTAssertEqual(result.title, "report.pdf, photo.jpg")
        XCTAssertEqual(result.detail, "2 files")
        XCTAssertFalse(result.title.contains("/Users/private"))
    }

    func testImagePresentationReportsFileSize() {
        let result = presentation(.imagePNG(Data(repeating: 1, count: 2_048)))
        XCTAssertEqual(result.iconName, "photo")
        XCTAssertEqual(result.title, "Image")
        XCTAssertTrue(result.isImage)
        XCTAssertFalse(result.detail.isEmpty)
    }

    func testEmptyTextHasSafeFallback() {
        let result = presentation(.text(.init(plainText: " \n ", rtfData: nil, htmlData: nil)))
        XCTAssertEqual(result.title, "Text")
    }

    private func presentation(_ payload: ClipboardHistoryPayload) -> ClipboardHistoryRowPresentation {
        ClipboardHistoryRowPresentation.resolve(
            entry: ClipboardHistoryEntry(
                id: UUID(),
                createdAt: now,
                payload: payload,
                fingerprint: "fixture"
            ),
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )
    }
}
