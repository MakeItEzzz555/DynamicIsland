import AppKit
import SwiftUI

struct CompactMediaView: View {
    @ObservedObject var media: MediaController

    var body: some View {
        AlbumArtworkView(image: media.artworkImage, size: 32)
        .accessibilityLabel("Media \(media.title)")
    }
}

struct AudioVisualizerView: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.18, paused: !isPlaying)) { timeline in
            let tick = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(isPlaying ? 0.86 : 0.44))
                        .frame(width: 4, height: barHeight(index: index, tick: tick))
                }
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityLabel(isPlaying ? "Audio playing" : "Audio paused")
    }

    private func barHeight(index: Int, tick: TimeInterval) -> CGFloat {
        guard isPlaying else { return CGFloat([8, 18, 12][index]) }
        let wave = sin((tick * 6.4) + Double(index) * 1.12)
        return 7 + CGFloat((wave + 1) * 8)
    }
}

struct AlbumArtworkView: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [.green, .cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.38, weight: .bold))
                            .foregroundStyle(.black.opacity(0.62))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                AlbumArtworkView(image: media.artworkImage, size: 136)
                VStack(alignment: .leading, spacing: 5) {
                    Text(media.title)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(media.artist)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                    Text(media.sourceName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                    HStack(spacing: 24) {
                        MediaButton(symbol: "backward.fill", label: "Previous track", action: media.previousTrack)
                        MediaButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", label: "Play or pause", action: media.playPause)
                        MediaButton(symbol: "forward.fill", label: "Next track", action: media.nextTrack)
                    }
                    .padding(.top, 12)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 10) {
                Slider(value: .constant(0.62))
                    .tint(.white.opacity(0.70))
                    .disabled(true)
                HStack {
                    Text("2:03")
                    Spacer()
                    Text("2:55")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                .frame(width: 36, height: 36)
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
                    .font(.system(size: 14, weight: .bold, design: .rounded))
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
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 112)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct TimerModuleView: View {
    @ObservedObject var timer: TimerController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Timer", systemImage: "timer")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(timer.isRunning ? timer.displayText : "Start a timer")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .lineLimit(1)
            HStack {
                Button("5m") { timer.start(minutes: 5) }
                Button("10m") { timer.start(minutes: 10) }
                Button(timer.isRunning ? "Stop" : "15m") {
                    timer.isRunning ? timer.stop() : timer.start(minutes: 15)
                }
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        VStack(alignment: .leading, spacing: 14) {
            Label("Shortcuts", systemImage: "bolt.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(shortcuts.shortcuts.prefix(6)) { shortcut in
                    Button {
                        shortcuts.open(shortcut)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: shortcut.symbolName)
                                .font(.system(size: 18, weight: .semibold))
                            Text(shortcut.title)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Open \(shortcut.title)")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
