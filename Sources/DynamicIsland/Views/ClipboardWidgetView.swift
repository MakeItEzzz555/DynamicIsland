import SwiftUI

struct ClipboardWidgetView: View {
    @ObservedObject var store: ClipboardHistoryStore
    let enabled: Bool
    let onOpen: () -> Void
    let onEnable: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Clipboard", systemImage: "clipboard").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button(action: enabled ? onOpen : onEnable) {
                    Image(systemName: enabled ? "arrow.up.right" : "gearshape")
                        .frame(width: 25, height: 25).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(enabled ? "Open Clipboard History" : "Configure Clipboard History")
            }
            if !enabled {
                Text("Enable Clipboard History in Settings to keep recent copies.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else if store.entries.isEmpty {
                Text("Recent copies appear here").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                ForEach(store.entries.prefix(4)) { entry in
                    let presentation = ClipboardHistoryRowPresentation.resolve(entry: entry)
                    Button { _ = store.copyEntryToPasteboard(id: entry.id) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc").foregroundStyle(.cyan)
                            Text(presentation.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 10)).padding(7)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityLabel("Copy \(presentation.title)")
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white).padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }
}
