import XCTest
import SwiftUI
@testable import DynamicIsland

private final class RenderNoSystemProvider: MediaDetectionProvider {
    let name = "Test"
    func snapshot() async -> MediaSnapshot? { nil }
}

/// Renders the real `MediaModuleView` at each semantic size from seeded
/// playback state. Set `DI_MEDIA_RENDER_DIR` to also write the PNGs for review.
@MainActor
final class MediaSizeRenderTests: XCTestCase {
    private func seededMedia(title: String, playing: Bool) async throws -> MediaController {
        let state = playing ? "playing" : "paused"
        let executor = MediaAutomationExecutor(runner: { source, _ in
            if source.contains("with timeout"), source.contains("tell application \"Spotify\"") {
                return MediaAutomationScriptResult(output: "\(title)||ATB||\(state)||Spotify||64||214||||70", failure: nil)
            }
            return MediaAutomationScriptResult(output: "", failure: nil)
        })
        let media = MediaController(automationExecutor: executor, systemNowPlayingProvider: RenderNoSystemProvider(),
                                    startsAutomatically: false)
        let published = expectation(description: "seeded")
        let subscription = media.$title.sink { if $0 == title { published.fulfill() } }
        media.refresh()
        await fulfillment(of: [published], timeout: 3)
        subscription.cancel()
        return media
    }

