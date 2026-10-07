import AppKit
import SwiftUI

@MainActor
struct ClipboardHistoryExternalActions {
    var addFilesToShelf: (([URL]) -> Void)?
    var addFilesToBasket: (([URL]) -> Void)?

    static let inert = Self()
}

struct ClipboardHistoryRowPresentation: Equatable {
    let iconName: String
    let title: String
    let detail: String
    let timestamp: String
    let isImage: Bool

    static func resolve(
        entry: ClipboardHistoryEntry,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        let timestamp: String
        if calendar.isDate(entry.createdAt, inSameDayAs: now) {
            timestamp = entry.createdAt.formatted(date: .omitted, time: .shortened)
        } else {
            timestamp = entry.createdAt.formatted(date: .abbreviated, time: .shortened)
        }

        let generated: (String, String, String, Bool)
        switch entry.payload {
        case let .text(payload):
            let normalized = payload.plainText
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            generated = (
                "text.alignleft",
                normalized.isEmpty ? "Text" : normalized,
                "\(payload.plainText.count) characters",
                false
            )
        case let .url(url):
            generated = (
                "link",
                url.host(percentEncoded: false) ?? "URL",
                url.absoluteString,
                false
            )
        case let .files(urls):
            let names = urls.prefix(2).map(\.lastPathComponent).filter { !$0.isEmpty }
            generated = (
                urls.count == 1 ? "doc" : "doc.on.doc",
                names.isEmpty ? "Files" : names.joined(separator: ", "),
                urls.count == 1 ? "1 file" : "\(urls.count) files",
                false
            )
        case let .imagePNG(data):
            generated = (
                "photo",
                "Image",
                ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file),
                true
            )
        }

        return Self(
            iconName: generated.0,
            title: entry.customTitle?.isEmpty == false ? entry.customTitle! : generated.1,
            detail: generated.2,
            timestamp: timestamp,
            isImage: generated.3
        )
    }
}

