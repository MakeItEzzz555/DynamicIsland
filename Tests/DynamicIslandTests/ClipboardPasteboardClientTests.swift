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
    func testColorIsCapturedAndWrittenBack() throws {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([NSColor(srgbRed: 0.25, green: 0.5, blue: 0.75, alpha: 1)]))
        let client = SystemClipboardPasteboardClient(pasteboard: pasteboard)

        guard case let .payload(.color(color)) = client.readSupportedPayload(limits: .standard, capturesImages: true)
        else { return XCTFail("expected color payload") }
        XCTAssertEqual(color.red, 0.25, accuracy: 0.001)
        XCTAssertEqual(color.blue, 0.75, accuracy: 0.001)
        XCTAssertEqual(color.hexString, "#4080BF")

        let other = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        XCTAssertTrue(SystemClipboardPasteboardClient(pasteboard: other).write(.color(color)).succeeded)
        let roundTrip = try XCTUnwrap(NSColor(from: other)?.usingColorSpace(.sRGB))
        XCTAssertEqual(roundTrip.greenComponent, 0.5, accuracy: 0.001)
    }

    @MainActor
    func testColorFlavorNextToTextStaysText() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setData(Data([1]), forType: .color)
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true)
        guard case let .payload(payload) = result else { return XCTFail("expected payload") }
        XCTAssertEqual(payload.kind, .text)
    }

    @MainActor
    func testConcealedColorIsExcluded() {
        let pasteboard = NSPasteboard(name: .init("ClipboardTests-\(UUID())"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(Data([1]), forType: .color)
        item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        XCTAssertTrue(pasteboard.writeObjects([item]))
        XCTAssertEqual(SystemClipboardPasteboardClient(pasteboard: pasteboard)
            .readSupportedPayload(limits: .standard, capturesImages: true), .sensitive)
    }

    func testExportShareItemsAndTemporaryFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipExport-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = FileShelfTemporaryStorage(rootURL: root)
        let text = ClipboardHistoryPayload.text(.init(plainText: "hello", rtfData: nil, htmlData: nil))
        let url = try XCTUnwrap(ClipboardEntryExport.writeTemporaryFile(for: text, storage: storage))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
        XCTAssertTrue(url.path.hasPrefix(root.standardizedFileURL.path))
        XCTAssertEqual(url.pathExtension, "txt")
        let png = try XCTUnwrap(ClipboardEntryExport.writeTemporaryFile(for: .imagePNG(Data([1, 2])), storage: storage))
        XCTAssertEqual(png.pathExtension, "png")
        XCTAssertNil(try ClipboardEntryExport.writeTemporaryFile(for: .url(URL(string: "https://a.b")!), storage: storage))
        XCTAssertEqual(ClipboardEntryExport.shareItems(for: text).count, 1)
        XCTAssertEqual(ClipboardEntryExport.shareItems(for: .files([URL(fileURLWithPath: "/nonexistent/x")])).count, 0)
    }

    func testColorFingerprintDiffersByValue() {
        let a = ClipboardHistoryFingerprint.make(for: .color(.init(red: 1, green: 0, blue: 0, alpha: 1)))
        let b = ClipboardHistoryFingerprint.make(for: .color(.init(red: 0, green: 1, blue: 0, alpha: 1)))
        XCTAssertNotEqual(a, b)
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
