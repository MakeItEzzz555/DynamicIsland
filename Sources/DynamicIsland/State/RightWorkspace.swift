import Foundation

/// Pages of the Island page's right column. Only one occupies the column's
/// geometry at a time; hidden pages never widen the island.
enum RightWorkspacePage: String, CaseIterable, Codable, Identifiable, Sendable {
    case overview
    case productivity
    case appsMedia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .productivity: "Productivity"
        case .appsMedia: "Apps & Media"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .productivity: "wand.and.stars"
        case .appsMedia: "square.stack.3d.up"
        }
    }
}

/// Productivity page controls. Every case routes to a production controller.
enum RightWorkspaceTool: String, CaseIterable, Codable, Identifiable, Sendable {
    case camera
    case keepAwake
    case windowSnap
    case terminal
    case voice
    case backgroundRemoval
    case convert
    case reminders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .keepAwake: "Keep Awake"
        case .windowSnap: "Window Snap"
        case .terminal: "Terminal"
        case .voice: "Voice"
        case .backgroundRemoval: "Remove BG"
        case .convert: "Convert"
        case .reminders: "Reminders"
        }
    }

    var symbolName: String {
        switch self {
        case .camera: "camera.fill"
        case .keepAwake: "cup.and.saucer.fill"
        case .windowSnap: "rectangle.split.2x1"
        case .terminal: "terminal.fill"
        case .voice: "mic.fill"
        case .backgroundRemoval: "person.crop.rectangle"
        case .convert: "arrow.triangle.2.circlepath"
        case .reminders: "checklist"
        }
    }
}

/// Apps & Media page sections.
enum RightWorkspaceSection: String, CaseIterable, Codable, Identifiable, Sendable {
    case appLibrary
    case spotify
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appLibrary: "App Library"
        case .spotify: "Spotify"
        case .calendar: "Calendar"
        }
    }

    var symbolName: String {
        switch self {
        case .appLibrary: "square.grid.3x3.fill"
        case .spotify: "music.note.list"
        case .calendar: "calendar"
        }
    }
}

enum RightWorkspaceIndicatorStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case dots
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dots: "Dots"
        case .hidden: "Hidden"
        }
    }
}

/// Ordered, visibility-aware layout of the right workspace. Stored by
/// stable identifiers only; always normalized (no duplicates, every known
/// item present exactly once, at least one visible page).
struct RightWorkspaceConfiguration: Codable, Equatable, Sendable {
    var pageOrder: [RightWorkspacePage]
    var hiddenPages: Set<RightWorkspacePage>
    var defaultPage: RightWorkspacePage
    var indicatorStyle: RightWorkspaceIndicatorStyle
    var swipeEnabled: Bool
    var toolOrder: [RightWorkspaceTool]
    var hiddenTools: Set<RightWorkspaceTool>
    var sectionOrder: [RightWorkspaceSection]
    var hiddenSections: Set<RightWorkspaceSection>

    static let `default` = RightWorkspaceConfiguration(
        pageOrder: RightWorkspacePage.allCases,
        hiddenPages: [],
        defaultPage: .overview,
        indicatorStyle: .dots,
        swipeEnabled: true,
        toolOrder: RightWorkspaceTool.allCases,
        hiddenTools: [],
        sectionOrder: RightWorkspaceSection.allCases,
        hiddenSections: []
    )

    var visiblePages: [RightWorkspacePage] {
        pageOrder.filter { !hiddenPages.contains($0) }
    }

    var visibleTools: [RightWorkspaceTool] {
        toolOrder.filter { !hiddenTools.contains($0) }
    }

    var visibleSections: [RightWorkspaceSection] {
        sectionOrder.filter { !hiddenSections.contains($0) }
    }

    var normalized: RightWorkspaceConfiguration {
        var copy = self
        copy.pageOrder = Self.normalizedOrder(pageOrder)
        copy.toolOrder = Self.normalizedOrder(toolOrder)
        copy.sectionOrder = Self.normalizedOrder(sectionOrder)
        if copy.hiddenPages.count >= RightWorkspacePage.allCases.count {
            copy.hiddenPages.remove(.overview)
        }
        if copy.hiddenPages.contains(copy.defaultPage) {
            copy.defaultPage = copy.visiblePages.first ?? .overview
        }
        return copy
    }

    /// Keeps the first occurrence of each known value and appends any
    /// missing ones in declaration order.
    static func normalizedOrder<T: CaseIterable & Hashable>(_ order: [T]) -> [T] where T.AllCases == [T] {
        var seen = Set<T>()
        var result = order.filter { seen.insert($0).inserted }
        result += T.allCases.filter { !seen.contains($0) }
        return result
    }

    mutating func setVisibility<T: Hashable>(
        _ item: T,
        visible: Bool,
        in keyPath: WritableKeyPath<RightWorkspaceConfiguration, Set<T>>
    ) {
        if visible {
            self[keyPath: keyPath].remove(item)
        } else {
            self[keyPath: keyPath].insert(item)
        }
    }

