import AppKit

@MainActor
protocol CameraLocalEventWindow: AnyObject {
    var cameraEventGate: ((NSEvent) -> Bool)? { get set }
}

@MainActor
final class CameraInteractionRouter {
    private weak var window: NSWindow?
    private var monitor: Any?
    private var globalMonitor: Any?
    private var sequence = 1
    private(set) var isPressed = false
    private var pendingSequence = false
    private weak var slider: NSSlider?
    private weak var editingBridge: CameraSliderEditingBridge.EditingView?
    private var sliderStartValue = 0.0
    private(set) var physicalUntil: TimeInterval = 0
    private var physicalButtonDown = false
    private var physicalTouchActive = false
    var onPhysicalInput: (() -> Void)?
    var allowsCameraInput: () -> Bool = { true }

    init(window: NSWindow) {
        self.window = window
        (window as? CameraLocalEventWindow)?.cameraEventGate = { [weak self] event in self?.accept(event) ?? true }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .mouseMoved, .scrollWheel, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if !Self.isCameraEvent(event), event.window !== self.window { self.recordPhysical(event) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .leftMouseDragged, .mouseMoved, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.recordPhysical(event) }
        }
    }

    private func accept(_ event: NSEvent) -> Bool {
        if Self.isCameraEvent(event) {
            guard (event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0) & ~1 == eventTag else { return false }
            guard event.type == .leftMouseUp || (allowsCameraInput() && window?.isVisible == true) else { cancel(); return false }
            if event.type == .leftMouseUp { pendingSequence = false }
            return true
        }
        guard [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
               .mouseMoved, .scrollWheel, .keyDown].contains(event.type) else { return true }
        let cancelBeforePhysical = isPressed || pendingSequence
        recordPhysical(event)
        if cancelBeforePhysical {
            NSApp.postEvent(event, atStart: false)
            return false
        }
        return true
    }

    private var eventTag: Int64 { (0x444943 << 32) | (Int64(sequence) << 1) }
    private var eventNumber: Int { -20_001 - (sequence % 9_000) }
    static func isCameraEvent(_ event: NSEvent) -> Bool { (event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0) >> 32 == 0x444943 }
    static func isCancellationEvent(_ event: NSEvent?) -> Bool {
        guard let event, isCameraEvent(event) else { return false }
        return (event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0) & 1 == 1
    }
    var physicalOwnsInput: Bool { physicalButtonDown || physicalTouchActive || ProcessInfo.processInfo.systemUptime < physicalUntil }

    func physicalTouchSession(active: Bool) {
        guard active != physicalTouchActive else { return }
        physicalTouchActive = active
        physicalUntil = ProcessInfo.processInfo.systemUptime + 0.7
        cancel(); onPhysicalInput?()
    }

    private func recordPhysical(_ event: NSEvent) {
        physicalUntil = ProcessInfo.processInfo.systemUptime + 0.7
        if event.type == .leftMouseDown || event.type == .rightMouseDown { physicalButtonDown = true }
        if event.type == .leftMouseUp || event.type == .rightMouseUp { physicalButtonDown = false }
        cancel()
        onPhysicalInput?()
    }

    func press(at point: CGPoint) {
        guard !physicalOwnsInput, !isPressed, window?.isVisible == true, window is CameraLocalEventWindow else { return }
        isPressed = true; pendingSequence = true
        if let control = slider(at: point), control.isEnabled, control.sliderType == .linear {
            slider = control; sliderStartValue = control.doubleValue
            editingBridge = window?.contentView.flatMap { CameraSliderEditingBridge.find(in: $0, at: point) }
            editingBridge?.onEditingChanged(true)
            pendingSequence = false
            updateSlider(at: point, ended: false)
            return
        }
        post(.leftMouseDown, point: point)
    }

    func drag(to point: CGPoint) {
        guard isPressed, !physicalOwnsInput else { cancel(); return }
        if slider != nil { updateSlider(at: point, ended: false); return }
        post(.leftMouseDragged, point: point)
    }

    func release(at point: CGPoint) {
        guard isPressed else { return }
        if slider != nil {
            updateSlider(at: point, ended: true)
            editingBridge?.onEditingChanged(false); editingBridge = nil
            slider = nil; isPressed = false; return
        }
        isPressed = false; post(.leftMouseUp, point: point)
    }

    func cancel() {
        let wasPressed = isPressed || pendingSequence
        isPressed = false; pendingSequence = false; sequence += 1
        if let slider {
            editingBridge?.onCancel(); editingBridge = nil
            if !slider.isContinuous { slider.doubleValue = sliderStartValue }
            self.slider = nil
            return
        }
        if wasPressed { post(.leftMouseUp, point: CGPoint(x: -10_000, y: -10_000), atStart: true, cancelled: true) }
    }

    func isInteractive(at point: CGPoint) -> Bool {
        guard let content = window?.contentView else { return false }
        var view = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
        while let candidate = view {
            if let control = candidate as? NSControl { return control.isEnabled }
            view = candidate.superview
        }
        return false
    }

    private func slider(at point: CGPoint) -> NSSlider? {
        guard let content = window?.contentView else { return nil }
        var view = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
        while let candidate = view {
            if let slider = candidate as? NSSlider { return slider }
            view = candidate.superview
        }
        return nil
    }

    /// NSSlider tracking reads the physical cursor. This adapter changes only
    /// an enabled, still-mounted linear control through its own target/action.
    private func updateSlider(at point: CGPoint, ended: Bool) {
        guard let slider, slider.window === window, slider.isEnabled,
              let cell = slider.cell as? NSSliderCell else { cancel(); return }
        let local = slider.convert(point, from: nil)
        let bar = cell.barRect(flipped: slider.isFlipped)
        let knob = cell.knobRect(flipped: slider.isFlipped)
        let start = slider.isVertical ? bar.minY + knob.height / 2 : bar.minX + knob.width / 2
        let extent = slider.isVertical ? bar.height - knob.height : bar.width - knob.width
        guard extent > 0 else { return }
        var fraction = ((slider.isVertical ? local.y : local.x) - start) / extent
        if slider.isVertical && slider.isFlipped { fraction = 1 - fraction }
        var value = slider.minValue + min(max(fraction, 0), 1) * (slider.maxValue - slider.minValue)
        if slider.allowsTickMarkValuesOnly { value = slider.closestTickMarkValue(toValue: value) }
        slider.doubleValue = value
        if slider.isContinuous || ended { _ = slider.sendAction(slider.action, to: slider.target) }
    }

    private func post(_ type: NSEvent.EventType, point: CGPoint, atStart: Bool = false, cancelled: Bool = false) {
        guard let window, let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: eventNumber, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { return }
        guard let cg = event.cgEvent else { return }
        cg.setIntegerValueField(.eventSourceUserData, value: eventTag | (cancelled ? 1 : 0))
        guard let tagged = NSEvent(cgEvent: cg) else { return }
        NSApp.postEvent(tagged, atStart: atStart)
    }

    func scroll(at point: CGPoint, delta: Double) {
        guard !physicalOwnsInput, !isPressed, let window, let content = window.contentView,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: Int32(min(max(delta, -80), 80)), wheel2: 0, wheel3: 0) else { return }
        guard let local = NSEvent(cgEvent: event) else { return }
        var target = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
        while let view = target {
            if let scroll = view as? NSScrollView, let document = scroll.documentView {
                // A local wheel has no WindowServer window association. Route
                // its delta through the existing native viewport instead.
                let clip = scroll.contentView
                var bounds = clip.bounds
                bounds.origin.y += (document.isFlipped ? -1 : 1) * local.scrollingDeltaY
                clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
                scroll.reflectScrolledClipView(clip)
                return
            }
            target = view.superview
        }
    }

    func shutdown() {
        cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        monitor = nil; globalMonitor = nil; onPhysicalInput = nil
        (window as? CameraLocalEventWindow)?.cameraEventGate = nil
    }
}
