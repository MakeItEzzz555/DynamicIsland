import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DynamicIsland

final class ClipboardImageNormalizerTests: XCTestCase {
    func testSmallPNGAcceptedWithoutChangingPixels() throws {
        try assertAccepted(UTType.png)
    }

    func testSmallJPEGAcceptedAtFullResolution() throws {
        try assertAccepted(UTType.jpeg)
    }

    func testSmallTIFFAcceptedWithoutChangingPixels() throws {
        try assertAccepted(UTType.tiff)
    }

    func testEncodedLimitRejectedBeforeRasterization() {
        var calls = 0
        let result = ClipboardImageNormalizer.normalize(
            Data(repeating: 0, count: ClipboardImageResourcePolicy.maximumEncodedBytes + 1),
            maximumPNGBytes: ClipboardHistoryLimits.standard.maximumImageBytes
        ) { _, _ in calls += 1; return Data() }
        XCTAssertEqual(result, .oversized)
        XCTAssertEqual(calls, 0)
    }

    func testEncodedLimitBoundaryProceedsToInspection() {
        let result = ClipboardImageNormalizer.normalize(
            Data(repeating: 0, count: ClipboardImageResourcePolicy.maximumEncodedBytes), maximumPNGBytes: 1
        ) { _, _ in XCTFail("Invalid bytes must not rasterize"); return Data() }
        XCTAssertEqual(result, .unsupported)
    }

    func testExcessiveWidthRejected() {
        XCTAssertFalse(ClipboardImageResourcePolicy.allows(width: 8_193, height: 1))
    }

    func testExcessiveHeightRejected() {
        XCTAssertFalse(ClipboardImageResourcePolicy.allows(width: 1, height: 8_193))
    }

    func testTotalPixelBudgetRejectsIndividuallyAllowedDimensions() {
        XCTAssertFalse(ClipboardImageResourcePolicy.allows(width: 8_192, height: 8_192))
    }

    func testPixelBudgetBoundaryAndOrdinary4KScreenshotAllowed() {
        XCTAssertTrue(ClipboardImageResourcePolicy.allows(width: 8_192, height: 2_048))
        XCTAssertFalse(ClipboardImageResourcePolicy.allows(width: 8_192, height: 2_049))
        XCTAssertTrue(ClipboardImageResourcePolicy.allows(width: 3_840, height: 2_160))
    }

    func testHighBitDepthHasDecodedMemoryBudget() {
        XCTAssertTrue(ClipboardImageResourcePolicy.allows(width: 4_096, height: 2_048, depth: 16))
        XCTAssertFalse(ClipboardImageResourcePolicy.allows(width: 4_096, height: 2_049, depth: 16))
        XCTAssertFalse(ClipboardImageResourcePolicy.allows(width: 1, height: 1, depth: 33))
    }

    func testOverflowAndNonpositiveDimensionsFailWithoutTrapping() {
        for pair in [(Int.max, Int.max), (Int.max, 1), (1, Int.max), (0, 1), (1, 0), (-1, 1)] {
            XCTAssertFalse(ClipboardImageResourcePolicy.allows(width: pair.0, height: pair.1))
        }
        XCTAssertFalse(ClipboardImageResourcePolicy.allows(width: 1, height: 1, depth: Int.max))
    }

    func testMalformedMetadataNumbersRejected() {
        let values: [Any?] = [nil, "123", NSNumber(value: true), NSNumber(value: 0), NSNumber(value: -1),
                              NSNumber(value: Double.nan), NSNumber(value: Double.infinity),
                              NSNumber(value: 1.5), NSNumber(value: Double.greatestFiniteMagnitude),
                              NSNumber(value: Double(Int.max))]
        for value in values { XCTAssertNil(ClipboardImageResourcePolicy.integer(value)) }
        XCTAssertEqual(ClipboardImageResourcePolicy.integer(NSNumber(value: 8_192)), 8_192)
    }

    func testCompressionBombMetadataRejectedBeforeRasterization() throws {
        let png = zeroFilledPNG(width: 4_097, height: 4_096)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(ClipboardImageResourcePolicy.integer(properties[kCGImagePropertyPixelWidth]), 4_097)
        XCTAssertLessThan(png.count, 512 * 1_024)
        var calls = 0
        XCTAssertEqual(ClipboardImageNormalizer.normalize(png, maximumPNGBytes: 8 * 1_024 * 1_024) { _, _ in
            calls += 1; return Data()
        }, .oversized)
        XCTAssertEqual(calls, 0)
    }

