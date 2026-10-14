import AppKit
import SwiftUI

/// One native presentation for toolbar requests and accepted drops, independent of page/widget mounting.
@MainActor
final class FileActionPresenter: NSObject, NSPopoverDelegate {
    private let shelf: FileShelfStore
    private let operations: BackgroundOperationController
    private let layout: IslandLayoutStore
    private let popover = NSPopover()
    private var requestID: UUID?
    private let owner = TransientInteractionOwner.fileActionPanel(UUID())
    private weak var presentingWindow: NSWindow?
    private weak var previousFirstResponder: NSResponder?
    private var restoreFocus = false
    private var frameObservers: [NSObjectProtocol] = []
    var isShown: Bool { popover.isShown }
    var presentationWindow: NSWindow? { popover.contentViewController?.view.window }

    init(shelf: FileShelfStore, operations: BackgroundOperationController, layout: IslandLayoutStore) {
        self.shelf = shelf; self.operations = operations; self.layout = layout
        super.init()
        // Folder selection may transfer key focus to a native panel; explicit Close/Escape owns dismissal.
        popover.behavior = .applicationDefined
        popover.delegate = self
    }

    @discardableResult
    func present(_ request: FileTrayActionRequest, relativeTo frame: NSRect, of view: NSView, permitted: Bool, reduceMotion: Bool = false) -> Bool {
        guard permitted, !isShown, view.window?.isVisible == true, !frame.isEmpty,
              !request.urls.isEmpty, request.urls.allSatisfy({ shelf.files.contains($0) }) else { return false }
        requestID = request.id
        presentingWindow = view.window
        previousFirstResponder = view.window?.firstResponder
        restoreFocus = view.window?.isKeyWindow == true
        popover.animates = !reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        layout.setTransientInteraction(true, owner: owner)
        let width = min(570, max(360, (view.window?.screen?.visibleFrame.width ?? 602) - 32))
        popover.contentViewController = NSHostingController(rootView: FileActionPanel(urls: request.urls, operations: operations,
            addOutput: { [weak shelf] output in shelf?.add([output]); shelf?.select(output) },
            dismiss: { [weak self] in self?.close() }).frame(width: width))
        popover.show(relativeTo: frame, of: view, preferredEdge: .minY)
        observePresentationFrame()
        fitToPresentingDisplay()
        if !popover.isShown { release() }
        return popover.isShown
    }
    func close() {
        if popover.isShown { popover.close() }
        else { release(); popover.contentViewController = nil }
    }
    func popoverDidClose(_ notification: Notification) {
        release()
        popover.contentViewController = nil
    }
    func popoverDidShow(_ notification: Notification) {
        // The popover window may only exist once shown; registration is idempotent.
        observePresentationFrame()
        fitToPresentingDisplay()
    }
    /// NSPopover repositions its own window during the show animation and on
    /// content layout, so a one-time fit can be undone on slower machines.
    /// Re-fit after every move/resize while shown.
    private func observePresentationFrame() {
        removeFrameObservers()
        guard let window = presentationWindow else { return }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            frameObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fitToPresentingDisplay() }
            })
        }
    }
    private func removeFrameObservers() {
        frameObservers.forEach(NotificationCenter.default.removeObserver)
        frameObservers = []
    }
    private func fitToPresentingDisplay() {
        guard let window = presentationWindow, let screen = presentingWindow?.screen else { return }
        let frame = window.frame
        let origin = Self.fittedOrigin(of: frame, in: screen.visibleFrame)
        // Moving only when needed keeps the move notification from looping.
        if origin != frame.origin { window.setFrameOrigin(origin) }
    }
    /// Keeps a popup inside the display's visible frame (8 pt margin).
    nonisolated static func fittedOrigin(of frame: NSRect, in visible: NSRect) -> NSPoint {
        let bounds = visible.insetBy(dx: 8, dy: 8)
        return NSPoint(
            x: min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width)),
            y: min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height)))
    }
    private func release() {
        removeFrameObservers()
        let id = requestID; requestID = nil
        layout.setTransientInteraction(false, owner: owner)
        if let id { shelf.dismissFileActions(id) }
        if restoreFocus, let window = presentingWindow, window.isVisible, NSApp.isActive,
           NSApp.keyWindow == nil || NSApp.keyWindow === window {
            if NSApp.keyWindow == nil { window.makeKey() }
            if let view = previousFirstResponder as? NSView, view.window === window { window.makeFirstResponder(view) }
        }
        presentingWindow = nil; previousFirstResponder = nil; restoreFocus = false
    }
}