    mutating func move<T: Equatable>(_ keyPath: WritableKeyPath<RightWorkspaceConfiguration, [T]>, item: T, by offset: Int) {
        var list = self[keyPath: keyPath]
        guard let index = list.firstIndex(of: item) else { return }
        let target = min(max(index + offset, 0), list.count - 1)
        guard target != index else { return }
        list.remove(at: index)
        list.insert(item, at: target)
        self[keyPath: keyPath] = list
    }
}

/// Persists the workspace configuration and owns the current page.
@MainActor
final class RightWorkspaceStore: ObservableObject {
    static let defaultsKey = "rightWorkspace.configuration.v1"

    @Published private(set) var configuration: RightWorkspaceConfiguration
    @Published private(set) var currentPage: RightWorkspacePage
    /// +1 when the last change moved forward, -1 backward; drives the
    /// direction of the page transition.
    @Published private(set) var transitionDirection = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(RightWorkspaceConfiguration.self, from: $0) }
        let configuration = (stored ?? .default).normalized
        self.configuration = configuration
        currentPage = configuration.defaultPage
    }

    func update(_ change: (inout RightWorkspaceConfiguration) -> Void) {
        var next = configuration
        change(&next)
        next = next.normalized
        guard next != configuration else { return }
        configuration = next
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        if !next.visiblePages.contains(currentPage) {
            currentPage = next.defaultPage
        }
    }

    func resetToDefaults() {
        update { $0 = .default }
    }

    var canGoNext: Bool { adjacentPage(offset: 1) != nil }
    var canGoPrevious: Bool { adjacentPage(offset: -1) != nil }

    /// Returns whether the page changed. Pages do not wrap.
    @discardableResult
    func showNext() -> Bool { step(1) }

    @discardableResult
    func showPrevious() -> Bool { step(-1) }

    func show(_ page: RightWorkspacePage) {
        let pages = configuration.visiblePages
        guard pages.contains(page), page != currentPage,
              let from = pages.firstIndex(of: currentPage),
              let to = pages.firstIndex(of: page) else { return }
        transitionDirection = to > from ? 1 : -1
        currentPage = page
    }

    func resetToDefaultPage() {
        currentPage = configuration.defaultPage
    }

    private func step(_ offset: Int) -> Bool {
        guard let page = adjacentPage(offset: offset) else { return false }
        transitionDirection = offset > 0 ? 1 : -1
        currentPage = page
        return true
    }

    private func adjacentPage(offset: Int) -> RightWorkspacePage? {
        let pages = configuration.visiblePages
        guard let index = pages.firstIndex(of: currentPage) else { return pages.first }
        let target = index + offset
        return pages.indices.contains(target) ? pages[target] : nil
    }
}

/// Horizontal paging intent, ported from Droppy's
/// `NotchWindowController.handleScrollEvent(_:)`: a new sequence after
/// 0.3 s of quiet, horizontal dominance of 1.5×, accumulated movement past
/// 30 points on a trackpad. Divergence: Droppy toggles an idempotent state,
/// so it may fire again within one gesture; paging is not idempotent, so a
/// sequence fires at most once (latched until quiet or a new physical
/// gesture) and momentum can never skip pages.
struct RightWorkspaceSwipeRecognizer: Equatable, Sendable {
    static let sequenceTimeout: TimeInterval = 0.3
    static let horizontalDominance: CGFloat = 1.5
    static let trackpadThreshold: CGFloat = 30

    enum Phase: Equatable, Sendable {
        case began
        case changed
        case ended
        case momentum
        case none
    }

    enum Outcome: Equatable, Sendable {
        /// Not a horizontal workspace gesture; let other handlers see it.
        case ignored
        /// Horizontal intent owned by the workspace, below threshold or latched.
        case consumed
        /// Swipe left (content moves left): next page.
        case next
        /// Swipe right: previous page.
        case previous
    }

    private(set) var accumulatedX: CGFloat = 0
    private(set) var lastEventAt: TimeInterval?
    private(set) var isLatched = false
    private(set) var ownsSequence = false

    mutating func handle(deltaX: CGFloat, deltaY: CGFloat, phase: Phase, at time: TimeInterval) -> Outcome {
        if phase == .began || lastEventAt.map({ time - $0 > Self.sequenceTimeout }) == true {
            reset()
        }
        lastEventAt = time

        let horizontal = abs(deltaX) > abs(deltaY) * Self.horizontalDominance
        if !ownsSequence {
            guard horizontal else { return .ignored }
            ownsSequence = true
        }
        if isLatched || phase == .momentum {
            return .consumed
        }
        guard horizontal else { return .consumed }
        accumulatedX += deltaX
        if accumulatedX < -Self.trackpadThreshold {
            isLatched = true
            accumulatedX = 0
            return .next
        }
        if accumulatedX > Self.trackpadThreshold {
            isLatched = true
            accumulatedX = 0
            return .previous
        }
        return .consumed
    }

    mutating func reset() {
        accumulatedX = 0
        isLatched = false
        ownsSequence = false
    }
}
