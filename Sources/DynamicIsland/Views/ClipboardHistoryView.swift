import AppKit
import SwiftUI

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

        switch entry.payload {
        case let .text(payload):
            let normalized = payload.plainText
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            return Self(
                iconName: "text.alignleft",
                title: normalized.isEmpty ? "Text" : normalized,
                detail: "\(payload.plainText.count) characters",
                timestamp: timestamp,
                isImage: false
            )
        case let .url(url):
            return Self(
                iconName: "link",
                title: url.host(percentEncoded: false) ?? "URL",
                detail: url.absoluteString,
                timestamp: timestamp,
                isImage: false
            )
        case let .files(urls):
            let names = urls.prefix(2).map(\.lastPathComponent).filter { !$0.isEmpty }
            let title = names.isEmpty ? "Files" : names.joined(separator: ", ")
            return Self(
                iconName: urls.count == 1 ? "doc" : "doc.on.doc",
                title: title,
                detail: urls.count == 1 ? "1 file" : "\(urls.count) files",
                timestamp: timestamp,
                isImage: false
            )
        case let .imagePNG(data):
            return Self(
                iconName: "photo",
                title: "Image",
                detail: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file),
                timestamp: timestamp,
                isImage: true
            )
        }
    }
}

@MainActor
private final class ClipboardThumbnailCache: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]

    private let capacity = 24
    private var order: [String] = []

    func image(for fingerprint: String) -> NSImage? {
        images[fingerprint]
    }

    func loadIfNeeded(fingerprint: String, data: Data) {
        guard images[fingerprint] == nil, let image = NSImage(data: data) else { return }
        images[fingerprint] = image
        order.removeAll { $0 == fingerprint }
        order.append(fingerprint)

        while order.count > capacity {
            let evicted = order.removeFirst()
            images.removeValue(forKey: evicted)
        }
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardHistoryStore
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var thumbnailCache = ClipboardThumbnailCache()
    @State private var copiedEntryID: UUID?
    @State private var copiedFeedbackGeneration = 0
    @State private var confirmsClearAll = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.08))

            if store.entries.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 7) {
                        ForEach(store.entries) { entry in
                            row(for: entry)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .scrollIndicators(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .background(Color.black.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard History")
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clipboard")
                    .foregroundStyle(.white.opacity(0.78))

                Text("Clipboard History")
                    .font(.system(size: 13, weight: .semibold))

                Text("\(store.entries.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())

                Spacer(minLength: 4)

                if !store.entries.isEmpty {
                    Button("Clear All") {
                        confirmsClearAll.toggle()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(confirmsClearAll ? Color.red.opacity(0.9) : .white.opacity(0.62))
                    .help("Clear clipboard history")
                    .accessibilityLabel("Clear all clipboard history")
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.72))
                .help("Close Clipboard History")
                .accessibilityLabel("Close Clipboard History")
            }

            if confirmsClearAll {
                HStack(spacing: 8) {
                    Text("Clear all clipboard entries?")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.66))
                    Spacer()
                    Button("Cancel") { confirmsClearAll = false }
                        .buttonStyle(.plain)
                    Button("Clear") {
                        store.clearHistory()
                        copiedEntryID = nil
                        confirmsClearAll = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.9))
                }
                .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.34))
            Text("No clipboard history")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
            Text("Copied text, links, files, and images appear here.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.38))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func row(for entry: ClipboardHistoryEntry) -> some View {
        let presentation = ClipboardHistoryRowPresentation.resolve(entry: entry)
        return HStack(spacing: 9) {
            thumbnail(for: entry, presentation: presentation)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 5) {
                    Text(presentation.detail)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("•")
                    Text(presentation.timestamp)
                }
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.42))
            }

            Spacer(minLength: 4)

            Button {
                copy(entry)
            } label: {
                Image(systemName: copiedEntryID == entry.id ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(
                        copiedEntryID == entry.id
                            ? Color.green.opacity(0.92)
                            : Color.white.opacity(0.84)
                    )
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.14), value: copiedEntryID == entry.id)
            .help(copiedEntryID == entry.id ? "Copied" : "Copy")
            .accessibilityLabel(copiedEntryID == entry.id ? "Copied" : "Copy clipboard entry")

            Button {
                if copiedEntryID == entry.id {
                    copiedEntryID = nil
                }
                store.removeEntry(id: entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.44))
            .help("Delete")
            .accessibilityLabel("Delete clipboard entry")
        }
        .foregroundStyle(.white.opacity(0.84))
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { copy(entry) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func thumbnail(
        for entry: ClipboardHistoryEntry,
        presentation: ClipboardHistoryRowPresentation
    ) -> some View {
        if case let .imagePNG(data) = entry.payload {
            Group {
                if let image = thumbnailCache.image(for: entry.fingerprint) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: presentation.iconName)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
            .frame(width: 34, height: 34)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .task(id: entry.fingerprint) {
                thumbnailCache.loadIfNeeded(fingerprint: entry.fingerprint, data: data)
            }
        } else {
            Image(systemName: presentation.iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private func copy(_ entry: ClipboardHistoryEntry) {
        guard store.copyEntryToPasteboard(id: entry.id) else { return }
        copiedFeedbackGeneration += 1
        let generation = copiedFeedbackGeneration
        copiedEntryID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard generation == copiedFeedbackGeneration else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                copiedEntryID = nil
            }
        }
    }
}
