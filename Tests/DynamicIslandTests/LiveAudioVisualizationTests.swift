import AppKit
import Combine
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Counts backend calls; frames are published only when a test asks.
private final class CountingBackend: AudioSpectrumCaptureBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _starts = 0, _stops = 0
    let mailbox = AudioSpectrumMailbox()
    var starts: Int { lock.withLock { _starts } }
    var stops: Int { lock.withLock { _stops } }
    func start(generation: UInt64) async throws -> AudioSpectrumMailbox { lock.withLock { _starts += 1 }; return mailbox }
    func stop(generation: UInt64) async throws { lock.withLock { _stops += 1 } }
}

private func frame(_ bands: SIMD8<Float>, signal: Bool = true, sequence: UInt64 = 1) -> AudioSpectrumFrame {
    AudioSpectrumFrame(sequence: sequence, hostTime: sequence, sampleRate: 48_000, bands: bands, rms: 0.3, peak: 0.6, hasSignal: signal)
}

@MainActor
final class LiveAudioVisualizationTests: XCTestCase {
    // MARK: Binding

    func testEightBarsFollowTheEightBandsExactly() {
        let bands = SIMD8<Float>(0, 0.1, 0.2, 0.4, 0.5, 0.7, 0.9, 1)
        let levels = SpectrumBarMapper.levels(bands: bands, barCount: 8)
        for index in 0..<8 {
            XCTAssertEqual(levels[index], SpectrumBarMapper.floor + (SpectrumBarMapper.cap - SpectrumBarMapper.floor) * CGFloat(bands[index]), accuracy: 1e-5)
        }
    }

    func testOtherBarCountsInterpolateAndNeverRepeatAPattern() {
        let bands = SIMD8<Float>(0.9, 0.1, 0.8, 0.2, 0.7, 0.3, 0.6, 0.4)
        let seven = SpectrumBarMapper.levels(bands: bands, barCount: 7)
        XCTAssertEqual(seven.count, 7)
        XCTAssertEqual(seven.first!, SpectrumBarMapper.levels(bands: bands, barCount: 8).first!, accuracy: 1e-5)
        XCTAssertEqual(seven.last!, SpectrumBarMapper.levels(bands: bands, barCount: 8).last!, accuracy: 1e-5)
        XCTAssertGreaterThan(Set(seven.map { ($0 * 1000).rounded() }).count, 4, "bars move independently")
    }

    func testInvalidBandsClampToTheFloorAndRange() {
        let levels = SpectrumBarMapper.levels(bands: SIMD8<Float>(.nan, -1, 4, .infinity, 0, 0, 0, 0), barCount: 8)
        XCTAssertEqual(levels[0], SpectrumBarMapper.floor)
        XCTAssertEqual(levels[1], SpectrumBarMapper.floor)
        XCTAssertEqual(levels[2], SpectrumBarMapper.cap)
        XCTAssertEqual(levels[3], SpectrumBarMapper.floor)
        XCTAssertTrue(levels.allSatisfy { $0 >= SpectrumBarMapper.floor && $0 <= SpectrumBarMapper.cap })
    }

    // MARK: Droppy band dynamics

    func testAutoGainLetsAQuietMixUseItsFullRangeLikeDroppy() {
        var dynamics = SpectrumDynamics()
        // A quiet, compressed mix whose bands never exceed 0.5 still reaches the top.
        for _ in 0..<20 { _ = dynamics.advance(raw: SIMD8<Float>(repeating: 0.5)) }
        XCTAssertEqual(Double(dynamics.advance(raw: SIMD8<Float>(repeating: 0.5))[0]), 1, accuracy: 0.01)
        // The same band at half its recent peak sits near half height, so it moves with the music.
        var dip = SIMD8<Float>.zero
        for _ in 0..<12 { dip = dynamics.advance(raw: SIMD8<Float>(repeating: 0.25)) }
        XCTAssertEqual(Double(dip[0]), 0.5, accuracy: 0.03)
        // Below the 0.35 floor nothing is boosted to full scale.
        var faint = SpectrumDynamics()
        for _ in 0..<20 { _ = faint.advance(raw: SIMD8<Float>(repeating: 0.07)) }
        XCTAssertEqual(Double(faint.advance(raw: SIMD8<Float>(repeating: 0.07))[0]), 0.2, accuracy: 0.02)
    }

