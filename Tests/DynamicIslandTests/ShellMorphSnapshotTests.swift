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

    /// Content choreography grids: the shell morphs top-pinned on the panel
    /// curve while the outgoing page shrinks/blurs/fades and the incoming page
    /// mounts at the handoff and springs open from the top. Each cell is one
    /// sampled time (ExpandedIslandMotion.sample); red = screen top, cyan =
    /// page-area top (inner content scale anchor).
    func testRenderContentChoreographyGrids() throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_MORPH_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_MORPH_SNAPSHOT_DIR to render choreography grids.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "Choreography-\(UUID().uuidString)")!)
        let standard = CGSize(width: 860, height: 286)
        let agents = ExpandedPresentationProfile.agentsWorkspace.resolvedSize(from: standard)
        let cases: [(String, ExpandedIslandPage, CGSize, ExpandedIslandPage, CGSize)] = [
            ("island-to-agents", .island, standard, .agents, agents),
            ("agents-to-island", .agents, agents, .island, standard),
            ("tray-to-agents", .tray, standard, .agents, agents),
            ("agents-to-tray", .agents, agents, .tray, standard),
            ("tools-to-agents", .tools, standard, .agents, agents),
            ("agents-to-tools", .agents, agents, .tools, standard)
        ]
        let plans: [(String, ExpandedIslandMotion.Plan)] = [
            ("full", ExpandedIslandMotion.plan(.init(
                shellDuration: 0.40, isInstant: false, reduceMotion: false,
                useBlurTransitions: true, useScaleTransitions: true,
                prefersLightweightEffects: false, refreshRate: 120
            ))),
            ("reduced", ExpandedIslandMotion.plan(.init(
                shellDuration: 0.24, isInstant: false, reduceMotion: true,
                useBlurTransitions: true, useScaleTransitions: true,
                prefersLightweightEffects: false, refreshRate: 120
            )))
        ]
        for (planName, plan) in plans {
            let times: [TimeInterval] = planName == "full"
                ? [0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40, 0.55]
                : [0, 0.03, 0.06, 0.09, 0.12, 0.16, 0.20, 0.24, 0.30]
            for (name, fromPage, from, toPage, to) in cases {
                var cells: [NSImage] = []
                for time in times {
                    let view = ChoreographyFrame(
                        settings: settings,
                        sample: ExpandedIslandMotion.sample(plan, at: time),
                        time: time,
                        fromPage: fromPage,
                        from: from,
                        toPage: toPage,
                        to: to
                    )
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1
                    cells.append(try XCTUnwrap(renderer.nsImage))
                }
                try write(
                    grid(cells, columns: 3, scale: 0.5),
                    to: output.appendingPathComponent("70-choreo-\(planName)-\(name).png")
                )
            }
        }
    }

    private func grid(_ images: [NSImage], columns: Int, scale: CGFloat) -> NSImage {
        let cell = CGSize(width: images[0].size.width * scale, height: images[0].size.height * scale)
        let rows = Int((Double(images.count) / Double(columns)).rounded(.up))
        let gap: CGFloat = 6
        let size = CGSize(
            width: cell.width * CGFloat(columns) + gap * CGFloat(columns - 1),
            height: cell.height * CGFloat(rows) + gap * CGFloat(rows - 1)
        )
        let result = NSImage(size: size)
        result.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, image) in images.enumerated() {
            let column = index % columns
            let row = index / columns
            let origin = CGPoint(
                x: CGFloat(column) * (cell.width + gap),
                y: size.height - CGFloat(row + 1) * cell.height - CGFloat(row) * gap
            )
            image.draw(in: CGRect(origin: origin, size: cell))
        }
        result.unlockFocus()
        return result
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

/// One sampled frame: the production IslandSurface at the eased shell size,
/// top-pinned, hosting placeholder pages driven by the production
/// ExpandedPageMorphModifier with the sampled values.
private struct ChoreographyFrame: View {
    let settings: AppSettings
    let sample: ExpandedIslandMotion.FrameSample
    let time: TimeInterval
    let fromPage: ExpandedIslandPage
    let from: CGSize
    let toPage: ExpandedIslandPage
    let to: CGSize

    private let outer = CGSize(width: 980, height: 520)
    private let padding = IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true)
    private let header: CGFloat = 34
    private let headerGap: CGFloat = 10

    private func pageSize(_ shell: CGSize) -> CGSize {
        CGSize(
            width: shell.width - padding * 2,
            height: shell.height - IslandShellLayout.expandedTopPadding
                - IslandShellLayout.expandedBottomPadding - header - headerGap
        )
    }

    var body: some View {
        let p = CGFloat(sample.shellProgress)
        let shell = CGSize(
            width: from.width + (to.width - from.width) * p,
            height: from.height + (to.height - from.height) * p
        )
        let pageTop = IslandShellLayout.expandedTopPadding + header + headerGap
        ZStack(alignment: .top) {
            Color(white: 0.55)
            IslandSurface(settings: settings, isExpanded: true, visualProgress: 1) {
                VStack(alignment: .leading, spacing: headerGap) {
                    Capsule().fill(.white.opacity(0.12)).frame(width: 230, height: header)
                    ZStack(alignment: .top) {
                        if let outgoing = sample.outgoing {
                            PlaceholderPage(page: fromPage, size: pageSize(from))
                                .modifier(ExpandedPageMorphModifier(
                                    opacity: outgoing.opacity, blur: outgoing.blur, scale: outgoing.scale
                                ))
                        }
                        if let incoming = sample.incoming {
                            PlaceholderPage(page: toPage, size: pageSize(to))
                                .modifier(ExpandedPageMorphModifier(
                                    opacity: incoming.opacity, blur: incoming.blur, scale: incoming.scale
                                ))
                        }
                    }
                    .frame(width: pageSize(shell).width, height: pageSize(shell).height, alignment: .top)
                    .clipped()
                }
                .padding(.horizontal, padding)
                .padding(.top, IslandShellLayout.expandedTopPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .notchIntegrated(true)
            .frame(width: shell.width, height: shell.height)
            Rectangle().fill(Color.cyan.opacity(0.8)).frame(height: 1).offset(y: pageTop)
            Rectangle().fill(Color.red).frame(height: 2)
            Text(label)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(width: outer.width, height: outer.height, alignment: .top)
    }

    private var label: String {
        func format(_ content: ExpandedIslandMotion.ContentSample?) -> String {
            guard let content else { return "-" }
            return String(format: "o%.2f b%.1f s%.3f", content.opacity, content.blur, content.scale)
        }
        return String(
            format: "t=%.2fs shell=%.2f out[%@] in[%@]",
            time, sample.shellProgress, format(sample.outgoing), format(sample.incoming)
        )
    }
}

private struct PlaceholderPage: View {
    let page: ExpandedIslandPage
    let size: CGSize

    var body: some View {
        content
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .agents:
            VStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(index == 0 ? 0.85 : 0.45))
                        .frame(height: 40)
                }
            }
        case .tray:
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.6))
                        .frame(height: size.height * 0.8)
                }
            }
        case .tools:
            VStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.6))
                        }
                    }
                }
            }
        default:
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: size.width * 0.5, height: size.height)
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12).fill(Color.teal.opacity(0.6))
                    }
                }
                .frame(height: size.height)
            }
        }
    }
}
