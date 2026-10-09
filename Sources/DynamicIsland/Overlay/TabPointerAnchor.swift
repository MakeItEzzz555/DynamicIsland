import AppKit
import SwiftUI

/// A clicked tab owns hover only until its existing shell morph settles.
@MainActor
final class TabPointerAnchor {
    private struct Target {
        let page: ExpandedIslandPage
        let generation: Int
        let offset: CGPoint
        var pointer: CGPoint
        var frame: CGRect
        var userMovement: CGFloat = 0
    }
    private struct FrameSource {
        let owner: UUID
        let frame: () -> CGRect?
    }
    private var frames: [ExpandedIslandPage: FrameSource] = [:]
    private var target: Target?
    private var timer: Timer?
    private let pointerLocation: () -> CGPoint
    private let movePointer: (CGPoint) -> Bool
    private(set) var generation = 0
    var isActive: Bool { target != nil }
    var selectedTab: ExpandedIslandPage? { target?.page }
    static let movementTolerance: CGFloat = 4

    init(pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
         movePointer: @escaping (CGPoint) -> Bool = { point in
             let top = CGDisplayBounds(CGMainDisplayID()).height
             return CGWarpMouseCursorPosition(CGPoint(x: point.x, y: top - point.y)) == .success
         }) {
        self.pointerLocation = pointerLocation
        self.movePointer = movePointer
    }

    func register(_ page: ExpandedIslandPage, owner: UUID, frame: @escaping () -> CGRect?) {
        frames[page] = FrameSource(owner: owner, frame: frame)
    }
    func unregister(_ page: ExpandedIslandPage, owner: UUID) {
        guard frames[page]?.owner == owner else { return }
        frames.removeValue(forKey: page)
        if target?.page == page { cancel() }
    }

    @discardableResult
    func activate(_ page: ExpandedIslandPage, eventType: NSEvent.EventType?,
                  pointer: CGPoint, maximumDuration: TimeInterval) -> Int? {
        cancel()
        guard eventType == .leftMouseUp, let frame = validFrame(page), frame.contains(pointer) else { return nil }
        target = Target(page: page, generation: generation,
            offset: CGPoint(x: pointer.x - frame.minX, y: pointer.y - frame.minY), pointer: pointer, frame: frame)
        let expected = generation
        let deadline = ProcessInfo.processInfo.systemUptime + maximumDuration
        let sampling = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] sampling in
            guard let self else { sampling.invalidate(); return }
            MainActor.assumeIsolated {
                if ProcessInfo.processInfo.systemUptime >= deadline { self.finish(generation: expected) }
                else { self.update(generation: expected) }
            }
        }
        timer = sampling
        RunLoop.main.add(sampling, forMode: .common)
        return expected
    }

    func selectionChanged(to page: ExpandedIslandPage) {
        if let target, target.page != page { cancel() }
    }
    func observePointer(_ pointer: CGPoint) {
        guard var current = target else { return }
        current.userMovement += hypot(pointer.x - current.pointer.x, pointer.y - current.pointer.y)
        current.pointer = pointer
        if current.userMovement > Self.movementTolerance { cancel() }
        else { target = current }
    }
    func update(generation expected: Int) {
        guard let current = target, current.generation == expected else { return }
        observePointer(pointerLocation())
        guard var current = target, let frame = validFrame(current.page) else {
            if target != nil { cancel() }
            return
        }
        guard frame != current.frame else { return }
        current.frame = frame
        let point = CGPoint(x: frame.minX + min(max(current.offset.x, 1), frame.width - 1),
                            y: frame.minY + min(max(current.offset.y, 1), frame.height - 1))
        guard hypot(point.x - current.pointer.x, point.y - current.pointer.y) > 0.25 else { target = current; return }
        guard movePointer(point) else { cancel(); return }
        current.pointer = pointerLocation()
        target = current
    }
    func finish(generation expected: Int) {
        guard target?.generation == expected else { return }
        update(generation: expected)
        cancel()
    }
    func cancel() {
        generation &+= 1
        target = nil
        timer?.invalidate()
        timer = nil
    }
    private func validFrame(_ page: ExpandedIslandPage) -> CGRect? {
        guard let frame = frames[page]?.frame(), !frame.isEmpty, !frame.isNull, !frame.isInfinite else { return nil }
        return frame
    }
}

/// Samples the rendered AppKit frame, including SwiftUI's animated placement.
struct TabPointerFrame: NSViewRepresentable {
    let page: ExpandedIslandPage
    let anchor: TabPointerAnchor
    func makeNSView(context: Context) -> FrameView { FrameView() }
    func updateNSView(_ view: FrameView, context: Context) {
        view.anchor = anchor
        view.page = page
        anchor.register(page, owner: view.owner) { [weak view] in
            guard let view, let window = view.window, window.isVisible else { return nil }
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
    }
    static func dismantleNSView(_ view: FrameView, coordinator: ()) {
        if let page = view.page { view.anchor?.unregister(page, owner: view.owner) }
    }
    final class FrameView: NSView {
        let owner = UUID()
        weak var anchor: TabPointerAnchor?
        var page: ExpandedIslandPage?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
