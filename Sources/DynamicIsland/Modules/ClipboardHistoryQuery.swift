import Foundation

enum ClipboardHistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case text = "Text"
    case images = "Images"
    case links = "Links"
    case files = "Files"
    case favorites = "Favorites"

    var id: String { rawValue }
}

struct ClipboardHistoryQuery: Equatable, Sendable {
    var text = ""
    var filter: ClipboardHistoryFilter = .all
    var tagID: UUID?

    func apply(entries: [ClipboardHistoryEntry], tags: [ClipboardTag]) -> [ClipboardHistoryEntry] {
        let normalized = Self.normalize(text)
        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })

        return entries.filter { entry in
            guard matchesFilter(entry), matchesTag(entry, tagsByID: tagsByID) else { return false }
            guard !normalized.isEmpty else { return true }
            return Self.searchText(for: entry, tagsByID: tagsByID).contains(normalized)
        }
    }

    private func matchesFilter(_ entry: ClipboardHistoryEntry) -> Bool {
        switch filter {
        case .all: true
        case .text: entry.payload.kind == .text
        case .images: entry.payload.kind == .image
        case .links: entry.payload.kind == .url
        case .files: entry.payload.kind == .files
        case .favorites: entry.isFavorite
        }
    }

    private func matchesTag(_ entry: ClipboardHistoryEntry, tagsByID: [UUID: String]) -> Bool {
        // A deleted tag must not leave the history filtered to nothing.
        guard let tagID, tagsByID[tagID] != nil else { return true }
        return entry.tagIDs.contains(tagID)
    }

    private static func searchText(
        for entry: ClipboardHistoryEntry,
        tagsByID: [UUID: String]
    ) -> String {
        var fields: [String] = []
        if let title = entry.customTitle { fields.append(title) }
        if let source = entry.sourceApplication {
            fields.append(source.name)
            fields.append(source.bundleIdentifier)
        }
        fields.append(contentsOf: entry.tagIDs.compactMap { tagsByID[$0] })

        switch entry.payload {
        case let .text(value):
            fields.append(value.plainText)
        case let .url(url):
            fields.append(url.absoluteString)
            if let host = url.host(percentEncoded: false) { fields.append(host) }
        case let .files(urls):
            fields.append(contentsOf: urls.map(\.lastPathComponent))
        case .imagePNG:
            break
        }
        return normalize(fields.joined(separator: "\n"))
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
