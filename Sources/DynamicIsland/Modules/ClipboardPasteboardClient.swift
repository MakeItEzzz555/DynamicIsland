import AppKit
import CryptoKit
import Foundation

struct ClipboardHistoryLimits: Equatable, Sendable {
    static let standard = Self(
        maximumPlainTextBytes: 2 * 1_024 * 1_024,
        maximumRichTextBytesPerRepresentation: 1 * 1_024 * 1_024,
        maximumImageBytes: 8 * 1_024 * 1_024,
        maximumFilesPerEntry: 100,
        maximumURLStringBytes: 16 * 1_024,
        maximumTotalHistoryPayloadBytes: 64 * 1_024 * 1_024
    )

    let maximumPlainTextBytes: Int
    let maximumRichTextBytesPerRepresentation: Int
    let maximumImageBytes: Int
    let maximumFilesPerEntry: Int
    let maximumURLStringBytes: Int
    let maximumTotalHistoryPayloadBytes: Int
}

struct ClipboardTextPayload: Codable, Equatable, Sendable {
    let plainText: String
    let rtfData: Data?
    let htmlData: Data?
}

enum ClipboardHistoryPayload: Equatable, Sendable {
    case text(ClipboardTextPayload)
    case url(URL)
    case files([URL])
    case imagePNG(Data)

    var kind: ClipboardHistoryEntryKind {
        switch self {
        case .text: .text
        case .url: .url
        case .files: .files
        case .imagePNG: .image
        }
    }

    var byteCount: Int {
        switch self {
        case let .text(payload):
            payload.plainText.utf8.count
                + (payload.rtfData?.count ?? 0)
                + (payload.htmlData?.count ?? 0)
        case let .url(url):
            url.absoluteString.utf8.count
        case let .files(urls):
            urls.reduce(into: 0) { $0 += $1.standardizedFileURL.absoluteString.utf8.count }
        case let .imagePNG(data):
            data.count
        }
    }
}

extension ClipboardHistoryPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case url
        case files
        case imagePNG
    }

    private enum Discriminator: String, Codable {
        case text
        case url
        case files
        case image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Discriminator.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(ClipboardTextPayload.self, forKey: .text))
        case .url:
            self = .url(try container.decode(URL.self, forKey: .url))
        case .files:
            self = .files(try container.decode([URL].self, forKey: .files))
        case .image:
            self = .imagePNG(try container.decode(Data.self, forKey: .imagePNG))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(payload):
            try container.encode(Discriminator.text, forKey: .type)
            try container.encode(payload, forKey: .text)
        case let .url(url):
            try container.encode(Discriminator.url, forKey: .type)
            try container.encode(url, forKey: .url)
        case let .files(urls):
            try container.encode(Discriminator.files, forKey: .type)
            try container.encode(urls, forKey: .files)
        case let .imagePNG(data):
            try container.encode(Discriminator.image, forKey: .type)
            try container.encode(data, forKey: .imagePNG)
        }
    }
}

enum ClipboardHistoryEntryKind: String, Codable, Equatable, Sendable, CaseIterable {
    case text
    case url
    case files
    case image
}

/// Value snapshot taken at copy time. We intentionally persist only the app's
/// human name and bundle identifier — never window titles or process objects.
struct ClipboardSourceApplication: Codable, Equatable, Sendable {
    let name: String
    let bundleIdentifier: String
}

enum ClipboardTagColor: String, Codable, CaseIterable, Equatable, Sendable {
    case red, orange, yellow, green, blue, purple, pink, gray
}

struct ClipboardTag: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var color: ClipboardTagColor
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, color: ClipboardTagColor, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
    }
}

struct ClipboardHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let lastUsedAt: Date?
    let payload: ClipboardHistoryPayload
    let fingerprint: String
    let sourceApplication: ClipboardSourceApplication?
    let isFavorite: Bool
    let customTitle: String?
    let tagIDs: [UUID]

    init(
        id: UUID,
        createdAt: Date,
        lastUsedAt: Date? = nil,
        payload: ClipboardHistoryPayload,
        fingerprint: String,
        sourceApplication: ClipboardSourceApplication? = nil,
        isFavorite: Bool = false,
        customTitle: String? = nil,
        tagIDs: [UUID] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.payload = payload
        self.fingerprint = fingerprint
        self.sourceApplication = sourceApplication
        self.isFavorite = isFavorite
        self.customTitle = customTitle
        self.tagIDs = tagIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, lastUsedAt, payload, fingerprint
        case sourceApplication, isFavorite, customTitle, tagIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        payload = try c.decode(ClipboardHistoryPayload.self, forKey: .payload)
        fingerprint = try c.decode(String.self, forKey: .fingerprint)
        sourceApplication = try c.decodeIfPresent(ClipboardSourceApplication.self, forKey: .sourceApplication)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle)
        tagIDs = try c.decodeIfPresent([UUID].self, forKey: .tagIDs) ?? []
    }
}

