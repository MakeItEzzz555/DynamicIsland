import AppKit
import SwiftUI

/// The realized content end can differ from a lazy document's estimated end.
/// Weak native geometry only; no transcript content or rendering tree is held.
@MainActor
final class AgentTranscriptTailAnchor {
    weak var view: NSView?
    var geometryChanged: (() -> Void)?
    func end(in document: NSView) -> CGFloat? {
        guard let view, let window = view.window, document.window === window else { return nil }
        return view.convert(view.bounds, to: document).maxY
    }
}

struct AgentTranscriptTailMarker: NSViewRepresentable {
    let anchor: AgentTranscriptTailAnchor
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) {
        view.anchor = anchor; anchor.view = view
        anchor.geometryChanged?()
    }
    final class Marker: NSView {
        weak var anchor: AgentTranscriptTailAnchor?
        override func layout() { super.layout(); anchor?.geometryChanged?() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); anchor?.geometryChanged?() }
    }
}

/// Viewport intent survives shell/page unmounts. It is presentation state,
/// keyed by the exact provider/session/generation, with a bounded LRU.
@MainActor
final class AgentTranscriptViewportStore {
    struct Position: Equatable {
        var followingLatest = true
        var origin = CGPoint.zero
        var width: CGFloat = 0
        var readingEntryID: String?
        var readingEntryOffset: CGFloat = 0
    }
    static let shared = AgentTranscriptViewportStore()
    static let capacity = 64
    private var positions: [AgentSessionInstanceID: Position] = [:]
    private var order: [AgentSessionInstanceID] = []
    var count: Int { positions.count }
    func position(for id: AgentSessionInstanceID) -> Position { positions[id] ?? Position() }
    func save(_ position: Position, for id: AgentSessionInstanceID) {
        positions[id] = position
        order.removeAll { $0 == id }; order.append(id)
        if order.count > Self.capacity { positions.removeValue(forKey: order.removeFirst()) }
    }
}