@MainActor
private final class ClipboardVisualCache: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var appIcons: [String: NSImage] = [:]

    private let imageCapacity = 32
    private var imageOrder: [String] = []

    func image(for fingerprint: String) -> NSImage? { images[fingerprint] }
    func appIcon(for bundleID: String) -> NSImage? { appIcons[bundleID] }

    func loadImageIfNeeded(fingerprint: String, data: Data) {
        guard images[fingerprint] == nil, let image = NSImage(data: data) else { return }
        images[fingerprint] = image
        imageOrder.removeAll { $0 == fingerprint }
        imageOrder.append(fingerprint)
        while imageOrder.count > imageCapacity {
            images.removeValue(forKey: imageOrder.removeFirst())
        }
    }

    func loadAppIconIfNeeded(bundleID: String) {
        guard appIcons[bundleID] == nil,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        appIcons[bundleID] = NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardHistoryStore
    let onClose: () -> Void
    var externalActions: ClipboardHistoryExternalActions = .inert

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandDisplayMetrics) private var metrics
    @StateObject private var cache = ClipboardVisualCache()
    @State private var query = ClipboardHistoryQuery()
    @State private var selectedEntryID: UUID?
    @State private var copiedEntryID: UUID?
    @State private var copiedFeedbackGeneration = 0
    @State private var confirmsClearAll = false
    @State private var renameEntryID: UUID?
    @State private var renameDraft = ""
    @State private var showTagEditor = false
    @State private var newTagName = ""
    @State private var newTagColor: ClipboardTagColor = .blue
    @State private var editingTagID: UUID?
    @State private var editingTagName = ""
    @State private var editingTagColor: ClipboardTagColor = .blue
    @FocusState private var searchFocused: Bool
    @FocusState private var renameFocused: Bool

    private var visibleEntries: [ClipboardHistoryEntry] {
        query.apply(entries: store.entries, tags: store.tagsEnabled ? store.tags : [])
    }

    var body: some View {
        keyboardSurface
            .onAppear {
                if store.autoFocusSearchEnabled {
                    DispatchQueue.main.async { searchFocused = true }
                }
                reconcileSelection()
            }
            .onChange(of: visibleEntries.map(\.id)) { _, _ in reconcileSelection() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Clipboard History")
    }

    private var keyboardSurface: some View {
        clipboardSurface
            .focusable()
            .onKeyPress(.downArrow) { moveSelection(1); return .handled }
            .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            .onKeyPress(.return) {
                guard let selectedEntryID else { return .ignored }
                copy(id: selectedEntryID)
                return .handled
            }
            .onKeyPress(KeyEquivalent("f"), phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                searchFocused = true
                return .handled
            }
            .onKeyPress(.escape) {
                if renameEntryID != nil {
                    renameEntryID = nil
                    renameDraft = ""
                    renameFocused = false
                    return .handled
                }
                if !query.text.isEmpty || searchFocused {
                    query.text = ""
                    searchFocused = false
                    return .handled
                }
                onClose()
                return .handled
            }
    }

    private var clipboardSurface: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.08))
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .background(Color.black.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 17 * metrics.cornerRadiusScale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17 * metrics.cornerRadiusScale, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: metrics.dividerThickness)
        }
    }

    private var header: some View {
        VStack(spacing: metrics.spacing(8, minimum: 6, maximum: 10)) {
            HStack(spacing: 8) {
                Image(systemName: "clipboard")
                    .foregroundStyle(.white.opacity(0.80))
                Text("Clipboard")
                    .font(.system(size: metrics.font(13, minimum: 11, maximum: 15), weight: .semibold))

                Text("\(store.entries.count)")
                    .font(.system(size: metrics.font(9.5, minimum: 8.5, maximum: 11), weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())

                Spacer(minLength: 4)

                if !store.entries.isEmpty {
                    Button("Clear All") { confirmsClearAll.toggle() }
                        .font(.system(size: metrics.font(10.5, minimum: 9.5, maximum: 12), weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(confirmsClearAll ? Color.red.opacity(0.9) : .white.opacity(0.62))
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityLabel("Close Clipboard")
            }

            searchControls

            if showTagEditor, store.tagsEnabled {
                tagEditor
            }

            if confirmsClearAll {
                HStack(spacing: 8) {
                    Text("Clear all clipboard entries?")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.66))
                    Spacer()
                    Button("Cancel") { confirmsClearAll = false }.buttonStyle(.plain)
                    Button("Clear") {
                        store.clearHistory()
                        selectedEntryID = nil
                        confirmsClearAll = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.92))
                }
            }
        }
        .padding(metrics.spacing(12, minimum: 10, maximum: 14))
    }

    private var searchControls: some View {
        HStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                TextField("Search clipboard", text: $query.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: metrics.font(10.5, minimum: 9.5, maximum: 12)))
                    .focused($searchFocused)
                if !query.text.isEmpty {
                    Button {
                        query.text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.38))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28 * metrics.compactControlScale)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Menu {
                ForEach(ClipboardHistoryFilter.allCases) { filter in
                    Button {
                        query.filter = filter
                    } label: {
                        if query.filter == filter {
                            Label(filter.rawValue, systemImage: "checkmark")
                        } else {
                            Text(filter.rawValue)
                        }
                    }
                }
            } label: {
                Label(query.filter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: metrics.font(9.5, minimum: 8.5, maximum: 11), weight: .semibold))
                    .frame(height: 28 * metrics.compactControlScale)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if store.tagsEnabled, !store.tags.isEmpty {
                Menu {
                    Button("All Tags") { query.tagID = nil }
                    Divider()
                    ForEach(store.tags) { tag in
                        Button {
                            query.tagID = tag.id
                        } label: {
                            Label(tag.name, systemImage: query.tagID == tag.id ? "checkmark" : "tag")
                        }
                    }
                } label: {
                    Image(systemName: query.tagID == nil ? "tag" : "tag.fill")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Filter by tag")
            }

            if store.tagsEnabled {
                Button {
                    showTagEditor.toggle()
                } label: {
                    Image(systemName: "tag.circle")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showTagEditor ? Color.accentColor : Color.white.opacity(0.55))
                .help("Manage tags")
                .accessibilityLabel("Manage clipboard tags")
            }
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("New tag", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9.5))
                    .padding(.horizontal, 7)
                    .frame(height: 25)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))

                Menu {
                    ForEach(ClipboardTagColor.allCases, id: \.self) { color in
                        Button(color.rawValue.capitalized) { newTagColor = color }
                    }
                } label: {
                    Circle()
                        .fill(newTagColor.swiftUIColor)
                        .frame(width: 13, height: 13)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    if store.addTag(name: newTagName, color: newTagColor) != nil {
                        newTagName = ""
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !store.tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(store.tags) { tag in
                            Menu {
                                Button("Rename") {
                                    editingTagID = tag.id
                                    editingTagName = tag.name
                                    editingTagColor = tag.color
                                }
                                Button("Delete", role: .destructive) {
                                    store.deleteTag(id: tag.id)
                                    if query.tagID == tag.id { query.tagID = nil }
                                }
                            } label: {
                                Label(tag.name, systemImage: "tag.fill")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(tag.color.swiftUIColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(tag.color.swiftUIColor.opacity(0.12), in: Capsule())
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let editingTagID {
                HStack(spacing: 6) {
                    TextField("Tag name", text: $editingTagName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 9.5))
                    Menu(editingTagColor.rawValue.capitalized) {
                        ForEach(ClipboardTagColor.allCases, id: \.self) { color in
                            Button(color.rawValue.capitalized) { editingTagColor = color }
                        }
                    }
                    Button("Save") {
                        store.updateTag(id: editingTagID, name: editingTagName, color: editingTagColor)
                        self.editingTagID = nil
                    }
                    .buttonStyle(.plain)
                    Button("Cancel") { self.editingTagID = nil }
                        .buttonStyle(.plain)
                }
                .font(.system(size: 9.5, weight: .medium))
            }
        }
        .padding(7)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty {
            emptyState(title: "No clipboard history", detail: "Copied text, links, files, and images appear here.")
        } else if visibleEntries.isEmpty {
            emptyState(title: "No matches", detail: "Try another search or filter.")
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: metrics.spacing(8, minimum: 6, maximum: 10)) {
                    ForEach(visibleEntries) { entry in
                        card(for: entry)
                    }
                }
                .padding(metrics.spacing(10, minimum: 8, maximum: 12))
            }
            .scrollIndicators(.visible)
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: metrics.icon(24, minimum: 20, maximum: 28), weight: .light))
                .foregroundStyle(.white.opacity(0.32))
            Text(title)
                .font(.system(size: metrics.font(12, minimum: 10.5, maximum: 14), weight: .medium))
            Text(detail)
                .font(.system(size: metrics.font(9.5, minimum: 8.5, maximum: 11)))
                .foregroundStyle(.white.opacity(0.40))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.68))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func card(for entry: ClipboardHistoryEntry) -> some View {
        let presentation = ClipboardHistoryRowPresentation.resolve(entry: entry)
        let isSelected = selectedEntryID == entry.id

        return HStack(alignment: .top, spacing: metrics.spacing(9, minimum: 7, maximum: 11)) {
            thumbnail(for: entry, presentation: presentation)

            VStack(alignment: .leading, spacing: 5) {
                if renameEntryID == entry.id {
                    TextField("Title", text: $renameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: metrics.font(11, minimum: 10, maximum: 13), weight: .semibold))
                        .focused($renameFocused)
                        .onSubmit { commitRename(entry) }
                } else {
                    Text(presentation.title)
                        .font(.system(size: metrics.font(11, minimum: 10, maximum: 13), weight: .semibold))
                        .lineLimit(entry.payload.kind == .text ? 3 : 2)
                        .textSelection(.enabled)
                }

                if case let .text(text) = entry.payload {
                    Text(text.plainText)
                        .font(.system(size: metrics.font(9.5, minimum: 8.5, maximum: 11)))
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(presentation.detail)
                        .font(.system(size: metrics.font(9.2, minimum: 8.2, maximum: 10.8)))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                metadataRow(entry, timestamp: presentation.timestamp)

                if store.tagsEnabled, !entry.tagIDs.isEmpty {
                    tagRow(entry)
                }
            }

            Spacer(minLength: 2)

            VStack(spacing: 5) {
                Button { store.toggleFavorite(id: entry.id) } label: {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(entry.isFavorite ? Color.yellow : Color.white.opacity(0.48))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.isFavorite ? "Unfavorite" : "Favorite")

                Button { copy(entry) } label: {
                    Image(systemName: copiedEntryID == entry.id ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(copiedEntryID == entry.id ? Color.green : Color.white.opacity(0.78))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(copiedEntryID == entry.id ? "Copied" : "Copy")
            }
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            isSelected ? Color.white.opacity(0.105) : Color.white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 11 * metrics.cornerRadiusScale, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11 * metrics.cornerRadiusScale, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.17) : .clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { copy(entry) }
        .onTapGesture { selectedEntryID = entry.id }
        .contextMenu { contextMenu(for: entry) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func metadataRow(_ entry: ClipboardHistoryEntry, timestamp: String) -> some View {
        HStack(spacing: 5) {
            if let app = entry.sourceApplication {
                if let icon = cache.appIcon(for: app.bundleIdentifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                }
                Text(app.name)
                    .lineLimit(1)
                    .task(id: app.bundleIdentifier) {
                        cache.loadAppIconIfNeeded(bundleID: app.bundleIdentifier)
                    }
                Text("•")
            }
            Text(timestamp)
            Text("•")
            Text(entry.payload.kind.rawValue.capitalized)
        }
        .font(.system(size: metrics.font(8.5, minimum: 7.8, maximum: 10)))
        .foregroundStyle(.white.opacity(0.37))
    }

    @ViewBuilder
    private func tagRow(_ entry: ClipboardHistoryEntry) -> some View {
        HStack(spacing: 4) {
            ForEach(store.tags.filter { entry.tagIDs.contains($0.id) }.prefix(3)) { tag in
                Text(tag.name)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tag.color.swiftUIColor.opacity(0.95))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(tag.color.swiftUIColor.opacity(0.12), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func thumbnail(
        for entry: ClipboardHistoryEntry,
        presentation: ClipboardHistoryRowPresentation
    ) -> some View {
        let size = presentation.isImage ? CGSize(width: 68, height: 52) : CGSize(width: 38, height: 38)
        if case let .imagePNG(data) = entry.payload {
            Group {
                if let image = cache.image(for: entry.fingerprint) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.white.opacity(0.46))
                }
            }
            .frame(width: size.width * metrics.expandedCardScale, height: size.height * metrics.expandedCardScale)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8 * metrics.cornerRadiusScale, style: .continuous))
            .task(id: entry.fingerprint) {
                cache.loadImageIfNeeded(fingerprint: entry.fingerprint, data: data)
            }
        } else {
            Image(systemName: presentation.iconName)
                .font(.system(size: metrics.icon(15, minimum: 13, maximum: 18), weight: .medium))
                .foregroundStyle(.white.opacity(0.60))
                .frame(width: size.width, height: size.height)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private func contextMenu(for entry: ClipboardHistoryEntry) -> some View {
        Button("Copy") { copy(entry) }
        Button(entry.isFavorite ? "Unfavorite" : "Favorite") {
            store.toggleFavorite(id: entry.id)
        }
        Button("Rename") { beginRename(entry) }

        if store.tagsEnabled, !store.tags.isEmpty {
            Menu("Tags") {
                ForEach(store.tags) { tag in
                    let assigned = entry.tagIDs.contains(tag.id)
                    Button(assigned ? "Remove \(tag.name)" : tag.name) {
                        store.setTag(tag.id, on: entry.id, enabled: !assigned)
                    }
                }
            }
        }

        switch entry.payload {
        case let .url(url):
            Divider()
            Button("Open") { NSWorkspace.shared.open(url) }
        case let .files(urls):
            Divider()
            Button("Quick Look") { _ = FileShelfQuickLookController.shared.preview(existingFiles(urls)) }
            Button("Reveal in Finder") {
                let files = existingFiles(urls)
                if !files.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(files) }
            }
            if let add = externalActions.addFilesToShelf {
                Button("Add to Shelf") {
                    let files = existingFiles(urls)
                    if !files.isEmpty { add(files) }
                }
            }
            if let add = externalActions.addFilesToBasket {
                Button("Add to Basket") {
                    let files = existingFiles(urls)
                    if !files.isEmpty { add(files) }
                }
            }
        case .imagePNG, .text:
            EmptyView()
        }

        Divider()
        Button("Delete from History", role: .destructive) {
            store.removeEntry(id: entry.id)
            if selectedEntryID == entry.id { selectedEntryID = nil }
        }
    }

    private func beginRename(_ entry: ClipboardHistoryEntry) {
        renameEntryID = entry.id
        renameDraft = entry.customTitle ?? ClipboardHistoryRowPresentation.resolve(entry: entry).title
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename(_ entry: ClipboardHistoryEntry) {
        store.renameEntry(id: entry.id, title: renameDraft)
        renameEntryID = nil
        renameDraft = ""
        renameFocused = false
    }

    private func copy(_ entry: ClipboardHistoryEntry) {
        copy(id: entry.id)
    }

    private func copy(id: UUID) {
        guard store.copyEntryToPasteboard(id: id) else { return }
        copiedFeedbackGeneration += 1
        let generation = copiedFeedbackGeneration
        copiedEntryID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard generation == copiedFeedbackGeneration else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                copiedEntryID = nil
            }
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !visibleEntries.isEmpty else { selectedEntryID = nil; return }
        let current = selectedEntryID.flatMap { id in visibleEntries.firstIndex { $0.id == id } }
        let next = min(max((current ?? (delta > 0 ? -1 : visibleEntries.count)) + delta, 0), visibleEntries.count - 1)
        selectedEntryID = visibleEntries[next].id
    }

    private func reconcileSelection() {
        guard !visibleEntries.isEmpty else { selectedEntryID = nil; return }
        if let id = selectedEntryID, visibleEntries.contains(where: { $0.id == id }) { return }
        selectedEntryID = visibleEntries.first?.id
    }

    private func existingFiles(_ urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private extension ClipboardTagColor {
    var swiftUIColor: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}
