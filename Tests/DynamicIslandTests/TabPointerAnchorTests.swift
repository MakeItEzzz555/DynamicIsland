import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class TabPointerAnchorTests: XCTestCase {
    @MainActor private final class Fixture {
        var pointer = CGPoint(x: 312, y: 715)
        var frame = CGRect(x: 300, y: 700, width: 32, height: 26)
        var moves: [CGPoint] = []
        lazy var anchor = TabPointerAnchor(pointerLocation: { [unowned self] in pointer }, movePointer: { [unowned self] point in
            pointer = point; moves.append(point); return true
        })
        func register(_ page: ExpandedIslandPage) {
            anchor.register(page, owner: UUID()) { [unowned self] in frame }
        }
        func begin(_ page: ExpandedIslandPage = .timer) throws -> Int {
            register(page)
            return try XCTUnwrap(anchor.activate(page, eventType: .leftMouseUp, pointer: pointer, maximumDuration: 5))
        }
    }

    func testWideNarrowAndSameWidthClicksPreserveExactTabOffsetAndRelease() throws {
        for shift: CGFloat in [240, -240, 0] {
            let f = Fixture()
            let generation = try f.begin(.timer)
            XCTAssertTrue(f.anchor.isActive)
            f.frame.origin.x += shift
            f.anchor.update(generation: generation)
            XCTAssertEqual(f.anchor.selectedTab, .timer)
            XCTAssertEqual(f.pointer.x, f.frame.minX + 12, accuracy: 0.01)
            XCTAssertEqual(f.pointer.y, f.frame.minY + 15, accuracy: 0.01)
            XCTAssertEqual(ExpandedHoverContainment.decide(pointer: .zero,
                shellFrame: CGRect(x: 300, y: 100, width: 300, height: 600), holds: .tabPointerAnchor), .held(.tabPointerAnchor))
            f.anchor.finish(generation: generation)
            XCTAssertFalse(f.anchor.isActive)
            XCTAssertEqual(f.moves.count, shift == 0 ? 0 : 1)
        }
    }

    func testMeaningfulUserMovementImmediatelyReleasesAndNeverWarps() throws {
        let f = Fixture()
        let generation = try f.begin()
        f.pointer.x += TabPointerAnchor.movementTolerance + 1
        f.anchor.observePointer(f.pointer)
        f.frame.origin.x += 240
        f.anchor.update(generation: generation)
        XCTAssertFalse(f.anchor.isActive)
        XCTAssertTrue(f.moves.isEmpty)
    }

    func testSlowIntentionalMovementAccumulatesWithoutFightingTheUser() throws {
        let f = Fixture()
        let generation = try f.begin()
        for _ in 0..<3 {
            f.pointer.x += 1
            f.anchor.update(generation: generation)
        }
        XCTAssertTrue(f.anchor.isActive)
        XCTAssertTrue(f.moves.isEmpty, "An unchanged tab never pulls a moving user back")
        f.pointer.x += 2
        f.anchor.update(generation: generation)
        XCTAssertFalse(f.anchor.isActive)
        XCTAssertTrue(f.moves.isEmpty)
    }

    func testConsecutiveClicksRejectStaleMovesAndCompletion() throws {
        let f = Fixture()
        let old = try f.begin(.agents)
        let latest = try f.begin(.timer)
        f.frame.origin.x += 200
        f.anchor.update(generation: old)
        f.anchor.finish(generation: old)
        XCTAssertTrue(f.anchor.isActive)
        XCTAssertEqual(f.anchor.selectedTab, .timer)
        XCTAssertTrue(f.moves.isEmpty)
        f.anchor.update(generation: latest)
        XCTAssertEqual(f.moves.count, 1)
        f.anchor.finish(generation: latest)
        XCTAssertFalse(f.anchor.isActive)
    }

    func testKeyboardAccessibilityAndProgrammaticSelectionDoNotAnchor() {
        let f = Fixture()
        f.register(.timer)
        for type: NSEvent.EventType? in [.keyDown, nil, .scrollWheel, .gesture] {
            XCTAssertNil(f.anchor.activate(.timer, eventType: type, pointer: f.pointer, maximumDuration: 5))
            XCTAssertFalse(f.anchor.isActive)
        }
        XCTAssertTrue(f.moves.isEmpty)
    }

    func testGestureNavigationCancelsPendingClickedTab() throws {
        let f = Fixture()
        let generation = try f.begin(.agents)
        f.anchor.selectionChanged(to: .timer)
        f.frame.origin.x += 240
        f.anchor.update(generation: generation)
        XCTAssertFalse(f.anchor.isActive)
        XCTAssertTrue(f.moves.isEmpty)
    }

    func testNativeScreenFramesFollowWidthMorphAndPanelSettlement() async throws {
        let fixture = NativeTabFrameFixture()
        let host = NSHostingView(rootView: NativeTabFrameFixtureView(fixture: fixture))
        let window = NSWindow(contentRect: CGRect(x: 40, y: 40, width: 1000, height: 80),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { fixture.anchor.cancel(); window.contentView = nil; window.close() }
        func settle() async throws {
            for _ in 0..<15 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        }
        func tab(in view: NSView) -> TabPointerFrame.FrameView? {
            if let frame = view as? TabPointerFrame.FrameView, frame.page == .timer { return frame }
            for child in view.subviews { if let found = tab(in: child) { return found } }
            return nil
        }
        func screenFrame() throws -> CGRect {
            let view = try XCTUnwrap(tab(in: host))
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
        try await settle()
        for width: CGFloat in [320, 850, 850, 400] {
            let before = try screenFrame()
            fixture.pointer = CGPoint(x: before.minX + 12, y: before.minY + 15)
            let generation = try XCTUnwrap(fixture.anchor.activate(.timer, eventType: .leftMouseUp,
                pointer: fixture.pointer, maximumDuration: 5))
            fixture.width = width
            try await settle()
            window.setFrameOrigin(CGPoint(x: window.frame.minX + 20, y: window.frame.minY + 10))
            try await settle()
            let after = try screenFrame()
            fixture.anchor.finish(generation: generation)
            XCTAssertEqual(fixture.pointer.x, after.minX + 12, accuracy: 0.5)
            XCTAssertEqual(fixture.pointer.y, after.minY + 15, accuracy: 0.5)
            XCTAssertFalse(fixture.anchor.isActive)
        }
        XCTAssertGreaterThan(fixture.moves.count, 4, "Native frame sampling follows the rendered transition, including panel settlement")
    }

    func testFailureAndMissingFrameCannotCaptureCursor() throws {
        let f = Fixture()
        let generation = try f.begin()
        f.frame = .zero
        f.anchor.update(generation: generation)
        XCTAssertFalse(f.anchor.isActive)
        let failed = TabPointerAnchor(pointerLocation: { CGPoint(x: 12, y: 15) }, movePointer: { _ in false })
        var frame = CGRect(x: 0, y: 0, width: 32, height: 26)
        failed.register(.timer, owner: UUID()) { frame }
        let g = try XCTUnwrap(failed.activate(.timer, eventType: .leftMouseUp,
            pointer: CGPoint(x: 12, y: 15), maximumDuration: 5))
        frame.origin.x = 200
        failed.update(generation: g)
        XCTAssertFalse(failed.isActive)
    }
}

@MainActor
private final class NativeTabFrameFixture: ObservableObject {
    @Published var width: CGFloat = 850
    var pointer = CGPoint.zero
    var moves: [CGPoint] = []
    let settings = AppSettings(defaults: SettingsPreviewDefaults())
    let navigation = IslandNavigationStore()
    lazy var anchor = TabPointerAnchor(pointerLocation: { [unowned self] in pointer }, movePointer: { [unowned self] point in
        pointer = point; moves.append(point); return true
    })
}

private struct NativeTabFrameFixtureView: View {
    @ObservedObject var fixture: NativeTabFrameFixture
    var body: some View {
        ExpandedIslandPageSwitcher(settings: fixture.settings, navigation: fixture.navigation, pointerAnchor: fixture.anchor)
            .frame(width: fixture.width, height: 40)
            .frame(width: 1000, height: 80)
            .animation(.linear(duration: 0.1), value: fixture.width)
    }
}
