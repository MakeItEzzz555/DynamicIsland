import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Sizes for the quick-action circles attached below the expanded island.
enum FileTrayQuickActionMetrics {
    static let diameter: CGFloat = 36
    static let spacing: CGFloat = 10
    /// Gap between the shell's bottom edge and the circles.
    static let gap: CGFloat = 8
    /// Transparent panel space reserved below the shell while Tray is shown.
    static let accessoryHeight: CGFloat = gap + diameter + 12
}

enum FileTrayQuickAction: String, CaseIterable, Identifiable {
    case removeBackground
    case convert
    case share

    var id: String { rawValue }

    var title: String {
        switch self {
        case .removeBackground: "Remove Background"
        case .convert: "Convert"
        case .share: "Share"
        }
    }

    var symbolName: String {
        switch self {
        case .removeBackground: "person.crop.rectangle"
        case .convert: "arrow.triangle.2.circlepath"
        case .share: "square.and.arrow.up"
        }
    }
}

/// Which files a quick action operates on and whether it is available.
/// Never guesses: explicit selection, or the single file when exactly one
/// file is on the Tray and nothing is selected.
struct FileTrayActionTargets: Equatable {
    let urls: [URL]

    static func resolve(files: [URL], selection: Set<URL>) -> FileTrayActionTargets {
        let selected = files.filter { selection.contains($0) }
        if !selected.isEmpty { return FileTrayActionTargets(urls: selected) }
        if files.count == 1 { return FileTrayActionTargets(urls: files) }
        return FileTrayActionTargets(urls: [])
    }

    enum Availability: Equatable {
        case available
        case unavailable(String)

        var isAvailable: Bool { self == .available }
    }

    func availability(of action: FileTrayQuickAction, converter: FileConversionController.Type = FileConversionController.self) -> Availability {
        switch action {
        case .removeBackground:
            guard urls.count == 1 else {
                return .unavailable(urls.isEmpty ? "Select an image" : "Select one image")
            }
            return Self.isImage(urls[0]) ? .available : .unavailable("Background removal needs an image")
        case .convert:
            guard urls.count == 1 else {
                return .unavailable(urls.isEmpty ? "Select a file to convert" : "Select one file to convert")
            }
            return converter.targetFormats(for: urls[0]).isEmpty
                ? .unavailable("No supported conversion for this file")
                : .available
        case .share:
            return urls.isEmpty ? .unavailable("Select files to share") : .available
        }
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}

// MARK: - Conversion

enum FileConversionFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case heic
    case tiff

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        }
    }

    var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .tiff: "tiff"
        }
    }
}

enum FileConversionError: LocalizedError, Equatable {
    case unsupported
    case decodeFailed
    case encodeFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: "This conversion is not supported."
        case .decodeFailed: "The file could not be read as an image."
        case .encodeFailed: "The converted image could not be encoded."
        case .writeFailed(let message): "The converted file could not be saved: \(message)"
        }
    }
}

/// Local image format conversion with ImageIO. Only formats this Mac can
/// actually encode are offered. The original is never modified.
enum FileConversionController {
    /// Encoders available on this system (checked at runtime).
    static var availableFormats: [FileConversionFormat] {
        let encodable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return FileConversionFormat.allCases.filter { encodable.contains($0.type.identifier) }
    }

    /// Formats the file can be converted to (images only; excludes its
    /// current format).
    static func targetFormats(for url: URL) -> [FileConversionFormat] {
        guard FileTrayActionTargets.isImage(url) else { return [] }
        let current = UTType(filenameExtension: url.pathExtension)
        return availableFormats.filter { format in
            guard let current else { return true }
            return !current.conforms(to: format.type) && !(format == .jpeg && current.conforms(to: .jpeg))
        }
    }

    static func outputURL(
        for source: URL,
        format: FileConversionFormat,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let directory = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent.isEmpty ? "Converted" : source.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let name = index == 1 ? "\(base).\(format.fileExtension)" : "\(base) \(index).\(format.fileExtension)"
            let candidate = directory.appendingPathComponent(name)
            if candidate.standardizedFileURL != source.standardizedFileURL, !fileExists(candidate) {
                return candidate
            }
            index += 1
        }
    }

    /// Converts off the main thread. Keeps orientation and metadata by
    /// re-encoding from the image source; validates the written file.
    static func convert(_ source: URL, to format: FileConversionFormat) async throws -> URL {
        guard targetFormats(for: source).contains(format) else { throw FileConversionError.unsupported }
        return try await Task.detached(priority: .userInitiated) {
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  CGImageSourceGetCount(imageSource) > 0,
                  CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil else {
                throw FileConversionError.decodeFailed
            }
            let destinationURL = outputURL(for: source, format: format)
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else {
                throw FileConversionError.encodeFailed
            }
            var properties: [CFString: Any] = [:]
            if format == .jpeg || format == .heic {
                properties[kCGImageDestinationLossyCompressionQuality] = 0.9
            }
            CGImageDestinationAddImageFromSource(destination, imageSource, 0, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw FileConversionError.encodeFailed }
            do {
                try (data as Data).write(to: destinationURL, options: .withoutOverwriting)
            } catch {
                throw FileConversionError.writeFailed(error.localizedDescription)
            }
            guard CGImageSourceCreateWithURL(destinationURL as CFURL, nil)
                .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) != nil else {
                try? FileManager.default.removeItem(at: destinationURL)
                throw FileConversionError.encodeFailed
            }
            return destinationURL
        }.value
    }
}
