import AppKit
import SwiftUI

/// Mounts one controller-owned emulator. A host disappearing detaches only the
/// native view; it never closes the PTY or discards shell/scrollback state.
struct NativeTerminalHost: NSViewRepresentable {
    let controller: TerminalSessionController
    let initialDirectory: String?
    let isVisible: Bool
    let focusRequest: Int
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> TerminalMountView {
        TerminalMountView()
    }
    func updateNSView(_ host: TerminalMountView, context: Context) {
        let terminal = controller.terminalView
        // A retiring SwiftUI tree may still issue updates during its fade-out.
        // Only a newly visible/new host may claim an emulator owned elsewhere.
        // Routine updates from the retiring host must never steal it back.
        if isVisible && (!host.wasVisible || host.terminal !== terminal || terminal.superview === host) {
            host.mount(terminal)
        }
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
        }
    }
    static func dismantleNSView(_ host: TerminalMountView, coordinator: ()) {
        host.releaseFocus()
        host.detach()
    }
}

@MainActor
final class TerminalMountView: NSView {
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
        // Only user-engaged focus publishes text-input focus (which holds the
        // expanded island open on pointer exit). The Terminal page focuses the
        // emulator automatically so typing works immediately; that alone must
        // never veto collapse.
        let isResponder = wasVisible && terminal?.superview === self && window?.firstResponder === terminal
        if !isResponder { terminal?.userEngaged = false }
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
        let terminal = terminal
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
        if terminal?.superview === self { terminal?.removeFromSuperview() }
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
