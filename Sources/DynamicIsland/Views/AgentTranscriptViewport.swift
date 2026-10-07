import AppKit
import SwiftUI

/// The realized content end can differ from a lazy document's estimated end.
/// Weak native geometry only; no transcript content or rendering tree is held.
@MainActor
final class AgentTranscriptTailAnchor {
    weak var view: NSView?
    var geometryChanged: (() -> Void)?
    weak var geometryOwner: AnyObject?
    private var entries: [String: WeakEntry] = [:]
    private final class WeakEntry { weak var view: NSView?; init(_ view: NSView) { self.view = view } }
    func register(_ view: NSView, entryID: String) { entries[entryID] = WeakEntry(view); geometryChanged?() }
    func unregister(_ view: NSView, entryID: String) {
        if entries[entryID]?.view === view { entries.removeValue(forKey: entryID) }
    }
    func entryStart(_ entryID: String, in document: NSView) -> CGFloat? {
        guard let view = entries[entryID]?.view, let window = view.window,
              document.window === window, view.bounds.height > 0 else { return nil }
        return view.convert(view.bounds, to: document).minY
    }

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

/// Measured row origin owns history restoration across width/stack changes.
/// Weak, realized rows only; dismantling removes entries from the registry.
struct AgentTranscriptEntryMarker: NSViewRepresentable {
    let anchor: AgentTranscriptTailAnchor
    let entryID: String
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.configure(anchor: anchor, entryID: entryID) }
    static func dismantleNSView(_ view: Marker, coordinator: ()) { view.detach() }
    final class Marker: NSView {
        private weak var anchor: AgentTranscriptTailAnchor?
        private var entryID: String?
        func configure(anchor: AgentTranscriptTailAnchor, entryID: String) {
            if self.anchor !== anchor || self.entryID != entryID { detach() }
            self.anchor = anchor; self.entryID = entryID
            anchor.register(self, entryID: entryID)
        }
        override func layout() { super.layout(); anchor?.geometryChanged?() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); anchor?.geometryChanged?() }
        func detach() {
            if let entryID { anchor?.unregister(self, entryID: entryID) }
            anchor = nil; entryID = nil
        }
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
    private var restoringHistory: Set<AgentSessionInstanceID> = []
    func isRestoringHistory(for id: AgentSessionInstanceID) -> Bool { restoringHistory.contains(id) }
    func setRestoringHistory(_ restoring: Bool, for id: AgentSessionInstanceID) {
        if restoring { restoringHistory.insert(id) } else { restoringHistory.remove(id) }
    }
    var count: Int { positions.count }
    func position(for id: AgentSessionInstanceID) -> Position { positions[id] ?? Position() }
    func save(_ position: Position, for id: AgentSessionInstanceID) {
        positions[id] = position
        order.removeAll { $0 == id }; order.append(id)
        if order.count > Self.capacity {
            let removed = order.removeFirst(); positions.removeValue(forKey: removed)
            restoringHistory.remove(removed)
        }
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
    var realizeReadingAnchor: (String) -> Bool = { _ in false }
    var onFollowingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        view.configure(sessionID: sessionID, contentToken: contentToken,
                       jumpRequest: jumpRequest, realizationID: realizationID, tail: tail, realizeLatest: realizeLatest, realizeReadingAnchor: realizeReadingAnchor, changed: onFollowingChanged)
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
        /// A structural scrollTo can precede lazy row realization. Retry only
        /// after another native layout boundary, never through timer polling.
        private var realizationAttempts = 0
        private var layoutEpoch: UInt64 = 0
        private var realizationEpoch: UInt64?
        private var isConfigured = false
        static let maximumRealizationAttempts = 8
        private var realizationID: String?
        private var realizeReadingAnchor: (String) -> Bool = { _ in false }
        private var requestedReadingRealization = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            geometryDidChange()
        }
        override func layout() { super.layout(); geometryDidChange() }
        private func geometryDidChange() {
            layoutEpoch &+= 1
            scheduleLayoutCorrection()
        }

