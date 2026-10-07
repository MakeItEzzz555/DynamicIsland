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