    func testInvalidAndMissingImageMetadataFailBeforeRasterization() {
        for data in [Data(), Data("not an image".utf8), Data([137, 80, 78, 71, 13, 10, 26, 10])] {
            XCTAssertEqual(ClipboardImageNormalizer.normalize(data, maximumPNGBytes: 100) { _, _ in
                XCTFail("Unreadable metadata must not rasterize"); return Data()
            }, .unsupported)
        }
    }

    func testTruncatedImageCannotProduceEntry() throws {
        let png = try imageData(.png)
        XCTAssertEqual(ClipboardImageNormalizer.normalize(Data(png.prefix(40)), maximumPNGBytes: 100) { _, _ in
            XCTFail("Incomplete image must not rasterize"); return Data()
        }, .unsupported)
    }

    func testPNGOutputLimitBelowAtAndAboveBoundary() {
        let limit = ClipboardHistoryLimits.standard.maximumImageBytes
        for count in [limit - 1, limit, limit + 1] {
            let data = Data(repeating: 1, count: count)
            let result = ClipboardImageResourcePolicy.checkedPNG(data, maximumBytes: limit)
            XCTAssertEqual(result, count <= limit ? .payload(.imagePNG(data)) : .oversized)
        }
    }

    func testSingleEncodeResultIsCheckedAndReturnedUnchanged() throws {
        let input = try imageData(.png)
        let encoded = try imageData(.png)
        var calls = 0
        let result = ClipboardImageNormalizer.normalize(input, maximumPNGBytes: encoded.count) { _, _ in
            calls += 1; return encoded
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(result, .payload(.imagePNG(encoded)))
    }

    func testRealNormalizedOutputPayloadBoundary() throws {
        let input = try imageData(.png)
        guard case let .payload(.imagePNG(png)) = ClipboardImageNormalizer.normalize(input, maximumPNGBytes: 1_024) else {
            return XCTFail("Expected PNG")
        }
        XCTAssertEqual(ClipboardImageNormalizer.normalize(input, maximumPNGBytes: png.count), .payload(.imagePNG(png)))
        XCTAssertEqual(ClipboardImageNormalizer.normalize(input, maximumPNGBytes: png.count - 1), .oversized)
    }

    func testNormalizationPreservesPreviousCopyBackEncoding() throws {
        let input = try imageData(.png)
        let first = ClipboardImageNormalizer.normalize(input, maximumPNGBytes: 1_024)
        guard case let .payload(.imagePNG(png)) = first else { return XCTFail("Expected PNG") }
        XCTAssertEqual(ClipboardImageNormalizer.normalize(input, maximumPNGBytes: 1_024), first)
        let previousCopyBack = try XCTUnwrap(NSBitmapImageRep(data: png)?.representation(using: .png, properties: [:]))
        XCTAssertEqual(ClipboardImageNormalizer.normalize(png, maximumPNGBytes: 1_024), .payload(.imagePNG(previousCopyBack)))
    }

    func testPNGNormalizationMatchesPreviousCanonicalEncoding() throws {
        let input = try imageData(.png)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: input))
        let previousPNG = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        XCTAssertEqual(ClipboardImageNormalizer.normalize(input, maximumPNGBytes: 1_024), .payload(.imagePNG(previousPNG)))
    }

    func testOrientedJPEGMatchesPreviousRasterizedPixels() throws {
        let input = try imageData(.jpeg, properties: [kCGImagePropertyOrientation: 6] as CFDictionary)
        let previousImage = try XCTUnwrap(NSImage(data: input))
        let previousTIFF = try XCTUnwrap(previousImage.tiffRepresentation)
        let previous = try XCTUnwrap(NSBitmapImageRep(data: previousTIFF))
        guard case let .payload(.imagePNG(png)) = ClipboardImageNormalizer.normalize(input, maximumPNGBytes: 1_024) else {
            return XCTFail("Expected JPEG normalization")
        }
        let normalized = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(normalized.pixelsWide, previous.pixelsWide)
        XCTAssertEqual(normalized.pixelsHigh, previous.pixelsHigh)
    }

    @MainActor
    func testAllPasteboardRepresentationsUseSameBoundsAndPrecedence() throws {
        for type in [NSPasteboard.PasteboardType.png, .tiff, .init("public.jpeg")] {
            let pasteboard = NSPasteboard(name: .init("ClipboardImageBounds-\(UUID())"))
            defer { pasteboard.releaseGlobally() }
            let item = NSPasteboardItem()
            item.setData(Data(repeating: 0, count: ClipboardImageResourcePolicy.maximumEncodedBytes + 1), forType: type)
            item.setString("fallback", forType: .string)
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.writeObjects([item]))
            XCTAssertEqual(SystemClipboardPasteboardClient(pasteboard: pasteboard)
                .readSupportedPayload(limits: .standard, capturesImages: true), .oversized)
        }
        let pasteboard = NSPasteboard(name: .init("ClipboardImagePrecedence-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setData(Data("invalid PNG".utf8), forType: .png)
        item.setData(try imageData(.tiff), forType: .tiff)
        item.setString("fallback", forType: .string)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let result = SystemClipboardPasteboardClient(pasteboard: pasteboard).readSupportedPayload(limits: .standard, capturesImages: true)
        guard case .payload(.imagePNG) = result else { return XCTFail("Valid TIFF must precede text") }
    }

    private func assertAccepted(_ type: UTType) throws {
        let data = try imageData(type)
        let result = ClipboardImageNormalizer.normalize(data, maximumPNGBytes: 1_024)
        guard case let .payload(.imagePNG(png)) = result else { return XCTFail("Expected accepted \(type)") }
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(image.pixelsWide, 4)
        XCTAssertEqual(image.pixelsHigh, 3)
        let original = try XCTUnwrap(NSBitmapImageRep(data: data))
        var expected = [Int](repeating: 0, count: 4)
        var actual = [Int](repeating: 0, count: 4)
        original.getPixel(&expected, atX: 0, y: 0)
        image.getPixel(&actual, atX: 0, y: 0)
        XCTAssertEqual(Array(actual.prefix(3)), Array(expected.prefix(3)))
    }

    private func imageData(_ type: UTType, properties: CFDictionary? = nil) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 16,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1, 0, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    // A valid, highly compressed PNG without allocating its 64+ MiB bitmap.
    // Fixed-Huffman DEFLATE repeats one zero byte using length=258/distance=1.
    private func zeroFilledPNG(width: Int, height: Int) -> Data {
        let byteCount = (width * 4 + 1) * height
        var compressed = Data([0x78, 0x01])
        var buffer: UInt32 = 0
        var bitCount = 0
        func bits(_ value: UInt32, _ count: Int) {
            buffer |= value << bitCount
            bitCount += count
            while bitCount >= 8 {
                compressed.append(UInt8(buffer & 0xff))
                buffer >>= 8
                bitCount -= 8
            }
        }
        bits(3, 3) // final block, fixed Huffman
        bits(0x0c, 8) // literal zero (reversed fixed code 0x30)
        var remaining = byteCount - 1
        while remaining >= 258 {
            bits(0xa3, 8) // length 258 (reversed fixed code 285)
            bits(0, 5) // distance one
            remaining -= 258
        }
        for _ in 0..<remaining { bits(0x0c, 8) }
        bits(0, 7) // end of block
        if bitCount > 0 { compressed.append(UInt8(buffer & 0xff)) }
        appendBigEndian(UInt32(byteCount % 65_521) << 16 | 1, to: &compressed)
        var png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        var header = Data()
        appendBigEndian(UInt32(width), to: &header)
        appendBigEndian(UInt32(height), to: &header)
        header.append(contentsOf: [8, 6, 0, 0, 0])
        for (name, payload) in [("IHDR", header), ("IDAT", compressed), ("IEND", Data())] {
            appendBigEndian(UInt32(payload.count), to: &png)
            let chunk = Data(name.utf8) + payload
            png.append(chunk)
            appendBigEndian(crc32(chunk), to: &png)
        }
        return png
    }

    private func appendBigEndian(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb8_8320) }
        }
        return crc ^ 0xffff_ffff
    }
}
