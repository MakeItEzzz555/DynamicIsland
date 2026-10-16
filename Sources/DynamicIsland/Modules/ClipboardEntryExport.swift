import AppKit
import Foundation

/// Share items and temporary-file export for clipboard entries. Never logs content.
enum ClipboardEntryExport {
    /// Items for `NSSharingServicePicker`; empty when the entry has nothing shareable.
    static func shareItems(for payload: ClipboardHistoryPayload) -> [Any] {
        switch payload {
        case let .text(text): [text.plainText]
        case let .url(url): [url]
        case let .files(urls): urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        case let .imagePNG(data): NSImage(data: data).map { [$0] } ?? []
        case let .color(color): [color.hexString]
        }
    }

    /// Writes text/image payloads into the File Tray's temporary root so the
    /// ownership ledger can delete the file once no surface owns it.
    static func writeTemporaryFile(
        for payload: ClipboardHistoryPayload,
        storage: FileShelfTemporaryStorage = .shared
    ) throws -> URL? {
        let name: String
        let data: Data
        switch payload {
        case let .text(text):
            name = "Clipboard Text.txt"
            data = Data(text.plainText.utf8)
        case let .imagePNG(png):
            name = "Clipboard Image.png"
            data = png
        default:
            return nil
        }
        try FileManager.default.createDirectory(at: storage.rootURL, withIntermediateDirectories: true)
        let url = storage.rootURL.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: url, options: .atomic)
        return url
    }
}
