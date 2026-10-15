import CoreGraphics

/// Expanded Now Playing geometry, shared by Standard (2x1) and Large (2x2):
/// one top-to-bottom composition - artwork, title, artist, provider row
/// (source + visualizer), five controls, scrubber with elapsed/remaining.
///
/// The plan is a pure function of the allocated cell. Every metric (fonts,
/// control sizes, gaps) is multiplied by one `scale` derived from the cell, so
/// the sizes share a composition instead of owning two; the artwork absorbs
/// the remaining height, which is why Large leads with a much bigger cover.
/// The view places each element at its planned frame.
struct MediaExpandedLayout: Equatable {
    enum Slot: Hashable, CaseIterable { case artwork, title, artist, provider, controls, elapsed, progress, remaining, volume }
    struct Content: Equatable {
        var artwork = true, title = true, artist = true, provider = true, progress = true, volume = false
    }

    // Reference metrics at scale 1.
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 4
    static let titleFont: CGFloat = 15, artistFont: CGFloat = 12, providerFont: CGFloat = 10, timeFont: CGFloat = 9.5
    static let titleHeight: CGFloat = 18, artistHeight: CGFloat = 14, providerHeight: CGFloat = 14
    static let progressHeight: CGFloat = 14, volumeHeight: CGFloat = 14
    static let artworkGap: CGFloat = 6, artistGap: CGFloat = 2, providerGap: CGFloat = 2
    static let controlsGap: CGFloat = 3, progressGap: CGFloat = 1, volumeGap: CGFloat = 3
    static let timeWidth: CGFloat = 36
    static let visualizerSize = CGSize(width: 24, height: 13)
    static let providerIcon: CGFloat = 11
    /// Width of the controls/scrubber column at scale 1; capped by the cell.
    static let columnWidth: CGFloat = 240
    static let controls = MediaControlRowMetrics(secondary: 20, transport: 26, play: 34)

    static let artworkReference: CGFloat = 60
    static let artworkMinimum: CGFloat = 34
    static let artworkWidthRatio: CGFloat = 0.56
    /// Volume only appears while the cover stays a clear hero.
    static let volumeArtworkFloor: CGFloat = 88
    static let minimumScale: CGFloat = 0.88, maximumScale: CGFloat = 1.5, emergencyScale: CGFloat = 0.5

    let frames: [Slot: CGRect]
    let scale: CGFloat
    let artworkSide: CGFloat

    var titleFont: CGFloat { Self.titleFont * scale }
    var artistFont: CGFloat { Self.artistFont * scale }
    var providerFont: CGFloat { Self.providerFont * scale }
    var timeFont: CGFloat { Self.timeFont * scale }
    var controls: MediaControlRowMetrics { Self.controls.scaled(by: scale) }
    var visualizerSize: CGSize { .init(width: Self.visualizerSize.width * scale, height: Self.visualizerSize.height * scale) }
    var providerIcon: CGFloat { Self.providerIcon * scale }

    static func make(cell: CGSize, content: Content, topAttached: Bool = false) -> Self {
        let width = cell.width.isFinite ? max(0, cell.width) : 0
        let height = cell.height.isFinite ? max(0, cell.height) : 0
        let full = plan(width: width, height: height, content: content, topAttached: topAttached)
        guard content.volume, content.artwork, full.artworkSide < volumeArtworkFloor else { return full }
        var withoutVolume = content
        withoutVolume.volume = false
        return plan(width: width, height: height, content: withoutVolume, topAttached: topAttached)
    }

    private static func plan(width: CGFloat, height: CGFloat, content: Content, topAttached: Bool) -> Self {
        let inner = max(0, width - horizontalPadding * 2)
        // Unscaled height of everything except the artwork.
        var fixed = verticalPadding * 2 + controls.play
        if content.artwork { fixed += artworkGap }
        if content.title { fixed += titleHeight }
        if content.artist { fixed += artistHeight + (content.title ? artistGap : 0) }
        if content.provider { fixed += providerHeight + providerGap }
        fixed += controlsGap
        if content.progress { fixed += progressGap + progressHeight }
        if content.volume { fixed += volumeGap + volumeHeight }

        let reference = fixed + (content.artwork ? artworkReference : 0)
        let widthScale = inner / (columnWidth * 0.9)
        var scale = min(maximumScale, max(minimumScale, height / max(1, reference)), max(emergencyScale, widthScale))
        if content.artwork, height - fixed * scale < artworkMinimum {
            scale = max(emergencyScale, min(scale, (height - artworkMinimum) / fixed))
        }
        let artwork = content.artwork
            ? max(0, min(height - fixed * scale, inner, width * artworkWidthRatio))
            : 0

        let used = fixed * scale + artwork
        var y = topAttached ? 0 : verticalPadding * scale + max(0, (height - used) / 2)
        var frames: [Slot: CGRect] = [:]
        func put(_ slot: Slot, width w: CGFloat, height h: CGFloat) {
            frames[slot] = CGRect(x: (width - w) / 2, y: y, width: w, height: h * scale)
            y += h * scale
        }
        let column = min(inner, columnWidth * scale)
        if content.artwork {
            frames[.artwork] = CGRect(x: (width - artwork) / 2, y: y, width: artwork, height: artwork)
            y += artwork + artworkGap * scale
        }
        if content.title { put(.title, width: inner, height: titleHeight) }
        if content.artist {
            if content.title { y += artistGap * scale }
            put(.artist, width: inner, height: artistHeight)
        }
        if content.provider { y += providerGap * scale; put(.provider, width: inner, height: providerHeight) }
        y += controlsGap * scale
        put(.controls, width: column, height: controls.play)
        if content.progress {
            y += progressGap * scale
            let row = CGRect(x: (width - column) / 2, y: y, width: column, height: progressHeight * scale)
            let time = min(timeWidth * scale, column / 4)
            frames[.elapsed] = CGRect(x: row.minX, y: row.minY, width: time, height: row.height)
            frames[.remaining] = CGRect(x: row.maxX - time, y: row.minY, width: time, height: row.height)
            frames[.progress] = CGRect(x: row.minX + time, y: row.minY, width: max(0, column - 2 * time), height: row.height)
            y += row.height
        }
        if content.volume { y += volumeGap * scale; put(.volume, width: column, height: volumeHeight) }
        return Self(frames: frames, scale: scale, artworkSide: artwork)
    }
}
