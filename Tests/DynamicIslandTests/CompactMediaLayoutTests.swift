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

/// Standard Media: the native Now Playing structure.
final class StandardMediaLayoutTests: XCTestCase {
    private typealias Slot = MediaStandardLayout.Slot
    private let cells: [CGSize] = [CGFloat(1), 0.918].map { scale in
        let grid = WidgetGridMetrics.make(surface: .media, metrics: .fallback)
        return CGSize(width: grid.size(for: .standard).width * scale, height: grid.size(for: .standard).height * scale)
    }

    func testReferenceStructureTopRowProgressRowControls() throws {
        for cell in cells {
            let f = MediaStandardLayout.make(cell: cell, content: .init()).frames
            let art = try XCTUnwrap(f[.artwork]), title = try XCTUnwrap(f[.title]), artist = try XCTUnwrap(f[.artist])
            let viz = try XCTUnwrap(f[.visualizer])
            let elapsed = try XCTUnwrap(f[.elapsed]), track = try XCTUnwrap(f[.progress]), remaining = try XCTUnwrap(f[.remaining])
            let controls = try XCTUnwrap(f[.controls])
            XCTAssertEqual(art.minX, MediaStandardLayout.horizontalPadding, accuracy: 0.01, "artwork left")
            XCTAssertGreaterThan(title.minX, art.maxX, "title right of the artwork")
            XCTAssertEqual(artist.minX, title.minX, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(artist.minY, title.maxY - 0.01, "artist under title")
            XCTAssertEqual(viz.maxX, cell.width - MediaStandardLayout.horizontalPadding, accuracy: 0.01, "visualizer upper right")
            XCTAssertLessThan(viz.midY, track.minY)
            XCTAssertLessThanOrEqual(title.maxX, viz.minX, "title never runs under the visualizer")
            XCTAssertGreaterThanOrEqual(track.minY, art.maxY - 0.01, "progress below the top row")
            XCTAssertLessThan(elapsed.maxX, track.minX); XCTAssertLessThan(track.maxX, remaining.minX)
            XCTAssertEqual(elapsed.minX, MediaStandardLayout.horizontalPadding, accuracy: 0.01)
            XCTAssertEqual(remaining.maxX, cell.width - MediaStandardLayout.horizontalPadding, accuracy: 0.01, "progress spans the card")
            XCTAssertGreaterThanOrEqual(controls.minY, track.maxY - 0.01, "controls at the bottom")
            XCTAssertEqual(controls.midX, cell.width / 2, accuracy: 0.5)
            let bounds = CGRect(origin: .zero, size: cell).insetBy(dx: -0.01, dy: -0.01)
            let list = Array(f.values)
            for (i, a) in list.enumerated() {
                XCTAssertTrue(bounds.contains(a), "\(cell): \(a) clips")
                for b in list.dropFirst(i + 1) { XCTAssertFalse(a.insetBy(dx: 0.01, dy: 0.01).intersects(b.insetBy(dx: 0.01, dy: 0.01))) }
            }
        }
    }

    func testMissingArtworkAndProgressStayBalanced() throws {
        let cell = CGSize(width: 305, height: 149)
        let noArt = MediaStandardLayout.make(cell: cell, content: .init(artwork: false))
        XCTAssertNil(noArt.frames[.artwork])
        XCTAssertEqual(noArt.frames[.title]?.minX ?? 0, MediaStandardLayout.horizontalPadding, accuracy: 0.01)
        let noProgress = MediaStandardLayout.make(cell: cell, content: .init(progress: false))
        XCTAssertNil(noProgress.frames[.progress])
        XCTAssertNotNil(noProgress.frames[.controls])
    }
}

/// Advanced Now Playing controls: capability model, mode machine, row.
final class MediaAdvancedControlTests: XCTestCase {
    func testControlRowOrderMatchesTheReferenceAndCentersPlay() {
        XCTAssertEqual(MediaControlSlot.standardOrder, [.queue, .favorite, .previous, .playPause, .next, .mode, .output])
        for metrics in [MediaControlRowMetrics.standard, .large] {
            let width: CGFloat = 281
            let centers = metrics.centers(width: width)
            XCTAssertEqual(centers[3], width / 2, accuracy: 0.01, "Play/Pause sits on the row's center")
            XCTAssertGreaterThan(metrics.play, metrics.transport)
            XCTAssertGreaterThan(metrics.transport, metrics.secondary)
            XCTAssertEqual(centers, centers.sorted())
        }
    }