struct ClipboardHistoryArchive: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let entries: [ClipboardHistoryEntry]
    let tags: [ClipboardTag]

    init(schemaVersion: Int, entries: [ClipboardHistoryEntry], tags: [ClipboardTag] = []) {
        self.schemaVersion = schemaVersion
        self.entries = entries
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, entries, tags }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        entries = try c.decode([ClipboardHistoryEntry].self, forKey: .entries)
        tags = try c.decodeIfPresent([ClipboardTag].self, forKey: .tags) ?? []
    }
}

enum ClipboardPasteboardReadResult: Equatable, Sendable {
    case payload(ClipboardHistoryPayload)
    case empty
    case unsupported
    case sensitive
    case oversized
}

struct ClipboardPasteboardWriteResult: Equatable, Sendable {
    let succeeded: Bool
    let resultingChangeCount: Int
}

@MainActor
protocol ClipboardPasteboardClient: AnyObject {
    var changeCount: Int { get }

    func readSupportedPayload(
        limits: ClipboardHistoryLimits,
        capturesImages: Bool
    ) -> ClipboardPasteboardReadResult

    func prepareCapture(limits: ClipboardHistoryLimits, capturesImages: Bool) -> ClipboardPasteboardCapture

    @discardableResult
    func write(_ payload: ClipboardHistoryPayload) -> ClipboardPasteboardWriteResult
}

extension ClipboardPasteboardClient {
    func prepareCapture(limits: ClipboardHistoryLimits, capturesImages: Bool) -> ClipboardPasteboardCapture {
        .ready(readSupportedPayload(limits: limits, capturesImages: capturesImages))
    }
}

enum ClipboardSensitivePasteboardTypes {
    static let all: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "com.typeit4me.clipping",
        "de.petermaurer.TransientPasteboardType"
    ]
}

@MainActor
final class SystemClipboardPasteboardClient: ClipboardPasteboardClient {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func readSupportedPayload(
        limits: ClipboardHistoryLimits,
        capturesImages: Bool
    ) -> ClipboardPasteboardReadResult {
        // Synchronous compatibility entry point; monitoring uses prepareCapture so
        // immutable image bytes can be normalized off the main actor.
        switch prepareCapture(limits: limits, capturesImages: capturesImages) {
        case let .ready(result): return result
        case let .image(capture): return capture.resolve()
        }
    }

    func prepareCapture(limits: ClipboardHistoryLimits, capturesImages: Bool) -> ClipboardPasteboardCapture {
        let items = pasteboard.pasteboardItems ?? []
        guard !items.isEmpty else { return .ready(.empty) }
        guard !containsSensitiveMarker(items) else {
            #if DEBUG
            print("[ClipboardHistory] skipped sensitive item")
            #endif
            return .ready(.sensitive)
        }
        if let fileResult = readFiles(limits: limits) { return .ready(fileResult) }
        let representations = capturesImages ? readImageRepresentations(items: items) : []
        let fallback = readURL(items: items, limits: limits)
            ?? readText(items: items, limits: limits) ?? .unsupported
        guard !representations.isEmpty else { return .ready(fallback) }
        return .image(ClipboardImageCapture(
            representations: representations, maximumPNGBytes: limits.maximumImageBytes, fallback: fallback
        ))
    }

    func write(_ payload: ClipboardHistoryPayload) -> ClipboardPasteboardWriteResult {
        pasteboard.clearContents()
        let succeeded: Bool

        switch payload {
        case let .text(text):
            let item = NSPasteboardItem()
            item.setString(text.plainText, forType: .string)
            if let rtfData = text.rtfData {
                item.setData(rtfData, forType: .rtf)
            }
            if let htmlData = text.htmlData {
                item.setData(htmlData, forType: .html)
            }
            succeeded = pasteboard.writeObjects([item])
        case let .url(url):
            succeeded = pasteboard.writeObjects([url as NSURL])
        case let .files(urls):
            succeeded = pasteboard.writeObjects(urls.map { $0 as NSURL })
        case let .imagePNG(data):
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            succeeded = pasteboard.writeObjects([item])
        }

        return ClipboardPasteboardWriteResult(
            succeeded: succeeded,
            resultingChangeCount: pasteboard.changeCount
        )
    }

