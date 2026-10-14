import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class FileDragOrbitSnapshotTests: XCTestCase {
    func testRenderCurrentTwoByTwoDropSurface() throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_FILE_DRAG_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_FILE_DRAG_SNAPSHOT_DIR to render current drop-surface screenshots.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let view = FileDropZonesOverlay(reduceMotion: true, onTargetChange: { _ in }, onDrop: { _, _ in false })
            .frame(width: 400, height: 180)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 180)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("file-drop-two-by-two.png"))
    }
}
