import AppKit
import SwiftUI

/// A value-only rendering model. Production CoreAudio does not expose a battery
/// reading here; previews and future public providers must supply one explicitly.
struct AudioDevicePresentation: Equatable, Sendable {
    let name: String
    let family: AudioOutputDeviceKind
    let batteryPercentage: Int?

    init(name: String, family: AudioOutputDeviceKind? = nil, batteryPercentage: Int? = nil) {
        self.name = name
        self.family = family ?? .classify(name: name)
        self.batteryPercentage = batteryPercentage.flatMap { (0...100).contains($0) ? $0 : nil }
    }

    var status: String {
        batteryPercentage.map { "Connected · \($0)%" } ?? "Connected"
    }
}

enum AudioDeviceModelMotion {
    static func rotation(normalizedX: Double, enabled: Bool, reduceMotion: Bool) -> Double {
        guard enabled, !reduceMotion, normalizedX.isFinite else { return 0 }
        return min(max(normalizedX, -1), 1) * 12
    }
}

/// The layered public-symbol treatment takes its visual reference from Droppy's
/// AirPodsHUDView / SettingsPreviewViews at dd2d16c (GPL-3.0 + Commons Clause).
/// The upstream HUD uses depth without rotation. Optional bounded Y-axis hover
/// is DynamicIsland's adaptation of the separate Parallax3DModifier reference;
/// it uses existing native motion tokens and never runs a repeating animation.
struct AudioDeviceModelView: View {
    let family: AudioOutputDeviceKind
    var size: CGFloat = 26
    var motionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var normalizedX = 0.0

    private var symbol: String {
        family.resolvedSymbolName { name in
            NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        }
    }

    var body: some View {
        let symbol = self.symbol
        ZStack {
            Image(systemName: symbol)
                .foregroundStyle(Color(white: 0.30))
                .offset(x: size * 0.035, y: size * 0.055)
            Image(systemName: symbol)
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.70)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: symbol)
                .foregroundStyle(LinearGradient(colors: [.white.opacity(0.72), .clear],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .offset(x: -size * 0.014, y: -size * 0.018)
                .blendMode(.screen)
        }
        .font(.system(size: size * 0.82, weight: .medium))
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.22), radius: size * 0.10, y: size * 0.07)
        .rotation3DEffect(.degrees(AudioDeviceModelMotion.rotation(normalizedX: normalizedX,
                                                                 enabled: motionEnabled, reduceMotion: reduceMotion)),
                          axis: (x: 0, y: 1, z: 0), perspective: 0.24)
        .onContinuousHover { phase in
            guard motionEnabled, !reduceMotion else { return }
            switch phase {
            case .active(let location): normalizedX = Double(location.x / max(size, 1)) * 2 - 1
            case .ended: normalizedX = 0
            }
        }
        .animation(WorkspaceEditorMotion.hover(entering: normalizedX != 0,
                                              reduceMotion: reduceMotion || !motionEnabled), value: normalizedX)
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { normalizedX = 0 }
        }
        .onChange(of: motionEnabled) { _, enabled in
            if !enabled { normalizedX = 0 }
        }
        .onDisappear { normalizedX = 0 }
        .accessibilityHidden(true)
    }
}

struct AudioDeviceConnectionLabel: View {
    let name: String
    var batteryPercentage: Int? = nil
    @Environment(\.islandDisplayMetrics) private var displayMetrics

    var body: some View {
        let device = AudioDevicePresentation(name: name, batteryPercentage: batteryPercentage)
        VStack(alignment: .trailing, spacing: 1) {
            Text(device.name)
                .font(.system(size: displayMetrics.font(8.2, minimum: 7.4, maximum: 10), weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1).truncationMode(.middle)
            Text(device.status)
                .font(.system(size: displayMetrics.font(7, minimum: 6.8, maximum: 9), weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name), \(device.status)")
    }
}

/// Both the production HUD and its synthetic settings fixture render this view.
struct AudioDeviceHUDContentView: View {
    let name: String
    var family: AudioOutputDeviceKind? = nil
    var batteryPercentage: Int? = nil
    let layout: CompactCollapsedSideSlotGeometry
    var motionEnabled = true
    @Environment(\.islandDisplayMetrics) private var displayMetrics

    var body: some View {
        let device = AudioDevicePresentation(name: name, family: family, batteryPercentage: batteryPercentage)
        CompactCollapsedSideSlotLayout(geometry: layout) {
            AudioDeviceModelView(family: device.family,
                                 size: 24 * displayMetrics.collapsedSideContentScale,
                                 motionEnabled: motionEnabled)
        } right: {
            AudioDeviceConnectionLabel(name: device.name, batteryPercentage: device.batteryPercentage)
                .frame(width: max(layout.rightRegionWidth, 48) - 4, alignment: .trailing)
        }
    }
}
