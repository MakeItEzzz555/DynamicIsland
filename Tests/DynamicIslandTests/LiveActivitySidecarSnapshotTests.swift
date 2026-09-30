import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class LiveActivitySidecarSnapshotTests: XCTestCase {
    func testRenderSidecarReviewSnapshots() throws {
        guard let raw = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_ACTIVITY_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIVE_ACTIVITY_SNAPSHOT_DIR to render sidecar screenshots.")
        }
        let output = URL(fileURLWithPath: raw, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let media = activity("media", .media, title: "Now Playing", subtitle: "Artist", progress: 0.42)
        let timer = activity("timer", .timer, title: "Timer", subtitle: "4:18", progress: 0.64)
        let battery = activity(
            "battery",
            .battery,
            title: "Battery",
            subtitle: "18%",
            progress: 0.18,
            batteryState: .low
        )
        let agent = activity("agent", .agent, title: "Codex", subtitle: "Working", progress: nil)
        let hud = activity("systemHUD", .system, title: "Volume", subtitle: "68%", progress: 0.68)

        try render(name: "01-notched-media-primary", activities: [media], hasNotch: true, output: output)
        try render(name: "02-media-timer-sidecar", activities: [media, timer], hasNotch: true, output: output)
        try render(name: "03-sidecar-media-sidecar", activities: [media, battery, timer], hasNotch: true, output: output)
        try render(name: "04-agent-timer", activities: [agent, timer], hasNotch: true, output: output)
        try render(name: "05-volume-overlay-media-timer", activities: [media, timer, hud], hasNotch: true, output: output)
        try render(
            name: "06-constrained-width",
            activities: [media, battery, timer],
            hasNotch: true,
            availableWidth: 230,
            output: output
        )
        try render(name: "07-notchless-three-slot", activities: [media, battery, timer], hasNotch: false, output: output)
        try render(name: "08-radial-timer-progress", activities: [media, timer], hasNotch: false, output: output)
    }

    private func render(
        name: String,
        activities: [DynamicIslandLiveActivity],
        hasNotch: Bool,
        availableWidth: CGFloat = 340,
        output: URL
    ) throws {
        let canvas = CGSize(width: 380, height: 86)
        let primary = CGRect(x: 82, y: 27, width: 216, height: 34)
        let resolution = LiveActivityLayoutResolver.resolve(
            activities: activities,
            context: LiveActivityLayoutContext(
                availableWidth: availableWidth,
                hasHardwareNotch: hasNotch,
                hardwareNotchWidth: hasNotch ? 176 : 0,
                primaryMinimumWidth: 172,
                primaryIdealWidth: 216,
                sidecarDiameter: LiveActivitySidecarMetrics.diameter,
                sidecarGap: LiveActivitySidecarMetrics.gap,
                allowSimultaneousSidecars: true,
                timerSidePreference: .automatic
            )
        )
        let geometry = LiveActivityCompositeGeometry.resolve(
            primaryFrame: primary,
            canvasSize: canvas,
            resolution: resolution,
            sidecarDiameter: LiveActivitySidecarMetrics.diameter,
            sidecarGap: LiveActivitySidecarMetrics.gap
        )

        let view = ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color.black.opacity(0.95), Color(red: 0.04, green: 0.05, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )

            snapshotPrimary(resolution: resolution, hasNotch: hasNotch)
                .frame(width: primary.width, height: primary.height)
                .position(x: primary.midX, y: canvas.height - primary.midY)

            LiveActivitySidecarLayer(
                resolution: resolution,
                compositeGeometry: geometry,
                canvasHeight: canvas.height,
                reduceMotion: true,
                onActivate: { _ in }
            )

            if let overlay = resolution.overlayTransient?.activity {
                CollapsedSystemHUDCompactView(
                    activity: overlay,
                    layout: CompactCollapsedSideSlotGeometry(
                        isNotchIntegrated: false,
                        leftRegionWidth: 0,
                        notchCoreWidth: 0,
                        rightRegionWidth: 0
                    )
                )
                .padding(.horizontal, 12)
                .frame(width: primary.width, height: primary.height)
                .background(Color.black.opacity(0.985), in: Capsule())
                .position(x: primary.midX, y: canvas.height - primary.midY)
            }
        }
        .frame(width: canvas.width, height: canvas.height)

        try renderHosted(
            view,
            size: canvas,
            to: output.appendingPathComponent(name + ".png")
        )
    }

    @ViewBuilder
    private func snapshotPrimary(
        resolution: LiveActivityLayoutResolution,
        hasNotch: Bool
    ) -> some View {
        HStack(spacing: 7) {
            if let primary = resolution.primary?.activity {
                Image(systemName: primary.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 20)

                Text(primary.title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if hasNotch {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black)
                        .frame(width: 72, height: 20)
                } else if let subtitle = primary.subtitle {
                    Text(subtitle)
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.985), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private func renderHosted<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let hostingView = NSHostingView(
            rootView: view
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not allocate hosted render for \(url.lastPathComponent)")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            XCTFail("Could not render \(url.lastPathComponent)")
            return
        }
        try png.write(to: url, options: .atomic)
    }

    private func activity(
        _ id: String,
        _ kind: DynamicIslandLiveActivityKind,
        title: String,
        subtitle: String?,
        progress: Double?,
        batteryState: BatteryLiveActivityState? = nil
    ) -> DynamicIslandLiveActivity {
        let symbolName: String = switch kind {
        case .media: "music.note"
        case .timer: "timer"
        case .fileTray: "tray.fill"
        case .battery: "battery.25percent"
        case .system: "speaker.wave.2.fill"
        case .agent: "cpu"
        case .keepAwake: "cup.and.saucer.fill"
        case .terminalTask: "terminal.fill"
        case .windowSnapPreview: "rectangle.split.2x1"
        case .reminder: "checklist"
        case .voiceRecording: "mic.fill"
        case .voiceTranscription: "waveform"
        case .camera: "camera.fill"
        case .backgroundRemoval: "person.crop.rectangle"
        case .message: "message.fill"
        }
        let priority: Int = switch kind {
        case .system: 200
        case .agent: 130
        case .timer: 90
        case .media: 80
        case .battery: 85
        case .fileTray: 60
        case .keepAwake: 72
        case .terminalTask: 88
        case .windowSnapPreview: 170
        case .reminder: 78
        case .voiceRecording: 125
        case .voiceTranscription: 105
        case .camera: 128
        case .backgroundRemoval: 84
        case .message: MessagingController.freshPriority
        }
        return DynamicIslandLiveActivity(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            priority: priority,
            isActive: true,
            progress: progress,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            batteryState: batteryState
        )
    }
}
