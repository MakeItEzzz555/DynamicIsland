import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CompactMediaView: View {
    @ObservedObject var media: MediaController

    var body: some View {
        FlippingAlbumArtworkView(media: media, size: CollapsedActivityLayoutProfile.mediaLeftContentWidth)
            .accessibilityLabel("Media \(media.title)")
    }
}

struct AudioVisualizerView: View {
    let isPlaying: Bool
    var isActive = true
    var accentColor: Color = ArtworkAccentColorExtractor.fallbackColor
    var variant: AudioVisualizerVariant = .compact
    var barCount = 12
    var pauseDuringShellMorph = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isShellMorphing) private var isShellMorphing
    @State private var isPlaybackVisuallyActive = false
    @State private var playbackHoldGeneration = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !shouldAnimateContinuously)) { timeline in
            bars(
                tick: shouldAnimateContinuously ? timeline.date.timeIntervalSinceReferenceDate : nil,
                opacity: visualizerOpacity
            )
        }
        .frame(width: variant.size.width, height: variant.size.height)
        .accessibilityLabel(isPlaying ? "Audio playing" : "Audio paused")
        .onAppear {
            updatePlaybackHold()
        }
        .onChange(of: isPlaying) { _, _ in
            updatePlaybackHold()
        }
        .onChange(of: isActive) { _, _ in
            updatePlaybackHold()
        }
    }

    private var shouldAnimateContinuously: Bool {
        isPlaybackVisuallyActive &&
            !reduceMotion &&
            !(pauseDuringShellMorph && isShellMorphing)
    }

    private var visualizerOpacity: Double {
        if isPlaybackVisuallyActive {
            return 0.92
        }
        return isActive ? 0.48 : 0.28
    }

    private func updatePlaybackHold() {
        playbackHoldGeneration += 1
        let generation = playbackHoldGeneration

        guard isPlaying && isActive else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.playbackHoldDuration) {
                guard generation == playbackHoldGeneration else { return }
                guard !(isPlaying && isActive) else {
                    isPlaybackVisuallyActive = true
                    return
                }
                isPlaybackVisuallyActive = false
            }
            return
        }

        isPlaybackVisuallyActive = true
    }

    private func bars(tick: TimeInterval?, opacity: Double) -> some View {
        HStack(alignment: .center, spacing: variant.spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(opacity))
                    .frame(width: variant.barWidth, height: barHeight(index: index, tick: tick))
                    .shadow(color: accentColor.opacity(tick == nil || reduceMotion ? 0 : 0.22), radius: 3)
            }
        }
    }

    private func barHeight(index: Int, tick: TimeInterval?) -> CGFloat {
        guard let tick else {
            return variant.maximumBarHeight * Self.pausedFractions[index % Self.pausedFractions.count]
        }

        let samples = Self.playingFractions[index % Self.playingFractions.count]
        let phase = tick.truncatingRemainder(dividingBy: Self.loopDuration) / Self.loopDuration
        let offsetPhase = (phase + (Double(index) * 0.047)).truncatingRemainder(dividingBy: 1)
        let samplePosition = offsetPhase * Double(samples.count)
        let lowerIndex = Int(floor(samplePosition)) % samples.count
        let upperIndex = (lowerIndex + 1) % samples.count
        let progress = CGFloat(samplePosition - floor(samplePosition))
        let easedProgress = progress * progress * (3 - 2 * progress)

        let fraction = samples[lowerIndex] + ((samples[upperIndex] - samples[lowerIndex]) * easedProgress)
        return variant.maximumBarHeight * min(max(fraction, 0.14), 1)
    }

    private static let playbackHoldDuration: TimeInterval = 0.34
    private static let loopDuration: TimeInterval = 1.72
    private static let pausedFractions: [CGFloat] = [0.24, 0.36, 0.28, 0.46, 0.31, 0.40, 0.27, 0.34, 0.44, 0.30, 0.38, 0.26]
    private static let playingFractions: [[CGFloat]] = [
        [0.28, 0.80, 0.42, 0.92, 0.33, 0.62],
        [0.64, 0.34, 0.96, 0.46, 0.74, 0.38],
        [0.40, 0.88, 0.30, 0.70, 0.52, 0.95],
        [0.76, 0.42, 0.58, 0.98, 0.36, 0.66]
    ]
}

enum AudioVisualizerVariant {
    case compact
    case expanded

