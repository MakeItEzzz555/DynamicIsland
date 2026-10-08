import AppKit
import SwiftUI

/// Allocated before conditional Terminal children appear, so a retiring page
/// cannot gain a newer lease merely by creating its native child late.
@MainActor
struct NativeTerminalPresentationScope: ViewModifier {
    @StateObject private var identity = TerminalPresentationIdentity()

    func body(content: Content) -> some View {
        content.environment(\.terminalPresentationGeneration, identity.generation)
    }
}

private struct TerminalPresentationGenerationKey: EnvironmentKey {
    static let defaultValue: UInt64? = nil
}

extension EnvironmentValues {
    var terminalPresentationGeneration: UInt64? {
        get { self[TerminalPresentationGenerationKey.self] }
        set { self[TerminalPresentationGenerationKey.self] = newValue }
    }
}

@MainActor
private final class TerminalPresentationIdentity: ObservableObject {
    let generation = TerminalMountGeneration.nextSequence()
}

struct TerminalMountGeneration: Comparable {
    let presentation: UInt64
    let host: UInt64
    @MainActor private static var sequence: UInt64 = 0

    @MainActor static func nextSequence() -> UInt64 {
        sequence += 1
        return sequence
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.presentation == rhs.presentation ? lhs.host < rhs.host : lhs.presentation < rhs.presentation
    }
}

/// The session retains authority independently of native attachment. All lease
/// validation and reparenting happen synchronously on the AppKit main actor.
@MainActor
final class TerminalMountCoordinator {
    struct Lease: Equatable {
        let hostID: ObjectIdentifier
        let generation: TerminalMountGeneration
    }
    private(set) var authoritativeLease: Lease?
    private(set) weak var owner: TerminalMountView?
    private weak var emulator: InteractiveTerminalView?

    @discardableResult
    func acquire(_ terminal: InteractiveTerminalView, by host: TerminalMountView) -> Bool {
        let lease = Lease(hostID: ObjectIdentifier(host), generation: host.mountGeneration)
        if let current = authoritativeLease {
            guard lease.generation >= current.generation,
                  lease.generation != current.generation || lease.hostID == current.hostID else { return false }
        }
        authoritativeLease = lease
        owner = host
        emulator = terminal
        host.mount(terminal)
        return true
    }

    func release(_ host: TerminalMountView) {
        let lease = Lease(hostID: ObjectIdentifier(host), generation: host.mountGeneration)
        guard authoritativeLease == lease, owner === host else { return }
        if emulator?.superview === host { emulator?.removeFromSuperview() }
        owner = nil
        // Keep the generation watermark: stale callbacks cannot claim an orphan.
    }
}

/// Mounts one controller-owned emulator. A host disappearing detaches only the
/// native view; it never closes the PTY or discards shell/scrollback state.
struct NativeTerminalHost: NSViewRepresentable {
    let controller: TerminalSessionController
    let initialDirectory: String?
    let isVisible: Bool
    let focusRequest: Int
    var onFocusChange: (Bool) -> Void = { _ in }
    @Environment(\.terminalPresentationGeneration) private var presentationGeneration

    func makeNSView(context: Context) -> TerminalMountView {
        let host = TerminalMountView()
        if let presentationGeneration {
            host.mountGeneration = TerminalMountGeneration(presentation: presentationGeneration,
                                                           host: host.mountGeneration.host)
        }
        host.mountCoordinator = controller.mountCoordinator
        return host
    }
    func updateNSView(_ host: TerminalMountView, context: Context) {
        let terminal = controller.terminalView
        if isVisible { controller.mountCoordinator.acquire(terminal, by: host) }
        host.onFocusChange = onFocusChange
        host.isHidden = !isVisible
        let requested = isVisible && (!host.wasVisible || host.focusRequest != focusRequest)
        host.wasVisible = isVisible
        host.focusRequest = focusRequest
        if isVisible {
            // Start/focus outside SwiftUI/AppKit layout callbacks. Remounting
            // only calls the idempotent startShell; existing cwd remains owned
            // by the user's live shell.
            DispatchQueue.main.async { [weak host, weak controller] in
                guard let host, host.wasVisible, let controller, controller.terminalView.superview === host else { return }
                do { try controller.startShell(initialDirectory: initialDirectory) } catch { return }
                if requested, let window = host.window {
                    window.makeKey()
                    window.makeFirstResponder(controller.terminalView)
                }
            }
        } else {
            host.releaseFocus()
            controller.mountCoordinator.release(host)
        }
    }
    static func dismantleNSView(_ host: TerminalMountView, coordinator: ()) {
        host.releaseFocus()
        host.detach()
    }
}

