import AppKit
import Combine
import SwiftUI

/// How a media visualizer is driven right now. Live data is used only while
/// capture reports frames *and* MediaController says media is playing:
/// audio silence never decides playback, and other apps' audio never makes
/// a paused track look like it is playing.
enum LiveVisualizerMode: Equatable {
    /// Real spectrum bands with signal.
    case live
    /// Capturing, media playing, but the captured mix is silent: low bars.
    case liveSilent
    /// Not capturing (off, starting, suspended, failed): the labelled
    /// decorative animation, never presented as measurement.
    case decorative
    /// Reduce Motion: no continuous bar motion, live or decorative.
    case still

    static func resolve(isMediaPalette: Bool, presentation: AudioSpectrumPresentation,
                        mediaPlaying: Bool, reduceMotion: Bool) -> Self {
        if reduceMotion { return .still }
        guard isMediaPalette, mediaPlaying, presentation.availability == .capturing,
              let frame = presentation.frame else { return .decorative }
        return frame.hasSignal ? .live : .liveSilent
    }

    var isLive: Bool { self == .live || self == .liveSilent }

    var accessibilityDescription: String {
        switch self {
        case .live: "Live audio levels"
        case .liveSilent: "Live audio levels, silent"
        case .decorative: "Decorative animation, not measuring audio"
        case .still: "Visualizer paused for Reduce Motion"
        }
    }
}

/// Maps the eight ascending log-spaced bands onto any bar count by linear
/// interpolation, so every bar follows real frequency content (no repeats).
enum SpectrumBarMapper {
    static let floor: CGFloat = 0.12
    /// Droppy clamps live bar scale to at most 0.9 of the bar height.
    static let cap: CGFloat = 0.9

    static func levels(bands: SIMD8<Float>, barCount: Int) -> [CGFloat] {
        guard barCount > 0 else { return [] }
        let values = (0..<8).map { CGFloat(min(max(bands[$0].isFinite ? bands[$0] : 0, 0), 1)) }
        return (0..<barCount).map { index in
            let position = barCount == 1 ? 0 : CGFloat(index) / CGFloat(barCount - 1) * 7
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, 7)
            let t = position - CGFloat(lower)
            let value = values[lower] + (values[upper] - values[lower]) * t
            return floor + (cap - floor) * value
        }
    }

    static func silent(barCount: Int) -> [CGFloat] { Array(repeating: floor, count: max(barCount, 0)) }
}

/// Droppy 16.0.1's per-band analyzer tick, reverse-engineered constants
/// (reports/DROPPY_16_VISUALIZER_RE_2026-10-14.md), applied as a
/// presentation stage on Codex's bands (its DSP stays untouched):
/// - peak-tracking auto-gain, so every band uses its full range for any
///   loudness/mastering (the reason Droppy's bars follow the music);
/// - asymmetric smoothing, fast attack and slow release;
/// - silence snap to zero, and a rising-edge boost so beats punch.
/// Droppy ticks at 60 Hz; our frames arrive at ~30 Hz, so each frame runs
/// two ticks.
struct SpectrumDynamics: Equatable {
    static let peakDecay = 0.9985
    static let agcFloor = 0.35
    static let attack = 0.85
    static let release = 0.28
    static let silenceSnap = 0.004
    static let transientBoost = 0.45
    static let ticksPerFrame = 2

    private(set) var peaks = [Double](repeating: 0, count: 8)
    private(set) var smoothed = [Double](repeating: 0, count: 8)
    private(set) var published = [Double](repeating: 0, count: 8)

    /// One Droppy analyzer tick for every band.
    mutating func tick(raw: SIMD8<Float>) {
        for band in 0..<8 {
            let value = raw[band].isFinite ? max(0, Double(raw[band])) : 0
            peaks[band] = max(value, peaks[band] * Self.peakDecay)
            let normalized = min(value / max(peaks[band], Self.agcFloor), 1)
            var next = smoothed[band] + (normalized - smoothed[band]) * (normalized > smoothed[band] ? Self.attack : Self.release)
            if next < Self.silenceSnap, normalized == 0 { next = 0 }
            next = min(max(next, 0), 1)
            published[band] = min(1, next + max(0, next - published[band]) * Self.transientBoost)
            smoothed[band] = next
        }
    }

