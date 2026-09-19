import AppKit
import ImageIO

// Retained PNGs are capped separately at 8 MiB. Four times that input allowance
// admits uncompressed 4K RGBA TIFFs; the pixel budget admits 4K screenshots with
// headroom without making Clipboard History an unbounded image editor.
enum ClipboardImageResourcePolicy {
    static let maximumEncodedBytes = 32 * 1_024 * 1_024
    static let maximumDimension = 8_192
    static let maximumDecodedBytes = 64 * 1_024 * 1_024
    static let maximumPixels = maximumDecodedBytes / 4

    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value > 0, value.rounded(.towardZero) == value,
              let integer = Int(exactly: value) else { return nil }
        return integer
    }

    static func allows(width: Int, height: Int, depth: Int = 8) -> Bool {
        guard width > 0, height > 0, depth > 0, depth <= 32,
              width <= maximumDimension, height <= maximumDimension else { return false }
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        // Allow higher bit-depth input only when its conservative four-channel cost fits.
        let bytesPerPixel = 4 * ((depth + 7) / 8)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: bytesPerPixel)
        return !pixelOverflow && !byteOverflow && pixels <= maximumPixels && bytes <= maximumDecodedBytes
    }

    static func checkedPNG(_ data: Data, maximumBytes: Int) -> ClipboardPasteboardReadResult {
        data.count <= maximumBytes ? .payload(.imagePNG(data)) : .oversized
    }
}

enum ClipboardImageNormalizer {
    // Metadata queries must not request decoded caching. The decode/encode closure
    // is also the narrow test seam proving rejected metadata never reaches rasterization.
    static func normalize(
        _ data: Data,
        maximumPNGBytes: Int,
        rasterizeAndEncode: (CGImageSource, Data) -> Data? = rasterizeAndEncode
    ) -> ClipboardPasteboardReadResult {
        guard data.count <= ClipboardImageResourcePolicy.maximumEncodedBytes else { return .oversized }
        guard !data.isEmpty else { return .unsupported }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = ClipboardImageResourcePolicy.integer(properties[kCGImagePropertyPixelWidth]),
              let height = ClipboardImageResourcePolicy.integer(properties[kCGImagePropertyPixelHeight]),
              let depth = ClipboardImageResourcePolicy.integer(properties[kCGImagePropertyDepth]) else {
            return .unsupported
        }
        guard ClipboardImageResourcePolicy.allows(width: width, height: height, depth: depth) else {
            return .oversized
        }
        guard CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let png = rasterizeAndEncode(source, data) else { return .unsupported }
        return ClipboardImageResourcePolicy.checkedPNG(png, maximumBytes: maximumPNGBytes)
    }

    private static func rasterizeAndEncode(_ source: CGImageSource, _ data: Data) -> Data? {
        if CGImageSourceGetType(source) == "public.png" as CFString {
            // Preserve AppKit's canonical PNG bytes/fingerprints. Bitmap creation
            // now occurs only after ImageIO metadata and resource validation.
            guard let representation = NSBitmapImageRep(data: data) else { return nil }
            return representation.representation(using: .png, properties: [:])
        }
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false] as CFDictionary
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] else { return nil }
        let image: CGImage?
        if let orientation = properties[kCGImagePropertyOrientation] as? NSNumber, orientation.intValue != 1 {
            // Transform only after full-resolution dimensions pass the budget.
            // This preserves the orientation previously applied by NSImage/TIFF.
            let thumbnailOptions = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldAllowFloat: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(
                    (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0,
                    (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
                )
            ] as CFDictionary
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, options)
        }
        guard let image else { return nil }
        let (bytes, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !overflow, bytes <= ClipboardImageResourcePolicy.maximumDecodedBytes else { return nil }
        let representation = NSBitmapImageRep(cgImage: image)
        // Keep source DPI in the PNG, as the previous AppKit representation path did.
        if let dpiX = properties[kCGImagePropertyDPIWidth] as? NSNumber,
           let dpiY = properties[kCGImagePropertyDPIHeight] as? NSNumber,
           dpiX.doubleValue.isFinite, dpiY.doubleValue.isFinite,
           dpiX.doubleValue > 0, dpiY.doubleValue > 0 {
            let width = Double(image.width) * 72 / dpiX.doubleValue
            let height = Double(image.height) * 72 / dpiY.doubleValue
            if width.isFinite, height.isFinite, width > 0, height > 0 {
                representation.size = NSSize(width: width, height: height)
            }
        }
        return representation.representation(using: .png, properties: [:])
    }
}

enum ClipboardImageRepresentation: Sendable {
    case encoded(Data)
    case oversized
}

struct ClipboardImageCapture: Sendable {
    let representations: [ClipboardImageRepresentation]
    let maximumPNGBytes: Int
    let fallback: ClipboardPasteboardReadResult

    func resolve() -> ClipboardPasteboardReadResult {
        autoreleasepool {
            for representation in representations {
                let result: ClipboardPasteboardReadResult
                switch representation {
                case let .encoded(data):
                    result = ClipboardImageNormalizer.normalize(data, maximumPNGBytes: maximumPNGBytes)
                case .oversized:
                    result = .oversized
                }
                // Invalid data falls through to the next representation, just as before.
                if result != .unsupported { return result }
            }
            return fallback
        }
    }
}

enum ClipboardPasteboardCapture: Sendable {
    case ready(ClipboardPasteboardReadResult)
    case image(ClipboardImageCapture)
}
