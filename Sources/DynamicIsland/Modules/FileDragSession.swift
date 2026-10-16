import AppKit
import Foundation

/// Real native actions exposed while an *external* file drag is active.
/// Quickshare stays absent until the user approves an upload host. Add to
/// Basket and Compress run through app-owned services (`FileDragLocalActions`)
/// and are offered only when that service can execute them. Convert is
/// deliberately absent: it needs a target-format choice, so a drop would not be
/// one unambiguous action.
enum FileDragSourceRegion: Hashable, Sendable {
    case collapsedIsland
    case trayShelf
    case trayAirDrop
    /// One of the four Tray drop zones (Keep, Messages, Share, ZIP).
    case trayDropZone
}

enum FileDragQuickAction: String, CaseIterable, Identifiable, Sendable {
    case airDrop
    case messages
    case mail
    case share
    case addToBasket
    case compress

    /// The system-sharing targets; the only actions a basket's own bar shows
    /// (adding to a basket from inside a basket is meaningless, and the basket
    /// has its own compress).
    static let shareActions: [FileDragQuickAction] = [.airDrop, .messages, .mail, .share]

    /// Orbit targets in display order; app-owned ones only when executable.
    @MainActor
    static func orbitActions(local: FileDragLocalActions) -> [FileDragQuickAction] {
        shareActions + [.addToBasket, .compress].filter(local.isAvailable)
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .airDrop: "AirDrop"
        case .messages: "Messages"
        case .mail: "Mail"
        case .share: "Share"
        case .addToBasket: "Add to Basket"
        case .compress: "Compress"
        }
    }

    var symbolName: String {
        switch self {
        case .airDrop: "person.2.wave.2"
        case .messages: "message.fill"
        case .mail: "envelope.fill"
        case .share: "square.and.arrow.up"
        case .addToBasket: "tray.and.arrow.down.fill"
        case .compress: "doc.zipper"
        }
    }

    var explanation: String {
        switch self {
        case .airDrop: "Drop to share with AirDrop"
        case .messages: "Drop to share in Messages"
        case .mail: "Drop to attach to an email"
        case .share: "Drop to choose a sharing service"
        case .addToBasket: "Drop to add to a Basket"
        case .compress: "Drop to create a ZIP archive"
        }
    }
}

enum FileDragActionOutcome: Equatable, Sendable {
    /// The files were handed to the native system UI. This is deliberately
    /// not called "sent": NSSharingService does not provide send confirmation.
    case handedOff
    case unavailable(String)
    case failed(String)
}

/// App-owned services behind the non-sharing orbit targets. A missing entry
/// means the target is hidden and cannot be executed.
@MainActor
struct FileDragLocalActions {
    struct Entry {
        let isAvailable: @MainActor () -> Bool
        let run: @MainActor ([URL]) -> FileDragActionOutcome
    }

    var addToBasket: Entry?
    var compress: Entry?

    static let none = FileDragLocalActions()

    func entry(for action: FileDragQuickAction) -> Entry? {
        switch action {
        case .addToBasket: addToBasket
        case .compress: compress
        case .airDrop, .messages, .mail, .share: nil
        }
    }

    func isAvailable(_ action: FileDragQuickAction) -> Bool { entry(for: action)?.isAvailable() ?? false }
}

@MainActor
final class FileDragActionExecutor {
    typealias Handler = @MainActor (FileDragQuickAction, [URL], NSView?) -> FileDragActionOutcome

    private let handler: Handler?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    convenience init(_ handler: @escaping Handler) {
        self.init(handler: handler)
    }

    private init() { handler = nil }

    func perform(_ action: FileDragQuickAction, urls: [URL], anchor: NSView?, layoutStore: IslandLayoutStore? = nil,
                 local: FileDragLocalActions = .none) -> FileDragActionOutcome {
        guard !urls.isEmpty else { return .failed("No files were materialized") }
        if let handler { return handler(action, urls, anchor) }
        if !FileDragQuickAction.shareActions.contains(action) {
            guard let entry = local.entry(for: action), entry.isAvailable() else {
                return .unavailable("\(action.title) is unavailable")
            }
            return entry.run(urls)
        }
        return NativeFileSharingSession.present(action, urls: urls, anchor: anchor, layoutStore: layoutStore)
    }

