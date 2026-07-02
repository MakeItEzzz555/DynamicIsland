import SwiftUI

struct CompactMediaView: View {
    @ObservedObject var media: MediaController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: media.isPlaying ? "waveform" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(media.isPlaying ? Color.green : Color.white.opacity(0.85))
            Text(media.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Media \(media.title)")
    }
}

struct CompactShelfBadge: View {
    @ObservedObject var fileShelf: FileShelfStore

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "tray.full")
            Text("\(fileShelf.files.count)")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(fileShelf.files.isEmpty ? .white.opacity(0.48) : .cyan)
        .accessibilityLabel("\(fileShelf.files.count) files in shelf")
    }
}

struct MediaModuleView: View {
    @ObservedObject var media: MediaController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.green, .mint, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.black.opacity(0.68))
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(media.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                MediaButton(symbol: "backward.fill", label: "Previous track", action: media.previousTrack)
                MediaButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", label: "Play or pause", action: media.playPause)
                MediaButton(symbol: "forward.fill", label: "Next track", action: media.nextTrack)
                Spacer()
                Button {
                    media.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityLabel("Refresh media")
            }
        }
        .padding(14)
        .frame(width: 292, height: 126)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct MediaButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }
}

struct FileShelfModuleView: View {
    @ObservedObject var fileShelf: FileShelfStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("File Shelf", systemImage: "tray.full")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Clear") {
                    fileShelf.clear()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.66))
                .disabled(fileShelf.files.isEmpty)
            }
            .foregroundStyle(.white)

            if fileShelf.files.isEmpty {
                Text("Drag files onto the island to hold them here temporarily.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(fileShelf.files, id: \.self) { url in
                            ShelfFileChip(url: url) {
                                fileShelf.remove(url)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ShelfFileChip: View {
    let url: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
            Text(url.lastPathComponent)
                .lineLimit(1)
                .frame(maxWidth: 130)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(url.lastPathComponent)")
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(.white)
        .background(.white.opacity(0.12), in: Capsule())
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
    }
}

struct ShortcutsModuleView: View {
    @ObservedObject var shortcuts: ShortcutsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Shortcuts", systemImage: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                ForEach(shortcuts.shortcuts.prefix(6)) { shortcut in
                    Button {
                        shortcuts.open(shortcut)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: shortcut.symbolName)
                                .font(.system(size: 18, weight: .semibold))
                            Text(shortcut.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        .frame(width: 64, height: 64)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Open \(shortcut.title)")
                }
            }
        }
        .padding(14)
        .frame(width: 284, height: 126)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
