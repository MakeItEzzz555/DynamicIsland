import AppKit
import XCTest
@testable import DynamicIsland

final class ClipboardPasteboardClientTests: XCTestCase {
    @MainActor
    func testFileURLsTakePrecedenceAndDeduplicateInOrder() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let first = URL(fileURLWithPath: "/tmp/one")
        let second = URL(fileURLWithPath: "/tmp/two")
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([first as NSURL, second as NSURL, first as NSURL]))

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(result, .payload(.files([first.standardizedFileURL, second.standardizedFileURL])))
    }

    @MainActor
    func testURLTakesPrecedenceOverText() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let item = NSPasteboardItem()
        item.setString("https://example.com/path", forType: .URL)
        item.setString("fallback text", forType: .string)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(result, .payload(.url(URL(string: "https://example.com/path")!)))
    }

    @MainActor
    func testPlainStringWithHTTPSURLIsCapturedAsURL() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let value = "https://example.com/plain-string"
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(result, .payload(.url(URL(string: value)!)))
    }

    @MainActor
    func testTwentyThousandCharacterPlainWordIsCapturedAsText() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let value = String(repeating: "a", count: 20_000)
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(
            result,
            .payload(.text(.init(plainText: value, rtfData: nil, htmlData: nil)))
        )
    }

    @MainActor
    func testSchemeLessRelativePathIsCapturedAsText() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let value = "notes/archive/today.txt"
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(
            result,
            .payload(.text(.init(plainText: value, rtfData: nil, htmlData: nil)))
        )
    }

    @MainActor
    func testValidHTTPSURLOverURLLimitIsOversized() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let value = "https://example.com/"
            + String(repeating: "a", count: ClipboardHistoryLimits.standard.maximumURLStringBytes)
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(result, .oversized)
    }

    @MainActor
    func testTextOverPlainTextLimitIsOversized() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let value = String(
            repeating: "a",
            count: ClipboardHistoryLimits.standard.maximumPlainTextBytes + 1
        )
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(result, .oversized)
    }

    @MainActor
    func testPunctuationWithoutSchemeIsCapturedAsText() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let value = "Reminder, buy milk! (two cartons) #errands"
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(
            result,
            .payload(.text(.init(plainText: value, rtfData: nil, htmlData: nil)))
        )
    }

    @MainActor
    func testWhitespaceOnlyTextIsRejected() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        pasteboard.clearContents()
        pasteboard.setString(" \n\t", forType: .string)

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(result, .empty)
    }

    @MainActor
    func testSensitiveMarkerPreventsExtraction() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let item = NSPasteboardItem()
        item.setString("secret", forType: .string)
        item.setString("1", forType: .init("org.nspasteboard.ConcealedType"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(result, .sensitive)
    }

    @MainActor
    func testOversizedOptionalRichRepresentationsAreDiscarded() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setData(Data(repeating: 1, count: 12), forType: .rtf)
        item.setData(Data(repeating: 2, count: 12), forType: .html)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let limits = ClipboardHistoryLimits(
            maximumPlainTextBytes: 100,
            maximumRichTextBytesPerRepresentation: 4,
            maximumImageBytes: 100,
            maximumFilesPerEntry: 10,
            maximumURLStringBytes: 100,
            maximumTotalHistoryPayloadBytes: 1_000
        )

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: limits, capturesImages: true)

        XCTAssertEqual(
            result,
            .payload(.text(.init(plainText: "plain", rtfData: nil, htmlData: nil)))
        )
    }

    func testStableFingerprintsIncludePayloadType() {
        let text = ClipboardHistoryPayload.text(
            .init(plainText: "https://example.com", rtfData: nil, htmlData: nil)
        )
        let url = ClipboardHistoryPayload.url(URL(string: "https://example.com")!)

        XCTAssertEqual(
            ClipboardHistoryFingerprint.make(for: text),
            ClipboardHistoryFingerprint.make(for: text)
        )
        XCTAssertNotEqual(
            ClipboardHistoryFingerprint.make(for: text),
            ClipboardHistoryFingerprint.make(for: url)
        )
    }

    @MainActor
    func testImageTakesPrecedenceAndIsNormalizedToPNG() throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.addRepresentation(bitmap)
        let tiff = image.tiffRepresentation!
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let item = NSPasteboardItem()
        item.setData(tiff, forType: .tiff)
        item.setString("https://example.com", forType: .URL)
        item.setString("fallback", forType: .string)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        guard case let .payload(.imagePNG(data)) = result else {
            return XCTFail("Expected normalized image payload")
        }
        XCTAssertNotNil(NSBitmapImageRep(data: data))
        XCTAssertLessThanOrEqual(data.count, ClipboardHistoryLimits.standard.maximumImageBytes)
    }

    @MainActor
    func testOversizedNormalizedImageIsRejected() {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let png = bitmap.representation(using: .png, properties: [:])!
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let limits = ClipboardHistoryLimits(
            maximumPlainTextBytes: 100,
            maximumRichTextBytesPerRepresentation: 100,
            maximumImageBytes: 1,
            maximumFilesPerEntry: 10,
            maximumURLStringBytes: 100,
            maximumTotalHistoryPayloadBytes: 100
        )

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: limits, capturesImages: true)

        XCTAssertEqual(result, .oversized)
    }

    @MainActor
    func testInvalidExplicitURLIsRejectedSafely() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        let item = NSPasteboardItem()
        item.setString(":// invalid", forType: .URL)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)

        XCTAssertEqual(result, .unsupported)
    }
}
