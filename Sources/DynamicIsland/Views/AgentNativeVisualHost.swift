import SwiftUI
import AppKit
import LibrariesNative

// NotificationCenter retains observer tokens. A bag releases them even if a
// hosting view is destroyed without a normal SwiftUI dismantle callback.
private final class NativeVisualObserverBag: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    func clear() { tokens.forEach(NotificationCenter.default.removeObserver); tokens.removeAll() }
    deinit { clear() }
}

struct NativeVisualVisibility: NSViewRepresentable {
    var changed: (Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed; view.refresh() }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.stop() }

    final class Probe: NSView {
        var changed: (Bool) -> Void
        private let observers = NativeVisualObserverBag()
        private var reported: Bool?
        init(changed: @escaping (Bool) -> Void) { self.changed = changed; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); observe(); refresh() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); observe(); refresh() }
        override func layout() { super.layout(); refresh() }
        override func viewDidHide() { super.viewDidHide(); refresh() }
        override func viewDidUnhide() { super.viewDidUnhide(); refresh() }
        private func observe() {
            stop()
            if let window {
                for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                    observers.tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
                }
            }
            var ancestor = superview
            while let view = ancestor {
                if let clip = view as? NSClipView {
                    clip.postsBoundsChangedNotifications = true
                    observers.tokens.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
                }
                ancestor = view.superview
            }
        }
        func refresh() {
            let value = window?.isVisible == true && window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
            guard reported != value else { return }
            reported = value
            DispatchQueue.main.async { [weak self] in guard let self, self.reported == value else { return }; self.changed(value) }
        }
        func stop() { observers.clear() }
    }
}

struct NativeAvatarPointer: NSViewRepresentable {
    var enabled: Bool
    let player: BotAvatarPlayer
    func makeNSView(context: Context) -> TrackingView { TrackingView() }
    func updateNSView(_ view: TrackingView, context: Context) {
        view.enabled = enabled; view.player = player; view.updateTrackingAreas()
    }
    static func dismantleNSView(_ view: TrackingView, coordinator: ()) { view.player?.simulation.setPointer(x: 0, y: 0, strength: 0) }
    final class TrackingView: NSView {
        var enabled = false
        weak var player: BotAvatarPlayer?
        private var area: NSTrackingArea?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            if let area { removeTrackingArea(area); self.area = nil }
            super.updateTrackingAreas()
            guard enabled else { player?.simulation.setPointer(x: 0, y: 0, strength: 0); return }
            let area = NSTrackingArea(rect: bounds.insetBy(dx: -bounds.width, dy: -bounds.height), options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self)
            addTrackingArea(area); self.area = area
        }
        override func mouseMoved(with event: NSEvent) {
            guard enabled, bounds.width > 0 else { return }
            let p = convert(event.locationInWindow, from: nil)
            let x = (p.x-bounds.midX)/bounds.width, y = -(p.y-bounds.midY)/bounds.height
            let strength = max(0, 1-hypot(x, y)/1.8)
            player?.simulation.setPointer(x: x, y: y, strength: strength)
        }
        override func mouseExited(with event: NSEvent) { player?.simulation.setPointer(x: 0, y: 0, strength: 0) }
    }
}
