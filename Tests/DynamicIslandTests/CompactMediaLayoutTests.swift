import XCTest
@testable import DynamicIsland

/// Compact Media is an artwork-first Now Playing square, not a shrunk
/// Standard player. `MediaCompactLayout` is the exact geometry the view draws.
final class CompactMediaLayoutTests: XCTestCase {
    private typealias Slot = MediaCompactLayout.Slot
    /// Island (fallback and the measured 0.918 display scale) and Agents units.
    private let squares: [CGFloat] = [
        WidgetGridMetrics.make(surface: .media, metrics: .fallback).side,
        WidgetGridMetrics.mediaBaseSide * 0.918,
        WidgetGridMetrics.make(surface: .agents, metrics: .fallback).side,
    ]

    private func plan(_ side: CGFloat, _ content: MediaCompactLayout.Content = .init()) -> MediaCompactLayout {
        MediaCompactLayout.make(cell: CGSize(width: side, height: side), content: content)
    }

    func testCompactCellIsATrueSquareOnEverySurface() {
        for surface in [WorkspaceSurface.media, .agents] {
            let size = WidgetGridMetrics.make(surface: surface, metrics: .fallback).size(for: .compact)
            XCTAssertEqual(size.width, size.height)
        }
    }

    func testArtworkIsTheCenteredSquareHeroAtTheTop() throws {
        for side in squares {
            let layout = plan(side)
            let art = try XCTUnwrap(layout.frames[.artwork])
            XCTAssertEqual(art.width, art.height, "artwork stays square")
            XCTAssertEqual(art.midX, side / 2, accuracy: 0.5, "artwork is centered")
            XCTAssertGreaterThanOrEqual(art.width / side, MediaCompactLayout.artworkMinimumRatio - 0.01, "\(side): artwork is dominant")
            XCTAssertLessThanOrEqual(art.width / side, MediaCompactLayout.artworkTargetRatio + 0.01)
            XCTAssertLessThan(art.minY, side * 0.2, "artwork sits near the top")
            let largest = layout.frames.values.map { $0.width * $0.height }.max() ?? 0
            XCTAssertEqual(art.width * art.height, largest, accuracy: 0.5, "artwork is the largest element")
        }
    }

    func testInformationOrderIsArtworkMetadataTransportProgress() throws {
        for side in squares {
            let f = plan(side).frames
            let order: [Slot] = [.artwork, .title, .artist, .source, .transport, .progress, .times, .volume].filter { f[$0] != nil }
            for (a, b) in zip(order, order.dropFirst()) {
                XCTAssertGreaterThanOrEqual(f[b]!.minY, f[a]!.maxY - 0.01, "\(side): \(b) is below \(a)")
            }
            XCTAssertNotNil(f[.title]); XCTAssertNotNil(f[.artist]); XCTAssertNotNil(f[.transport])
            XCTAssertNotNil(f[.progress], "\(side): playback progress survives at every compact size")
        }
    }

    func testEverythingIsCenteredInsideTheSquareWithoutOverlapOrClipping() {
        for side in squares {
            let frames = plan(side).frames
            let bounds = CGRect(x: 0, y: 0, width: side, height: side)
            for (slot, frame) in frames {
                XCTAssertEqual(frame.midX, side / 2, accuracy: 0.5, "\(slot) is centered")
                XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(frame), "\(side): \(slot) \(frame) clips")
            }
            let list = Array(frames.values)
            for (index, a) in list.enumerated() {
                for b in list.dropFirst(index + 1) {
                    XCTAssertFalse(a.insetBy(dx: 0.01, dy: 0.01).intersects(b.insetBy(dx: 0.01, dy: 0.01)), "\(side): \(a) overlaps \(b)")
                }
            }
        }
    }

    func testNoGiantEmptyRegionAndUsableHitTargets() throws {
        for side in squares {
            let frames = plan(side).frames
            let top = frames.values.map(\.minY).min() ?? 0, bottom = frames.values.map(\.maxY).max() ?? 0
            XCTAssertLessThanOrEqual(top, side * 0.15)
            XCTAssertGreaterThanOrEqual(bottom, side * 0.85, "\(side): no large empty band at the bottom")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[.transport]).height, 20)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[.progress]).height, 10)
        }
    }

    func testProgressTrackIsShortAndCentered() throws {
        for side in squares {
            let progress = try XCTUnwrap(plan(side).frames[.progress])
            XCTAssertGreaterThanOrEqual(progress.width / side, 0.6)
            XCTAssertLessThanOrEqual(progress.width / side, 0.75, "the slider never runs edge to edge")
        }
    }

    func testIslandSquareFoldsSourceIntoTheArtistLineBeforeDroppingProgress() throws {
        let island = plan(WidgetGridMetrics.mediaBaseSide * 0.918)
        XCTAssertNil(island.frames[.source])
        XCTAssertTrue(island.sourceInline, "Source/App stays visible beside the artist")
        XCTAssertNil(island.frames[.times], "time labels go first")
        XCTAssertNil(island.frames[.volume], "volume is lower priority than progress")
        XCTAssertTrue(island.showsSkipButtons)
        // A larger (216 pt) square keeps every line, the times and volume.
        let agents = plan(216)
        for slot in Slot.allCases { XCTAssertNotNil(agents.frames[slot], "\(slot) fits in a 216 pt square") }
        XCTAssertFalse(agents.sourceInline)
    }

    func testMissingMetadataLeavesNoAwkwardSpacing() throws {
        let side = WidgetGridMetrics.make(surface: .agents, metrics: .fallback).side
        let layout = plan(side, .init(artist: false, source: false))
        let title = try XCTUnwrap(layout.frames[.title]), transport = try XCTUnwrap(layout.frames[.transport])
        XCTAssertEqual(transport.minY - title.maxY, MediaCompactLayout.controlsGap, accuracy: 0.01)
        XCTAssertNil(layout.frames[.artist]); XCTAssertNil(layout.frames[.source])
        XCTAssertFalse(layout.sourceInline)
    }

    func testUnavailableProgressAndHiddenArtworkStayBalanced() throws {
        let side = WidgetGridMetrics.mediaBaseSide * 0.918
        let noProgress = plan(side, .init(progress: false))
        XCTAssertNil(noProgress.frames[.progress]); XCTAssertNil(noProgress.frames[.times])
        XCTAssertGreaterThanOrEqual(noProgress.artworkSide, plan(side).artworkSide, "freed height goes to the artwork")
        let noArtwork = plan(side, .init(artwork: false))
        XCTAssertNil(noArtwork.frames[.artwork])
        let frames = noArtwork.frames.values
        let top = frames.map(\.minY).min() ?? 0, bottom = frames.map(\.maxY).max() ?? 0
        XCTAssertEqual(top, side - bottom, accuracy: 0.5, "a text-only square is vertically centered")
    }

    func testLayoutIsPureSoPlaybackStateAndReduceMotionCannotMoveIt() {
        // The plan has no playback, hover or motion input: paused/playing and
        // Reduce Motion render the same geometry.
        for side in squares { XCTAssertEqual(plan(side), plan(side)) }
        XCTAssertEqual(MediaCompactLayout.make(cell: .init(width: CGFloat.nan, height: 100), content: .init()).frames[.artwork]?.width ?? 0,
                       0, accuracy: 24, "invalid input stays finite")
    }

    func testLongTitleIsBoundedToTheSquare() throws {
        let side = WidgetGridMetrics.mediaBaseSide * 0.918
        let title = try XCTUnwrap(plan(side).frames[.title])
        XCTAssertEqual(title.width, side - MediaCompactLayout.horizontalPadding * 2, accuracy: 0.01,
                       "the title truncates inside the padded width")
    }
}

