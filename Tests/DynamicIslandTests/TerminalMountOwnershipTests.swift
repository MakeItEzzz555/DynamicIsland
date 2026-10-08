import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class TerminalMountOwnershipTests: XCTestCase {
    func testSwiftUIParentGenerationPrecedesLateConditionalChildCreation() async throws {
        _ = NSApplication.shared
        let runner = TerminalMountTestRunner()
        let controller = TerminalSessionController(liveActivities: LiveActivityStore(),
            capabilities: IslandCapabilityRegistry(), runner: runner, workingDirectoryPath: "/tmp")
        let olderState = DeferredTerminalState()
        let newerState = DeferredTerminalState()
        newerState.showsTerminal = true
        func root(_ state: DeferredTerminalState) -> AnyView {
            AnyView(DeferredTerminalContent(state: state, controller: controller)
                .modifier(NativeTerminalPresentationScope()))
        }
        let older = NSHostingView(rootView: root(olderState))
        let newer = NSHostingView(rootView: root(newerState))
        let size = CGSize(width: 420, height: 240)
        let windows = [older, newer].enumerated().map { index, hosting in
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -5000 - index * 1000, y: -5000), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            hosting.frame = CGRect(origin: .zero, size: size)
            window.contentView = hosting
            return window
        }
        defer {
            controller.terminate()
            for window in windows { window.makeFirstResponder(nil); window.contentView = nil; window.close() }
        }
        windows[0].orderFrontRegardless()
        let parentDeadline = ContinuousClock.now + .seconds(2)
        while olderState.generation == nil, ContinuousClock.now < parentDeadline {
            try await Task.sleep(for: .milliseconds(3))
            older.layoutSubtreeIfNeeded()
        }
        let olderGeneration = try XCTUnwrap(olderState.generation)
        windows[1].orderFrontRegardless()
        let newerDeadline = ContinuousClock.now + .seconds(2)
        while (controller.terminalView.superview == nil || !controller.isRunning), ContinuousClock.now < newerDeadline {
            try await Task.sleep(for: .milliseconds(3))
            newer.layoutSubtreeIfNeeded()
        }
        let newerMount = try XCTUnwrap(controller.terminalView.superview as? TerminalMountView)
        XCTAssertGreaterThan(newerMount.mountGeneration.presentation, olderGeneration)

        olderState.showsTerminal = true
        func findMount(_ view: NSView) -> TerminalMountView? {
            if let mount = view as? TerminalMountView { return mount }
            return view.subviews.lazy.compactMap(findMount).first
        }
        let lateDeadline = ContinuousClock.now + .seconds(2)
        while findMount(older) == nil, ContinuousClock.now < lateDeadline {
            try await Task.sleep(for: .milliseconds(3))
            older.layoutSubtreeIfNeeded()
        }
        let lateChild = try XCTUnwrap(findMount(older))
        XCTAssertTrue(lateChild.wasVisible)
        XCTAssertGreaterThan(lateChild.mountGeneration.host, newerMount.mountGeneration.host)
        XCTAssertEqual(lateChild.mountGeneration.presentation, olderGeneration)
        XCTAssertTrue(controller.terminalView.superview === newerMount,
                      "a native child created later still belongs to the older logical presentation")
        older.rootView = AnyView(EmptyView())
        let removalDeadline = ContinuousClock.now + .seconds(2)
        while lateChild.wasVisible, ContinuousClock.now < removalDeadline {
            try await Task.sleep(for: .milliseconds(3))
            older.layoutSubtreeIfNeeded()
        }
        XCTAssertFalse(lateChild.wasVisible)
        XCTAssertTrue(controller.terminalView.superview === newerMount)
        XCTAssertTrue(controller.mountCoordinator.owner === newerMount)
        XCTAssertEqual(runner.starts, 1)
        XCTAssertEqual(controller.processID, 42)
    }

    private func host(_ presentation: UInt64, _ sequence: UInt64,
                      coordinator: TerminalMountCoordinator) -> TerminalMountView {
        let host = TerminalMountView()
        host.mountGeneration = .init(presentation: presentation, host: sequence)
        host.mountCoordinator = coordinator
        host.wasVisible = true
        return host
    }

    func testStaleAcquireUpdateAndDismantleCannotDetachNewerOwner() {
        _ = NSApplication.shared
        let coordinator = TerminalMountCoordinator()
        let terminal = InteractiveTerminalView()
        let older = host(1, 1, coordinator: coordinator)
        let newer = host(2, 2, coordinator: coordinator)
        XCTAssertTrue(coordinator.acquire(terminal, by: older))
        XCTAssertTrue(coordinator.acquire(terminal, by: newer))
        XCTAssertFalse(coordinator.acquire(terminal, by: older))
        coordinator.release(older)
        NativeTerminalHost.dismantleNSView(older, coordinator: ())
        XCTAssertTrue(coordinator.owner === newer)
        XCTAssertEqual(coordinator.authoritativeLease?.generation.presentation, 2)
        XCTAssertEqual(coordinator.authoritativeLease?.hostID, ObjectIdentifier(newer))
        XCTAssertTrue(terminal.superview === newer)

        NativeTerminalHost.dismantleNSView(newer, coordinator: ())
        XCTAssertNil(coordinator.owner)
        XCTAssertNil(terminal.superview)
        XCTAssertFalse(coordinator.acquire(terminal, by: older), "release preserves the generation watermark")
    }

    func testOnlyCurrentGenerationCanReclaimUnexpectedlyDetachedEmulator() {
        _ = NSApplication.shared
        let coordinator = TerminalMountCoordinator()
        let terminal = InteractiveTerminalView()
        let older = host(1, 1, coordinator: coordinator)
        let newer = host(2, 2, coordinator: coordinator)
        XCTAssertTrue(coordinator.acquire(terminal, by: older))
        XCTAssertTrue(coordinator.acquire(terminal, by: newer))
        terminal.removeFromSuperview()
        XCTAssertFalse(coordinator.acquire(terminal, by: older))
        XCTAssertNil(terminal.superview)
        XCTAssertTrue(coordinator.acquire(terminal, by: newer))
        XCTAssertTrue(terminal.superview === newer)
        XCTAssertTrue(coordinator.owner === newer)
        newer.detach()
    }

    func testLateChildCreationCannotPromoteRetiredPresentation() {
        _ = NSApplication.shared
        let coordinator = TerminalMountCoordinator()
        let terminal = InteractiveTerminalView()
        let newerPresentation = host(2, 10, coordinator: coordinator)
        let lateOlderChild = host(1, 11, coordinator: coordinator)
        XCTAssertTrue(coordinator.acquire(terminal, by: newerPresentation))
        XCTAssertFalse(coordinator.acquire(terminal, by: lateOlderChild))
        lateOlderChild.detach()
        XCTAssertTrue(terminal.superview === newerPresentation)
        newerPresentation.detach()
    }

    func testRemountWithinSamePresentationRejectsOldHostAndRetainsEmulator() {
        _ = NSApplication.shared
        let coordinator = TerminalMountCoordinator()
        let terminal = InteractiveTerminalView()
        let compact = host(1, 1, coordinator: coordinator)
        let standard = host(1, 2, coordinator: coordinator)
        let large = host(1, 3, coordinator: coordinator)
        for host in [compact, standard, large] { XCTAssertTrue(coordinator.acquire(terminal, by: host)) }
        for retired in [compact, standard] {
            XCTAssertFalse(coordinator.acquire(terminal, by: retired))
            retired.detach()
            XCTAssertTrue(terminal.superview === large)
        }
        large.detach()
    }

    func testRetiredHostWindowNotificationsCannotClearCurrentKeyboardEngagement() {
        _ = NSApplication.shared
        let coordinator = TerminalMountCoordinator()
        let terminal = InteractiveTerminalView()
        let older = host(1, 1, coordinator: coordinator)
        let newer = host(2, 2, coordinator: coordinator)
        let window = NSWindow(contentRect: CGRect(x: -5000, y: -5000, width: 420, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 420, height: 240))
        root.addSubview(older)
        root.addSubview(newer)
        window.contentView = root
        defer { newer.detach(); window.contentView = nil; window.close() }
        XCTAssertTrue(coordinator.acquire(terminal, by: older))
        XCTAssertTrue(coordinator.acquire(terminal, by: newer))
        XCTAssertTrue(window.makeFirstResponder(terminal))
        terminal.userEngaged = true
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        XCTAssertTrue(terminal.userEngaged)
        XCTAssertTrue(terminal.superview === newer)
        window.makeFirstResponder(nil)
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        XCTAssertFalse(terminal.userEngaged)
        XCTAssertTrue(terminal.superview === newer, "focus loss must not release the mount lease")
    }
}

@MainActor
private final class DeferredTerminalState: ObservableObject {
    @Published var showsTerminal = false
    var generation: UInt64?
}

private struct DeferredTerminalContent: View {
    @ObservedObject var state: DeferredTerminalState
    let controller: TerminalSessionController
    @Environment(\.terminalPresentationGeneration) private var generation

    var body: some View {
        ZStack {
            Color.clear.onAppear { state.generation = generation }
            if state.showsTerminal {
                NativeTerminalHost(controller: controller, initialDirectory: "/tmp", isVisible: true, focusRequest: 0)
            }
        }
    }
}

@MainActor
private final class TerminalMountTestRunner: TerminalProcessRunning {
    private final class Handle: TerminalProcessHandle {
        var isRunning = true
        var processID: Int32? { 42 }
        func terminate() { isRunning = false }
    }
    var starts = 0
    func start(command: String, shellPath: String, workingDirectory: URL?,
               onOutput: @escaping @Sendable (String) -> Void,
               onExit: @escaping @Sendable (Int32) -> Void) throws -> TerminalProcessHandle {
        starts += 1
        return Handle()
    }
}
