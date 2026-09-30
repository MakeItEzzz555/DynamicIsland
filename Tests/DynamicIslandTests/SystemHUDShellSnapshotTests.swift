import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Opt-in renders of the production interactive HUD shell for visual review.
/// The physical notch of the reference display is outlined so clearance can be
/// judged. Enable with DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR=<dir>.
@MainActor
final class SystemHUDShellSnapshotTests: XCTestCase {
    func testRenderInteractiveHUDShells() throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR to render HUD screenshots.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for collapsedHeight in [29.87, 44.0] {
            let settings = AppSettings(defaults: UserDefaults(suiteName: "HUDRender-\(UUID().uuidString)")!)
            settings.collapsedHeight = collapsedHeight
            for kind in [SystemHUDKind.brightness, .volume] {
                for value in [0.0, 0.5, 1.0] {
                    let activity = DynamicIslandLiveActivity(
                        id: LiveActivityStore.systemHUDActivityID,
                        kind: .system,
                        title: kind == .brightness ? "Brightness" : "Volume",
                        subtitle: SystemHUDFormatting.percentage(value),
                        symbolName: kind == .brightness ? "sun.max.fill" : "speaker.wave.3.fill",
                        priority: 100,
                        isActive: true,
                        progress: value,
                        updatedAt: Date(),
                        systemHUDKind: kind
                    )
                    let geometry = SystemHUDShellPreview.geometry(settings: settings, activity: activity)
                    let notch = try XCTUnwrap(geometry.notchRect)
                    let shell = geometry.collapsedFrame
                    let canvas = CGSize(width: shell.width + 80, height: shell.height + 40)
                    let view = ZStack(alignment: .top) {
                        Color(white: 0.42)
                        SystemHUDShellPreview(settings: settings, activity: activity)
                        // Physical notch outline, in shell-relative coordinates.
                        Rectangle()
                            .stroke(Color.red.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .frame(width: notch.width, height: notch.height)
                            .offset(x: notch.midX - shell.midX, y: shell.maxY - notch.maxY)
                    }
                    .frame(width: canvas.width, height: canvas.height, alignment: .top)
                    .preferredColorScheme(.dark)
                    let name = String(
                        format: "50-hud-%@-%03d-collapsed%02d",
                        kind == .brightness ? "brightness" : "volume",
                        Int(value * 100),
                        Int(collapsedHeight.rounded())
                    )
                    try render(view, size: canvas, name: name, to: output)
                }
            }
        }
    }

    /// Renders through a real window composited by WindowServer so state
    /// set in onAppear, animated fills, symbol tint and the outer glow are
    /// captured as the island draws them (layer caching misses those).
    private func render<V: View>(_ view: V, size: CGSize, name: String, to directory: URL) throws {
        let window = NSWindow(
            contentRect: CGRect(x: 40, y: 40, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw XCTSkip("WindowServer capture unavailable (Screen Recording permission).")
        }
        let rep = NSBitmapImageRep(cgImage: image)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
