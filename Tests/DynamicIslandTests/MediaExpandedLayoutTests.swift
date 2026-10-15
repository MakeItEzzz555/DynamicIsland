import XCTest
@testable import DynamicIsland

/// Standard and Large Media share one composition: `MediaExpandedLayout` is
/// the exact geometry the view draws, scaled from the allocated cell.
final class MediaExpandedLayoutTests: XCTestCase {
    private typealias Slot = MediaExpandedLayout.Slot
    private let grid = WidgetGridMetrics.make(surface: .media, metrics: .fallback)
    /// Island (fallback), the measured 0.918 display scale, and the Agents unit.
    private var cells: [(WidgetPresentationSize, CGSize)] {
        let agents = WidgetGridMetrics.make(surface: .agents, metrics: .fallback)
        return [(.standard, grid.size(for: .standard)), (.large, grid.size(for: .large)),
                (.standard, CGSize(width: grid.size(for: .standard).width * 0.918, height: grid.size(for: .standard).height * 0.918)),
                (.large, CGSize(width: grid.size(for: .large).width * 0.918, height: grid.size(for: .large).height * 0.918)),
                (.standard, agents.size(for: .standard)), (.large, agents.size(for: .large))]
    }

    func testCompositionOrderIsArtworkTitleArtistProviderControlsScrubber() throws {
        for (size, cell) in cells {
            let f = MediaExpandedLayout.make(cell: cell, content: .init(volume: true)).frames
            let order: [Slot] = [.artwork, .title, .artist, .provider, .controls, .progress]
            for (upper, lower) in zip(order, order.dropFirst()) {
                let a = try XCTUnwrap(f[upper]), b = try XCTUnwrap(f[lower])
                XCTAssertLessThanOrEqual(a.maxY, b.minY + 0.01, "\(size) \(cell): \(upper) above \(lower)")
            }
            for slot in [Slot.artwork, .title, .artist, .provider, .controls, .progress] {
                XCTAssertEqual(try XCTUnwrap(f[slot]).midX, cell.width / 2, accuracy: 0.01, "\(size) \(slot) is centered")
            }
            let elapsed = try XCTUnwrap(f[.elapsed]), track = try XCTUnwrap(f[.progress]), remaining = try XCTUnwrap(f[.remaining])
            XCTAssertLessThan(elapsed.maxX, track.minX + 0.01)
            XCTAssertLessThan(track.maxX, remaining.minX + 0.01)
            XCTAssertEqual(elapsed.minY, track.minY, accuracy: 0.01, "times sit on the scrubber row")
        }
    }

    func testNothingOverlapsOrClipsAtEitherSize() {
        for contents in [MediaExpandedLayout.Content(), .init(volume: true), .init(artwork: false), .init(provider: false, progress: false),
                         .init(title: false, artist: false)] {
            for attached in [false, true] {
                for (size, cell) in cells {
                    let f = MediaExpandedLayout.make(cell: cell, content: contents, topAttached: attached).frames
                    let bounds = CGRect(origin: .zero, size: cell).insetBy(dx: -0.01, dy: -0.01)
                    let list = Array(f.values)
                    for (i, a) in list.enumerated() {
                        XCTAssertTrue(bounds.contains(a), "\(size) \(cell) \(contents): \(a) clips")
                        for b in list.dropFirst(i + 1) {
                            XCTAssertFalse(a.insetBy(dx: 0.01, dy: 0.01).intersects(b.insetBy(dx: 0.01, dy: 0.01)), "\(size) \(cell): \(a) overlaps \(b)")
                        }
                    }
                }
            }
        }
    }

    func testLargeIsTheSameCompositionAtALargerScale() throws {
        let standard = MediaExpandedLayout.make(cell: grid.size(for: .standard), content: .init())
        let large = MediaExpandedLayout.make(cell: grid.size(for: .large), content: .init())
        XCTAssertGreaterThan(large.scale, standard.scale)
        XCTAssertGreaterThan(large.titleFont, standard.titleFont)
        XCTAssertGreaterThan(large.controls.play, standard.controls.play)
        XCTAssertGreaterThan(large.artworkSide, standard.artworkSide * 2, "Large leads with a much bigger cover")
        XCTAssertEqual(Set(standard.frames.keys), Set(large.frames.keys), "same elements at both sizes")
        XCTAssertLessThanOrEqual(large.scale, MediaExpandedLayout.maximumScale)
    }

    func testStandardKeepsReadableTypeAndAHeroCover() {
        for (size, cell) in cells where size == .standard {
            let plan = MediaExpandedLayout.make(cell: cell, content: .init())
            XCTAssertGreaterThanOrEqual(plan.titleFont, 13, "\(cell)")
            XCTAssertGreaterThanOrEqual(plan.timeFont, 8.3)
            XCTAssertGreaterThanOrEqual(plan.artworkSide, 44, "\(cell): the cover is the first thing read")
            XCTAssertGreaterThanOrEqual(plan.controls.secondary, 17, "hit targets stay usable")
        }
    }

