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

    func testPromisedDropCompletionCleansOnlyRetiredTargetsOwnMaterialization() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-promises-\(UUID().uuidString)")
        let storage = FileDragPromiseStorage(rootURL: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let retired = try storage.makeDropDirectory(), other = try storage.makeDropDirectory()
        let file = retired.appendingPathComponent("inert.txt")
        let retainedSibling = retired.appendingPathComponent("retained-output.zip")
        for url in [file, retainedSibling] { try Data("promised".utf8).write(to: url) }
        let ownership = TemporaryFileOwnershipLedger(temporaryRoots: [root])
        ownership.retain([retainedSibling], by: .shelf)
        var target: FilePromiseDropNSView? = FilePromiseDropNSView(storage: storage)
        weak var weakTarget = target
        let finish = try XCTUnwrap(target).promisedDropCompletion(claim: 1, destination: retired, ownership: ownership)
        target = nil
        XCTAssertNil(weakTarget, "The pending receiver must not retain the native destination")
        finish([file], [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedSibling.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "Other drops retain their own temporary files")
        ownership.release([retainedSibling], by: .shelf)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retired.path))
    }

    func testPromisedDropFailureNeverHandsOffPartialPayloadOrRemovesAnotherDrop() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-failed-promises-\(UUID().uuidString)")
        let storage = FileDragPromiseStorage(rootURL: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try storage.makeDropDirectory(), other = try storage.makeDropDirectory()
        let file = destination.appendingPathComponent("partial.txt")
        try Data("partial".utf8).write(to: file)
        let target = FilePromiseDropNSView(storage: storage)
        var failures: [String] = []
        target.onFilesReceived = { _, _ in XCTFail("A partial promise cannot be shared") }
        target.onMaterializationFailed = { claim, message in XCTAssertEqual(claim, 7); failures.append(message) }
        target.promisedDropCompletion(claim: 7, destination: destination,
            ownership: TemporaryFileOwnershipLedger(temporaryRoots: [root]))([file], ["Inert materialization failure"])
        XCTAssertEqual(failures, ["Inert materialization failure"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }

    func testImmediateAndDelayedPromiseCleanupRespectAllSurfaceOwners() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-cleanup-\(UUID().uuidString)")
        let storage = FileDragPromiseStorage(rootURL: root)
        let ownership = TemporaryFileOwnershipLedger(temporaryRoots: [root])
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try storage.makeDropDirectory()
        let basket = directory.appendingPathComponent("basket.txt")
        let sibling = directory.appendingPathComponent("output.zip")
        let orphan = directory.appendingPathComponent("orphan.txt")
        for file in [basket, sibling, orphan] { try Data("inert".utf8).write(to: file) }
        let basketOwner = FileSurfaceOwner.basket(UUID())
        ownership.retain([basket], by: basketOwner)
        ownership.retain([sibling], by: .shelf)
        storage.removeIfOwned([basket, orphan], ownership: ownership)
        XCTAssertTrue(FileManager.default.fileExists(atPath: basket.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        try Data("inert".utf8).write(to: orphan)
        let cleanup = storage.scheduleCleanup([basket, orphan], after: 0, ownership: ownership)
        await cleanup?.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: basket.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        let lateOwner = storage.scheduleCleanup([sibling], after: 0, ownership: ownership)
        await lateOwner?.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
        ownership.release([basket], by: basketOwner)
        ownership.release([sibling], by: .shelf)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testSuccessfulOwnedPromiseBasketDropSurvivesCallbackReplayAndCleanup() async throws {
        let fixture = try await Fixture(localActions: true)
        defer { fixture.close() }
        let directory = try FileDragPromiseStorage.shared.makeDropDirectory()
        let promised = directory.appendingPathComponent("basket-owned.txt")
        try Data("inert promise".utf8).write(to: promised)
        let owner = FileSurfaceOwner.basket(UUID())
        defer { TemporaryFileOwnershipLedger.shared.release([promised], by: owner) }
        fixture.modules.fileDragSession.localActions.addToBasket = .init(isAvailable: { true }, run: { urls in
            TemporaryFileOwnershipLedger.shared.retain(urls, by: owner)
            fixture.basketDrops.append(urls)
            return .handedOff
        })
        fixture.modules.fileDragSession.setSourceTargeted(true)
        try await fixture.settle()
        let target = try XCTUnwrap(fixture.targets.dropFirst(4).first)
        let claim = try XCTUnwrap(target.onDropStarted?())
        target.onFilesReceived?(claim, [promised])
        target.onFilesReceived?(claim, [promised])
        await FileDragPromiseStorage.shared.scheduleCleanup([promised], after: 0)?.value
        XCTAssertEqual(fixture.basketDrops, [[promised]])
        XCTAssertTrue(FileManager.default.fileExists(atPath: promised.path))
    }

    func testOrbitReservationContainsEveryTargetWithoutChangingTheShell() {
        let session = FileDragSessionController()
        let shell = CGRect(x: 100, y: 160, width: 320, height: 260)
        var profile = ExpandedPresentationProfile.standard
        FileDragOrbitMetrics.reserve(in: &profile, session: session)
        XCTAssertEqual(profile, .standard)
        session.localActions = .init(addToBasket: .init(isAvailable: { true }, run: { _ in .handedOff }),
                                     compress: .init(isAvailable: { true }, run: { _ in .handedOff }))
        session.setSourceTargeted(true)
        FileDragOrbitMetrics.reserve(in: &profile, session: session)
        let panel = profile.panelFrame(forExpandedFrame: shell)
        let orbit = FileDragOrbitMetrics.frame(shell: shell, actionCount: 6)
        XCTAssertTrue(panel.contains(orbit))
        XCTAssertEqual(profile.resolvedSize(from: shell.size), shell.size)
        for index in 0..<6 {
            let local = FileDragOrbitMetrics.targetFrame(index: index, count: 6)
            XCTAssertTrue(CGRect(origin: .zero, size: orbit.size).contains(local))
            for other in 0..<index {
                XCTAssertFalse(local.intersects(FileDragOrbitMetrics.targetFrame(index: other, count: 6)))
            }
        }
    }

    func testAlreadyExpandedNativePanelReservesAndReleasesOrbitSpace() async throws {
        _ = NSApplication.shared
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.mediaEnabled = false
        settings.reduceExtraMotion = true
        settings.showNavigationControls = false
        settings.rememberLastSelectedTab = true
        let modules = NativeIslandFixtureModules.make(settings: settings)
        modules.navigation.showTray()
        let state = IslandStateStore()
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OverlayWindowController(settings: settings, islandState: state, modules: modules,
                                                 geometryService: NotchGeometryService())
        let panel = try XCTUnwrap(NSApp.windows.first { $0 is IslandOverlayPanel && !before.contains(ObjectIdentifier($0)) })
        defer { controller.setVisible(false); panel.close() }
        controller.show()
        state.expand()
        try await Task.sleep(for: .milliseconds(80))
        let original = panel.frame
        XCTAssertEqual(state.state, .expanded)
        modules.fileDragSession.setSourceTargeted(true, region: .trayShelf)
        try await Task.sleep(for: .milliseconds(100))
        let expanded = panel.frame
        XCTAssertEqual(expanded.maxY, original.maxY, accuracy: 1, "The shell stays pinned while accessory space grows below it")
        XCTAssertEqual(expanded.height - original.height, FileDragOrbitMetrics.accessoryHeight, accuracy: 1)
        let content = try XCTUnwrap(panel.contentView)
        content.layoutSubtreeIfNeeded()
        func targets(_ view: NSView) -> [FilePromiseDropNSView] {
            (view as? FilePromiseDropNSView).map { [$0] } ?? view.subviews.flatMap(targets)
        }
        let nativeTargets = targets(content)
        XCTAssertEqual(nativeTargets.count, 4)
        for target in nativeTargets {
            XCTAssertTrue(CGRect(origin: .zero, size: panel.frame.size).contains(target.convert(target.bounds, to: nil)))
        }
        modules.fileDragSession.setActionTargeted(.mail, true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(panel.frame, expanded, "Changing targets within one drag cannot churn native geometry")
        modules.fileDragSession.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(panel.frame, original)
        XCTAssertTrue(targets(content).isEmpty)
    }

    func testProductionRootMountsReachableNativeTargetsAndOneDropRunsOneAction() async throws {
        let fixture = try await Fixture(localActions: true, reducedMotion: false)
        defer { fixture.close() }
        XCTAssertTrue(fixture.targets.isEmpty, "Idle roots must not expose drag actions")
        fixture.modules.fileDragSession.setSourceTargeted(true, region: .trayShelf)
        try await fixture.settle()
        let targets = fixture.targets
        XCTAssertEqual(targets.count, 6)
        XCTAssertEqual(fixture.layout.expandedAccessoryFrames.count, 1, "The orbit replaces navigation only during the drag")
        let orbit = try XCTUnwrap(fixture.layout.expandedAccessoryFrames.first)
        for target in targets {
            let nativeFrame = target.convert(target.bounds, to: fixture.host)
            XCTAssertTrue(fixture.host.bounds.contains(nativeFrame))
            XCTAssertTrue(orbit.contains(target.convert(target.bounds, to: nil)),
                          "Native targets must be inside registered accessory hit geometry")
            // NSView.hitTest takes its superview's coordinates; NSHostingView is flipped.
            let point = fixture.host.convert(CGPoint(x: nativeFrame.midX, y: nativeFrame.midY), to: fixture.host.superview)
            let hit = try XCTUnwrap(fixture.host.hitTest(point))
            XCTAssertTrue(hit === target || hit.isDescendant(of: target), "A real native hit must reach the target; hit=\(type(of: hit)), hitFrame=\(hit.frame), target=\(nativeFrame), flipped=\(fixture.host.isFlipped)")
        }
        try fixture.capture("native-root-six-targets")
        let stableFrames = targets.map { $0.convert($0.bounds, to: nil) }
        fixture.modules.fileDragSession.setActionTargeted(.mail, true)
        try await fixture.settle()
        XCTAssertEqual(fixture.targets.map { $0.convert($0.bounds, to: nil) }, stableFrames)
        try fixture.capture("native-root-targeted-mail")
        let drag = try fixture.drag()
        let basket = targets[4]
        XCTAssertEqual(basket.draggingEntered(drag), .copy)
        XCTAssertTrue(basket.performDragOperation(drag))
        XCTAssertEqual(fixture.basketDrops, [[fixture.file.standardizedFileURL]])
        XCTAssertEqual(fixture.compressions, 0)
        XCTAssertFalse(fixture.modules.fileDragSession.isActive)
        let completedGeneration = fixture.modules.fileDragSession.generation
        // A callback replay from this native destination cannot execute again.
        basket.onFilesReceived?(fixture.modules.fileDragSession.generation - 1, [fixture.file])
        XCTAssertEqual(fixture.basketDrops.count, 1)
        try await fixture.settle()
        XCTAssertTrue(fixture.targets.isEmpty)
        XCTAssertFalse(fixture.modules.fileDragSession.isActive, "Deferred native entered/exit callbacks cannot resurrect a completed drag")
        XCTAssertEqual(fixture.modules.fileDragSession.generation, completedGeneration)
        XCTAssertFalse(fixture.layout.expandedAccessoryFrames.contains(orbit))
    }

    func testCollapseImmediatelyRevokesAMaterializingNativeDrop() async throws {
        let fixture = try await Fixture(localActions: true)
        defer { fixture.close() }
        fixture.modules.fileDragSession.setSourceTargeted(true)
        try await fixture.settle()
        let target = try XCTUnwrap(fixture.targets.dropFirst(4).first)
        let claim = try XCTUnwrap(target.onDropStarted?())
        fixture.state.collapse()
        // Receiver delivery can precede SwiftUI's deferred onChange cancellation.
        target.onFilesReceived?(claim, [fixture.file])
        XCTAssertTrue(fixture.basketDrops.isEmpty)
        try await fixture.settle()
        XCTAssertFalse(fixture.modules.fileDragSession.isActive)
    }

    func testBridgeKeepsExternalDragAliveAndCollapseRejectsDelayedMaterialization() async throws {
        let fixture = try await Fixture(localActions: true)
        defer { fixture.close() }
        fixture.modules.fileDragSession.setSourceTargeted(true, region: .trayShelf)
        try await fixture.settle()
        let bridge = try XCTUnwrap(fixture.descendants.compactMap { $0 as? FileDragBridgeNSView }.first)
        let drag = try fixture.drag()
        XCTAssertEqual(bridge.draggingEntered(drag), .copy)
        await Task.yield()
        fixture.modules.fileDragSession.setSourceTargeted(false, region: .trayShelf)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(fixture.modules.fileDragSession.isActive, "The native bridge owns gaps between targets")
        let basket = try XCTUnwrap(fixture.targets.dropFirst(4).first)
        let generation = try XCTUnwrap(basket.onDropStarted?())
        XCTAssertNil(fixture.targets.first?.onDropStarted?(), "The first destination owns the drop")
        fixture.layout.isExpandedContentExiting = true
        try await fixture.settle()
        XCTAssertFalse(fixture.modules.fileDragSession.isActive)
        XCTAssertTrue(fixture.targets.isEmpty)
        XCTAssertTrue(fixture.layout.expandedAccessoryFrames.isEmpty)
        let promisedDirectory = try FileDragPromiseStorage.shared.makeDropDirectory()
        let promised = promisedDirectory.appendingPathComponent("stale-inert.txt")
        try Data("stale promise".utf8).write(to: promised)
        let retainedSibling = promisedDirectory.appendingPathComponent("retained-by-shelf.txt")
        try Data("retained".utf8).write(to: retainedSibling)
        TemporaryFileOwnershipLedger.shared.retain([retainedSibling], by: .shelf)
        defer { TemporaryFileOwnershipLedger.shared.release([retainedSibling], by: .shelf) }
        basket.onFilesReceived?(generation, [promised])
        XCTAssertFalse(FileManager.default.fileExists(atPath: promised.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedSibling.path), "Stale cleanup cannot delete an owned sibling")
        basket.onFilesReceived?(generation, [retainedSibling])
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedSibling.path), "A retained file cannot be deleted by a stale callback")
        XCTAssertTrue(fixture.basketDrops.isEmpty)
        _ = bridge.draggingEntered(drag)
        fixture.modules.fileDragSession.cancel()
        let cancelledGeneration = fixture.modules.fileDragSession.generation
        try await fixture.settle()
        XCTAssertEqual(fixture.modules.fileDragSession.generation, cancelledGeneration,
                       "A retired bridge cannot publish targeting into another generation")
        fixture.state.collapse()
        try await fixture.settle()
        XCTAssertFalse(fixture.modules.fileDragSession.isActive)
        XCTAssertTrue(fixture.layout.expandedAccessoryFrames.isEmpty)
    }

    func testShareOnlyOrbitAndReducedMotionUseTheSameNativeGeometry() async throws {
        let fixture = try await Fixture(localActions: false)
        defer { fixture.close() }
        fixture.modules.fileDragSession.setSourceTargeted(true, region: .collapsedIsland)
        try await fixture.settle()
        XCTAssertEqual(fixture.targets.count, 4, "Unavailable Basket/Compress services expose no native destinations")
        XCTAssertEqual(fixture.modules.fileDragSession.orbitActions, FileDragQuickAction.shareActions)
        try fixture.capture("native-root-share-only-reduced-motion")
        let bridge = try XCTUnwrap(fixture.descendants.compactMap { $0 as? FileDragBridgeNSView }.first)
        let drag = try fixture.drag()
        _ = bridge.draggingEntered(drag)
        await Task.yield()
        fixture.modules.fileDragSession.setSourceTargeted(false, region: .collapsedIsland)
        bridge.draggingExited(drag)
        try await Task.sleep(for: .milliseconds(300))
        try await fixture.settle()
        XCTAssertFalse(fixture.modules.fileDragSession.isActive)
        XCTAssertTrue(fixture.targets.isEmpty)
        XCTAssertEqual(fixture.layout.expandedAccessoryFrames.count, 1, "Navigation returns after drag cancellation")
    }

    @MainActor
    private final class Fixture {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        let modules: IslandModules
        let state = IslandStateStore()
        let layout = IslandLayoutStore()
        let window: NSWindow
        let host: NSView
        let file: URL
        var basketDrops: [[URL]] = []
        var compressions = 0

        init(localActions: Bool, reducedMotion: Bool = true) async throws {
            _ = NSApplication.shared
            settings.mediaEnabled = false
            settings.reduceExtraMotion = reducedMotion
            settings.contentAnimationEnabled = false
            modules = NativeIslandFixtureModules.make(settings: settings)
            modules.navigation.showTray()
            file = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-fixture-\(UUID().uuidString).txt")
            try Data("Inert native drag fixture".utf8).write(to: file)
            let panel = CGRect(x: 0, y: 0, width: 800, height: 550)
            layout.canvasSize = panel.size
            layout.collapsedSurfaceFrame = CGRect(x: 290, y: 516, width: 220, height: 34)
            layout.expandedSurfaceFrame = CGRect(x: 20, y: 130, width: 760, height: 400)
            layout.expandedSize = layout.expandedSurfaceFrame.size
            layout.hasHardwareNotch = false
            state.expand()
            let root = IslandRootView(settings: settings, islandState: state, layoutStore: layout,
                escapeRouter: IslandEscapeRouter(), modules: modules, rendersExpandedVisualContent: true,
                onRequestExpand: {}, onRequestCollapse: {}, onOpenSettings: {})
                .environment(\.isSettingsPreview, true)
                .environment(\.settingsPreviewReduceMotion, reducedMotion)
            host = NSHostingView(rootView: root)
            window = IslandOverlayPanel(contentRect: panel, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            window.orderFrontRegardless()
            if localActions {
                modules.fileDragSession.localActions = .init(
                    addToBasket: .init(isAvailable: { true }, run: { [weak self] urls in self?.basketDrops.append(urls); return .handedOff }),
                    compress: .init(isAvailable: { true }, run: { [weak self] _ in self?.compressions += 1; return .handedOff }))
            }
            try await settle()
        }

        var descendants: [NSView] {
            func flatten(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(flatten) }
            return flatten(host)
        }
        var targets: [FilePromiseDropNSView] {
            descendants.compactMap { $0 as? FilePromiseDropNSView }.sorted {
                $0.convert($0.bounds, to: host).midX < $1.convert($1.bounds, to: host).midX
            }
        }
        func settle() async throws {
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
        }
        func drag() throws -> OrbitDraggingInfo {
            let pasteboard = NSPasteboard(name: .init("OrbitFixture-\(UUID().uuidString)"))
            XCTAssertTrue(pasteboard.writeObjects([file as NSURL]))
            return OrbitDraggingInfo(pasteboard: pasteboard, window: window)
        }
        func capture(_ name: String) throws {
            guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_FILE_DRAG_SNAPSHOT_DIR"] else { return }
            let output = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
        }
        func close() {
            modules.fileDragSession.cancel()
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: file)
        }
    }
}

@MainActor
private final class OrbitDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow?
    init(pasteboard: NSPasteboard, window: NSWindow) {
        draggingPasteboard = pasteboard; draggingDestinationWindow = window
    }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
