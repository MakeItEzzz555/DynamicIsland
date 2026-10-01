import SwiftUI
import XCTest
@testable import DynamicIsland

/// Opt-in visual acceptance for the production drag-orbit visuals. The AppKit
/// drop hosts are intentionally not invoked here; their lifecycle is covered
/// by FileDragSessionTests/FilePromiseDropTarget tests. Enable with
/// DYNAMIC_ISLAND_FILE_DRAG_SNAPSHOT_DIR=<dir>.
@MainActor
final class FileDragOrbitSnapshotTests: XCTestCase {
    func testRenderOrbitStatesNotchedAndNotchless() throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_FILE_DRAG_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_FILE_DRAG_SNAPSHOT_DIR to render drag-orbit screenshots.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: "FileDragIdleRender-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let shelf = FileShelfStore(settings: settings, defaults: defaults)
        let layoutStore = IslandLayoutStore()
        layoutStore.canvasSize = CGSize(width: 760, height: 250)
        let registry = IslandCapabilityRegistry()
        let backgroundRemoval = BackgroundRemovalController(
            liveActivities: LiveActivityStore(),
            capabilities: registry,
            addToShelf: { _ in }
        )
        try render(
            ZStack {
                Color(white: 0.18)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.black)
                    .frame(width: 660, height: 150)
                    .offset(y: -45)
                FileTrayQuickActionBar(
                    fileShelf: shelf,
                    backgroundRemoval: backgroundRemoval,
                    layoutStore: layoutStore,
                    reduceMotion: false
                )
                .offset(y: 62)
            }
            .coordinateSpace(name: IslandCanvasCoordinateSpace.name)
            .preferredColorScheme(.dark),
            name: "shelf-orbit-idle-production-tray",
            to: output
        )

        let states: [(String, FileDragQuickAction?, Bool, CGFloat)] = [
            ("drag-begin", nil, false, 0.50),
            ("orbit-quarter", nil, false, 0.75),
            ("orbit-visible", nil, false, 1.00),
            ("airdrop-hover", .airDrop, false, 1.00),
            ("airdrop-targeted", .airDrop, true, 1.00),
            ("messages-targeted", .messages, true, 1.00),
            ("reduce-motion", .mail, true, 1.00)
        ]

        for notched in [true, false] {
            for (name, action, targeted, entranceScale) in states {
                let reduceMotion = name == "reduce-motion"
                try render(
                    OrbitSnapshotScene(
                        notched: notched,
                        highlightedAction: action,
                        targeted: targeted,
                        reduceMotion: reduceMotion,
                        entranceScale: reduceMotion ? 1 : entranceScale
                    ),
                    name: "shelf-orbit-\(notched ? "notched" : "floating")-\(name)",
                    to: output
                )
            }
        }
    }

    private func render<V: View>(_ view: V, name: String, to directory: URL) throws {
        let size = CGSize(width: 760, height: 250)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name + ".png"))
    }
}

private struct OrbitSnapshotScene: View {
    let notched: Bool
    let highlightedAction: FileDragQuickAction?
    let targeted: Bool
    let reduceMotion: Bool
    let entranceScale: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Color(white: 0.18)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black)
                .frame(width: 660, height: 150)
                .overlay(alignment: .top) {
                    if notched {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.black)
                            .frame(width: 180, height: 34)
                    }
                }

            VStack(spacing: 10) {
                Spacer().frame(height: 148)
                HStack(spacing: FileDragQuickActionMetrics.spacing) {
                    ForEach(FileDragQuickAction.allCases) { action in
                        FileDragQuickActionCircleVisual(
                            action: action,
                            targeted: targeted && highlightedAction == action,
                            hovering: !targeted && highlightedAction == action,
                            reduceMotion: reduceMotion
                        )
                        .opacity(Double(entranceScale))
                        .scaleEffect(reduceMotion ? 1 : entranceScale)
                    }
                }
                .frame(
                    width: FileDragQuickActionMetrics.orbitWidth,
                    height: FileDragQuickActionMetrics.diameter + 8
                )

                Text(highlightedAction?.explanation ?? "Drag files to a quick action")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .preferredColorScheme(.dark)
    }
}