        func configure(sessionID: AgentSessionInstanceID, contentToken: String,
                       jumpRequest: Int, realizationID: String, tail: AgentTranscriptTailAnchor, realizeLatest: @escaping () -> Void, realizeReadingAnchor: @escaping (String) -> Bool = { _ in false }, changed: @escaping (Bool) -> Void) {
            isConfigured = true
            self.changed = changed
            self.realizeLatest = realizeLatest
            self.realizeReadingAnchor = realizeReadingAnchor
            self.tail = tail
            tail.geometryOwner = self
            tail.geometryChanged = { [weak self] in self?.geometryDidChange() }
            if self.sessionID != sessionID {
                save();
                if let previousID = self.sessionID { AgentTranscriptViewportStore.shared.setRestoringHistory(false, for: previousID) }
                observations.clear(); scroll = nil
                self.sessionID = sessionID
                position = AgentTranscriptViewportStore.shared.position(for: sessionID)
                restoringReadingAnchor = !position.followingLatest && position.readingEntryID != nil
                AgentTranscriptViewportStore.shared.setRestoringHistory(restoringReadingAnchor, for: sessionID)
                token = nil; reported = nil
                realizationWidth = nil
                realizationAttempts = 0; realizationEpoch = nil
                requestedReadingRealization = false
            }
            if jump != jumpRequest {
                position.followingLatest = true; restoringReadingAnchor = false
                AgentTranscriptViewportStore.shared.setRestoringHistory(false, for: sessionID)
            }
            jump = jumpRequest
            if self.realizationID != realizationID {
                self.realizationID = realizationID
                realizationWidth = nil
                realizationAttempts = 0; realizationEpoch = nil
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
                        MainActor.assumeIsolated { self?.geometryDidChange() }
                    },
                NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification,
                    object: scroll, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.restoringReadingAnchor = false
                            if let id = self.sessionID { AgentTranscriptViewportStore.shared.setRestoringHistory(false, for: id) }
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
                restoringReadingAnchor = false
                if let id = sessionID { AgentTranscriptViewportStore.shared.setRestoringHistory(false, for: id) }
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
            guard isConfigured, correction == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, isConfigured else { return }
                correction = nil
                attach()
                guard let scroll, let document = scroll.documentView,
                      scroll.contentView.bounds.height > 0 else { return }
                guard !userScrolling else { return }
                correcting = true
                defer { correcting = false }
                let clip = scroll.contentView.bounds
                if position.followingLatest, tail?.end(in: document) == nil {
                    // One attempt per native geometry boundary, bounded per
                    // width/latest row. Layout and row marker notifications own
                    // subsequent attempts; no per-token/frame retry chain.
                    if realizationWidth != clip.width {
                        realizationWidth = clip.width
                        realizationAttempts = 0; realizationEpoch = nil
                    }
                    if realizationAttempts < Self.maximumRealizationAttempts, realizationEpoch != layoutEpoch {
                        realizationEpoch = layoutEpoch
                        realizationAttempts += 1
                        realizeLatest()
                        AgentPerformanceProbe.count("agents.viewport.realizeLatest")
                    }
                    return
                }
                let bottom = max(0, (tail?.end(in: document) ?? document.bounds.maxY) - clip.height)
                var readingOrigin = position.origin
                if !position.followingLatest, let entryID = position.readingEntryID,
                   restoringReadingAnchor || clip.size != lastViewportSize || document.frame.size != lastDocumentSize {
                    if let start = tail?.entryStart(entryID, in: document) {
                        // The actual row, not the current lazy clip estimate, owns
                        // the saved intra-row offset. Repeat while geometry settles.
                        readingOrigin = CGPoint(x: clip.minX, y: start + position.readingEntryOffset)
                    } else if restoringReadingAnchor, !requestedReadingRealization {
                        requestedReadingRealization = true
                        if realizeReadingAnchor(entryID) {
                            return // Do not overwrite saved intent with an early clamped origin.
                        }
                        // The bounded transcript no longer contains the row.
                        // Restore the saved origin rather than waiting for an impossible marker.
                        restoringReadingAnchor = false
                        if let id = sessionID { AgentTranscriptViewportStore.shared.setRestoringHistory(false, for: id) }
                    } else if restoringReadingAnchor {
                        return
                    }
                }
                let origin = position.followingLatest ? CGPoint(x: clip.minX, y: bottom)
                    : CGPoint(x: readingOrigin.x, y: min(max(0, readingOrigin.y), bottom))
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
            isConfigured = false
            if let id = sessionID { AgentTranscriptViewportStore.shared.setRestoringHistory(false, for: id) }
            save(); correction?.cancel(); correction = nil
            if tail?.geometryOwner === self {
                tail?.geometryChanged = nil; tail?.geometryOwner = nil
            }
            realizeLatest = {}; realizeReadingAnchor = { _ in false }; changed = { _ in }
            observations.clear(); scroll = nil
        }
    }
}

private final class TranscriptViewportObservations: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    func clear() { tokens.forEach(NotificationCenter.default.removeObserver); tokens.removeAll() }
    deinit { clear() }
}