/// Standard Media: artwork left, metadata centered beside it, controls and
/// full-width sliders below filling the rectangle.
final class StandardMediaLayoutTests: XCTestCase {
    private typealias Slot = MediaStandardLayout.Slot
    private let cells: [CGSize] = [WorkspaceSurface.media, .agents].flatMap { surface in
        [CGFloat(1), 0.918].map { scale in
            let grid = WidgetGridMetrics.make(surface: surface, metrics: .fallback)
            return CGSize(width: grid.size(for: .standard).width * scale, height: grid.size(for: .standard).height * scale)
        }
    }

    func testArtworkLeftAndOneCenteredStackOnTheRight() throws {
        for cell in cells {
            let f = MediaStandardLayout.make(cell: cell, content: .init()).frames
            let art = try XCTUnwrap(f[.artwork])
            XCTAssertEqual(art.minX, MediaStandardLayout.horizontalPadding, accuracy: 0.01, "artwork is on the left")
            XCTAssertEqual(art.width, art.height, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(art.width, 44, "\(cell): artwork is not shrunk below the old 44 pt baseline")
            XCTAssertEqual(art.midY, cell.height / 2, accuracy: 0.5, "artwork is vertically centered")
            let order: [Slot] = [.title, .artist, .source, .transport, .progress, .volume]
            let column = try order.map { try XCTUnwrap(f[$0], "\(cell): \($0)") }
            for frame in column {
                XCTAssertEqual(frame.midX, column[0].midX, accuracy: 0.5, "one centered column")
                XCTAssertGreaterThanOrEqual(frame.minX, art.maxX, "right of the artwork")
            }
            for (a, b) in zip(column, column.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b.minY, a.maxY - 0.01)
                XCTAssertLessThanOrEqual(b.minY - a.maxY, MediaStandardLayout.stackGap + 0.01, "\(cell): stacked tightly")
            }
            let top = column.first!.minY, bottom = column.last!.maxY
            XCTAssertEqual(top, cell.height - bottom, accuracy: 0.5, "\(cell): the stack is vertically centered")
            let progress = try XCTUnwrap(f[.progress])
            XCTAssertLessThanOrEqual(progress.width / cell.width, 0.70, "\(cell): short sliders preserved")
        }
    }

    func testControlsStayInsideTheCardWithoutOverlap() throws {
        for cell in cells {
            let f = MediaStandardLayout.make(cell: cell, content: .init()).frames
            let bounds = CGRect(origin: .zero, size: cell).insetBy(dx: -0.01, dy: -0.01)
            let list = Array(f.values)
            for (i, a) in list.enumerated() {
                XCTAssertTrue(bounds.contains(a), "\(cell): \(a) clips")
                for b in list.dropFirst(i + 1) { XCTAssertFalse(a.insetBy(dx: 0.01, dy: 0.01).intersects(b.insetBy(dx: 0.01, dy: 0.01))) }
            }
        }
    }

    func testShortCellsDropVolumeThenProgressBeforeCrushingTheArtwork() {
        let short = MediaStandardLayout.make(cell: .init(width: 300, height: 110), content: .init())
        XCTAssertNil(short.frames[.volume])
        XCTAssertGreaterThanOrEqual(short.artworkSide, MediaStandardLayout.artworkMinimum)
        let noArtwork = MediaStandardLayout.make(cell: .init(width: 300, height: 150), content: .init(artwork: false))
        XCTAssertNil(noArtwork.frames[.artwork])
        XCTAssertEqual(noArtwork.frames[.title]?.midX ?? 0, 150, accuracy: 0.5, "without artwork the stack centers in the card")
        XCTAssertLessThanOrEqual(noArtwork.frames[.progress]?.width ?? 0, 300 * 0.70 + 0.01)
    }
}
