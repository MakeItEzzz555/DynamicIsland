import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Source parity: Droppy/BasketState.swift, FloatingBasketWindowController.swift
// (BasketAccentColor), DragMonitor.swift (detectJiggle). DynamicIsland keeps
// its own implementation; see research/FLOATING_BASKET_PHASE6_2026-10-01.md.

/// Per-basket identity colour. Values follow Droppy's subtle dark-surface
/// accents; only shown when 2+ baskets are visible.
enum BasketAccent: Int, CaseIterable, Sendable {
    case teal, coral, indigo, amber, rose, mint

    var color: Color {
        switch self {
        case .teal: Color(hue: 0.50, saturation: 0.55, brightness: 0.75)
        case .coral: Color(hue: 0.03, saturation: 0.55, brightness: 0.90)
        case .indigo: Color(hue: 0.72, saturation: 0.50, brightness: 0.80)
        case .amber: Color(hue: 0.12, saturation: 0.60, brightness: 0.95)
        case .rose: Color(hue: 0.92, saturation: 0.45, brightness: 0.85)
        case .mint: Color(hue: 0.42, saturation: 0.45, brightness: 0.80)
        }
    }

    var name: String {
        switch self {
        case .teal: "Teal"
        case .coral: "Coral"
        case .indigo: "Indigo"
        case .amber: "Amber"
        case .rose: "Rose"
        case .mint: "Mint"
        }
    }

    /// Lowest accent not used by `existing`; wraps when all are taken.
    static func next(excluding existing: [BasketAccent]) -> BasketAccent {
        allCases.first { !existing.contains($0) } ?? allCases[existing.count % allCases.count]
    }
}

enum BasketLayoutMode: String, Sendable {
    case grid
    case list
}

/// One file staged in a basket. Metadata is resolved once when the item is
/// added so SwiftUI bodies never touch the file system.
struct BasketItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let byteCount: Int64?
    let isImage: Bool
    let isDirectory: Bool
    let isDocument: Bool

    init(url: URL, id: UUID = UUID()) {
        let url = url.standardizedFileURL
        self.id = id
        self.url = url
        name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentTypeKey])
        byteCount = values?.fileSize.map(Int64.init)
        isDirectory = values?.isDirectory ?? false
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        isImage = type?.conforms(to: .image) ?? false
        isDocument = [.pdf, .text, .presentation, .spreadsheet].contains { type?.conforms(to: $0) ?? false }
    }
}

/// Reasons a visible basket must not auto-hide. Each is set and cleared by
/// its own owner, mirroring IslandLayoutStore's owner-scoped holds.
enum BasketHold: String, CaseIterable, Hashable, Sendable {
    case pointer
    case selectionDrag
    case externalDrag
    /// A drop was accepted and its file promises are still materializing.
    case dropInFlight
    case quickActions
    case nativeMenu
    case modal
    case dragOut
}

@MainActor
final class BasketState: ObservableObject, Identifiable {
    let id: UUID
    let accent: BasketAccent

    @Published private(set) var items: [BasketItem] = [] {
        didSet {
            let ids = Set(items.map(\.id))
            if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
            if let anchor = selectionAnchor, !ids.contains(anchor) { selectionAnchor = nil }
            totalByteCount = items.reduce(0) { $0 + ($1.byteCount ?? 0) }
        }
    }
    @Published private(set) var selection: Set<UUID> = []
    @Published private(set) var totalByteCount: Int64 = 0
    @Published var layout: BasketLayoutMode = .grid
    @Published var isExpanded = false
    @Published private(set) var isVisible = false
    @Published var isTargeted = false
    @Published private(set) var holds: Set<BasketHold> = []
    /// Window origin the user last left the basket at (screen points).
    var lastOrigin: CGPoint?
    private(set) var lastInteraction = Date()
    private var selectionAnchor: UUID?

    init(id: UUID = UUID(), accent: BasketAccent) {
        self.id = id
        self.accent = accent
    }

    var urls: [URL] { items.map(\.url) }

