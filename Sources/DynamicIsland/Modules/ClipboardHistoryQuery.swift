import Foundation

enum ClipboardHistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case text = "Text"
    case images = "Images"
    case links = "Links"
    case files = "Files"
    case colors = "Colors"
    case favorites = "Favorites"

    var id: String { rawValue }
}

struct ClipboardHistoryQuery: Equatable, Sendable {
    var text = ""
    var filter: ClipboardHistoryFilter = .all
    var tagID: UUID?
    /// Bundle identifier of the captured source application; nil shows every source.
    var sourceBundleIdentifier: String?

    /// Distinct source apps present in history, sorted by name (then bundle id).
    static func sourceApplications(in entries: [ClipboardHistoryEntry]) -> [ClipboardSourceApplication] {
        var byID: [String: ClipboardSourceApplication] = [:]
        for case let source? in entries.map(\.sourceApplication) where byID[source.bundleIdentifier] == nil {
            byID[source.bundleIdentifier] = source
        }
        return byID.values.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.bundleIdentifier < $1.bundleIdentifier : order == .orderedAscending
        }
    }

    func apply(entries: [ClipboardHistoryEntry], tags: [ClipboardTag]) -> [ClipboardHistoryEntry] {
        let normalized = Self.normalize(text)
        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        // A source that left history (entries deleted) must not filter everything away.
        let source = sourceBundleIdentifier.flatMap { id in
            entries.contains { $0.sourceApplication?.bundleIdentifier == id } ? id : nil
        }

        return entries.filter { entry in
            guard matchesFilter(entry), matchesTag(entry, tagsByID: tagsByID) else { return false }
            if let source, entry.sourceApplication?.bundleIdentifier != source { return false }
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
        case .colors: entry.payload.kind == .color
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
        case let .color(color):
            fields.append(color.hexString)
        case .imagePNG:
            break
        }
        return normalize(fields.joined(separator: "\n"))
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