    static let production = FileDragActionExecutor()

    func cancelPresentations() { NativeFileSharingSession.cancelAll() }

}

/// Generation-scoped state machine for the external drag orbit. Shelf
/// selection is intentionally not part of this type: the payload for an orbit
/// drop always comes from the current system drag.
@MainActor
final class FileDragSessionController: ObservableObject {
    enum Phase: Equatable, Sendable {
        case idle
        case dragging
        case targeting(FileDragQuickAction)
        case materializing(FileDragQuickAction)
        case materializingShelf
        case performing(FileDragQuickAction)
    }

    struct DropClaim: Equatable, Sendable {
        let generation: Int
        let action: FileDragQuickAction
    }

    struct ShelfDropClaim: Equatable, Sendable { let generation: Int }

    func claimShelfDrop() -> ShelfDropClaim? {
        ensureSession()
        guard !dropClaimed else { return nil }
        dropClaimed = true
        exitTask?.cancel(); exitTask = nil
        phase = .materializingShelf
        return ShelfDropClaim(generation: generation)
    }

    @discardableResult
    func completeShelfDrop(_ claim: ShelfDropClaim, urls: [URL], shelf: FileShelfStore,
                           allowed: Bool, openAfterDrop: Bool = false, requestActions: Bool = true) -> [URL]? {
        guard claim.generation == generation, dropClaimed, phase == .materializingShelf else {
            shelf.discardUnacceptedDrop(urls)
            return nil
        }
        defer { reset(incrementGeneration: true) }
        guard allowed else { shelf.discardUnacceptedDrop(urls); return [] }
        shelf.add(urls)
        let accepted = shelf.files.filter(Set(urls.map(\.standardizedFileURL)).contains)
        if requestActions { shelf.requestFileActions(for: accepted, openShelfAfterDrop: openAfterDrop) }
        return accepted
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var targetedAction: FileDragQuickAction?
    @Published private(set) var hoveredAction: FileDragQuickAction?
    @Published private(set) var lastOutcome: FileDragActionOutcome?
    @Published private(set) var generation = 0

    private var sourceRegions: Set<FileDragSourceRegion> = []
    private var bridgeTargeted = false
    private var actionTargets: Set<FileDragQuickAction> = []
    private var dropClaimed = false
    private var exitTask: Task<Void, Never>?
    private var outcomeClearTask: Task<Void, Never>?
    private let exitGraceNanoseconds: UInt64

    init(exitGraceNanoseconds: UInt64 = 180_000_000) {
        self.exitGraceNanoseconds = exitGraceNanoseconds
    }

    /// Set once by the composition root; empty means share targets only.
    var localActions = FileDragLocalActions.none
    var orbitActions: [FileDragQuickAction] { FileDragQuickAction.orbitActions(local: localActions) }

    var isActive: Bool { phase != .idle }
    var isDropInFlight: Bool { dropClaimed }

    var outcomeMessage: String? {
        switch lastOutcome {
        case .unavailable(let message)?, .failed(let message)?: message
        case .handedOff?, nil: nil
        }
    }

    func setSourceTargeted(_ targeted: Bool, region: FileDragSourceRegion = .trayShelf) {
        if targeted {
            sourceRegions.insert(region)
            ensureSession()
        } else {
            sourceRegions.remove(region)
            scheduleEndIfUnowned()
        }
    }

    func setBridgeTargeted(_ targeted: Bool) {
        bridgeTargeted = targeted
        targeted ? ensureSession() : scheduleEndIfUnowned()
    }

    func setHoveredAction(_ action: FileDragQuickAction?) {
        hoveredAction = action
    }

    var explanatoryAction: FileDragQuickAction? { targetedAction ?? hoveredAction }

    func setActionTargeted(_ action: FileDragQuickAction, _ targeted: Bool) {
        if targeted {
            actionTargets.insert(action)
            ensureSession()
            targetedAction = action
            if !dropClaimed { phase = .targeting(action) }
        } else {
            actionTargets.remove(action)
            if targetedAction == action {
                targetedAction = actionTargets.first
                if !dropClaimed {
                    phase = targetedAction.map(Phase.targeting) ?? .dragging
                }
            }
            scheduleEndIfUnowned()
        }
    }

    @discardableResult
    func claimDrop(_ action: FileDragQuickAction) -> DropClaim? {
        ensureSession()
        guard !dropClaimed else { return nil }
        dropClaimed = true
        exitTask?.cancel()
        exitTask = nil
        targetedAction = action
        phase = .materializing(action)
        return DropClaim(generation: generation, action: action)
    }

    @discardableResult
    func completeDrop(
        claim: DropClaim,
        action: FileDragQuickAction,
        urls: [URL],
        anchor: NSView?,
        executor: FileDragActionExecutor = .production
    ) -> FileDragActionOutcome? {
        guard claim.generation == generation,
              claim.action == action,
              dropClaimed,
              case .materializing(action) = phase else {
            return nil
        }
        guard !urls.isEmpty else {
            let outcome: FileDragActionOutcome = .failed("No files were materialized")
            lastOutcome = outcome
            reset(incrementGeneration: true, preserveOutcome: true)
            scheduleOutcomeClearIfNeeded()
            return outcome
        }

        phase = .performing(action)
        let outcome = executor.perform(action, urls: urls, anchor: anchor, local: localActions)
        lastOutcome = outcome
        reset(incrementGeneration: true, preserveOutcome: true)
        scheduleOutcomeClearIfNeeded()
        return outcome
    }

    func materializationFailed(claim: DropClaim, message: String) {
        guard claim.generation == generation,
              dropClaimed,
              phase == .materializing(claim.action) else { return }
        lastOutcome = .failed(message)
        reset(incrementGeneration: true, preserveOutcome: true)
        scheduleOutcomeClearIfNeeded()
    }

    func cancel() {
        reset(incrementGeneration: true)
    }

    private func ensureSession() {
        exitTask?.cancel()
        exitTask = nil
        guard phase == .idle else { return }
        generation &+= 1
        dropClaimed = false
        outcomeClearTask?.cancel()
        outcomeClearTask = nil
        lastOutcome = nil
        phase = .dragging
    }

    private var hasTargetOwnership: Bool {
        !sourceRegions.isEmpty || bridgeTargeted || !actionTargets.isEmpty
    }

    private func scheduleEndIfUnowned() {
        guard !dropClaimed, !hasTargetOwnership, phase != .idle else { return }
        let observedGeneration = generation
        exitTask?.cancel()
        exitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.exitGraceNanoseconds ?? 0)
            guard !Task.isCancelled, let self,
                  self.generation == observedGeneration,
                  !self.hasTargetOwnership,
                  !self.dropClaimed else { return }
            self.reset(incrementGeneration: true)
        }
    }

    private func scheduleOutcomeClearIfNeeded() {
        guard outcomeMessage != nil else { return }
        outcomeClearTask?.cancel()
        let observedGeneration = generation
        outcomeClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self,
                  self.generation == observedGeneration,
                  self.phase == .idle else { return }
            self.lastOutcome = nil
            self.outcomeClearTask = nil
        }
    }

    private func reset(incrementGeneration: Bool, preserveOutcome: Bool = false) {
        exitTask?.cancel()
        exitTask = nil
        if incrementGeneration { generation &+= 1 }
        sourceRegions.removeAll()
        bridgeTargeted = false
        actionTargets.removeAll()
        dropClaimed = false
        targetedAction = nil
        hoveredAction = nil
        phase = .idle
        if !preserveOutcome {
            outcomeClearTask?.cancel()
            outcomeClearTask = nil
            lastOutcome = nil
        }
    }
}