    var titleText: String {
        let count = items.count
        let noun: String
        if !items.isEmpty, items.allSatisfy(\.isImage) {
            noun = count == 1 ? "Image" : "Images"
        } else if !items.isEmpty, items.allSatisfy(\.isDocument) {
            noun = count == 1 ? "Document" : "Documents"
        } else {
            noun = count == 1 ? "File" : "Files"
        }
        return "\(count) \(noun)"
    }

    var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalByteCount, countStyle: .file)
    }

    /// Finder-like selection: plain click selects one, Command toggles,
    /// Shift extends a contiguous range in basket order.
    func select(_ id: UUID, extend: Bool = false, range: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        touch()
        if range, let anchor = selectionAnchor, let anchorIndex = items.firstIndex(where: { $0.id == anchor }) {
            let bounds = min(anchorIndex, index)...max(anchorIndex, index)
            selection.formUnion(items[bounds].map(\.id))
            return
        }
        if extend {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
        selectionAnchor = id
    }

    func selectAll() {
        selection = Set(items.map(\.id))
        selectionAnchor = items.first?.id
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
    }

    /// Rubber-band selection result.
    func setSelection(_ ids: Set<UUID>) {
        let valid = ids.intersection(items.map(\.id))
        if valid != selection { selection = valid }
    }

    /// Dragging a selected item drags the whole selection (basket order);
    /// dragging an unselected item drags only that item.
    func dragPayload(startingAt id: UUID) -> [URL] {
        if selection.contains(id) {
            return items.filter { selection.contains($0.id) }.map(\.url)
        }
        return items.first { $0.id == id }.map { [$0.url] } ?? []
    }

    /// Targets for an action invoked on `id` (context menu): the selection
    /// if `id` is part of it, otherwise just that item.
    func actionTargets(for id: UUID) -> [BasketItem] {
        if selection.contains(id) { return items.filter { selection.contains($0.id) } }
        return items.filter { $0.id == id }
    }

    func setHold(_ hold: BasketHold, _ active: Bool) {
        if active {
            guard !holds.contains(hold) else { return }
            holds.insert(hold)
            touch()
        } else {
            guard holds.contains(hold) else { return }
            holds.remove(hold)
        }
    }

    func touch() { lastInteraction = Date() }

    // Mutations are owned by BasketManager (ownership bookkeeping).
    func appendItems(_ new: [BasketItem]) {
        guard !new.isEmpty else { return }
        items.append(contentsOf: new)
        touch()
    }

    @discardableResult
    func removeItems(_ ids: Set<UUID>) -> [BasketItem] {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return [] }
        items.removeAll { ids.contains($0.id) }
        touch()
        return removed
    }

    func replaceItem(_ id: UUID, with item: BasketItem) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = item
    }

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        if !visible {
            isTargeted = false
            holds.subtract([.pointer, .externalDrag, .quickActions, .selectionDrag])
        }
    }
}

// MARK: - Jiggle

/// Pure shake detector for an active external file drag.
struct BasketJiggleDetector {
    static let timeWindow: TimeInterval = 0.5
    /// Droppy: a reversal is a direction dot product below -0.3.
    static let reversalDot: CGFloat = -0.3

    static func requiredDirectionChanges(sensitivity: Int) -> Int {
        max(2, min(5, Int((6.0 - Double(sensitivity)).rounded())))
    }

    static func minimumMovement(sensitivity: Int) -> CGFloat {
        max(3.0, min(8.0, 9.0 - CGFloat(sensitivity) * 1.25))
    }

    private(set) var sensitivity: Int
    private var generation: Int?
    private var hasTriggered = false
    private var lastLocation: CGPoint = .zero
    private var lastDirection: CGPoint = .zero
    private var reversals: [TimeInterval] = []

    init(sensitivity: Int) {
        self.sensitivity = min(max(sensitivity, 1), 5)
    }

    mutating func setSensitivity(_ value: Int) {
        sensitivity = min(max(value, 1), 5)
    }

