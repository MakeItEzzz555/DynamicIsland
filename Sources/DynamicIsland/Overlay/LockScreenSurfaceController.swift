import AppKit
import SwiftUI

enum LockScreenSpaceAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

/// The only route onto the secure lock-screen layer. The production default is
/// `UnavailableLockScreenSpace` (public APIs only); a private implementation
/// may be added only with explicit approval and must fail closed.
@MainActor
protocol LockScreenSpaceProviding: AnyObject {
    var availability: LockScreenSpaceAvailability { get }
    /// Moves one window onto the lock-screen space. False means it was not
    /// adopted and must not be shown.
    func adopt(windowNumber: Int) -> Bool
    /// Idempotent; drops every adopted window from the space.
    func teardown()
}

/// No public API draws above macOS's secure lock screen, so nothing is shown.
@MainActor
final class UnavailableLockScreenSpace: LockScreenSpaceProviding {
    let availability = LockScreenSpaceAvailability.unavailable(
        reason: "macOS has no public API for widgets above the Lock Screen.")
    func adopt(windowNumber: Int) -> Bool { false }
    func teardown() {}
}

enum LockScreenSurfaceKind: String, CaseIterable, Sendable {
    case hud, nowPlaying, timer, alert, sideHUD, status

    /// Only controls take the pointer; everything else is click-through.
    var isInteractive: Bool { self == .nowPlaying || self == .timer || self == .sideHUD }
}

/// Owns one separate window per lock-screen surface. Never touches the island's
/// panel. A window is ordered front only after the space adopted it; if the
/// state is not a confirmed lock, every surface is hidden.
@MainActor
final class LockScreenSurfaceController {
    private let space: LockScreenSpaceProviding
    private let frame: (LockScreenSurfaceKind) -> CGRect?
    private let content: (LockScreenSurfaceKind) -> AnyView
    private var windows: [LockScreenSurfaceKind: NSPanel] = [:]
    private var adopted: Set<LockScreenSurfaceKind> = []
    private(set) var visible: Set<LockScreenSurfaceKind> = []

    init(space: LockScreenSpaceProviding,
         frame: @escaping (LockScreenSurfaceKind) -> CGRect?,
         content: @escaping (LockScreenSurfaceKind) -> AnyView) {
        self.space = space
        self.frame = frame
        self.content = content
    }

    var availability: LockScreenSpaceAvailability { space.availability }

    /// Shows exactly `requested` when the screen is confirmed locked; hides the rest.
    func update(state: LockState, requested: Set<LockScreenSurfaceKind>) {
        let target = state.isConfirmedLocked && space.availability == .available ? requested : []
        for kind in visible.subtracting(target) { hide(kind) }
        for kind in target.subtracting(visible) { show(kind) }
    }

    /// Termination, disable or uncertain ownership. Idempotent.
    func stop() {
        for kind in visible { hide(kind) }
        for window in windows.values { window.contentView = nil; window.close() }
        windows.removeAll()
        adopted.removeAll()
        space.teardown()
    }

    private func show(_ kind: LockScreenSurfaceKind) {
        guard let rect = frame(kind) else { return }
        let window = windows[kind] ?? makeWindow(kind)
        windows[kind] = window
        window.setFrame(rect, display: false)
        if window.contentView == nil { window.contentView = NSHostingView(rootView: content(kind)) }
        if !adopted.contains(kind) {
            guard space.adopt(windowNumber: window.windowNumber) else { return }
            adopted.insert(kind)
        }
        window.orderFrontRegardless()
        visible.insert(kind)
    }

    private func hide(_ kind: LockScreenSurfaceKind) {
        windows[kind]?.orderOut(nil)
        visible.remove(kind)
    }

    static func makeWindow(_ kind: LockScreenSurfaceKind) -> NSPanel {
        let window = LockScreenPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.canBecomeVisibleWithoutLogin = true
        window.ignoresMouseEvents = !kind.isInteractive
        // Never captured into screenshots or recordings of the locked screen.
        window.sharingType = .none
        return window
    }

    private func makeWindow(_ kind: LockScreenSurfaceKind) -> NSPanel { Self.makeWindow(kind) }
}

/// Never key or main: a lock-screen control must not take keyboard focus away
/// from the password field.
final class LockScreenPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