    func testPlayPauseIsTheStrongestControlAndCenteredInItsFrame() throws {
        for (_, cell) in cells {
            let plan = MediaExpandedLayout.make(cell: cell, content: .init())
            let controls = try XCTUnwrap(plan.frames[.controls])
            XCTAssertEqual(controls.height, plan.controls.play, accuracy: 0.01)
            XCTAssertGreaterThan(plan.controls.play, plan.controls.transport)
            XCTAssertGreaterThan(plan.controls.transport, plan.controls.secondary)
            XCTAssertEqual(plan.controls.centers(width: controls.width, slots: MediaControlSlot.expandedOrder)[2], controls.width / 2, accuracy: 0.01)
            XCTAssertEqual(controls.midX, cell.width / 2, accuracy: 0.01)
        }
    }

    func testVolumeOnlyAppearsWhenTheCoverStaysAHero() {
        let standard = MediaExpandedLayout.make(cell: grid.size(for: .standard), content: .init(volume: true))
        XCTAssertNil(standard.frames[.volume], "Standard drops volume rather than shrinking the cover")
        let large = MediaExpandedLayout.make(cell: grid.size(for: .large), content: .init(volume: true))
        XCTAssertNotNil(large.frames[.volume])
        XCTAssertGreaterThanOrEqual(large.artworkSide, MediaExpandedLayout.volumeArtworkFloor)
    }

    func testTopAttachmentChangesOnlyVerticalOrigins() {
        for (_, cell) in cells {
            let before = MediaExpandedLayout.make(cell: cell, content: .init())
            let after = MediaExpandedLayout.make(cell: cell, content: .init(), topAttached: true)
            XCTAssertEqual(before.artworkSide, after.artworkSide, accuracy: 0.01)
            XCTAssertEqual(before.frames.mapValues(\.width), after.frames.mapValues(\.width))
            XCTAssertEqual(after.frames.values.map(\.minY).min() ?? -1, 0, accuracy: 0.01)
        }
    }

    func testPlanIsPureAndSurvivesDegenerateCells() {
        let cell = grid.size(for: .large)
        XCTAssertEqual(MediaExpandedLayout.make(cell: cell, content: .init()), MediaExpandedLayout.make(cell: cell, content: .init()))
        for bad in [CGSize.zero, CGSize(width: CGFloat.nan, height: 100), CGSize(width: 100, height: CGFloat.infinity), CGSize(width: 40, height: 40)] {
            let plan = MediaExpandedLayout.make(cell: bad, content: .init())
            XCTAssertTrue(plan.frames.values.allSatisfy { $0.minX.isFinite && $0.minY.isFinite && $0.width >= 0 && $0.height >= 0 })
            XCTAssertGreaterThanOrEqual(plan.scale, MediaExpandedLayout.emergencyScale - 0.0001)
        }
    }

    func testMediaOffersOnlyStandardAndLargeAndMigratesSavedCompact() throws {
        XCTAssertEqual(WidgetPresentationSize.supported(for: .media), [.standard, .large])
        XCTAssertEqual(WidgetPresentationSize.supported(for: .timer), WidgetPresentationSize.allCases)
        var value = WorkspaceConfiguration.initial
        let mediaID = try XCTUnwrap(value.placement(kind: .media, on: .media)).id
        if value.placement(kind: .timer, on: .media) == nil { value.add(.timer, on: .media) }
        let timerID = try XCTUnwrap(value.placement(kind: .timer, on: .media)).id
        value.setSize(.compact, for: timerID)
        // A saved Compact Media (hand-edited or from an older build) round-trips as Standard.
        var data = try JSONEncoder().encode(value)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var placements = try XCTUnwrap(json["placements"] as? [[String: Any]])
        for index in placements.indices where placements[index]["kind"] as? String == "media" { placements[index]["size"] = "compact" }
        json["placements"] = placements
        data = try JSONSerialization.data(withJSONObject: json)
        let migrated = WorkspaceConfiguration.decoded(data)
        XCTAssertEqual(migrated.placement(kind: .media, on: .media)?.size, .standard)
        XCTAssertEqual(migrated.placement(kind: .timer, on: .media)?.size, .compact, "other widgets keep their size")
        // Large survives, and the editor path cannot reintroduce Compact.
        var edited = migrated
        edited.setSize(.large, for: mediaID)
        XCTAssertEqual(edited.placement(kind: .media, on: .media)?.size, .large)
        edited.setSize(.compact, for: mediaID)
        XCTAssertEqual(edited.placement(kind: .media, on: .media)?.size, .standard)
        let region = try XCTUnwrap(edited.regions(on: .media).first { $0.widgets.first?.kind == .media })
        XCTAssertEqual(region.supportedSizes, [.standard, .large])
    }
}

/// Advanced Now Playing controls: capability model, mode machine, row.
final class MediaAdvancedControlTests: XCTestCase {
    func testControlRowOrderMatchesTheReferenceAndCentersPlay() {
        XCTAssertEqual(MediaControlSlot.standardOrder, [.queue, .favorite, .previous, .playPause, .next, .mode, .output])
        XCTAssertEqual(MediaControlSlot.expandedOrder, [.favorite, .previous, .playPause, .next, .output])
        for scale in [CGFloat(0.92), 1.4] {
            let metrics = MediaExpandedLayout.controls.scaled(by: scale)
            let width: CGFloat = 281
            let centers = metrics.centers(width: width)
            XCTAssertEqual(centers[3], width / 2, accuracy: 0.01, "Play/Pause sits on the row's center")
            let expanded = metrics.centers(width: width, slots: MediaControlSlot.expandedOrder)
            XCTAssertEqual(expanded[2], width / 2, accuracy: 0.01, "expanded row centers Play/Pause too")
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