    private func render(_ media: MediaController, size: WidgetPresentationSize, surface: WorkspaceSurface, name: String) throws -> CGImage {
        let cell = WidgetGridMetrics.make(surface: surface, metrics: .fallback).size(for: size)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "MediaSizeRenderTests-\(UUID().uuidString)")!)
        let view = MediaModuleView(settings: settings, media: media, availableHeight: cell.height)
            .environment(\.workspaceWidgetPlacement, WorkspaceWidgetPlacementContext(
                isSole: false, size: cell, fillsRow: true, presentationSize: size))
            .frame(width: cell.width, height: cell.height)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "\(name) renders")
        XCTAssertEqual(CGFloat(image.width), cell.width * 2, accuracy: 2)
        XCTAssertEqual(CGFloat(image.height), cell.height * 2, accuracy: 2, "\(name): the widget renders at its exact grid cell")
        if let directory = ProcessInfo.processInfo.environment["DI_MEDIA_RENDER_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        return image
    }

    func testNativeFirstVisibleMediaBoundsAreTopAttachedWithoutChangingTheCell() async throws {
        let media = try await seededMedia(title: "9PM (Till I Come)", playing: true)
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.showNavigationControls = false
        for semanticSize in WidgetPresentationSize.allCases {
            var configuration = WorkspaceConfiguration.initial
            for widget in configuration.widgets(on: .media) { configuration.remove(widget.id) }
            configuration.add(.media, on: .media)
            let id = try XCTUnwrap(configuration.widgets(on: .media).first?.id)
            configuration.setSize(semanticSize, for: id)
            configuration.markCustomized(.media)
            settings.showNavigationControls = false
            let presentation = SettingsPreviewPresentation(settings: settings, configuration: configuration)
            let cell = try XCTUnwrap(presentation.projection.frames.first?.frame)
            let origin = CGPoint(x: presentation.chrome.horizontalPadding + cell.minX,
                y: presentation.chrome.topPadding + presentation.chrome.tabSwitcherHeight
                    + presentation.chrome.tabToPageSpacing + cell.minY)
            let size = presentation.geometry.expandedFrame.size
            var gaps: [CGFloat] = []
            for attached in [false, true] {
                // Navigation-visible composition is exactly the previous centered Media layout.
                // Keep the production Gesture Only shell/cell geometry fixed for both captures.
                settings.showNavigationControls = !attached
                let module = MediaModuleView(settings: settings, media: media, availableHeight: cell.height)
                    .environment(\.workspaceWidgetPlacement, WorkspaceWidgetPlacementContext(isSole: true,
                        size: cell.size, fillsRow: true, presentationSize: semanticSize))
                    .frame(width: cell.width, height: cell.height)
                    .offset(x: origin.x, y: origin.y)
                let root = ZStack(alignment: .topLeading) { Color.black; module }
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, .dark)
                    .environment(\.isSettingsPreview, true)
                    .environment(\.nativeVisualSnapshotTime, 0)
                let window = NSWindow(contentRect: CGRect(x: 40, y: 40, width: size.width, height: size.height),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: root)
                window.contentView = host
                window.orderFrontRegardless()
                defer { window.contentView = nil; window.close() }
                for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let pixelScale = CGFloat(bitmap.pixelsHigh) / size.height
                let firstRow = try XCTUnwrap((0..<bitmap.pixelsHigh).first { y in
                    (0..<bitmap.pixelsWide).contains { x in
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        return max(color.redComponent, color.greenComponent, color.blueComponent) > 0.04
                    }
                })
                let gap = CGFloat(firstRow) / pixelScale - SettingsPreviewPresentation.metrics.hardwareNotchHeight
                gaps.append(gap)
                if attached {
                    XCTAssertGreaterThanOrEqual(gap, 0, "No physical notch overlap")
                    XCTAssertLessThanOrEqual(gap, origin.y - SettingsPreviewPresentation.metrics.hardwareNotchHeight + 1,
                        "Measure visible pixels, not just the semantic frame")
                    XCTAssertEqual(cell.size, presentation.projection.frames.first?.frame.size)
                }
                if let directory = ProcessInfo.processInfo.environment["DI_MEDIA_RENDER_DIR"] {
                    let file = URL(fileURLWithPath: directory).appendingPathComponent("native-\(semanticSize.rawValue)-\(attached ? "attached" : "centered").png")
                    try bitmap.representation(using: .png, properties: [:])?.write(to: file)
                }
            }
            XCTAssertLessThan(gaps[1], gaps[0], "\(semanticSize): the visible composition moves up")
            print("MEDIA_ATTACHMENT \(semanticSize.rawValue) frameGap=\(origin.y - SettingsPreviewPresentation.metrics.hardwareNotchHeight) visibleBefore=\(gaps[0]) visibleAfter=\(gaps[1]) cell=\(cell.size)")
        }
    }

    func testTopAttachmentChangesOnlyVerticalOriginsInCompactAndStandardPlans() {
        for surface in [WorkspaceSurface.media, .agents] {
            let grid = WidgetGridMetrics.make(surface: surface, metrics: .fallback)
            let compactCell = grid.size(for: .compact)
            let before = MediaCompactLayout.make(cell: compactCell, content: .init())
            let after = MediaCompactLayout.make(cell: compactCell, content: .init(), topAttached: true)
            XCTAssertEqual(before.artworkSide, after.artworkSide)
            XCTAssertEqual(before.frames.mapValues(\.size), after.frames.mapValues(\.size))
            XCTAssertEqual(after.frames.values.map(\.minY).min(), 0)
            XCTAssertTrue(after.frames.values.allSatisfy { CGRect(origin: .zero, size: compactCell).contains($0) })
            let standardCell = grid.size(for: .standard)
            let old = MediaStandardLayout.make(cell: standardCell, content: .init())
            let new = MediaStandardLayout.make(cell: standardCell, content: .init(), topAttached: true)
            XCTAssertEqual(old.artworkSide, new.artworkSide)
            XCTAssertEqual(old.frames.mapValues(\.size), new.frames.mapValues(\.size))
            XCTAssertEqual(new.frames.values.map(\.minY).min(), 0)
            XCTAssertTrue(new.frames.values.allSatisfy { CGRect(origin: .zero, size: standardCell).contains($0) })
        }
    }

    func testEverySizeRendersAtItsExactCellPlayingAndPaused() async throws {
        let playing = try await seededMedia(title: "9PM (Till I Come)", playing: true)
        for size in WidgetPresentationSize.allCases {
            for surface in [WorkspaceSurface.media, .agents] {
                _ = try render(playing, size: size, surface: surface, name: "media-\(size.rawValue)-\(surface.rawValue)-playing")
            }
        }
        let paused = try await seededMedia(title: "An Extraordinarily Long Track Title That Must Truncate Cleanly", playing: false)
        for size in WidgetPresentationSize.allCases {
            _ = try render(paused, size: size, surface: .media, name: "media-\(size.rawValue)-media-paused-long")
        }
    }
}
