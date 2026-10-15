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
    /// Creates the space ahead of time. A space created while the lock screen
    /// is already up only appears from the next lock on (measured live).
    func prepare() -> Bool
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
    func prepare() -> Bool { false }
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
    private var hosted: Set<LockScreenSurfaceKind> = []
    private(set) var visible: Set<LockScreenSurfaceKind> = []

    init(space: LockScreenSpaceProviding,
         frame: @escaping (LockScreenSurfaceKind) -> CGRect?,
         content: @escaping (LockScreenSurfaceKind) -> AnyView) {
        self.space = space
        self.frame = frame
        self.content = content
    }

    var availability: LockScreenSpaceAvailability { space.availability }

    /// While unlocked: create the space and adopt every surface window, hidden,
    /// so a lock only has to order them front.
    func prepare(_ kinds: Set<LockScreenSurfaceKind>) {
        guard space.availability == .available, space.prepare() else { return }
        for kind in kinds where !adopted.contains(kind) {
            guard let rect = frame(kind), rect.width > 0, rect.height > 0 else { continue }
            let window = windows[kind] ?? makeWindow(kind)
            windows[kind] = window
            // Make AppKit/SwiftUI construct the backing host on the unlocked
            // desktop, before SkyLight moves the window into the secure space.
            // An empty zero-sized panel adopted ahead of time can appear in
            // WindowServer listings without ever submitting rendered content
            // once loginwindow owns the display.
            window.setFrame(rect, display: false)
            installContent(kind, in: window)
            if space.adopt(windowNumber: window.windowNumber) { adopted.insert(kind) }
        }
    }

    /// Shows exactly `requested` when the screen is confirmed locked; hides the rest.
    func update(state: LockState, requested: Set<LockScreenSurfaceKind>) {
        let target = state.isConfirmedLocked && space.availability == .available ? requested : []
        for kind in visible.subtracting(target) { hide(kind) }
        for kind in target.subtracting(visible) { show(kind) }
    }

    /// Display configuration changed: move visible surfaces to their new frames.
    func relayout() {
        for kind in visible {
            guard let rect = frame(kind) else { hide(kind); continue }
            windows[kind]?.setFrame(rect, display: true)
        }
    }

    /// Termination, disable or uncertain ownership. Idempotent.
    func stop() {
        for kind in visible { hide(kind) }
        for window in windows.values { window.contentView = nil; window.close() }
        windows.removeAll()
        adopted.removeAll()
        hosted.removeAll()
        space.teardown()
    }

    private func show(_ kind: LockScreenSurfaceKind) {
        guard let rect = frame(kind) else { return }
        let window = windows[kind] ?? makeWindow(kind)
        windows[kind] = window
        window.setFrame(rect, display: false)
        installContent(kind, in: window)
        if !adopted.contains(kind) {
            guard space.adopt(windowNumber: window.windowNumber) else { return }
            adopted.insert(kind)
        }
        window.orderFrontRegardless()
        visible.insert(kind)
    }

    private func installContent(_ kind: LockScreenSurfaceKind, in window: NSPanel) {
        // NSPanel starts with a default empty contentView, not nil.
        // Remember our installed host instead of checking that property.
        guard !hosted.contains(kind) else { return }
        let host: NSView = kind.isInteractive
            ? LockScreenHostingView(rootView: content(kind))
            : NSHostingView(rootView: content(kind))
        host.frame = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = host
        hosted.insert(kind)
        // Establish the view hierarchy while still on the unlocked desktop;
        // actual pixels stay hidden until a confirmed lock.
        host.layoutSubtreeIfNeeded()
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

/// The panel never becomes key, so a control must act on the first click
/// instead of spending it on activation.
final class LockScreenHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Never key or main: a lock-screen control must not take keyboard focus away
/// from the password field.
final class LockScreenPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
