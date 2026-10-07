import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Tab -> wider page morph (2026-10-06). Measured on device: the canvas layer
/// slid -26 -> 0 pt during the morph and the shell grew one-sided (its left
/// edge pinned), because `TopPinnedHostRoot` centered the canvas in a hosting
/// proposal that lags one update behind the staged panel resize.
@MainActor
final class ShellMorphInvariantTests: XCTestCase {
    private final class Box { var minX: CGFloat = .nan; var minY: CGFloat = .nan }

    /// The exact mechanism: the canvas (already at the staged panel width)
    /// is wider than the proposal the hosting view still offers.
    func testCanvasStaysAtTheHostOriginWhileTheProposalLags() {
        XCTAssertEqual(TopPinnedHostRoot<EmptyView>.canvasAlignment, .topLeading)
        let box = Box()
        let canvas = Color.black.frame(width: 681, height: 505)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { box.minX = $0.minX; box.minY = $0.minY }
        let host = NSHostingView(rootView: TopPinnedHostRoot(content: canvas))
        host.frame = NSRect(x: 0, y: 0, width: 629, height: 505)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(box.minX, 0, accuracy: 0.01, "centering on the stale proposal put the canvas at -26")
        XCTAssertEqual(box.minY, 0, accuracy: 0.01, "top-pinned")
    }

    /// Every interpolated frame of a staged morph keeps the shell's screen
    /// midX and top edge (AppKit maxY) when the canvas origin is the panel
    /// origin; a canvas centered on a lagging proposal does not.
    func testStagedMorphKeepsMidXAndTopOnEveryFrame() {
        let old = CGRect(x: 259, y: 240, width: 629, height: 505)          // Agents shell (screen)
        let target = CGRect(x: 233, y: 376, width: 681, height: 369)       // Island shell (screen)
        let stage = old.union(target)                                     // staged panel
        let from = old.offsetBy(dx: -stage.minX, dy: -stage.minY)          // re-expressed locally
        let to = target.offsetBy(dx: -stage.minX, dy: -stage.minY)
        var centeredWorst: CGFloat = 0
        for step in 0...20 {
            let t = CGFloat(step) / 20
            let local = ExpandedShellMorph.interpolatedFrame(from: from, to: to, progress: t)
            let midX = stage.minX + local.midX                             // top-leading canvas
            XCTAssertEqual(midX, old.midX, accuracy: 0.5, "t=\(t)")
            XCTAssertEqual(stage.minY + local.maxY, old.maxY, accuracy: 0.5, "top edge fixed, t=\(t)")
            // Old behaviour: canvas centered in a proposal animating 629 -> 681.
            let proposal = old.width + (stage.width - old.width) * t
            centeredWorst = max(centeredWorst, abs(midX + (proposal - stage.width) / 2 - old.midX))
        }
        XCTAssertGreaterThan(centeredWorst, 20, "documents the measured one-sided growth")
    }
}