/// Observe actual AppKit document/clip geometry after layout. SwiftUI's lazy
/// estimates and a single yielded scrollTo are not a restoration boundary.
/// No observable/domain publication occurs in these layout callbacks.
struct AgentTranscriptViewportProbe: NSViewRepresentable {
    let sessionID: AgentSessionInstanceID
    let contentToken: String
    let jumpRequest: Int
    let realizationID: String
    let tail: AgentTranscriptTailAnchor
    var realizeLatest: () -> Void
    var onFollowingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        view.configure(sessionID: sessionID, contentToken: contentToken,
                       jumpRequest: jumpRequest, realizationID: realizationID, tail: tail, realizeLatest: realizeLatest, changed: onFollowingChanged)
    }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: NSView {
        weak var scroll: NSScrollView?
        private var sessionID: AgentSessionInstanceID?
        private var position = AgentTranscriptViewportStore.Position()
        private var token: String?
        private var jump = 0
        private let observations = TranscriptViewportObservations()
        private var correction: DispatchWorkItem?
        private var correcting = false
        private var lastDocumentSize = CGSize.zero
        private var lastViewportSize = CGSize.zero
        private var changed: (Bool) -> Void = { _ in }
        private var reported: Bool?
        private var restoringReadingAnchor = false
        private var userScrolling = false
        private weak var tail: AgentTranscriptTailAnchor?
        private var realizeLatest: () -> Void = { }
        private var realizationWidth: CGFloat?
        private var realizationID: String?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleLayoutCorrection()
        }
        override func layout() { super.layout(); scheduleLayoutCorrection() }

        func configure(sessionID: AgentSessionInstanceID, contentToken: String,
                       jumpRequest: Int, realizationID: String, tail: AgentTranscriptTailAnchor, realizeLatest: @escaping () -> Void, changed: @escaping (Bool) -> Void) {
            self.changed = changed
            self.realizeLatest = realizeLatest
            self.tail = tail
            tail.geometryChanged = { [weak self] in self?.scheduleLayoutCorrection() }
            if self.sessionID != sessionID {
                save(); observations.clear(); scroll = nil
                self.sessionID = sessionID
                position = AgentTranscriptViewportStore.shared.position(for: sessionID)
                restoringReadingAnchor = !position.followingLatest && position.readingEntryID != nil
                token = nil; reported = nil
                realizationWidth = nil
            }
            if jump != jumpRequest { position.followingLatest = true }
            jump = jumpRequest
            if self.realizationID != realizationID {
                self.realizationID = realizationID
                realizationWidth = nil
            }
            if token != contentToken { token = contentToken; scheduleLayoutCorrection() }
        }

        private func attach() {
            guard scroll == nil else { return }
            scroll = tail?.view?.enclosingScrollView
            if scroll == nil {
                func find(_ root: NSView) -> NSScrollView? {
                    if let value = root as? NSScrollView { return value }
                    for child in root.subviews { if let found = find(child) { return found } }
                    return nil
                }
                var ancestor = superview
                while let parent = ancestor {
                    if let found = find(parent) { scroll = found; break }
                    ancestor = parent.superview
                }
            }
            guard let scroll, let document = scroll.documentView else { return }
            scroll.contentView.postsBoundsChangedNotifications = true
            document.postsFrameChangedNotifications = true
            observations.tokens = [
                NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                    object: scroll.contentView, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.viewportMoved() }
                    },
                NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                    object: document, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.scheduleLayoutCorrection() }
                    },
                NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification,
                    object: scroll, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.userScrolling = true; self.position.followingLatest = false
                            self.save(); self.report()
                        }
                    },
                NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveScrollNotification,
                    object: scroll, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.viewportMoved(); self?.userScrolling = false
                        }
                    }
            ]
        }

        private func viewportMoved() {
            guard !correcting, let scroll, let document = scroll.documentView else { return }
            let clip = scroll.contentView.bounds
            let documentSize = document.frame.size
            let event = NSApp.currentEvent?.type
            let responder = scroll.window?.firstResponder as? NSView
            let scrollKey = event == .keyDown && [UInt16(116), 121, 115, 119, 125, 126].contains(NSApp.currentEvent?.keyCode ?? 0)
                && (responder === scroll || responder?.isDescendant(of: document) == true)
            if userScrolling || event == .scrollWheel || scrollKey {
                position.followingLatest = (tail?.end(in: document) ?? document.bounds.maxY) - clip.maxY <= AgentTranscriptFollowState.nearBottomThreshold
                position.origin = clip.origin; position.width = clip.width
                save(); report(); return
            }
            // Resizing and growing text are layout, not a request to stop
            // following. Correct again after the current AppKit layout turn.
            if clip.size != lastViewportSize || documentSize != lastDocumentSize {
                scheduleLayoutCorrection(); return
            }
            if position.followingLatest { scheduleLayoutCorrection() }
        }

        private func scheduleLayoutCorrection() {
            guard correction == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                correction = nil
                attach()
                guard let scroll, let document = scroll.documentView,
                      scroll.contentView.bounds.height > 0 else { return }
                guard !userScrolling else { return }
                correcting = true
                defer { correcting = false }
                let clip = scroll.contentView.bounds
                if position.followingLatest, tail?.end(in: document) == nil {
                    // A layout-ready structural realization, once per width.
                    // Never scroll blindly into unmeasured lazy estimates.
                    if realizationWidth != clip.width {
                        realizationWidth = clip.width
                        realizeLatest()
                    }
                    return
                }
                let bottom = max(0, (tail?.end(in: document) ?? document.bounds.maxY) - clip.height)
                if restoringReadingAnchor {
                    if position.width > 0, abs(position.width - clip.width) > 1 {
                        position.origin = CGPoint(x: clip.minX, y: clip.minY + position.readingEntryOffset)
                    }
                    restoringReadingAnchor = false
                }
                let origin = position.followingLatest ? CGPoint(x: clip.minX, y: bottom)
                    : CGPoint(x: position.origin.x, y: min(max(0, position.origin.y), bottom))
                if abs(clip.minY - origin.y) > 0.5 {
                    scroll.contentView.scroll(to: origin)
                    scroll.reflectScrolledClipView(scroll.contentView)
                    AgentPerformanceProbe.count("agents.viewport.layoutCorrection")
                }
                lastDocumentSize = document.frame.size
                lastViewportSize = scroll.contentView.bounds.size
                position.origin = scroll.contentView.bounds.origin
                position.width = scroll.contentView.bounds.width
                save(); report()
            }
            correction = work
            DispatchQueue.main.async(execute: work)
        }
        private func report() {
            guard reported != position.followingLatest else { return }
            reported = position.followingLatest
            let following = position.followingLatest
            DispatchQueue.main.async { [weak self] in
                guard let self, reported == following else { return }
                changed(following)
            }
        }
        private func save() {
            if let sessionID {
                let metadata = AgentTranscriptViewportStore.shared.position(for: sessionID)
                position.readingEntryID = metadata.readingEntryID
                position.readingEntryOffset = metadata.readingEntryOffset
                AgentTranscriptViewportStore.shared.save(position, for: sessionID)
            }
        }
        func detach() {
            save(); correction?.cancel(); correction = nil
            tail?.geometryChanged = nil
            realizeLatest = {}; changed = { _ in }
            observations.clear(); scroll = nil
        }
    }
}

private final class TranscriptViewportObservations: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    func clear() { tokens.forEach(NotificationCenter.default.removeObserver); tokens.removeAll() }
    deinit { clear() }
}
