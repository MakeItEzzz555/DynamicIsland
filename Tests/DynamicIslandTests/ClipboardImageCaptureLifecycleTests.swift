import AppKit
import XCTest
@testable import DynamicIsland

private actor SuspendedClipboardImageProcessor {
    private let started: XCTestExpectation
    private var continuation: CheckedContinuation<ClipboardPasteboardReadResult, Never>?

    init(started: XCTestExpectation) { self.started = started }

    func process(_ image: ClipboardImageCapture) async -> ClipboardPasteboardReadResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func finish(_ result: ClipboardPasteboardReadResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

final class ClipboardImageCaptureLifecycleTests: XCTestCase {
    @MainActor
    func testDefaultWorkerCapturesImageAndCopyBackPreservesPNG() async throws {
        try await withStore { settings, pasteboard, store in
            let png = try Self.smallPNG()
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            store.pollNow()
            XCTAssertTrue(store.entries.isEmpty, "Image processing must yield the main actor")
            await store.waitForPendingImageCaptureForTesting()
            let entry = try XCTUnwrap(store.entries.first)
            guard case let .imagePNG(normalized) = entry.payload else { return XCTFail("Expected PNG") }
            XCTAssertTrue(store.copyEntryToPasteboard(id: entry.id))
            XCTAssertEqual(pasteboard.data(forType: .png), normalized)
            store.pollNow()
            XCTAssertEqual(store.entries.count, 1)
            XCTAssertEqual(store.entries.first?.id, entry.id)
        }
    }

    @MainActor
    func testNewClipboardContentDiscardsOldImageAndCapturesLatestInOrder() async throws {
        try await withSuspendedStore { settings, pasteboard, store, processor in
            pasteboard.clearContents()
            pasteboard.setString("latest", forType: .string)
            // No second image job is scheduled while the first is running.
            store.pollNow()
            XCTAssertTrue(store.entries.isEmpty)
            await processor.finish(.payload(.imagePNG(Data([1]))))
            await store.waitForPendingImageCaptureForTesting()
            XCTAssertEqual(store.entries.map(\.payload), [.text(.init(plainText: "latest", rtfData: nil, htmlData: nil))])
        }
    }

    @MainActor
    func testDisableAndReenableMonitoringInvalidatesPendingImage() async throws {
        try await withSuspendedStore { settings, pasteboard, store, processor in
            settings.clipboardHistoryEnabled = false
            settings.clipboardHistoryEnabled = true
            await processor.finish(.payload(.imagePNG(Data([1]))))
            await store.waitForPendingImageCaptureForTesting()
            XCTAssertTrue(store.entries.isEmpty)
        }
    }

    @MainActor
    func testDisableAndReenableImageCaptureInvalidatesPendingImage() async throws {
        try await withSuspendedStore { settings, pasteboard, store, processor in
            settings.clipboardHistoryCaptureImagesEnabled = false
            settings.clipboardHistoryCaptureImagesEnabled = true
            await processor.finish(.payload(.imagePNG(Data([1]))))
            await store.waitForPendingImageCaptureForTesting()
            XCTAssertTrue(store.entries.isEmpty)
        }
    }

    @MainActor
    func testClearHistoryCannotBeUndoneByPendingImage() async throws {
        try await withSuspendedStore { settings, pasteboard, store, processor in
            store.clearHistory()
            await processor.finish(.payload(.imagePNG(Data([1]))))
            await store.waitForPendingImageCaptureForTesting()
            XCTAssertTrue(store.entries.isEmpty)
        }
    }

    @MainActor
    func testCopyBackInvalidatesPendingImageAndDoesNotRecaptureSelfWrite() async throws {
        let started = expectation(description: "Image processor suspended")
        let processor = SuspendedClipboardImageProcessor(started: started)
        try await withStore(processImage: { await processor.process($0) }) { settings, pasteboard, store in
            pasteboard.clearContents()
            pasteboard.setString("existing", forType: .string)
            store.pollNow()
            let entry = try XCTUnwrap(store.entries.first)
            pasteboard.clearContents()
            pasteboard.setData(try Self.smallPNG(), forType: .png)
            store.pollNow()
            await fulfillment(of: [started], timeout: 2)
            XCTAssertTrue(store.copyEntryToPasteboard(id: entry.id))
            await processor.finish(.payload(.imagePNG(Data([1]))))
            await store.waitForPendingImageCaptureForTesting()
            XCTAssertEqual(store.entries.map(\.id), [entry.id])
            XCTAssertEqual(pasteboard.string(forType: .string), "existing")
        }
    }

    @MainActor
    func testInvalidImageFallsBackToOriginalTextSnapshot() async throws {
        try await withStore { settings, pasteboard, store in
            let item = NSPasteboardItem()
            item.setData(Data("invalid".utf8), forType: .png)
            item.setString("fallback", forType: .string)
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.writeObjects([item]))
            store.pollNow()
            await store.waitForPendingImageCaptureForTesting()
            XCTAssertEqual(store.entries.map(\.payload), [.text(.init(plainText: "fallback", rtfData: nil, htmlData: nil))])
        }
    }

    @MainActor
    func testSensitiveReplacementCannotLeakPendingImage() async throws {
        try await withSuspendedStore { settings, pasteboard, store, processor in
            let item = NSPasteboardItem()
            item.setString("secret", forType: .string)
            item.setString("1", forType: .init("org.nspasteboard.ConcealedType"))
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.writeObjects([item]))
            await processor.finish(.payload(.imagePNG(Data([1]))))
            await store.waitForPendingImageCaptureForTesting()
            XCTAssertTrue(store.entries.isEmpty)
        }
    }

    @MainActor
    private func withSuspendedStore(
        check: @MainActor (AppSettings, NSPasteboard, ClipboardHistoryStore, SuspendedClipboardImageProcessor) async throws -> Void
    ) async throws {
        let started = expectation(description: "Image processor suspended")
        let processor = SuspendedClipboardImageProcessor(started: started)
        try await withStore(processImage: { await processor.process($0) }) { settings, pasteboard, store in
            pasteboard.clearContents()
            pasteboard.setData(try Self.smallPNG(), forType: .png)
            store.pollNow()
            await fulfillment(of: [started], timeout: 2)
            try await check(settings, pasteboard, store, processor)
        }
    }

    @MainActor
    private func withStore(
        processImage: (@Sendable (ClipboardImageCapture) async -> ClipboardPasteboardReadResult)? = nil,
        check: @MainActor (AppSettings, NSPasteboard, ClipboardHistoryStore) async throws -> Void
    ) async throws {
        let suite = "ClipboardImageCaptureTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.clipboardHistoryEnabled = true
        let pasteboard = NSPasteboard(name: .init(suite))
        defer { pasteboard.releaseGlobally() }
        let client = SystemClipboardPasteboardClient(pasteboard: pasteboard)
        let store: ClipboardHistoryStore
        if let processImage {
            store = ClipboardHistoryStore(settings: settings, pasteboard: client,
                automaticallySchedulesTimer: false, processImage: processImage)
        } else {
            store = ClipboardHistoryStore(settings: settings, pasteboard: client,
                automaticallySchedulesTimer: false)
        }
        try await check(settings, pasteboard, store)
        store.stopMonitoring()
    }

    private static func smallPNG() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.setColor(.red, atX: 0, y: 0)
        bitmap.setColor(.red, atX: 0, y: 1)
        bitmap.setColor(.red, atX: 1, y: 0)
        bitmap.setColor(.red, atX: 1, y: 1)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