    mutating func beginDrag(generation: Int, at location: CGPoint) {
        self.generation = generation
        hasTriggered = false
        lastLocation = location
        lastDirection = .zero
        reversals.removeAll()
    }

    mutating func endDrag() {
        generation = nil
        hasTriggered = false
        lastDirection = .zero
        reversals.removeAll()
    }

    /// Returns true exactly once for the active generation.
    mutating func sample(_ location: CGPoint, at time: TimeInterval, generation: Int) -> Bool {
        guard self.generation == generation, !hasTriggered else { return false }
        let dx = location.x - lastLocation.x
        let dy = location.y - lastLocation.y
        let magnitude = (dx * dx + dy * dy).squareRoot()
        // Droppy measures per-sample movement: the last location advances
        // even when the step is too small to count.
        lastLocation = location
        guard magnitude > Self.minimumMovement(sensitivity: sensitivity) else { return false }
        let direction = CGPoint(x: dx / magnitude, y: dy / magnitude)
        defer { lastDirection = direction }
        guard lastDirection != .zero else { return false }
        let dot = direction.x * lastDirection.x + direction.y * lastDirection.y
        guard dot < Self.reversalDot else { return false }
        reversals.append(time)
        reversals.removeAll { time - $0 >= Self.timeWindow }
        guard reversals.count >= Self.requiredDirectionChanges(sensitivity: sensitivity) else { return false }
        hasTriggered = true
        return true
    }
}

// MARK: - Placement

enum BasketPlacement {
    /// Screen whose visible frame contains `point`, else the nearest one.
    static func screen(for point: CGPoint, in screens: [CGRect]) -> CGRect? {
        if let containing = screens.first(where: { $0.contains(point) }) { return containing }
        return screens.min { distance(point, $0) < distance(point, $1) }
    }

    static func frame(centeredAt pointer: CGPoint, size: CGSize, screens: [CGRect]) -> CGRect {
        let frame = CGRect(x: pointer.x - size.width / 2, y: pointer.y - size.height / 2,
                           width: size.width, height: size.height)
        guard let screen = screen(for: pointer, in: screens) else { return frame }
        return clamp(frame, into: screen)
    }

    /// The remembered origin, only while a display still shows most of it.
    static func restoredFrame(origin: CGPoint?, size: CGSize, screens: [CGRect]) -> CGRect? {
        guard let origin else { return nil }
        let frame = CGRect(origin: origin, size: size)
        guard let screen = screens.max(by: { overlap(frame, $0) < overlap(frame, $1) }),
              overlap(frame, screen) >= frame.width * frame.height * 0.5 else { return nil }
        return clamp(frame, into: screen)
    }

    /// Resizes around the top-centre (the drag handle stays put).
    static func resized(_ frame: CGRect, to size: CGSize, screens: [CGRect]) -> CGRect {
        let resized = CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                             width: size.width, height: size.height)
        guard let screen = screens.max(by: { overlap(frame, $0) < overlap(frame, $1) }) else { return resized }
        return clamp(resized, into: screen)
    }

    static func clamp(_ frame: CGRect, into screen: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(frame.width, screen.width)
        result.size.height = min(frame.height, screen.height)
        result.origin.x = min(max(frame.minX, screen.minX), screen.maxX - result.width)
        result.origin.y = min(max(frame.minY, screen.minY), screen.maxY - result.height)
        return result
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

// MARK: - Auto-hide

enum BasketAutoHideDecision: Equatable {
    case keep
    case hide(after: TimeInterval)
    /// Empty baskets close (Droppy closes an empty basket when a drag ends
    /// without a drop, and whenever its last item leaves).
    case close
}

enum BasketAutoHidePolicy {
    static func decide(
        isEmpty: Bool,
        isVisible: Bool,
        holds: Set<BasketHold>,
        autoHideEnabled: Bool,
        delay: TimeInterval,
        externalDragActive: Bool
    ) -> BasketAutoHideDecision {
        guard isVisible, holds.isEmpty, !externalDragActive else { return .keep }
        if isEmpty { return .close }
        return autoHideEnabled ? .hide(after: delay) : .keep
    }
}