    var size: CGSize {
        switch self {
        case .compact:
            CGSize(width: CollapsedActivityLayoutProfile.mediaRightContentWidth, height: 14)
        case .expanded:
            CGSize(width: 76, height: 28)
        }
    }

    var barWidth: CGFloat {
        switch self {
        case .compact:
            1.55
        case .expanded:
            3.2
        }
    }

    var spacing: CGFloat {
        switch self {
        case .compact:
            1.05
        case .expanded:
            2.2
        }
    }

    var maximumBarHeight: CGFloat {
        size.height
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

struct FlippingAlbumArtworkView: View {
    @ObservedObject private var presentation: ArtworkPresentationCoordinator
    let size: CGFloat

    init(media: MediaController, size: CGFloat) {
        presentation = media.artworkPresentation
        self.size = size
    }

    var body: some View {
        AlbumArtworkView(image: presentation.displayedSnapshot?.image, size: size)
            .rotation3DEffect(
                .degrees(presentation.rotationDegrees),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.72
            )
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
    @ObservedObject var settings: AppSettings
    @ObservedObject var media: MediaController
    let availableHeight: CGFloat?
    let onLauncherActivated: () -> Void
    let onMediaSourceOpened: () -> Void
    @ObservedObject private var accentCache = ArtworkAccentColorCache.shared
    @ObservedObject private var artworkPresentation: ArtworkPresentationCoordinator

    init(
        settings: AppSettings,
        media: MediaController,
        availableHeight: CGFloat? = nil,
        onLauncherActivated: @escaping () -> Void = {},
        onMediaSourceOpened: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.media = media
        self.availableHeight = availableHeight
        self.onLauncherActivated = onLauncherActivated
        self.onMediaSourceOpened = onMediaSourceOpened
        artworkPresentation = media.artworkPresentation
    }

    private var usesCompactExpandedLayout: Bool {
        availableHeight != nil
    }

    private var artworkSize: CGFloat {
        usesCompactExpandedLayout ? 44 : 112
    }

    private var moduleSpacing: CGFloat {
        usesCompactExpandedLayout ? 6 : 14
    }

    private var headerSpacing: CGFloat {
        usesCompactExpandedLayout ? 9 : 14
    }

    private var metadataSpacing: CGFloat {
        usesCompactExpandedLayout ? 2 : 4
    }

    private var titleFontSize: CGFloat {
        usesCompactExpandedLayout ? 15 : 21
    }

    private var artistFontSize: CGFloat {
        usesCompactExpandedLayout ? 12 : 16
    }

    private var sourceFontSize: CGFloat {
        usesCompactExpandedLayout ? 10 : 14
    }

    private var visualizerTopPadding: CGFloat {
        usesCompactExpandedLayout ? 2 : 4
    }

    private var transportControlsSpacing: CGFloat {
        usesCompactExpandedLayout ? 10 : 18
    }

    private var transportControlsTopPadding: CGFloat {
        usesCompactExpandedLayout ? 5 : 12
    }

    private var sliderStackSpacing: CGFloat {
        usesCompactExpandedLayout ? 5 : 10
    }

    private var timeFontSize: CGFloat {
        usesCompactExpandedLayout ? 9 : 13
    }

    private var placeholderProgressHeight: CGFloat {
        usesCompactExpandedLayout ? 4 : 5
    }

    var body: some View {
        let activeBranch = shouldShowActivePlayer
        let _ = Self.debugRender(
            hasActiveMediaSource: media.hasActiveMediaSource,
            isPlaying: media.isPlaying,
            title: media.title,
            sourceName: media.sourceName,
            branch: activeBranch ? "active player" : "empty launcher"
        )

        let content = Group {
            if activeBranch {
                activePlayerView
            } else if shouldShowLauncher {
                EmptyMediaLauncherView(settings: settings, media: media, onLauncherActivated: onLauncherActivated)
            } else {
                disabledState
            }
        }

        if let availableHeight {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: availableHeight,
                maxHeight: availableHeight,
                alignment: .center
            )
        } else {
            content
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var shouldShowActivePlayer: Bool {
        guard settings.mediaEnabled else { return false }
        guard media.hasActiveMediaSource else { return false }
        return settings.showMediaWhenPaused || media.isPlaying
    }

    private var shouldShowLauncher: Bool {
        settings.mediaEnabled && settings.showMediaWhenNoSource && settings.mediaLauncherEnabled
    }

    private var visualizerColor: Color {
        switch settings.visualizerAccentMode {
        case .artwork:
            if settings.useArtworkAccentColor {
                return accentCache.color(
                    for: artworkPresentation.displayedSnapshot?.fingerprint,
                    image: artworkPresentation.displayedSnapshot?.image
                )
            }
            return .white
        case .white:
            return .white
        case .system:
            return .accentColor
        }
    }

    private var disabledState: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "music.note.slash")
                .font(.system(size: usesCompactExpandedLayout ? 20 : 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
            Text(settings.mediaEnabled ? "No media visible" : "Media disabled")
                .font(.system(size: usesCompactExpandedLayout ? 12 : 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var activePlayerView: some View {
        if usesCompactExpandedLayout {
            constrainedActivePlayerView
        } else {
            regularActivePlayerView
        }
    }

    @ViewBuilder
    private var regularActivePlayerView: some View {
        VStack(alignment: .leading, spacing: moduleSpacing) {
            HStack(alignment: .top, spacing: headerSpacing) {
                if settings.showAlbumArtwork {
                    ClickableAlbumArtworkButton(
                        settings: settings,
                        media: media,
                        size: artworkSize
                    ) {
                        let opened = media.openActiveMediaSource()
                        Self.debugMediaSourceOpenCollapse(opened: opened)
                        if opened {
                            onMediaSourceOpened()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: metadataSpacing) {
                    if settings.showMediaTitle {
                        Text(media.title)
                            .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    if settings.showMediaArtist {
                        Text(media.artist)
                            .font(.system(size: artistFontSize, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(1)
                    }
                    if settings.showMediaSourceName {
                        Text(media.sourceName)
                            .font(.system(size: sourceFontSize, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }
                    if settings.showVisualizer && settings.showExpandedVisualizer {
                        AudioVisualizerView(
                            isPlaying: media.isPlaying,
                            isActive: media.hasActiveMediaSource,
                            accentColor: visualizerColor,
                            variant: .expanded,
                            pauseDuringShellMorph: settings.disableVisualizerDuringMorph
                        )
                        .padding(.top, visualizerTopPadding)
                    }
                    if settings.showPlaybackControls {
                        HStack(spacing: transportControlsSpacing) {
                            MediaButton(
                                symbol: "backward.fill",
                                label: "Previous track",
                                symbolSize: usesCompactExpandedLayout ? 13 : 15,
                                buttonSize: usesCompactExpandedLayout ? 30 : 36,
                                isEnabled: media.isTransportControlAvailable,
                                action: media.previousTrack
                            )
                            MediaButton(
                                symbol: media.isPlaying ? "pause.fill" : "play.fill",
                                label: "Play or pause",
                                symbolSize: usesCompactExpandedLayout ? 13 : 15,
                                buttonSize: usesCompactExpandedLayout ? 30 : 36,
                                isEnabled: media.isTransportControlAvailable,
                                action: media.playPause
                            )
                            MediaButton(
                                symbol: "forward.fill",
                                label: "Next track",
                                symbolSize: usesCompactExpandedLayout ? 13 : 15,
                                buttonSize: usesCompactExpandedLayout ? 30 : 36,
                                isEnabled: media.isTransportControlAvailable,
                                action: media.nextTrack
                            )
                        }
                        .padding(.top, transportControlsTopPadding)
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: sliderStackSpacing) {
                if settings.showProgressSlider, media.hasPlaybackProgress {
                    Slider(
                        value: Binding(
                            get: { media.playbackPosition },
                            set: { media.updateScrubPosition($0) }
                        ),
                        in: 0...max(media.duration, 1),
                        onEditingChanged: { isEditing in
                            if !isEditing {
                                media.seek(to: media.playbackPosition)
                            }
                        }
                    )
                    .tint(.white.opacity(0.70))
                    .opacity(media.isSeekControlAvailable ? 1 : 0.38)
                    .disabled(!media.isSeekControlAvailable)
                    HStack {
                        Text(formatTime(media.playbackPosition))
                        Spacer()
                        Text(formatTime(media.duration))
                    }
                    .font(.system(size: timeFontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(0.58))
                } else if settings.showProgressSlider {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.16))
                        .frame(height: placeholderProgressHeight)
                    HStack {
                        Text("--:--")
                        Spacer()
                        Text("--:--")
                    }
                    .font(.system(size: timeFontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(0.36))
                }
                if settings.showVolumeSlider {
                    Slider(
                        value: Binding(
                            get: { media.volume },
                            set: { media.setVolume($0) }
                        ),
                        in: 0...1
                    )
                    .tint(.white.opacity(0.70))
                    .opacity(media.isVolumeControlAvailable ? 1 : 0.38)
                    .disabled(!media.isVolumeControlAvailable)
                    .accessibilityLabel("Media volume")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var constrainedActivePlayerView: some View {
        ViewThatFits(in: .vertical) {
            constrainedActivePlayerLayout(
                artworkSize: artworkSize,
                transportButtonSize: 28,
                transportSymbolSize: 12,
                sectionSpacing: 4,
                headerSpacing: 8,
                inlineVisualizerTopPadding: 1
            )
            constrainedActivePlayerLayout(
                artworkSize: 40,
                transportButtonSize: 26,
                transportSymbolSize: 11,
                sectionSpacing: 3,
                headerSpacing: 7,
                inlineVisualizerTopPadding: 0
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func constrainedActivePlayerLayout(
        artworkSize: CGFloat,
        transportButtonSize: CGFloat,
        transportSymbolSize: CGFloat,
        sectionSpacing: CGFloat,
        headerSpacing: CGFloat,
        inlineVisualizerTopPadding: CGFloat
    ) -> some View {
        return VStack(alignment: .leading, spacing: sectionSpacing) {
            HStack(alignment: .top, spacing: headerSpacing) {
                if settings.showAlbumArtwork {
                    ClickableAlbumArtworkButton(
                        settings: settings,
                        media: media,
                        size: artworkSize
                    ) {
                        let opened = media.openActiveMediaSource()
                        Self.debugMediaSourceOpenCollapse(opened: opened)
                        if opened {
                            onMediaSourceOpened()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    if settings.showMediaTitle {
                        Text(media.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    if settings.showMediaArtist {
                        Text(media.artist)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    HStack(alignment: .center, spacing: 6) {
                        if settings.showMediaSourceName {
                            Text(media.sourceName)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.48))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }

                        if settings.showVisualizer && settings.showExpandedVisualizer {
                            AudioVisualizerView(
                                isPlaying: media.isPlaying,
                                isActive: media.hasActiveMediaSource,
                                accentColor: visualizerColor,
                                variant: .compact,
                                pauseDuringShellMorph: settings.disableVisualizerDuringMorph
                            )
                            .padding(.top, inlineVisualizerTopPadding)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if settings.showPlaybackControls {
                HStack(spacing: 9) {
                    MediaButton(
                        symbol: "backward.fill",
                        label: "Previous track",
                        symbolSize: transportSymbolSize,
                        buttonSize: transportButtonSize,
                        isEnabled: media.isTransportControlAvailable,
                        action: media.previousTrack
                    )
                    MediaButton(
                        symbol: media.isPlaying ? "pause.fill" : "play.fill",
                        label: "Play or pause",
                        symbolSize: transportSymbolSize,
                        buttonSize: transportButtonSize,
                        isEnabled: media.isTransportControlAvailable,
                        action: media.playPause
                    )
                    MediaButton(
                        symbol: "forward.fill",
                        label: "Next track",
                        symbolSize: transportSymbolSize,
                        buttonSize: transportButtonSize,
                        isEnabled: media.isTransportControlAvailable,
                        action: media.nextTrack
                    )
                }
            }

            if settings.showProgressSlider {
                VStack(spacing: 3) {
                    if media.hasPlaybackProgress {
                        Slider(
                            value: Binding(
                                get: { media.playbackPosition },
                                set: { media.updateScrubPosition($0) }
                            ),
                            in: 0...max(media.duration, 1),
                            onEditingChanged: { isEditing in
                                if !isEditing {
                                    media.seek(to: media.playbackPosition)
                                }
                            }
                        )
                        .tint(.white.opacity(0.70))
                        .opacity(media.isSeekControlAvailable ? 1 : 0.38)
                        .disabled(!media.isSeekControlAvailable)

                        HStack {
                            Text(formatTime(media.playbackPosition))
                            Spacer()
                            Text(formatTime(media.duration))
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.58))
                    } else {
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.16))
                            .frame(height: 4)

                        HStack {
                            Text("--:--")
                            Spacer()
                            Text("--:--")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.36))
                    }
                }
            }

            if settings.showVolumeSlider {
                HStack(spacing: 6) {
                    Image(systemName: media.isVolumeControlAvailable ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(media.isVolumeControlAvailable ? 0.50 : 0.32))
                        .frame(width: 12)

                    Slider(
                        value: Binding(
                            get: { media.volume },
                            set: { media.setVolume($0) }
                        ),
                        in: 0...1
                    )
                    .tint(.white.opacity(0.70))
                    .opacity(media.isVolumeControlAvailable ? 1 : 0.38)
                    .disabled(!media.isVolumeControlAvailable)
                    .accessibilityLabel("Media volume")
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let wholeSeconds = max(0, Int(seconds.rounded()))
        return "\(wholeSeconds / 60):\(String(format: "%02d", wholeSeconds % 60))"
    }

    private static func debugRender(
        hasActiveMediaSource: Bool,
        isPlaying: Bool,
        title: String,
        sourceName: String,
        branch: String
    ) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" else { return }
        debugPrint(
            "DynamicIsland MediaModuleView render",
            "hasActiveMediaSource=\(hasActiveMediaSource)",
            "isPlaying=\(isPlaying)",
            "title=\(title)",
            "source=\(sourceName)",
            "branch=\(branch)"
        )
        #endif
    }

    private static func debugMediaSourceOpenCollapse(opened: Bool) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" else { return }
        debugPrint(
            "DynamicIsland media source open",
            "requestedCollapse=\(opened)"
        )
        #endif
    }
}

private struct ClickableAlbumArtworkButton: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var media: MediaController
    let size: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Group {
            if settings.openSourceOnArtworkClick {
                Button(action: action) {
                    artwork
                }
                .buttonStyle(.plain)
            } else {
                artwork
            }
        }
        .onHover { isHovering = $0 }
        .accessibilityLabel("Open media source")
        .accessibilityHint("Opens the app currently playing this media")
    }

    private var artwork: some View {
        FlippingAlbumArtworkView(media: media, size: size)
            .scaleEffect(isHovering ? 1.028 : 1)
            .brightness(isHovering ? 0.035 : 0)
            .animation(.easeOut(duration: 0.16), value: isHovering)
    }
}

struct EmptyMediaLauncherView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var media: MediaController
    let onLauncherActivated: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("No app seems to be running")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("Wanna open one?")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }

            HStack(spacing: 10) {
                if settings.showAppleMusicLauncher {
                    MediaLauncherButton(title: "Apple Music", symbol: "music.note", tint: .pink) {
                        media.openMusicApp()
                        onLauncherActivated()
                    }
                }
                if settings.showSpotifyLauncher {
                    MediaLauncherButton(title: "Spotify", symbol: "dot.radiowaves.left.and.right", tint: .green) {
                        media.openSpotifyApp()
                        onLauncherActivated()
                    }
                }
                if settings.showYouTubeLauncher {
                    MediaLauncherButton(title: "YouTube", symbol: "play.rectangle.fill", tint: .red) {
                        media.openYouTube()
                        onLauncherActivated()
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct MediaLauncherButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(tint)
                    .background(.white.opacity(0.10), in: Circle())
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(width: 86, height: 82)
            .foregroundStyle(.white)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title)")
    }
}

struct MediaButton: View {
    let symbol: String
    let label: String
    var symbolSize: CGFloat = 15
    var buttonSize: CGFloat = 36
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .bold))
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.38))
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

struct FileShelfModuleView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var fileShelf: FileShelfStore
    @ObservedObject var backgroundOperations: BackgroundOperationController
    var dragExplanation: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var thumbnailCache = FileThumbnailCache()

    private let columns = [
        GridItem(.adaptive(minimum: 78, maximum: 92), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if backgroundOperations.primaryOperation != nil {
                BackgroundOperationCenterView(
                    controller: backgroundOperations,
                    reduceMotion: reduceMotion || settings.reduceExtraMotion
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack {
                Label("File Shelf", systemImage: "tray.full")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                if settings.showFileCountBadge, !fileShelf.files.isEmpty {
                    Text("\(fileShelf.files.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan.opacity(0.92))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.cyan.opacity(0.12), in: Capsule(style: .continuous))
                        .accessibilityLabel("\(fileShelf.files.count) files")
                }
                Spacer()
                if fileShelf.files.count > 1 {
                    Button("Select All") {
                        fileShelf.selectAll()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.58))
                    .accessibilityLabel("Select all files in shelf")
                }
                Button("Clear") {
                    clearShelf()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(fileShelf.files.isEmpty ? 0.34 : 0.66))
                .disabled(fileShelf.files.isEmpty)
            }
            .foregroundStyle(.white)

            if fileShelf.files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                    Text("Drop files here")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                    Text(emptyShelfSubtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 118)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(fileShelf.files, id: \.self) { url in
                            ShelfFileTile(
                                settings: settings,
                                fileShelf: fileShelf,
                                url: url,
                                thumbnailCache: thumbnailCache,
                                isSelected: fileShelf.selection.contains(url.standardizedFileURL),
                                onRemove: { fileShelf.remove(url) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 176)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 154, maxHeight: backgroundOperations.primaryOperation == nil ? 214 : 260, alignment: .topLeading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if let dragExplanation {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.82))
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                        Text(dragExplanation)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                    .padding(14)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: dragExplanation)
    }

    private var emptyShelfSubtitle: String {
        if !settings.allowFileDropsOnExpandedTray {
            return "File drops disabled in Settings"
        }
        if settings.persistFileShelfAcrossLaunches {
            return "Files stay in your shelf and are saved across launches"
        }
        return "Files stay in your shelf for quick access"
    }

    private func clearShelf() {
        guard !fileShelf.files.isEmpty else { return }
        if settings.confirmBeforeClearShelf {
            let alert = NSAlert()
            alert.messageText = "Clear File Shelf?"
            alert.informativeText = "This removes files from the shelf only. It does not delete anything from disk."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Clear")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }
        fileShelf.clear()
    }
}

@MainActor
final class FileThumbnailCache: ObservableObject {
    @Published private var imagesByKey: [String: NSImage] = [:]
    private var loadingKeys: Set<String> = []

    func image(for url: URL) -> NSImage? {
        imagesByKey[cacheKey(for: url)]
    }

    func loadIfNeeded(for url: URL) {
        let key = cacheKey(for: url)
        guard imagesByKey[key] == nil, !loadingKeys.contains(key) else { return }
        loadingKeys.insert(key)

        let path = url.path
        let shouldLoadImagePreview = Self.isImageFile(url)
        let fileURL = url

        Task {
            let imageData = await Task.detached(priority: .utility) {
                shouldLoadImagePreview
                    ? try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
                    : nil
            }.value

            let image = imageData.flatMap(NSImage.init(data:)) ?? NSWorkspace.shared.icon(forFile: path)
            image.size = NSSize(width: 56, height: 56)
            imagesByKey[key] = image
            loadingKeys.remove(key)
        }
    }

    private func cacheKey(for url: URL) -> String {
        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = resourceValues?.fileSize ?? 0
        return "\(url.path)|\(modified)|\(size)"
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}

struct TimerModuleView: View {
    @ObservedObject var timer: TimerController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Timer", systemImage: "timer")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(timer.isRunning ? timer.displayText : "Start a timer")
                .font(.system(size: 20, weight: .bold, design: .rounded))
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
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

enum FileShelfActions {
    @discardableResult
    static func open(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            debugLog("FileShelfActions.open skipped missing file path=\(url.path)")
            return false
        }

        let didOpen = NSWorkspace.shared.open(url)
        debugLog("FileShelfActions.open path=\(url.path) success=\(didOpen)")
        return didOpen
    }

    @discardableResult
    static func revealInFinder(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            debugLog("FileShelfActions.reveal skipped missing file path=\(url.path)")
            return false
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        debugLog("FileShelfActions.reveal path=\(url.path)")
        return true
    }

    static func copyPath(_ url: URL) {
        copy(url.path)
        debugLog("FileShelfActions.copyPath path=\(url.path)")
    }

    static func copyName(_ url: URL) {
        copy(url.lastPathComponent)
        debugLog("FileShelfActions.copyName name=\(url.lastPathComponent)")
    }

    @MainActor
    @discardableResult
    static func quickLook(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            debugLog("FileShelfActions.quickLook skipped missing file path=\(url.path)")
            return false
        }
        let didPreview = FileShelfQuickLookController.shared.preview([url])
        debugLog("FileShelfActions.quickLook path=\(url.path) success=\(didPreview)")
        return didPreview
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" else { return }
        print("[DynamicIsland][FileShelfActions] \(message)")
        #endif
    }
}

struct ShelfFileTile: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var fileShelf: FileShelfStore
    let url: URL
    @ObservedObject var thumbnailCache: FileThumbnailCache
    var isSelected = false
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var showsRename = false
    @State private var renameText = ""
    @State private var operationError: String?
    @Environment(\.isShellMorphing) private var isShellMorphing

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                fileImage
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor : .white.opacity(isHovering ? 0.16 : 0.05),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if isHovering && settings.removeFileActionEnabled {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.94), .black.opacity(0.62))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .transition(.opacity)
                    .accessibilityLabel("Remove \(url.lastPathComponent) from Tray")
                }
            }

            Text(displayName)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: 78, alignment: .top)
                .frame(minHeight: 24)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 7)
        .frame(width: 84, alignment: .top)
        .background(
            isSelected ? Color.accentColor.opacity(0.22) : .white.opacity(isHovering ? 0.12 : 0.045),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(count: 2) {
            FileShelfActions.quickLook(url)
        }
        .onTapGesture {
            let modifiers = NSEvent.modifierFlags
            fileShelf.select(
                url,
                extend: modifiers.contains(.command),
                range: modifiers.contains(.shift)
            )
        }
        .focusable()
        .onKeyPress(.return) {
            let modifiers = NSEvent.modifierFlags
            fileShelf.select(
                url,
                extend: modifiers.contains(.command),
                range: modifiers.contains(.shift)
            )
            return .handled
        }
        .onHover { hovering in
            if isHovering != hovering {
                isHovering = hovering
            }
        }
        .onAppear {
            loadThumbnailIfNeeded()
        }
        .onChange(of: isShellMorphing) { _, newValue in
            if !newValue {
                loadThumbnailIfNeeded()
            }
        }
        .contextMenu {
            Button("Quick Look") {
                FileShelfActions.quickLook(url)
            }

            if settings.openFileActionEnabled {
                Divider()
                Button("Open") {
                    FileShelfActions.open(url)
                }
                let applications = FileShelfActions.openWithApplications(for: url)
                if !applications.isEmpty {
                    Menu("Open With") {
                        ForEach(applications, id: \.self) { appURL in
                            Button(appURL.deletingPathExtension().lastPathComponent) {
                                FileShelfActions.open(url, withApplication: appURL)
                            }
                        }
                    }
                }
            }

            Divider()
            Button("Copy") {
                _ = FileShelfActions.copyFiles(contextTargets)
            }
            Button("Rename…") {
                renameText = url.lastPathComponent
                showsRename = true
            }
            Button("Copy To…") {
                copyToChosenFolder()
            }
            Button("Move To…") {
                moveToChosenFolder()
            }

            if settings.revealInFinderActionEnabled {
                Button("Reveal in Finder") {
                    FileShelfActions.revealInFinder(url)
                }
            }

            if settings.copyPathActionEnabled {
                Divider()
                Button("Copy Path") {
                    FileShelfActions.copyPath(url)
                }
                Button("Copy File Name") {
                    FileShelfActions.copyName(url)
                }
            }

            if settings.removeFileActionEnabled {
                Divider()
                Button("Remove from Tray", role: .destructive) {
                    onRemove()
                }
            }
        }
        .popover(isPresented: $showsRename, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rename")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                TextField("File name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                    .onSubmit { performRename() }
                HStack {
                    Spacer()
                    Button("Cancel") { showsRename = false }
                    Button("Rename") { performRename() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)
        }
        .alert("File operation failed", isPresented: operationErrorBinding) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "Unknown error")
        }
        .accessibilityLabel("File \(url.lastPathComponent)")
        .accessibilityHint("Click to select for quick actions. Right-click for file actions")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
    }

    private var contextTargets: [URL] {
        if isSelected, !fileShelf.selection.isEmpty {
            return fileShelf.files.filter { fileShelf.selection.contains($0) }
        }
        return [url]
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )
    }

    private func performRename() {
        do {
            _ = try fileShelf.rename(url, to: renameText)
            showsRename = false
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func copyToChosenFolder() {
        guard let destination = FileShelfActions.chooseDestination(title: "Copy Files", prompt: "Copy") else { return }
        do {
            _ = try FileShelfDiskOperations.copy(contextTargets, to: destination)
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func moveToChosenFolder() {
        let targets = contextTargets
        guard let destination = FileShelfActions.chooseDestination(title: "Move Files", prompt: "Move") else { return }
        do {
            let moves = try FileShelfDiskOperations.move(targets, to: destination)
            for move in moves {
                fileShelf.recordMove(from: move.from, to: move.to)
            }
        } catch {
            operationError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var fileImage: some View {
        if settings.showFileThumbnails, let image = thumbnailCache.image(for: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(Self.isImageFile(url) ? 0 : 6)
        } else {
            Image(systemName: Self.placeholderSymbol(for: url))
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
        }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    private static func placeholderSymbol(for url: URL) -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return "folder.fill"
        }
        if isImageFile(url) {
            return "photo.fill"
        }
        return "doc.fill"
    }

    private func loadThumbnailIfNeeded() {
        guard settings.showFileThumbnails else { return }
        guard !isShellMorphing || !settings.deferThumbnailsDuringMorph else { return }
        thumbnailCache.loadIfNeeded(for: url)
    }

    private var displayName: String {
        settings.showFileExtensions
            ? url.lastPathComponent
            : url.deletingPathExtension().lastPathComponent
    }
}

struct ShortcutsModuleView: View {
    @ObservedObject var shortcuts: ShortcutsStore
    var availableHeight: CGFloat?
    var compactScale: CGFloat
    let onShortcutLaunched: () -> Void

    init(
        shortcuts: ShortcutsStore,
        availableHeight: CGFloat? = nil,
        compactScale: CGFloat = 1,
        onShortcutLaunched: @escaping () -> Void = {}
    ) {
        self.shortcuts = shortcuts
        self.availableHeight = availableHeight
        self.compactScale = compactScale
        self.onShortcutLaunched = onShortcutLaunched
    }

    var body: some View {
        VStack(alignment: .leading, spacing: max(7, 12 * compactScale)) {
            HStack(spacing: 8) {
                Label("Shortcuts", systemImage: "bolt.fill")
                    .font(.system(size: 14 * compactScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if hiddenShortcutCount > 0 {
                    Text("+\(hiddenShortcutCount)")
                        .font(.system(size: 10 * compactScale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                }
            }

            if shortcuts.shortcuts.isEmpty {
                Text("No shortcuts")
                    .font(.system(size: 10 * compactScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                GeometryReader { proxy in
                    shortcutsRow(availableWidth: proxy.size.width)
                }
                .frame(height: shortcutTileHeight)
            }
        }
        .padding(max(8, 12 * compactScale))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func shortcutsRow(availableWidth: CGFloat) -> some View {
        let spacing = max(7, 10 * compactScale)
        let visibleShortcuts = displayedShortcuts
        let visibleCount = max(min(visibleShortcuts.count, 3), 1)
        let fittedWidth = floor((availableWidth - (spacing * CGFloat(visibleCount - 1))) / CGFloat(visibleCount))
        let buttonWidth = max(fittedWidth, 0)

        return HStack(spacing: spacing) {
            ForEach(visibleShortcuts) { shortcut in
                shortcutButton(shortcut, width: buttonWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func shortcutButton(_ shortcut: LauncherShortcut, width: CGFloat) -> some View {
        let buttonScale = min(max(min(width / 112, shortcutTileHeight / 62) * compactScale, 0.70), 1)

        return Button {
            shortcuts.open(shortcut)
            onShortcutLaunched()
        } label: {
            VStack(spacing: max(3, 6 * buttonScale)) {
                Image(systemName: shortcut.symbolName)
                    .font(.system(size: 17 * buttonScale, weight: .semibold))
                Text(shortcut.title)
                    .font(.system(size: 11 * buttonScale, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
            }
            .frame(width: width, height: shortcutTileHeight)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel("Open \(shortcut.title)")
    }

    private var displayedShortcuts: [LauncherShortcut] {
        Array(shortcuts.shortcuts.prefix(3))
    }

    private var hiddenShortcutCount: Int {
        max(shortcuts.shortcuts.count - displayedShortcuts.count, 0)
    }

    private var shortcutTileHeight: CGFloat {
        guard let availableHeight else {
            return 58
        }
        let headerAndPadding: CGFloat = max(42, 54 * compactScale)
        let fittedRowHeight = availableHeight - headerAndPadding
        let clampedRowHeight = min(max(fittedRowHeight, 46), 68)
        return min(clampedRowHeight, max(fittedRowHeight, 0))
    }
}