@MainActor
final class TerminalMountView: NSView {
    var mountGeneration: TerminalMountGeneration = {
        let generation = TerminalMountGeneration.nextSequence()
        return TerminalMountGeneration(presentation: generation, host: generation)
    }()
    weak var mountCoordinator: TerminalMountCoordinator?
    weak var terminal: InteractiveTerminalView?
    var wasVisible = false
    var focusRequest = 0
    private var resizeWork: DispatchWorkItem?
    var onFocusChange: (Bool) -> Void = { _ in }
    private let observations = TerminalObservationBag()
    private var publishedFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observations.clear()
        guard let window else { return }
        observations.tokens = [NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification,
                                                               object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFocus() }
        }]
    }
    private func checkFocus() {
        guard terminal?.superview === self else {
            publishedFocus = false
            return
        }
        // Only user-engaged focus publishes text-input focus (which holds the
        // expanded island open on pointer exit). The Terminal page focuses the
        // emulator automatically so typing works immediately; that alone must
        // never veto collapse.
        let isResponder = wasVisible && terminal?.superview === self && window?.firstResponder === terminal
        if !isResponder, terminal?.superview === self { terminal?.userEngaged = false }
        let focused = isResponder && terminal?.userEngaged == true
        guard focused != publishedFocus else { return }
        publishedFocus = focused
        DispatchQueue.main.async { [weak self] in
            guard let self, publishedFocus == focused,
                  (wasVisible && terminal?.superview === self && window?.firstResponder === terminal
                   && terminal?.userEngaged == true) == focused else { return }
            onFocusChange(focused)
        }
    }


    func mount(_ terminal: InteractiveTerminalView) {
        guard self.terminal !== terminal || terminal.superview !== self else { return }
        // Restart replaces the controller's emulator. Remove the retired
        // renderer before mounting its replacement, including responder ownership.
        if let previous = self.terminal, previous !== terminal, previous.superview === self {
            if previous.window?.firstResponder === previous { previous.window?.makeFirstResponder(nil) }
            previous.removeFromSuperview()
        }
        self.terminal = terminal
        // At most one presentation owns this exact native emulator.
        terminal.removeFromSuperview()
        addSubview(terminal)
        scheduleResize()
    }
    override func layout() {
        super.layout()
        scheduleResize()
    }
    private func scheduleResize() {
        resizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let terminal, terminal.superview === self,
                  bounds.width > 20, bounds.height > 20 else { return }
            // Coalesces animated width changes; SwiftTerm emits TIOCSWINSZ only
            // when its integer cell dimensions change. No shell restart.
            if terminal.frame != bounds { terminal.frame = bounds }
        }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16), execute: work)
    }
    func releaseFocus() {
        guard let terminal else { return }
        let handler = onFocusChange
        let owner = ObjectIdentifier(self)
        DispatchQueue.main.async { [weak terminal, weak self] in
            if let parent = terminal?.superview {
                guard ObjectIdentifier(parent) == owner, self?.wasVisible == false else { return }
            }
            if let terminal, terminal.window?.firstResponder === terminal {
                terminal.window?.makeFirstResponder(nil)
            }
            handler(false)
        }
    }
    func detach() {
        resizeWork?.cancel()
        if let mountCoordinator {
            mountCoordinator.release(self)
        } else if terminal?.superview === self {
            terminal?.removeFromSuperview()
        }
        terminal = nil
        wasVisible = false
    }
}

/// Notification removal is safe on any teardown thread. Avoid actor-isolated
/// Objective-C NSView deinitializers on the macOS 14/15 runtime.
private final class TerminalObservationBag: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    func clear() { tokens.forEach(NotificationCenter.default.removeObserver); tokens.removeAll() }
    deinit { clear() }
}