    func testCapabilitiesReflectRealBackendsOnly() {
        let spotifyAuthed = MediaControlCapabilities.resolve(source: .spotify, spotifyConnected: true, hasOutputDevices: true)
        XCTAssertEqual(spotifyAuthed.queue, .supported); XCTAssertEqual(spotifyAuthed.favorite, .supported)
        XCTAssertTrue(spotifyAuthed.supportsRepeatOne)
        let spotify = MediaControlCapabilities.resolve(source: .spotify, spotifyConnected: false, hasOutputDevices: true)
        XCTAssertEqual(spotify.queue, .authRequired); XCTAssertEqual(spotify.favorite, .authRequired)
        XCTAssertEqual(spotify.playbackMode, .supported, "AppleScript shuffle/repeat works without auth")
        XCTAssertFalse(spotify.supportsRepeatOne, "repeat-one needs the Web API")
        let music = MediaControlCapabilities.resolve(source: .music, spotifyConnected: false, hasOutputDevices: true)
        XCTAssertEqual(music.queue, .unsupported, "Music has no queue API")
        XCTAssertEqual(music.favorite, .supported); XCTAssertTrue(music.supportsRepeatOne)
        for source in [MediaSourceKind.system, .browser, .unknown] {
            let value = MediaControlCapabilities.resolve(source: source, spotifyConnected: true, hasOutputDevices: true)
            XCTAssertEqual(value.queue, .unsupported); XCTAssertEqual(value.favorite, .unsupported)
            XCTAssertEqual(value.playbackMode, .unsupported); XCTAssertEqual(value.output, .supported)
        }
        XCTAssertEqual(MediaControlCapabilities.resolve(source: .music, spotifyConnected: false, hasOutputDevices: false).output, .unsupported)
        XCTAssertNotNil(MediaControlCapabilities.reason(.unsupported, source: "Safari"))
        XCTAssertNil(MediaControlCapabilities.reason(.supported, source: "Music"))
    }

    func testModeCycleAndIcons() {
        var mode = MediaPlaybackModeState()
        XCTAssertEqual(mode.symbol, "shuffle"); XCTAssertFalse(mode.isActive)
        mode = mode.next(supportsRepeatOne: true); XCTAssertEqual(mode, .init(shuffle: true, repeatMode: .off))
        XCTAssertEqual(mode.symbol, "shuffle"); XCTAssertTrue(mode.isActive)
        mode = mode.next(supportsRepeatOne: true); XCTAssertEqual(mode, .init(shuffle: false, repeatMode: .all))
        XCTAssertEqual(mode.symbol, "repeat")
        mode = mode.next(supportsRepeatOne: true); XCTAssertEqual(mode.symbol, "repeat.1")
        mode = mode.next(supportsRepeatOne: true); XCTAssertEqual(mode, MediaPlaybackModeState())
        XCTAssertEqual(MediaPlaybackModeState(shuffle: false, repeatMode: .all).next(supportsRepeatOne: false), MediaPlaybackModeState(),
                       "no repeat-one step where the provider cannot do it")
        XCTAssertEqual(MediaPlaybackModeState(shuffle: true, repeatMode: .all).accessibilityValue, "Shuffle and repeat all",
                       "independent provider states are never collapsed")
    }

    func testRemainingTimeIsNegativeAndClamped() {
        XCTAssertEqual(MediaAdvancedController.remainingLabel(position: 1, duration: 197), "-3:16")
        XCTAssertEqual(MediaAdvancedController.remainingLabel(position: 300, duration: 197), "-0:00")
        XCTAssertEqual(MediaAdvancedController.remainingLabel(position: .nan, duration: 61), "-1:01")
    }

    func testSpotifyPlaybackStateParsingAndRepeatMapping() throws {
        let json = #"{"shuffle_state":true,"repeat_state":"track","item":{"uri":"spotify:track:abc"}}"#
        let state = try XCTUnwrap(SpotifyPlaybackState.parse(Data(json.utf8)))
        XCTAssertTrue(state.shuffle); XCTAssertEqual(state.repeatState, .track); XCTAssertEqual(state.itemURI, "spotify:track:abc")
        XCTAssertNil(SpotifyPlaybackState.parse(Data("{}".utf8)), "no active device")
        for mode in MediaRepeatMode.allCases {
            XCTAssertEqual(MediaAdvancedController.mode(MediaAdvancedController.spotifyRepeat(mode)), mode)
        }
        XCTAssertTrue(MediaAdvancedController.parseFlags("true||false\n")! == (true, false))
    }
}
