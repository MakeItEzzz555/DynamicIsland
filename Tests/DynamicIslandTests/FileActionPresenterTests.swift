import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class FileActionPresenterTests: XCTestCase {
    func testCollapsedAnchorPresentsWithoutTrayHostAndReleasesOnlyItsOwner() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let cameraOwner = TransientInteractionOwner.cameraNavigation(UUID())
        fixture.layout.setTransientInteraction(true, owner: cameraOwner)
        let request = try XCTUnwrap(fixture.shelf.fileActionRequest)
        XCTAssertTrue(fixture.presenter.present(request, relativeTo: fixture.anchor, of: fixture.view, permitted: true))
        await fixture.settle()
        XCTAssertTrue(fixture.presenter.isShown)
        let content = try XCTUnwrap(fixture.presenter.presentationWindow?.contentView)
        XCTAssertGreaterThanOrEqual(content.bounds.width, 570, "Native popup must fit all six format tiles on a normal display")
        XCTAssertTrue(fixture.layout.transientInteractionOwners.contains(cameraOwner))
        XCTAssertEqual(fixture.layout.transientInteractionOwners.count, 2)
        XCTAssertFalse(fixture.presenter.present(request, relativeTo: fixture.anchor, of: fixture.view, permitted: true), "Repeated publication cannot mount a second popup")
        fixture.presenter.close(); await fixture.settle()
        XCTAssertFalse(fixture.presenter.isShown); XCTAssertNil(fixture.shelf.fileActionRequest)
        XCTAssertEqual(fixture.layout.transientInteractionOwners, [cameraOwner])
    }
    func testProtectedRequestWaitsAndStaleDismissPreservesNewerAcceptedDrop() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let first = try XCTUnwrap(fixture.shelf.fileActionRequest)
        XCTAssertFalse(fixture.presenter.present(first, relativeTo: fixture.anchor, of: fixture.view, permitted: false))
        XCTAssertEqual(fixture.shelf.fileActionRequest?.id, first.id)
        XCTAssertTrue(fixture.layout.transientInteractionOwners.isEmpty)
        XCTAssertTrue(fixture.presenter.present(first, relativeTo: fixture.anchor, of: fixture.view, permitted: true))
        await fixture.settle()
        fixture.shelf.requestFileActions(for: [fixture.file])
        let next = try XCTUnwrap(fixture.shelf.fileActionRequest)
        fixture.presenter.close(); await fixture.settle()
        XCTAssertEqual(fixture.shelf.fileActionRequest?.id, next.id)
        XCTAssertTrue(fixture.presenter.present(next, relativeTo: fixture.anchor, of: fixture.view, permitted: true))
        await fixture.settle()
        XCTAssertTrue(fixture.presenter.isShown)
    }
    func testPopupBoundsAndClosingCannotStealAnotherWindowsFocus() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        guard let screen = fixture.window.screen else { throw XCTSkip("A native display is required") }
        fixture.window.setFrameOrigin(.init(x: screen.visibleFrame.maxX - fixture.window.frame.width, y: screen.visibleFrame.minY + 30))
        let corner = CGRect(x: fixture.view.bounds.maxX - 40, y: fixture.view.bounds.maxY - 45, width: 30, height: 30)
        XCTAssertTrue(fixture.presenter.present(try XCTUnwrap(fixture.shelf.fileActionRequest), relativeTo: corner, of: fixture.view, permitted: true))
        await fixture.settle()
        let popup = try XCTUnwrap(fixture.presenter.presentationWindow)
        XCTAssertTrue(screen.visibleFrame.insetBy(dx: -2, dy: -2).contains(popup.frame), "Native popup must remain on its anchor's display: popup=\(popup.frame), visible=\(screen.visibleFrame)")
        let other = NSWindow(contentRect: .init(x: 100, y: 100, width: 250, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false; defer { other.close() }
        other.makeKeyAndOrderFront(nil)
        let wasKey = other.isKeyWindow
        fixture.presenter.close(); await fixture.settle()
        if wasKey { XCTAssertTrue(other.isKeyWindow) }
        XCTAssertFalse(fixture.layout.isTransientInteractionActive)
    }

    func testUnacceptedSourceAndMissingAnchorCannotClaimInteraction() throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let unknown = FileTrayActionRequest(id: UUID(), urls: [URL(fileURLWithPath: "/not-an-accepted-file")])
        XCTAssertFalse(fixture.presenter.present(unknown, relativeTo: fixture.anchor, of: fixture.view, permitted: true))
        XCTAssertFalse(fixture.presenter.present(try XCTUnwrap(fixture.shelf.fileActionRequest), relativeTo: .zero, of: fixture.view, permitted: true))
        XCTAssertTrue(fixture.layout.transientInteractionOwners.isEmpty)
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let file: URL
        let shelf: FileShelfStore
        let layout = IslandLayoutStore()
        let window: NSWindow
        let view: NSView
        let presenter: FileActionPresenter
        let name = "DynamicIsland.FileActions.Test.\(UUID().uuidString)"
        let anchor = NSRect(x: 200, y: 620, width: 190, height: 38)
        init() throws {
            _ = NSApplication.shared
            root = FileManager.default.temporaryDirectory.appendingPathComponent("file-presenter-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            file = root.appendingPathComponent("fixture.txt"); try Data("Synthetic file".utf8).write(to: file)
            let settings = AppSettings(defaults: SettingsPreviewDefaults())
            shelf = FileShelfStore(settings: settings, defaults: SettingsPreviewDefaults(), ownership: TemporaryFileOwnershipLedger(temporaryRoots: []))
            shelf.add([file]); shelf.requestFileActions(for: [file])
            window = SettingsWindowController.makeWindow(frameAutosaveName: name)
            view = NSHostingView(rootView: Color.black.frame(width: 720, height: 700))
            window.contentView = view; window.makeKeyAndOrderFront(nil)
            presenter = FileActionPresenter(shelf: shelf, operations: BackgroundOperationController(liveActivities: LiveActivityStore()), layout: layout)
        }
        func settle() async {
            for _ in 0..<10 { CameraNativeHostedFixture.pump(); try? await Task.sleep(for: .milliseconds(20)) }
        }
        func close() {
            presenter.close(); window.setFrameAutosaveName(""); window.close(); NSWindow.removeFrame(usingName: name)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