    /// Advances one ~30 Hz frame and returns the shaped bands.
    mutating func advance(raw: SIMD8<Float>) -> SIMD8<Float> {
        for _ in 0..<Self.ticksPerFrame { tick(raw: raw) }
        var out = SIMD8<Float>.zero
        for band in 0..<8 { out[band] = Float(published[band]) }
        return out
    }
}

/// User-facing Live Audio state, derived only from the controller.
struct LiveAudioStatus: Equatable {
    let isOn: Bool
    let detail: String
    /// System Settings deep link offered only after an explicit access error.
    let offersPrivacySettings: Bool

    init(_ presentation: AudioSpectrumPresentation) {
        switch presentation.availability {
        case .disabled:
            isOn = false; detail = "Off · bars are decorative"; offersPrivacySettings = false
        case .starting:
            isOn = true; detail = "Starting…"; offersPrivacySettings = false
        case .capturing:
            isOn = true
            detail = presentation.permission == .accessEstablished
                ? (presentation.playbackEvidence == .signalPresent ? "Live · system audio" : "Live · system audio silent")
                : "Audio buffers received · no signal verified"
            offersPrivacySettings = false
        case .suspended:
            isOn = false; detail = "Paused after sleep, session or audio-output change · turn on again"; offersPrivacySettings = false
        case .failed(.permissionDenied):
            isOn = false; detail = "System Audio Recording is off for DynamicIsland"; offersPrivacySettings = true
        case .failed(.unsupportedPlatform):
            isOn = false; detail = "Needs macOS 14.2 or later"; offersPrivacySettings = false
        case .failed(.noFrames):
            isOn = false; detail = "No audio frames arrived · try again"; offersPrivacySettings = false
        case .failed:
            isOn = false; detail = "Couldn’t start live audio"; offersPrivacySettings = false
        }
    }
}

/// Two-color bar gradient: index 0 is the primary color, the last bar the
/// secondary; bars in between blend smoothly through the center.
enum VisualizerGradient {
    static func color(at index: Int, count: Int, primary: Color, secondary: Color?) -> Color {
        guard let secondary, count > 1 else { return primary }
        let fraction = CGFloat(index) / CGFloat(count - 1)
        let from = NSColor(primary).usingColorSpace(.sRGB) ?? .white
        let to = NSColor(secondary).usingColorSpace(.sRGB) ?? .white
        func mix(_ a: CGFloat, _ b: CGFloat) -> Double { Double(a + (b - a) * fraction) }
        return Color(.sRGB, red: mix(from.redComponent, to.redComponent), green: mix(from.greenComponent, to.greenComponent),
                     blue: mix(from.blueComponent, to.blueComponent), opacity: mix(from.alphaComponent, to.alphaComponent))
    }
}

// MARK: - Environment

private struct LiveSpectrumKey: EnvironmentKey {
    static var defaultValue: (any LiveSpectrumProviding)? { nil }
}

extension EnvironmentValues {
    /// The app-owned spectrum controller. Absent in Settings previews and
    /// tests, which therefore always show the decorative fallback.
    var liveSpectrum: (any LiveSpectrumProviding)? {
        get { self[LiveSpectrumKey.self] }
        set { self[LiveSpectrumKey.self] = newValue }
    }
}

/// Context-menu content: the explicit Live Audio switch and its real state.
struct LiveAudioMenuItems: View {
    let provider: any LiveSpectrumProviding
    let status: LiveAudioStatus

    var body: some View {
        Section("Live Audio · \(status.detail)") {
            Toggle("Live Audio", isOn: Binding(
                get: { status.isOn },
                set: { on in on ? provider.startFromUserAction() : provider.stop() }
            ))
            if status.offersPrivacySettings {
                Button("Open Privacy & Security…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
