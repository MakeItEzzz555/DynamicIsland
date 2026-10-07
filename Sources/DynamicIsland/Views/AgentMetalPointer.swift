import AppKit
import LibrariesNative
import SwiftUI

@MainActor
enum AgentMetalModelStore {
    private static var models: [AgentSessionInstanceID: MetalFxModel] = [:]
    private static var order: [AgentSessionInstanceID] = []
    static func model(for id: AgentSessionInstanceID) -> MetalFxModel {
        if let model = models[id] { return model }
        let model = MetalFxModel()
        models[id] = model; order.append(id)
        if order.count > 32 { models.removeValue(forKey: order.removeFirst()) }
        return model
    }
}

/// Local AppKit tracking never mutates layout or provider/store state.
struct NativeMetalPointer: NSViewRepresentable {
    let model: MetalFxModel
    let enabled: Bool
    func makeNSView(context: Context) -> TrackingView { TrackingView() }
    func updateNSView(_ view: TrackingView, context: Context) {
        view.model = model; view.enabled = enabled; view.updateTrackingAreas()
    }
    static func dismantleNSView(_ view: TrackingView, coordinator: ()) { view.model?.setPointer(.zero) }
    final class TrackingView: NSView {
        weak var model: MetalFxModel?
        var enabled = false
        private var area: NSTrackingArea?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            if let area { removeTrackingArea(area); self.area = nil }
            super.updateTrackingAreas()
            guard enabled else { model?.setPointer(.zero); return }
            let area = NSTrackingArea(rect: bounds.insetBy(dx: -16, dy: -16),
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self)
            addTrackingArea(area); self.area = area
        }
        override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            model?.setPointer(Self.vector(point: point, bounds: bounds))
        }
        override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
        override func mouseExited(with event: NSEvent) { model?.setPointer(.zero) }
        static func vector(point: CGPoint, bounds: CGRect) -> CGVector {
            let dx = point.x - bounds.midX, dy = bounds.midY - point.y
            let distance = hypot(dx, dy)
            let radius = max(1, min(bounds.width, bounds.height) / 2)
            let strength = max(0, 1 - abs(distance - radius) / (radius + 16)) * 0.30
            guard distance > 0.01 else { return .zero }
            return CGVector(dx: dx / distance * strength, dy: dy / distance * strength)
        }
    }
}