    func testFastAttackSlowReleaseAndBeatsPunch() {
        var dynamics = SpectrumDynamics()
        dynamics.tick(raw: SIMD8<Float>(repeating: 0.3))
        XCTAssertGreaterThan(dynamics.published[0], dynamics.smoothed[0], "a rising edge is boosted above the smoothed level")
        dynamics = SpectrumDynamics()
        _ = dynamics.advance(raw: SIMD8<Float>(repeating: 0.6))
        let rise = dynamics.smoothed[0]
        for _ in 0..<10 { _ = dynamics.advance(raw: SIMD8<Float>(repeating: 0.6)) }
        _ = dynamics.advance(raw: SIMD8<Float>(repeating: 0.3))
        let fall = 1 - dynamics.smoothed[0]
        XCTAssertGreaterThan(rise, fall, "rising moves further per frame than falling")
        XCTAssertEqual(dynamics.published[0], dynamics.smoothed[0], accuracy: 1e-9, "falling is never boosted")
    }

    func testSilenceSnapsToZeroAndInvalidBandsAreSilent() {
        var dynamics = SpectrumDynamics()
        _ = dynamics.advance(raw: SIMD8<Float>(repeating: 0.8))
        var out = SIMD8<Float>(repeating: 1)
        for _ in 0..<30 { out = dynamics.advance(raw: .zero) }
        XCTAssertEqual(out, .zero, "silence settles exactly to zero")
        var invalid = SpectrumDynamics()
        XCTAssertEqual(invalid.advance(raw: SIMD8<Float>(.nan, .infinity, -1, 0, 0, 0, 0, 0)), .zero)
    }

    func testOneFrameRunsTwoDroppyTicks() {
        var frame = SpectrumDynamics(), ticks = SpectrumDynamics()
        _ = frame.advance(raw: SIMD8<Float>(repeating: 0.5))
        ticks.tick(raw: SIMD8<Float>(repeating: 0.5)); ticks.tick(raw: SIMD8<Float>(repeating: 0.5))
        XCTAssertEqual(frame, ticks)
    }

    // MARK: Drive mode: playback authority stays with MediaController

    func testLiveOnlyWhileCapturingAndMediaPlays() {
        var capturing = AudioSpectrumPresentation(availability: .capturing, permission: .accessEstablished,
                                                  playbackEvidence: .signalPresent, frame: frame(.one))
        XCTAssertEqual(LiveVisualizerMode.resolve(isMediaPalette: true, presentation: capturing, mediaPlaying: true, reduceMotion: false), .live)
        XCTAssertEqual(LiveVisualizerMode.resolve(isMediaPalette: true, presentation: capturing, mediaPlaying: false, reduceMotion: false),
                       .decorative, "other apps' audio never animates a paused track")
        capturing.frame = frame(.zero, signal: false)
        XCTAssertEqual(LiveVisualizerMode.resolve(isMediaPalette: true, presentation: capturing, mediaPlaying: true, reduceMotion: false),
                       .liveSilent, "silence lowers the bars; it never means paused")
        XCTAssertEqual(LiveVisualizerMode.resolve(isMediaPalette: false, presentation: capturing, mediaPlaying: true, reduceMotion: false),
                       .decorative, "call visualizers are never system-mix measurements")
        for availability: AudioCaptureAvailability in [.disabled, .starting, .suspended, .failed(.noFrames)] {
            XCTAssertEqual(LiveVisualizerMode.resolve(isMediaPalette: true, presentation: .init(availability: availability, frame: frame(.one)),
                                                      mediaPlaying: true, reduceMotion: false), .decorative)
        }
        XCTAssertEqual(LiveVisualizerMode.resolve(isMediaPalette: true, presentation: .init(availability: .capturing), mediaPlaying: true, reduceMotion: false),
                       .decorative, "capturing without a frame is not live")
    }

