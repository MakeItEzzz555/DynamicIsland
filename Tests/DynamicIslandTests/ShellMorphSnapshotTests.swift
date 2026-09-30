import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Opt-in frame strips of expanded tab morphs (DYNAMIC_ISLAND_MORPH_SNAPSHOT_DIR).
/// Each sampled frame hosts the production IslandSurface, positioned with the
/// island's own formula, in a hosting view sized to the AppKit-interpolated
/// panel frame, while the SwiftUI canvas runs one sample ahead (worst-case
/// timing mismatch). Rows: fixed top-pinned root; old NSHostingView centering;
/// and the c4fddc3 state (canvas committed to its target size at once).
@MainActor
final class ShellMorphSnapshotTests: XCTestCase {
    func testRenderTabMorphStrips() async throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_MORPH_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_MORPH_SNAPSHOT_DIR to render morph strips.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "MorphStrip-\(UUID().uuidString)")!)
        let standard = CGSize(width: 860, height: 286)
        let agents = ExpandedPresentationProfile.agentsWorkspace.resolvedSize(from: standard)
        let trayAccessory = ExpandedPresentationProfile.trayQuickActions.accessoryHeight
        let cases: [(String, CGSize, CGFloat, CGSize, CGFloat)] = [
            ("island-to-agents", standard, 0, agents, 0),
            ("agents-to-island", agents, 0, standard, 0),
            ("tray-to-agents", standard, trayAccessory, agents, 0),
            ("agents-to-tray", agents, 0, standard, trayAccessory)
        ]
        let samples: [CGFloat] = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1]
        for (name, from, fromAccessory, to, toAccessory) in cases {
            var rows: [NSImage] = []
            // Rows: fixed (top-pinned, canvas one sample ahead); old centering
            // with the same lead; c4fddc3 (centered, canvas at target at once).
            for (topPinned, canvasAtTarget) in [(true, false), (false, false), (false, true)] {
                var images: [NSImage] = []
                for (index, progress) in samples.enumerated() {
                    let windowProgress = progress
                    let canvasProgress = canvasAtTarget ? 1 : samples[min(index + 1, samples.count - 1)]
                    images.append(try await frame(
                        settings: settings,
                        window: lerp(from, fromAccessory, to, toAccessory, windowProgress),
                        canvas: lerp(from, fromAccessory, to, toAccessory, canvasProgress),
                        topPinned: topPinned
                    ))
                }
                rows.append(strip(images))
            }
            try write(stack(rows), to: output.appendingPathComponent("60-morph-\(name).png"))
        }
    }

    /// (shell size, panel size) at progress.
    private func lerp(_ a: CGSize, _ aAcc: CGFloat, _ b: CGSize, _ bAcc: CGFloat, _ t: CGFloat) -> (shell: CGSize, panel: CGSize) {
        let shell = CGSize(width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
        let accessory = aAcc + (bAcc - aAcc) * t
        return (shell, CGSize(width: shell.width, height: shell.height + accessory))
    }

    private func frame(
        settings: AppSettings,
        window: (shell: CGSize, panel: CGSize),
        canvas: (shell: CGSize, panel: CGSize),
        topPinned: Bool
    ) async throws -> NSImage {
        let canvasSize = canvas.panel
        // Panel-local AppKit coordinates: the shell occupies the top of the canvas.
        let shellFrame = CGRect(x: 0, y: canvasSize.height - canvas.shell.height, width: canvas.shell.width, height: canvas.shell.height)
        let canvasView = ZStack(alignment: .topLeading) {
            IslandSurface(settings: settings, isExpanded: true, visualProgress: 1) { Color.clear }
                .notchIntegrated(true)
                .frame(width: shellFrame.width, height: shellFrame.height)
                .position(x: shellFrame.midX, y: canvasSize.height - shellFrame.midY)
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)

        let root: AnyView = topPinned ? AnyView(TopPinnedHostRoot(content: canvasView)) : AnyView(canvasView)
        let outer = CGSize(width: 980, height: 520)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: (outer.width - window.panel.width) / 2, y: outer.height - window.panel.height,
                            width: window.panel.width, height: window.panel.height)
        let container = NSView(frame: CGRect(origin: .zero, size: outer))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.55, alpha: 1).cgColor
        container.addSubview(host)
        // Screen-top reference line.
        let line = NSView(frame: CGRect(x: 0, y: outer.height - 2, width: outer.width, height: 2))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.systemRed.cgColor
        container.addSubview(line)
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(60))
        container.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: container.bounds))
        container.cacheDisplay(in: container.bounds, to: rep)
        let image = NSImage(size: outer)
        image.addRepresentation(rep)
        return image
    }

    private func strip(_ images: [NSImage]) -> NSImage {
        let scale: CGFloat = 0.3
        let size = CGSize(width: images[0].size.width * scale, height: images[0].size.height * scale)
        let result = NSImage(size: CGSize(width: size.width * CGFloat(images.count) + CGFloat(images.count - 1) * 6, height: size.height))
        result.lockFocus()
        for (index, image) in images.enumerated() {
            image.draw(in: CGRect(x: CGFloat(index) * (size.width + 6), y: 0, width: size.width, height: size.height))
        }
        result.unlockFocus()
        return result
    }

    private func stack(_ rows: [NSImage]) -> NSImage {
        let width = rows.map(\.size.width).max() ?? 0
        let height = rows.map(\.size.height).reduce(0, +) + 10
        let result = NSImage(size: CGSize(width: width, height: height))
        result.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: result.size).fill()
        var y = height
        for row in rows {
            y -= row.size.height
            row.draw(in: CGRect(x: 0, y: y, width: row.size.width, height: row.size.height))
            y -= 10
        }
        result.unlockFocus()
        return result
    }

    private func write(_ image: NSImage, to url: URL) throws {
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
