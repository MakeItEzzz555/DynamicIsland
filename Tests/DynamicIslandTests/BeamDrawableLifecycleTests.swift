import AppKit
import XCTest
@testable import LibrariesNative

@MainActor
final class BeamDrawableLifecycleTests: XCTestCase {
    func testEveryDrawEntryPointSkipsUnattachedHiddenAndOrderedOutSurfaces() {
        let surface = NativeBeamMetalLayer.Surface()
        surface.frame = CGRect(x: 0, y: 0, width: 300, height: 160)
        surface.parameters = .blob(size: surface.bounds.size, radius: 12, borderWidth: 1,
            kind: 0, edgeMaskPx: 1, wrapCorners: true, radial: [], blobs: [], matrix: [], opacity: 1)
        surface.draw(in: surface)
        surface.layout()
        XCTAssertEqual(surface.submittedDrawCount, 0)

        let parent = NSView(frame: surface.frame)
        parent.addSubview(surface)
        parent.isHidden = true
        let window = NSWindow(contentRect: surface.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = parent
        defer { window.orderOut(nil); window.contentView = nil }
        window.orderFrontRegardless()
        for _ in 0..<40 { surface.draw(in: surface); surface.layout() }
        XCTAssertEqual(surface.submittedDrawCount, 0, "Native updates cannot acquire hidden drawables")
        window.orderOut(nil)
        parent.isHidden = false
        for _ in 0..<40 { surface.draw(in: surface); surface.layout() }
        XCTAssertEqual(surface.submittedDrawCount, 0, "Occlusion protection covers explicit draws, not only layout")
        surface.releaseDrawableResources()
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        surface.draw(in: surface)
        XCTAssertEqual(surface.submittedDrawCount, 0)
    }
}