    func testReduceMotionStopsLiveAndDecorativeMotionAndIsLabelled() {
        let capturing = AudioSpectrumPresentation(availability: .capturing, frame: frame(.one))
        XCTAssertEqual(LiveVisualizerMode.resolve(isMediaPalette: true, presentation: capturing, mediaPlaying: true, reduceMotion: true), .still)
        XCTAssertFalse(LiveVisualizerMode.still.isLive)
        XCTAssertTrue(LiveVisualizerMode.decorative.accessibilityDescription.contains("not measuring audio"))
        XCTAssertTrue(LiveVisualizerMode.live.accessibilityDescription.hasPrefix("Live"))
    }

    // MARK: Permission and status

    func testStatusReflectsOnlyWhatTheControllerObserved() {
        XCTAssertEqual(LiveAudioStatus(.init()).isOn, false)
        XCTAssertTrue(LiveAudioStatus(.init()).detail.contains("decorative"))
        XCTAssertTrue(LiveAudioStatus(.init(availability: .starting)).isOn)
        XCTAssertEqual(LiveAudioStatus(.init(availability: .capturing, permission: .accessEstablished, playbackEvidence: .signalPresent, frame: frame(.one))).detail, "Live · system audio")
        XCTAssertEqual(LiveAudioStatus(.init(availability: .capturing, permission: .accessEstablished, playbackEvidence: .silent)).detail, "Live · system audio silent")
        XCTAssertEqual(LiveAudioStatus(.init(availability: .capturing, playbackEvidence: .silent)).detail, "Audio buffers received · no signal verified",
                       "silent buffers alone do not prove authorization or actual system silence")
        let denied = LiveAudioStatus(.init(availability: .failed(.permissionDenied), permission: .denied))
        XCTAssertFalse(denied.isOn); XCTAssertTrue(denied.offersPrivacySettings)
        XCTAssertFalse(LiveAudioStatus(.init(availability: .failed(.noFrames))).offersPrivacySettings,
                       "no frames is not evidence of denied permission")
        XCTAssertFalse(LiveAudioStatus(.init(availability: .suspended)).isOn, "sleep/lock never resumes by itself")
    }

    // MARK: Lifecycle: only the explicit switch starts capture

    func testCreationSubscriptionAndMenuRenderingNeverStartCapture() async throws {
        let backend = CountingBackend()
        let controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
        var received: [AudioSpectrumPresentation] = []
        let subscription = controller.presentationPublisher.sink { received.append($0) }
        defer { subscription.cancel() }
        _ = LiveAudioMenuItems(provider: controller, status: LiveAudioStatus(controller.presentation)).body
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(backend.starts, 0)
        XCTAssertEqual(controller.presentation.availability, .disabled)
        XCTAssertFalse(received.isEmpty)
    }

    func testSwitchStartsOnceAndOffTearsDownAndClearsTheFrame() async throws {
        let backend = CountingBackend()
        let controller = AudioSpectrumController(backend: backend, observeSystemEvents: false)
        let menu = LiveAudioMenuItems(provider: controller, status: LiveAudioStatus(controller.presentation))
        menu.provider.startFromUserAction()
        menu.provider.startFromUserAction() // a double click must not start twice
        backend.mailbox.publish(frame(SIMD8<Float>(repeating: 0.5)))
        for _ in 0..<100 where controller.presentation.availability != .capturing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(backend.starts, 1)
        XCTAssertEqual(controller.presentation.availability, .capturing)
        XCTAssertEqual(LiveAudioStatus(controller.presentation).isOn, true)
        controller.stop()
        XCTAssertEqual(controller.presentation.availability, .disabled)
        XCTAssertNil(controller.presentation.frame, "a disabled widget never keeps painting the last frame")
        backend.mailbox.publish(frame(.one, sequence: 9))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(controller.presentation.availability, .disabled, "late frames cannot relight the bars")
        XCTAssertGreaterThanOrEqual(backend.stops, 1)
        await controller.shutdown()
    }