    private func containsSensitiveMarker(_ items: [NSPasteboardItem]) -> Bool {
        items.contains { item in
            item.types.contains { ClipboardSensitivePasteboardTypes.all.contains($0.rawValue) }
        }
    }

    private func readFiles(limits: ClipboardHistoryLimits) -> ClipboardPasteboardReadResult? {
        guard pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return nil
        }
        guard let readURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return nil
        }

        var seen = Set<String>()
        var urls: [URL] = []
        for url in readURLs where url.isFileURL {
            let standardized = url.standardizedFileURL
            if seen.insert(standardized.absoluteString).inserted {
                urls.append(standardized)
            }
        }
        guard !urls.isEmpty else { return nil }
        guard urls.count <= limits.maximumFilesPerEntry else { return .oversized }
        return .payload(.files(urls))
    }

    private func readImageRepresentations(items: [NSPasteboardItem]) -> [ClipboardImageRepresentation] {
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg")]
        var representations: [ClipboardImageRepresentation] = []
        for type in types {
            guard let data = items.lazy.compactMap({ $0.data(forType: type) }).first else { continue }
            if data.count > ClipboardImageResourcePolicy.maximumEncodedBytes {
                representations.append(.oversized)
                break
            }
            representations.append(.encoded(data))
        }
        return representations
    }

    private func readURL(
        items: [NSPasteboardItem],
        limits: ClipboardHistoryLimits
    ) -> ClipboardPasteboardReadResult? {
        for item in items {
            let value = item.string(forType: .URL) ?? item.string(forType: .string)
            guard let value else { continue }
            guard let url = URL(string: value),
                  let scheme = url.scheme,
                  !scheme.isEmpty,
                  !url.isFileURL,
                  !url.absoluteString.isEmpty else {
                continue
            }
            guard value.utf8.count <= limits.maximumURLStringBytes else {
                return .oversized
            }
            return .payload(.url(url))
        }
        return nil
    }

    private func readText(
        items: [NSPasteboardItem],
        limits: ClipboardHistoryLimits
    ) -> ClipboardPasteboardReadResult? {
        for item in items {
            guard let plainText = item.string(forType: .string) else { continue }
            guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .empty
            }
            guard plainText.utf8.count <= limits.maximumPlainTextBytes else {
                return .oversized
            }
            let rtf = bounded(item.data(forType: .rtf), maximum: limits.maximumRichTextBytesPerRepresentation)
            let html = bounded(item.data(forType: .html), maximum: limits.maximumRichTextBytesPerRepresentation)
            return .payload(
                .text(
                    ClipboardTextPayload(
                        plainText: plainText,
                        rtfData: rtf,
                        htmlData: html
                    )
                )
            )
        }
        return nil
    }

    private func bounded(_ data: Data?, maximum: Int) -> Data? {
        guard let data, data.count <= maximum else { return nil }
        return data
    }
}

enum ClipboardHistoryFingerprint {
    static func make(for payload: ClipboardHistoryPayload) -> String {
        var input = Data()
        switch payload {
        case let .text(text):
            append("type:text", to: &input)
            append(Data(text.plainText.utf8), to: &input)
            appendOptionalDigest(text.rtfData, to: &input)
            appendOptionalDigest(text.htmlData, to: &input)
        case let .url(url):
            append("type:url", to: &input)
            append(Data(url.absoluteString.utf8), to: &input)
        case let .files(urls):
            append("type:files", to: &input)
            for url in urls {
                append(Data(url.standardizedFileURL.absoluteString.utf8), to: &input)
            }
        case let .imagePNG(data):
            append("type:image", to: &input)
            append(data, to: &input)
        }
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private static func append(_ string: String, to data: inout Data) {
        append(Data(string.utf8), to: &data)
    }

    private static func append(_ value: Data, to data: inout Data) {
        var length = UInt64(value.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(value)
    }

    private static func appendOptionalDigest(_ value: Data?, to data: inout Data) {
        guard let value else {
            append("nil", to: &data)
            return
        }
        append(Data(SHA256.hash(data: value)), to: &data)
    }
}