    // MARK: Gradient and hover

    func testGradientRunsFromPrimaryToSecondaryThroughABlendedCenter() throws {
        let primary = Color(red: 1, green: 0, blue: 0), secondary = Color(red: 0, green: 0, blue: 1)
        func rgb(_ c: Color) -> (CGFloat, CGFloat, CGFloat) {
            let n = NSColor(c).usingColorSpace(.sRGB)!
            return (n.redComponent, n.greenComponent, n.blueComponent)
        }
        XCTAssertEqual(rgb(VisualizerGradient.color(at: 0, count: 7, primary: primary, secondary: secondary)).0, 1, accuracy: 0.01)
        XCTAssertEqual(rgb(VisualizerGradient.color(at: 6, count: 7, primary: primary, secondary: secondary)).2, 1, accuracy: 0.01)
        let middle = rgb(VisualizerGradient.color(at: 3, count: 7, primary: primary, secondary: secondary))
        XCTAssertEqual(middle.0, 0.5, accuracy: 0.02); XCTAssertEqual(middle.2, 0.5, accuracy: 0.02)
        XCTAssertEqual(rgb(VisualizerGradient.color(at: 4, count: 7, primary: primary, secondary: nil)).0, 1, accuracy: 0.01, "no artwork partner: solid")
    }

    func testSecondaryColorHandlesGrayscaleSimilarAndDistinctArtwork() throws {
        let grid = 4
        func samples(_ left: (Double, Double, Double), _ right: (Double, Double, Double)) -> [ArtworkColorSample] {
            (0..<(grid * grid)).map { i in
                let c = i % grid < grid / 2 ? left : right
                return ArtworkColorSample(red: c.0, green: c.1, blue: c.2, alpha: 1)
            }
        }
        let gray = NSColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        let tonal = try XCTUnwrap(ArtworkAccentColorExtractor.secondaryColor(from: samples((0.6, 0.6, 0.6), (0.6, 0.6, 0.6)), gridSize: grid, primary: gray))
        XCTAssertLessThan(tonal.usingColorSpace(.sRGB)!.saturationComponent, 0.01, "grayscale art never gets an invented hue")

        let red = NSColor(srgbRed: 0.9, green: 0.15, blue: 0.15, alpha: 1)
        let blueHalf = try XCTUnwrap(ArtworkAccentColorExtractor.secondaryColor(from: samples((0.9, 0.15, 0.15), (0.15, 0.2, 0.9)), gridSize: grid, primary: red))
        XCTAssertGreaterThan(blueHalf.usingColorSpace(.sRGB)!.blueComponent, 0.7)

        let shifted = try XCTUnwrap(ArtworkAccentColorExtractor.secondaryColor(from: samples((0.9, 0.15, 0.15), (0.88, 0.16, 0.15)), gridSize: grid, primary: red))
        XCTAssertGreaterThan(abs(shifted.usingColorSpace(.sRGB)!.hueComponent - red.usingColorSpace(.sRGB)!.hueComponent), 0.05,
                             "near-identical halves get a visible, hue-shifted partner")
    }

    func testHoverGlyphNamesTheActionForTheObservedState() {
        XCTAssertEqual(CollapsedVisualizerPlaybackControl<EmptyView>.glyph(isPlaying: true), "pause.fill")
        XCTAssertEqual(CollapsedVisualizerPlaybackControl<EmptyView>.glyph(isPlaying: false), "play.fill")
    }
}
