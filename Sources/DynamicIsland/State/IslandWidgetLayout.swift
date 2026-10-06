import Foundation
import Combine
import CoreGraphics

enum IslandWidget: String, CaseIterable, Codable, Identifiable {
    case media, files, clipboard, timer, calendar, shortcuts, activities, chat, terminal, feed, workspace
    case agentUsage, codexUsage, claudeUsage
    func isEligible(on surface: WorkspaceSurface) -> Bool {
        switch surface {
        case .media: return ![.chat, .terminal, .feed].contains(self)
        case .agents: return [.chat, .terminal, .feed, .timer, .agentUsage, .codexUsage, .claudeUsage].contains(self)
        }
    }
    var isUsage: Bool { [.agentUsage, .codexUsage, .claudeUsage].contains(self) }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .media: "Now Playing"
        case .files: "File Tray"
        case .clipboard: "Clipboard"
        case .timer: "Focus Timer"
        case .calendar: "Calendar"
        case .shortcuts: "Shortcuts"
        case .activities: "Live Activities"
        case .chat: "Chat"
        case .terminal: "Terminal"
        case .feed: "Feed"
        case .workspace: "Workspace"
        case .agentUsage: "Agent Usage"
        case .codexUsage: "Codex Usage"
        case .claudeUsage: "Claude Usage"
        }
    }
    var symbol: String {
        switch self {
        case .media: "music.note"
        case .files: "tray.fill"
        case .clipboard: "clipboard.fill"
        case .timer: "timer"
        case .calendar: "calendar"
        case .shortcuts: "bolt.fill"
        case .activities: "waveform.path"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .terminal: "terminal.fill"
        case .feed: "list.bullet.rectangle"
        case .workspace: "rectangle.split.2x1"
        case .agentUsage: "gauge.with.dots.needle.50percent"
        case .codexUsage: "sparkle"
        case .claudeUsage: "brain"
        }
    }
}

/// Usage gauges are strips (bands): consecutive band widgets form their own
/// centered row; their size changes density, not grid span.
extension IslandWidget {
    var isBand: Bool { self == .agentUsage || self == .codexUsage || self == .claudeUsage }
}

/// Only presentation IDs are stored. Controllers, permissions and running
/// work remain in IslandModules when a widget is removed or rearranged.
struct IslandWidgetLayout: Equatable {
    static let initial = Self(widgets: [.media, .files, .clipboard])
    private(set) var widgets: [IslandWidget]
    init(widgets: [IslandWidget]) {
        var seen = Set<IslandWidget>()
        self.widgets = widgets.filter { seen.insert($0).inserted }
    }
    init(stored: String) {
        self.init(widgets: stored.split(separator: ",").compactMap { IslandWidget(rawValue: String($0)) })
    }
    var stored: String { widgets.map(\.rawValue).joined(separator: ",") }
    mutating func toggle(_ widget: IslandWidget) {
        if widgets.contains(widget) { widgets.removeAll { $0 == widget } }
        else { widgets.append(widget) }
    }
    mutating func move(_ widget: IslandWidget, before target: IslandWidget) {
        guard widget != target, widgets.contains(widget), widgets.contains(target) else { return }
        widgets.removeAll { $0 == widget }
        widgets.insert(widget, at: widgets.firstIndex(of: target)!)
    }
    mutating func shift(_ widget: IslandWidget, by delta: Int) {
        guard let index = widgets.firstIndex(of: widget) else { return }
        let next = min(widgets.count - 1, max(0, index + delta))
        widgets.remove(at: index)
        widgets.insert(widget, at: next)
    }
}

enum FocusTimerMode: String, CaseIterable, Identifiable {
    case focus, rest
    var id: Self { self }
    var title: String { self == .focus ? "Focus" : "Break" }
}

enum TimerRulerScale {
    static let pointsPerMinute = 7.0
    static func minutes(_ value: Double) -> Int {
        value.isFinite ? Int(min(180, max(1, value)).rounded()) : 25
    }
    static func dragged(from minutes: Int, translation: Double) -> Int {
        self.minutes(Double(minutes) - translation / pointsPerMinute)
    }
}

// MARK: - Versioned workspace presentation

/// Presentation identity only. Never a process, session, controller, or SwiftUI identity.
struct WidgetID: RawRepresentable, Hashable, Codable, Identifiable {
    let rawValue: String
    var id: String { rawValue }
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

enum WorkspaceSurface: String, CaseIterable, Codable, Identifiable {
    case media, agents
    var id: String { rawValue }
}

enum WidgetPresentationSize: String, CaseIterable, Codable {
    case compact, standard, large
    var title: String { switch self { case .compact: "Compact"; case .standard: "Standard"; case .large: "Large" } }
    /// Grid span (Compact 1x1, Standard 2x1, Large 2x2). Size is a layout
    /// class with its own content hierarchy, never a scale factor.
    var span: (columns: Int, rows: Int) { WidgetGridMetrics.span(self) }
}

struct WidgetPlacement: Codable, Equatable, Identifiable {
    var id: WidgetID
    var kind: IslandWidget
    var surface: WorkspaceSurface
    var order: Int
    var isVisible: Bool
    var groupID: WidgetID?
    var size: WidgetPresentationSize
    /// Shares a column with the preceding region (placed directly below it).
    var stacksBelowPrevious: Bool
    init(id: WidgetID? = nil, kind: IslandWidget, surface: WorkspaceSurface,
         order: Int, isVisible: Bool = true, groupID: WidgetID? = nil, size: WidgetPresentationSize = .standard,
         stacksBelowPrevious: Bool = false) {
        self.id = id ?? WidgetID("\(surface.rawValue).\(kind.rawValue)")
        self.kind = kind; self.surface = surface; self.order = order
        self.isVisible = isVisible; self.groupID = groupID; self.size = size
        self.stacksBelowPrevious = stacksBelowPrevious
    }
    private enum CodingKeys: String, CodingKey { case id, kind, surface, order, isVisible, groupID, size, stacksBelowPrevious }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(IslandWidget.self, forKey: .kind)
        let surface = try values.decode(WorkspaceSurface.self, forKey: .surface)
        self.init(id: try values.decodeIfPresent(WidgetID.self, forKey: .id), kind: kind,
                  surface: surface, order: try values.decodeIfPresent(Int.self, forKey: .order) ?? 0,
                  isVisible: try values.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true,
                  groupID: try values.decodeIfPresent(WidgetID.self, forKey: .groupID),
                  size: (try? values.decode(WidgetPresentationSize.self, forKey: .size)) ?? .standard,
                  stacksBelowPrevious: (try? values.decode(Bool.self, forKey: .stacksBelowPrevious)) ?? false)
    }
}

struct WidgetGroup: Codable, Equatable, Identifiable {
    var id: WidgetID
    var surface: WorkspaceSurface
    var members: [WidgetID]
}

struct WorkspaceWidgetRegion: Equatable, Identifiable {
    var id: WidgetID
    var widgets: [WidgetPlacement]
    var isStack: Bool { widgets.count > 1 }
    /// Column membership with the preceding region (vertical composition).
    var stacksBelowPrevious: Bool { widgets.first?.stacksBelowPrevious ?? false }
}

struct NavigationTabConfiguration: Codable, Equatable {
    var order: [ExpandedIslandPage]
    var hidden: Set<ExpandedIslandPage>
    static let initial = Self(order: ExpandedIslandPage.allCases.filter { $0 != .messages }, hidden: [])
    init(order: [ExpandedIslandPage] = Self.initial.order, hidden: Set<ExpandedIslandPage> = []) {
        self.order = order; self.hidden = hidden
    }
    private enum CodingKeys: String, CodingKey { case order, hidden }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? values.decode([String].self, forKey: .order))?.compactMap(ExpandedIslandPage.init(rawValue:)) ?? Self.initial.order
        hidden = Set((try? values.decode([String].self, forKey: .hidden))?.compactMap(ExpandedIslandPage.init(rawValue:)) ?? [])
        self = normalized()
    }
    func normalized() -> Self {
        var seen = Set<ExpandedIslandPage>()
        let valid = order.filter { $0 != .messages && seen.insert($0).inserted }
        let missing = Self.initial.order.filter { !seen.contains($0) }
        return Self(order: valid + missing, hidden: hidden.subtracting([.island, .messages]))
    }
    mutating func move(_ page: ExpandedIslandPage, before target: ExpandedIslandPage?) {
        guard page != .messages, page != target else { return }
        self = normalized()
        order.removeAll { $0 == page }
        if let target, let index = order.firstIndex(of: target) { order.insert(page, at: index) }
        else { order.append(page) }
    }
    mutating func shift(_ page: ExpandedIslandPage, by delta: Int) {
        self = normalized()
        guard let index = order.firstIndex(of: page) else { return }
        let next = max(0, min(order.count - 1, index + delta))
        order.remove(at: index); order.insert(page, at: next)
    }
    mutating func setVisible(_ page: ExpandedIslandPage, visible: Bool) {
        guard page != .island, page != .messages else { return }
        if visible { hidden.remove(page) } else { hidden.insert(page) }
    }
}

/// One persisted source of truth; drag state and stack selection remain presentation-local.
struct WorkspaceConfiguration: Codable, Equatable {
    /// 2: the Agents usage row became the Combined Usage widget (migrated).
    static let currentVersion = 2
    var schemaVersion = currentVersion
    var placements: [WidgetPlacement]
    var groups: [WidgetGroup]
    var navigation: NavigationTabConfiguration
    var customizedSurfaces: [WorkspaceSurface]

    static let initial = Self(
        placements: IslandWidgetLayout.initial.widgets.enumerated().map {
            WidgetPlacement(kind: $0.element, surface: .media, order: $0.offset)
        } + [.init(kind: .agentUsage, surface: .agents, order: 0), .init(kind: .chat, surface: .agents, order: 1),
             .init(kind: .feed, surface: .agents, order: 2, size: .compact)],
        groups: [], navigation: .initial, customizedSurfaces: [])

    init(schemaVersion: Int = currentVersion, placements: [WidgetPlacement], groups: [WidgetGroup] = [],
         navigation: NavigationTabConfiguration = .initial, customizedSurfaces: [WorkspaceSurface] = []) {
        self.schemaVersion = schemaVersion; self.placements = placements
        self.groups = groups; self.navigation = navigation; self.customizedSurfaces = customizedSurfaces
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, placements, groups, navigation, customizedSurfaces }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        placements = (try? values.decode([Lossy<WidgetPlacement>].self, forKey: .placements))?.compactMap(\.value) ?? []
        groups = (try? values.decode([Lossy<WidgetGroup>].self, forKey: .groups))?.compactMap(\.value) ?? []
        navigation = (try? values.decode(NavigationTabConfiguration.self, forKey: .navigation)) ?? .initial
        customizedSurfaces = (try? values.decode([String].self, forKey: .customizedSurfaces))?.compactMap(WorkspaceSurface.init(rawValue:)) ?? []
    }
    func widgets(on surface: WorkspaceSurface) -> [WidgetPlacement] {
        placements.filter { $0.surface == surface && $0.isVisible }
            .sorted { $0.order == $1.order ? $0.id.rawValue < $1.id.rawValue : $0.order < $1.order }
    }
    func placement(kind: IslandWidget, on surface: WorkspaceSurface) -> WidgetPlacement? {
        placements.first { $0.kind == kind && $0.surface == surface }
    }
    func regions(on surface: WorkspaceSurface) -> [WorkspaceWidgetRegion] {
        let visible = widgets(on: surface)
        var emitted = Set<WidgetID>()
        return visible.compactMap { widget in
            if let groupID = widget.groupID,
               let group = groups.first(where: { $0.id == groupID && $0.surface == surface }) {
                guard emitted.insert(groupID).inserted else { return nil }
                let members = group.members.compactMap { id in visible.first { $0.id == id } }
                return WorkspaceWidgetRegion(id: groupID, widgets: members)
            }
            return WorkspaceWidgetRegion(id: widget.id, widgets: [widget])
        }
    }
    func normalized() -> Self {
        var result = self
        result.schemaVersion = Self.currentVersion
        result.navigation = navigation.normalized()
        result.customizedSurfaces = WorkspaceSurface.allCases.filter { customizedSurfaces.contains($0) }
        var identities = Set<WidgetID>()
        var singletons = Set<String>()
        result.placements = placements.enumerated().sorted {
            $0.element.order == $1.element.order ? $0.offset < $1.offset : $0.element.order < $1.element.order
        }.compactMap { _, placement in
            guard placement.kind.isEligible(on: placement.surface), !placement.id.rawValue.isEmpty,
                  identities.insert(placement.id).inserted,
                  singletons.insert("\(placement.surface.rawValue).\(placement.kind.rawValue)").inserted else { return nil }
            return placement
        }
        // Chat remains a usable primary surface. A corrupt/empty Media layout recovers Now Playing.
        if let index = result.placements.firstIndex(where: { $0.surface == .agents && $0.kind == .chat }) {
            result.placements[index].isVisible = true
        } else {
            result.placements.append(.init(id: result.uniqueID("agents.chat"), kind: .chat, surface: .agents, order: 0))
        }
        if !result.placements.contains(where: { $0.surface == .media && $0.isVisible }) {
            if let index = result.placements.firstIndex(where: { $0.surface == .media && $0.kind == .media }) {
                result.placements[index].isVisible = true
            } else {
                result.placements.append(.init(id: result.uniqueID("media.media"), kind: .media, surface: .media, order: 0))
            }
        }
        var groupIDs = Set<WidgetID>()
        var groupedMembers = Set<WidgetID>()
        result.groups = groups.compactMap { group in
            let members = group.members.compactMap { id in result.placements.first { $0.id == id && $0.isVisible && $0.surface == group.surface } }
            guard group.surface == .agents, members.count == 2,
                  Set(members.map(\.kind)) == Set([.chat, .terminal]),
                  !group.id.rawValue.isEmpty, !result.placements.contains(where: { $0.id == group.id }),
                  groupIDs.insert(group.id).inserted,
                  members.allSatisfy({ !groupedMembers.contains($0.id) }) else { return nil }
            groupedMembers.formUnion(members.map(\.id))
            // The first stack segment is consistently Chat, independent of drop direction.
            return WidgetGroup(id: group.id, surface: group.surface, members: members.sorted { $0.kind == .chat && $1.kind != .chat }.map(\.id))
        }
        for index in result.placements.indices {
            result.placements[index].groupID = result.groups.first { $0.members.contains(result.placements[index].id) }?.id
        }
        result.placements = WorkspaceSurface.allCases.flatMap { surface in
            result.placements.filter { $0.surface == surface }
        }
        for surface in WorkspaceSurface.allCases {
            let order = result.placements.filter { $0.surface == surface }.map(\.id)
            for (offset, id) in order.enumerated() {
                if let index = result.placements.firstIndex(where: { $0.id == id }) { result.placements[index].order = offset }
            }
            // A column needs a visible predecessor; stack segments never split vertically.
            let visibleIDs = result.regions(on: surface).map(\.id)
            for index in result.placements.indices where result.placements[index].surface == surface {
                let placement = result.placements[index]
                let regionID = placement.groupID ?? placement.id
                if !placement.isVisible || placement.groupID != nil || visibleIDs.first == regionID {
                    result.placements[index].stacksBelowPrevious = false
                }
            }
        }
        return result
    }
    private func uniqueID(_ base: String) -> WidgetID {
        var id = WidgetID(base); var suffix = 1
        while placements.contains(where: { $0.id == id }) || groups.contains(where: { $0.id == id }) {
            id = WidgetID("\(base).\(suffix)"); suffix += 1
        }
        return id
    }
    /// Resets only the edited host. Navigation and every other host stay intact.
    mutating func resetWidgets(on surface: WorkspaceSurface) {
        groups.removeAll { $0.surface == surface }
        placements.removeAll { $0.surface == surface }
        for placement in Self.initial.placements where placement.surface == surface {
            var restored = placement
            restored.id = uniqueID(placement.id.rawValue)
            placements.append(restored)
        }
        // A reset is an explicit layout choice; Done still owns persistence.
        markCustomized(surface)
        self = normalized()
    }

    mutating func markCustomized(_ surface: WorkspaceSurface) {
        if !customizedSurfaces.contains(surface) { customizedSurfaces.append(surface) }
    }
    mutating func add(_ kind: IslandWidget, on surface: WorkspaceSurface, before target: WidgetID? = nil) {
        guard kind.isEligible(on: surface) else { return }
        let id: WidgetID
        if let index = placements.firstIndex(where: { $0.kind == kind && $0.surface == surface }) {
            guard !placements[index].isVisible else { return }
            placements[index].isVisible = true; id = placements[index].id
        } else {
            id = uniqueID("\(surface.rawValue).\(kind.rawValue)")
            placements.append(.init(id: id, kind: kind, surface: surface, order: placements.count))
        }
        move(id, before: target, on: surface)
    }
    mutating func remove(_ id: WidgetID) {
        if let group = groups.first(where: { $0.id == id }) {
            for member in group.members { remove(member) }
            groups.removeAll { $0.id == id }
        } else if let index = placements.firstIndex(where: { $0.id == id }), placements[index].kind != .chat {
            releaseColumn(of: [id], on: placements[index].surface)
            placements[index].isVisible = false
            if let groupID = placements[index].groupID { separateStack(groupID) }
        }
        self = normalized()
    }
    mutating func move(_ id: WidgetID, before target: WidgetID?, on surface: WorkspaceSurface) {
        guard id != target else { return }
        let ids = groups.first(where: { $0.id == id })?.members ?? [id]
        let moving = placements.filter { ids.contains($0.id) }
        guard !moving.isEmpty, moving.allSatisfy({ $0.kind.isEligible(on: surface) }),
              moving.allSatisfy({ item in !placements.contains { !ids.contains($0.id) && $0.surface == surface && $0.kind == item.kind } }) else { return }
        let targetMember = groups.first(where: { $0.id == target })?.members.first ?? target
        guard !ids.contains(where: { $0 == targetMember }) else { return }
        releaseColumn(of: ids, on: surface)
        placements.removeAll { ids.contains($0.id) }
        let insertion = targetMember.flatMap { targetID in placements.firstIndex { $0.id == targetID && $0.surface == surface } } ?? placements.endIndex
        var moved = moving
        for index in moved.indices { moved[index].surface = surface }
        placements.insert(contentsOf: moved, at: insertion)
        for index in placements.indices { placements[index].order = index }
        if let groupIndex = groups.firstIndex(where: { $0.id == id }) { groups[groupIndex].surface = surface }
        self = normalized()
    }
    /// Leaving a column: the moved widget stands alone and a widget that was
    /// stacked below it inherits its column position.
    private mutating func releaseColumn(of ids: [WidgetID], on surface: WorkspaceSurface) {
        let regions = regions(on: surface)
        guard let index = regions.firstIndex(where: { region in region.widgets.contains { ids.contains($0.id) } }) else { return }
        let inherited = regions[index].stacksBelowPrevious
        if index + 1 < regions.count, regions[index + 1].stacksBelowPrevious {
            for widget in regions[index + 1].widgets {
                if let at = placements.firstIndex(where: { $0.id == widget.id }) { placements[at].stacksBelowPrevious = inherited }
            }
        }
        for at in placements.indices where ids.contains(placements[at].id) { placements[at].stacksBelowPrevious = false }
    }

    /// Places `id` directly above or below `target` in one column.
    mutating func stack(_ id: WidgetID, onto target: WidgetID, below: Bool, on surface: WorkspaceSurface) {
        guard id != target,
              let targetRegion = regions(on: surface).first(where: { $0.id == target }), !targetRegion.isStack,
              groups.first(where: { $0.id == id }) == nil else { return }
        let regionIDs = regions(on: surface).map(\.id)
        guard let targetIndex = regionIDs.firstIndex(of: target) else { return }
        if below {
            let after = regionIDs.dropFirst(targetIndex + 1).first { $0 != id }
            move(id, before: after, on: surface)
            if let at = placements.firstIndex(where: { $0.id == id }) { placements[at].stacksBelowPrevious = true }
        } else {
            let targetStacks = targetRegion.stacksBelowPrevious
            move(id, before: target, on: surface)
            if let at = placements.firstIndex(where: { $0.id == id }) { placements[at].stacksBelowPrevious = targetStacks }
            if let at = placements.firstIndex(where: { $0.id == target }) { placements[at].stacksBelowPrevious = true }
        }
        self = normalized()
    }

    mutating func shift(_ id: WidgetID, by delta: Int) {
        guard let surface = placements.first(where: { $0.id == id })?.surface ?? groups.first(where: { $0.id == id })?.surface else { return }
        let regions = regions(on: surface)
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        let destination = max(0, min(regions.count - 1, index + delta))
        guard destination != index else { return }
        let before = destination > index ? (destination + 1 < regions.count ? regions[destination + 1].id : nil) : regions[destination].id
        move(id, before: before, on: surface)
    }
    mutating func setSize(_ size: WidgetPresentationSize, for id: WidgetID) {
        let members = groups.first(where: { $0.id == id })?.members ?? [id]
        for index in placements.indices where members.contains(placements[index].id) { placements[index].size = size }
    }

    mutating func combineTerminalWithChat(on surface: WorkspaceSurface = .agents) {
        guard surface == .agents,
              let chat = placement(kind: .chat, on: surface), chat.isVisible,
              let terminal = placement(kind: .terminal, on: surface), terminal.isVisible else { return }
        guard !groups.contains(where: { $0.members.contains(chat.id) || $0.members.contains(terminal.id) }) else { return }
        let id = uniqueID("stack.\(chat.id.rawValue).\(terminal.id.rawValue)")
        groups.append(.init(id: id, surface: surface, members: [chat.id, terminal.id]))
        self = normalized()
    }
    mutating func separateStack(_ id: WidgetID) {
        groups.removeAll { $0.id == id }
        for index in placements.indices where placements[index].groupID == id { placements[index].groupID = nil }
        self = normalized()
    }
    /// Migration hook; unknown future schemas recover defaults rather than misinterpreting data.
    static func decoded(_ data: Data) -> Self {
        guard let decoded = try? JSONDecoder().decode(Self.self, from: data),
              decoded.schemaVersion <= currentVersion, decoded.schemaVersion >= 0 else { return .initial }
        return decoded.migrated().normalized()
    }
    /// v1 drew a permanent usage row above Agents. It is now the Combined
    /// Usage widget, inserted once; a later removal (hidden placement) sticks.
    func migrated() -> Self {
        guard schemaVersion < 2, !placements.contains(where: { $0.surface == .agents && $0.kind.isUsage }) else { return self }
        var result = self
        let first = placements.filter { $0.surface == .agents }.map(\.order).min() ?? 0
        result.placements.append(.init(id: result.uniqueID("agents.agentUsage"), kind: .agentUsage, surface: .agents, order: first - 1))
        return result
    }
}

private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

@MainActor
final class WorkspaceCustomizationStore: ObservableObject {
    static let persistenceKey = "workspaceCustomizationConfiguration"
    @Published private(set) var configuration: WorkspaceConfiguration
    private(set) var persistenceWriteCount = 0
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.persistenceKey) {
            configuration = WorkspaceConfiguration.decoded(data)
        } else if defaults.bool(forKey: "islandWidgetLayoutEnabled") {
            var legacy = WorkspaceConfiguration.initial
            let kinds = IslandWidgetLayout(stored: defaults.string(forKey: "islandWidgetLayout") ?? IslandWidgetLayout.initial.stored).widgets
            legacy.placements.removeAll { $0.surface == .media }
            legacy.placements += kinds.enumerated().map { .init(kind: $0.element, surface: .media, order: $0.offset) }
            legacy.markCustomized(.media)
            configuration = legacy.normalized()
        } else { configuration = .initial }
    }
    /// Called at Done/explicit reset only. Hover and drag previews never write preferences.
    func commit(_ configuration: WorkspaceConfiguration) {
        let next = configuration.normalized()
        guard next != self.configuration else { return }
        guard let data = try? JSONEncoder().encode(next) else { return }
        self.configuration = next
        defaults.set(data, forKey: Self.persistenceKey)
        persistenceWriteCount += 1
    }
    func reset() {
        let next = WorkspaceConfiguration.initial
        guard configuration != next || defaults.object(forKey: Self.persistenceKey) != nil else { return }
        configuration = next
        defaults.removeObject(forKey: Self.persistenceKey)
        // Legacy configuration must not reappear after resetting and relaunching.
        defaults.set(false, forKey: "islandWidgetLayoutEnabled")
        persistenceWriteCount += 1
    }
}

// MARK: - Pure drop resolution

enum WorkspaceDropTarget: Equatable {
    case insert(surface: WorkspaceSurface, before: WidgetID?)
    /// Above/below an existing widget, sharing its column.
    case stack(surface: WorkspaceSurface, onto: WidgetID, below: Bool)
    case combine(chat: WidgetID)
    case invalid
}

/// Spatial intent while dragging: which widget is hovered and on which edge
/// the dragged widget will land. Drives the preview and the target glow.
struct WorkspaceDropIntent: Equatable {
    enum Edge: Equatable { case leading, trailing, top, bottom, center }
    var target: WorkspaceDropTarget
    var hovered: WidgetID?
    var edge: Edge?
}

struct WorkspaceDropSlot: Equatable {
    var id: WidgetID
    var frame: CGRect
    var kind: IslandWidget
}

/// Midpoint insertion and an inset combine target keep target resolution independent of body order.
/// A previous insertion target remains valid within a small boundary band to prevent oscillation.
enum WorkspaceDropResolver {
    static func resolve(point: CGPoint, bounds: CGRect, surface: WorkspaceSurface,
                        slots: [WorkspaceDropSlot], draggedKind: IslandWidget,
                        previous: WorkspaceDropTarget? = nil, hysteresis: CGFloat = 8) -> WorkspaceDropTarget {
        guard bounds.contains(point), draggedKind.isEligible(on: surface) else { return .invalid }
        let ordered = slots.sorted {
            if abs($0.frame.minY - $1.frame.minY) > 1 { return $0.frame.minY < $1.frame.minY }
            return $0.frame.minX == $1.frame.minX ? $0.id.rawValue < $1.id.rawValue : $0.frame.minX < $1.frame.minX
        }
        if surface == .agents, draggedKind == .terminal,
           let chat = ordered.first(where: { $0.kind == .chat }) {
            // Combine is the card's center; the outer bands stay directional
            // (left/right insertion) so moving toward an edge never feels dead.
            var combineFrame = chat.frame.insetBy(dx: chat.frame.width * 0.3, dy: chat.frame.height * 0.22)
            if previous == .combine(chat: chat.id) { combineFrame = combineFrame.insetBy(dx: -hysteresis, dy: -hysteresis) }
            if combineFrame.contains(point) { return .combine(chat: chat.id) }
        }
        var rows: [[WorkspaceDropSlot]] = []
        for slot in ordered {
            if let last = rows.indices.last, let first = rows[last].first,
               abs(first.frame.minY - slot.frame.minY) <= 1 { rows[last].append(slot) }
            else { rows.append([slot]) }
        }
        guard !rows.isEmpty else { return .insert(surface: surface, before: nil) }
        func distance(to row: [WorkspaceDropSlot]) -> CGFloat {
            let low = row.map { $0.frame.minY }.min() ?? 0
            let high = row.map { $0.frame.maxY }.max() ?? 0
            return max(low - point.y, point.y - high, 0)
        }
        var rowIndex = rows.indices.min { distance(to: rows[$0]) < distance(to: rows[$1]) } ?? 0
        if case .insert(let previousSurface, let before) = previous, previousSurface == surface {
            let previousRow = before.flatMap { id in rows.firstIndex { $0.contains { $0.id == id } } } ?? (before == nil ? rows.count - 1 : nil)
            if let previousRow {
                let low = rows[previousRow].map { $0.frame.minY }.min() ?? 0
                let high = rows[previousRow].map { $0.frame.maxY }.max() ?? 0
                if point.y >= low - hysteresis && point.y <= high + hysteresis { rowIndex = previousRow }
            }
        }
        let row = rows[rowIndex]
        let nextRowFirst = rowIndex + 1 < rows.count ? rows[rowIndex + 1].first?.id : nil
        if case .insert(let priorSurface, let before) = previous, priorSurface == surface {
            if before == nextRowFirst, let last = row.last, point.x >= last.frame.midX - hysteresis {
                return .insert(surface: surface, before: nextRowFirst)
            }
            if let before, let index = row.firstIndex(where: { $0.id == before }) {
                let left = index == 0 ? bounds.minX : row[index - 1].frame.midX
                let right = row[index].frame.midX
                if point.x >= left - hysteresis && point.x <= right + hysteresis {
                    return .insert(surface: surface, before: before)
                }
            }
        }
        let before = row.first(where: { point.x < $0.frame.midX })?.id ?? nextRowFirst
        return .insert(surface: surface, before: before)
    }

    /// Directional spatial intent. Inside a hovered widget the dominant axis of
    /// the pointer's offset from its center decides left/right (insert, same
    /// midpoint semantics as `resolve`) versus above/below (share its column).
    /// The previous axis is kept within `axisBias` so the center never flickers.
    static func resolveIntent(point: CGPoint, bounds: CGRect, surface: WorkspaceSurface,
                              slots: [WorkspaceDropSlot], draggedKind: IslandWidget, draggedID: WidgetID?,
                              previous: WorkspaceDropIntent? = nil, hysteresis: CGFloat = 8,
                              axisBias: CGFloat = 0.18) -> WorkspaceDropIntent {
        let base = resolve(point: point, bounds: bounds, surface: surface, slots: slots.filter { $0.id != draggedID },
                           draggedKind: draggedKind, previous: previous?.target, hysteresis: hysteresis)
        switch base {
        case .invalid: return .init(target: .invalid, hovered: nil, edge: nil)
        case .combine(let chat): return .init(target: base, hovered: chat, edge: .center)
        default: break
        }
        guard let hovered = slots.first(where: { $0.id != draggedID && $0.frame.contains(point) }),
              hovered.frame.width > 1, hovered.frame.height > 1 else {
            return .init(target: base, hovered: nil, edge: nil)
        }
        let nx = (point.x - hovered.frame.midX) / (hovered.frame.width / 2)
        let ny = (point.y - hovered.frame.midY) / (hovered.frame.height / 2)
        let wasVertical = previous?.hovered == hovered.id && (previous?.edge == .top || previous?.edge == .bottom)
        let vertical = canShareColumn(draggedKind, hovered: hovered, surface: surface)
            && (wasVertical ? abs(ny) + axisBias >= abs(nx) : abs(ny) > abs(nx) + axisBias)
        if vertical {
            return .init(target: .stack(surface: surface, onto: hovered.id, below: ny > 0),
                         hovered: hovered.id, edge: ny > 0 ? .bottom : .top)
        }
        return .init(target: base, hovered: hovered.id, edge: nx >= 0 ? .trailing : .leading)
    }

    /// Maps a drop location in the live (possibly preview-resized) editor into
    /// the drag-start frame of reference. The shell grows symmetrically around
    /// the notch and editing rows are top-anchored, so only half of the width
    /// change moves the committed cards. Resolving against the drag-start
    /// projection removes the preview -> resize -> retarget feedback loop that
    /// made the stack-below band unstable.
    static func dragReferencePoint(_ location: CGPoint, currentSize: CGSize, startSize: CGSize) -> CGPoint {
        guard startSize.width > 0, startSize.height > 0, currentSize.width.isFinite, startSize.width.isFinite else { return location }
        return CGPoint(x: location.x - (currentSize.width - startSize.width) / 2, y: location.y)
    }

    /// Large primary surfaces (Chat, Terminal, Feed, a Chat/Terminal stack)
    /// never share a column; every compact widget can.
    static func canShareColumn(_ dragged: IslandWidget, hovered: WorkspaceDropSlot, surface: WorkspaceSurface) -> Bool {
        let large: Set<IslandWidget> = [.chat, .terminal, .feed]
        if large.contains(dragged) || large.contains(hovered.kind) { return false }
        return !(surface == .agents && hovered.kind == .workspace)
    }

    static func applying(_ target: WorkspaceDropTarget, to original: WorkspaceConfiguration,
                         draggedID: WidgetID?, paletteKind: IslandWidget?) -> WorkspaceConfiguration? {
        var draft = original
        switch target {
        case .invalid: return nil
        case .insert(let surface, let before):
            if let before, !draft.regions(on: surface).contains(where: { $0.id == before }),
               !draft.widgets(on: surface).contains(where: { $0.id == before }) { return nil }
            if let draggedID {
                let movingIDs = draft.groups.first(where: { $0.id == draggedID })?.members ?? [draggedID]
                let moving = draft.placements.filter { movingIDs.contains($0.id) }
                guard !moving.isEmpty, moving.allSatisfy({ $0.kind.isEligible(on: surface) }),
                      moving.allSatisfy({ item in !draft.placements.contains { !movingIDs.contains($0.id) && $0.surface == surface && $0.kind == item.kind } }) else { return nil }
                if let groupID = draft.placements.first(where: { $0.id == draggedID })?.groupID {
                    draft.separateStack(groupID)
                }
                draft.move(draggedID, before: before, on: surface)
            } else if let paletteKind {
                guard paletteKind.isEligible(on: surface) else { return nil }
                draft.add(paletteKind, on: surface, before: before)
            } else { return nil }
        case .stack(let surface, let onto, let below):
            guard draft.regions(on: surface).contains(where: { $0.id == onto && !$0.isStack }) else { return nil }
            let id: WidgetID
            if let draggedID {
                guard draggedID != onto, draft.groups.first(where: { $0.id == draggedID }) == nil,
                      let moving = draft.placements.first(where: { $0.id == draggedID }), moving.kind.isEligible(on: surface),
                      !draft.placements.contains(where: { $0.id != draggedID && $0.surface == surface && $0.kind == moving.kind }) else { return nil }
                if let groupID = moving.groupID { draft.separateStack(groupID) }
                id = draggedID
            } else if let paletteKind, paletteKind.isEligible(on: surface) {
                draft.add(paletteKind, on: surface)
                guard let added = draft.placement(kind: paletteKind, on: surface) else { return nil }
                id = added.id
            } else { return nil }
            draft.stack(id, onto: onto, below: below, on: surface)
        case .combine(let chat):
            guard draft.placements.contains(where: { $0.id == chat && $0.kind == .chat && $0.isVisible }) else { return nil }
            let terminalKind = draggedID.flatMap { id in draft.placements.first(where: { $0.id == id })?.kind } ?? paletteKind
            guard terminalKind == .terminal else { return nil }
            if draggedID == nil { draft.add(.terminal, on: .agents) }
            draft.combineTerminalWithChat()
        }
        return draft.normalized()
    }
}

// MARK: - Semantic widget grid

struct WorkspaceWidgetFrame: Equatable, Identifiable {
    let id: WidgetID
    let frame: CGRect
}

/// Apple-style size grammar, adapted for the island (not iPhone pixel sizes):
/// Compact = 1x1 square, Standard = 2x1 horizontal rectangle, Large = 2x2.
/// One unit side per surface is the single source of truth; every widget
/// cell, the shell size and the editor's drag frames derive from it.
struct WidgetGridMetrics: Equatable {
    let side: CGFloat
    let gutter: CGFloat

    /// Island page: dense player/timer/utility cells.
    static let mediaBaseSide: CGFloat = 162
    /// Agents page: Chat/Terminal/Feed need a functional Standard cell.
    static let agentsBaseSide: CGFloat = 236
    /// Agents stays a wide workspace: at least this many columns when they fit.
    static let agentsMinimumColumns = 3

    static func make(surface: WorkspaceSurface, metrics: ResolvedIslandMetrics) -> Self {
        let base = surface == .agents ? agentsBaseSide : mediaBaseSide
        return Self(side: base * metrics.expandedCardScale, gutter: metrics.spacing(8))
    }

    static func span(_ size: WidgetPresentationSize) -> (columns: Int, rows: Int) {
        switch size {
        case .compact: (1, 1)
        case .standard: (2, 1)
        case .large: (2, 2)
        }
    }

    func length(_ units: Int) -> CGFloat { CGFloat(units) * side + CGFloat(max(0, units - 1)) * gutter }
    func size(columns: Int, rows: Int) -> CGSize { CGSize(width: length(columns), height: length(rows)) }
    func size(for presentation: WidgetPresentationSize) -> CGSize {
        let span = Self.span(presentation)
        return size(columns: span.columns, rows: span.rows)
    }
    /// Columns that fit `width` (never fewer than the two a Standard needs).
    func columns(fitting width: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 2 }
        return max(2, Int(((width + gutter) / (side + gutter)).rounded(.down)))
    }
    /// A host narrower than two units shrinks the unit instead of overlapping.
    func fitted(to width: CGFloat) -> Self {
        guard width.isFinite, width > gutter, width < length(2) else { return self }
        return Self(side: max(1, (width - gutter) / 2), gutter: gutter)
    }

    /// Usage strips: size changes density, not grid span.
    static func bandSize(_ kind: IslandWidget, _ presentation: WidgetPresentationSize, metrics: ResolvedIslandMetrics) -> CGSize {
        let combined = kind == .agentUsage
        let base: CGSize = switch presentation {
        case .compact: combined ? .init(width: 300, height: 56) : .init(width: 160, height: 56)
        case .standard: combined ? .init(width: 420, height: 72) : .init(width: 210, height: 72)
        case .large: combined ? .init(width: 520, height: 96) : .init(width: 270, height: 96)
        }
        return .init(width: base.width * metrics.expandedCardScale, height: base.height * metrics.expandedCardScale)
    }
}

/// Resolves placements (in user order) onto the semantic grid. Shared by the
/// editor and the shell resolver; never owns screen anchoring or shell state.
///
/// - Each region occupies its size's span. A row-major cursor never moves
///   backwards, so user order stays authoritative while smaller widgets fill
///   the free cells beside a Large one (Large + 2 Compact form a 3x2 block).
/// - `stacksBelowPrevious` places a region directly below its anchor; later
///   regions continue beside the anchor, so a stack never strands empty cells.
/// - Consecutive band widgets (usage) form their own centered strip row;
///   removing them reclaims all of that height.
/// - Outside editing, a grid narrower than the shell (the notch-safe header
///   minimum) scales its unit uniformly - up to `fillScaleCap` - so Compact
///   stays square and Standard stays 2:1; sections are centered. Editing keeps
///   intrinsic, centered, top-anchored geometry (drag frames).
/// - The adaptive Chat hint can shorten the region containing Chat.
struct WorkspaceWidgetLayoutProjection: Equatable {
    let frames: [WorkspaceWidgetFrame]
    let contentSize: CGSize
    let columns: Int
    let rows: Int
    let requiresScrolling: Bool

    /// Upper bound for the uniform fill scale (a lone Compact never balloons).
    static let fillScaleCap: CGFloat = 1.5

    private struct Cell: Hashable { let row: Int; let column: Int }
    private struct Placed {
        let region: WorkspaceWidgetRegion
        let column: Int
        let row: Int
        let columns: Int
        let rows: Int
    }
    private enum Section {
        case grid([Placed])
        case band([WorkspaceWidgetRegion])
    }

    static func presentationSize(of region: WorkspaceWidgetRegion) -> WidgetPresentationSize {
        let rank: (WidgetPresentationSize) -> Int = { switch $0 { case .compact: 0; case .standard: 1; case .large: 2 } }
        return region.widgets.map(\.size).max { rank($0) < rank($1) } ?? .standard
    }
    private static func isBand(_ region: WorkspaceWidgetRegion) -> Bool {
        !region.isStack && region.widgets.allSatisfy(\.kind.isBand)
    }
    private static func surface(of regions: [WorkspaceWidgetRegion]) -> WorkspaceSurface {
        regions.first?.widgets.first?.surface ?? .media
    }

    private static func sections(_ regions: [WorkspaceWidgetRegion], columns: Int) -> [Section] {
        var result: [Section] = []
        var placed: [Placed] = []
        var occupied = Set<Cell>()
        var cursor = 0
        var bands: [WorkspaceWidgetRegion] = []
        func free(_ row: Int, _ column: Int, _ width: Int, _ height: Int) -> Bool {
            guard column >= 0, column + width <= columns else { return false }
            for r in row..<(row + height) { for c in column..<(column + width) where occupied.contains(Cell(row: r, column: c)) { return false } }
            return true
        }
        func place(_ region: WorkspaceWidgetRegion, _ row: Int, _ column: Int, _ width: Int, _ height: Int) {
            for r in row..<(row + height) { for c in column..<(column + width) { occupied.insert(Cell(row: r, column: c)) } }
            placed.append(Placed(region: region, column: column, row: row, columns: width, rows: height))
            cursor = row * columns + column + width
        }
        func flushGrid() {
            if !placed.isEmpty { result.append(.grid(placed)) }
            placed = []; occupied = []; cursor = 0
        }
        for region in regions {
            if isBand(region) {
                flushGrid()
                bands.append(region)
                continue
            }
            if !bands.isEmpty { result.append(.band(bands)); bands = [] }
            let span = WidgetGridMetrics.span(presentationSize(of: region))
            let width = min(span.columns, columns)
            if region.stacksBelowPrevious, let anchor = placed.last,
               free(anchor.row + anchor.rows, anchor.column, width, span.rows) {
                place(region, anchor.row + anchor.rows, anchor.column, width, span.rows)
                // Continue beside the anchor: the column relation must not
                // strand the cells to its right.
                cursor = anchor.row * columns + anchor.column + anchor.columns
                continue
            }
            var index = cursor
            while true {
                let row = index / columns, column = index % columns
                if free(row, column, width, span.rows) { place(region, row, column, width, span.rows); break }
                index += 1
            }
        }
        flushGrid()
        if !bands.isEmpty { result.append(.band(bands)) }
        return result
    }

    private struct Layout {
        var frames: [WorkspaceWidgetFrame] = []
        var size: CGSize = .zero
        var columns = 0
        var rows = 0
    }

    /// Lays sections out from y = 0, each section centered in the widest one.
    private static func layout(_ sections: [Section], grid: WidgetGridMetrics, metrics: ResolvedIslandMetrics,
                               minimumColumns: Int, availableWidth: CGFloat, chatHeightHint: CGFloat?) -> Layout {
        var result = Layout()
        var y: CGFloat = 0
        let gap = grid.gutter
        let pitch = grid.side + gap
        var rowsOfFrames: [(range: Range<Int>, width: CGFloat)] = []
        for section in sections {
            if result.size.height > 0 { y += gap }
            let first = result.frames.count
            var sectionWidth: CGFloat = 0
            switch section {
            case .grid(let placed):
                let used = max(minimumColumns, placed.map { $0.column + $0.columns }.max() ?? 0)
                var bottom: CGFloat = 0
                for item in placed {
                    var height = grid.length(item.rows)
                    // Compact Chat is a fixed square summary: no adaptive height.
                    if let hint = chatHeightHint, hint.isFinite, item.region.widgets.contains(where: { $0.kind == .chat }),
                       presentationSize(of: item.region) != .compact {
                        let floor = AgentChatHeightPolicy.minimumCellHeight * metrics.expandedCardScale
                        height = min(height, max(floor, hint))
                    }
                    let frame = CGRect(x: CGFloat(item.column) * pitch, y: y + CGFloat(item.row) * pitch,
                                       width: grid.length(item.columns), height: height)
                    result.frames.append(.init(id: item.region.id, frame: frame))
                    bottom = max(bottom, frame.maxY - y)
                }
                sectionWidth = grid.length(used)
                result.columns = max(result.columns, used)
                result.rows += placed.map { $0.row + $0.rows }.max() ?? 0
                y += bottom
            case .band(let regions):
                let sizes = regions.map { region in
                    WidgetGridMetrics.bandSize(region.widgets.first?.kind ?? .agentUsage,
                                               presentationSize(of: region), metrics: metrics)
                }
                let total = sizes.map(\.width).reduce(0, +) + CGFloat(max(0, sizes.count - 1)) * gap
                let factor = total > availableWidth && total > 0 ? availableWidth / total : 1
                var x: CGFloat = 0
                let height = sizes.map(\.height).max() ?? 0
                for (region, size) in zip(regions, sizes) {
                    result.frames.append(.init(id: region.id, frame: CGRect(x: x, y: y + (height - size.height) / 2,
                                                                            width: size.width * factor, height: size.height)))
                    x += size.width * factor + gap
                }
                sectionWidth = total * factor
                result.rows += 1
                y += height
            }
            rowsOfFrames.append((first..<result.frames.count, sectionWidth))
            result.size.width = max(result.size.width, sectionWidth)
            result.size.height = y
        }
        for row in rowsOfFrames where row.width < result.size.width {
            let dx = (result.size.width - row.width) / 2
            for index in row.range {
                result.frames[index] = .init(id: result.frames[index].id, frame: result.frames[index].frame.offsetBy(dx: dx, dy: 0))
            }
        }
        return result
    }

    /// Lays out at the natural unit; outside editing, a grid narrower than
    /// `fillWidth` is relaid with a uniformly scaled unit (aspect preserved).
    private static func fitted(_ regions: [WorkspaceWidgetRegion], width: CGFloat, fillWidth: CGFloat?,
                               metrics: ResolvedIslandMetrics, chatHeightHint: CGFloat?) -> Layout {
        let (grid, columns, minimum) = gridFor(regions, width: width, metrics: metrics)
        let laidSections = sections(regions, columns: columns)
        let natural = layout(laidSections, grid: grid, metrics: metrics, minimumColumns: minimum,
                             availableWidth: width, chatHeightHint: chatHeightHint)
        guard let fillWidth, natural.columns > 0, natural.size.width < fillWidth - 0.5 else { return natural }
        // Solve the unit so the widest grid section spans the target exactly.
        let k = CGFloat(natural.columns)
        let side = min(grid.side * fillScaleCap, (min(fillWidth, width) - (k - 1) * grid.gutter) / k)
        guard side > grid.side + 0.01 else { return natural }
        let filled = WidgetGridMetrics(side: side, gutter: grid.gutter)
        return layout(laidSections, grid: filled, metrics: metrics, minimumColumns: minimum,
                      availableWidth: width, chatHeightHint: chatHeightHint)
    }

    private static func gridFor(_ regions: [WorkspaceWidgetRegion], width: CGFloat,
                                metrics: ResolvedIslandMetrics) -> (WidgetGridMetrics, Int, Int) {
        let surface = surface(of: regions)
        let grid = WidgetGridMetrics.make(surface: surface, metrics: metrics).fitted(to: width)
        let columns = grid.columns(fitting: width)
        let minimum = surface == .agents ? min(WidgetGridMetrics.agentsMinimumColumns, columns) : 0
        return (grid, columns, minimum)
    }

    /// `minimumWidth` is the shell's own floor (the notch-safe header): the
    /// grid fills it the same way `make` will, so heights agree.
    static func preferredContentSize(regions: [WorkspaceWidgetRegion], maximumSize: CGSize,
                                     metrics: ResolvedIslandMetrics, editing: Bool = false,
                                     chatHeightHint: CGFloat? = nil, minimumWidth: CGFloat = 0) -> CGSize {
        let width = finite(maximumSize.width)
        let height = finite(maximumSize.height)
        let inset: CGFloat = editing ? 7 : 0
        let palette: CGFloat = editing ? 54 + metrics.spacing(8) : 0
        let laid = fitted(regions, width: max(1, width - inset * 2), fillWidth: editing || minimumWidth <= 0 ? nil : minimumWidth,
                          metrics: metrics, chatHeightHint: editing ? nil : chatHeightHint)
        // An empty enabled-feature projection remains a readable recovery surface.
        return .init(width: min(width, max(260 * metrics.expandedCardScale, laid.size.width) + inset * 2),
                     height: min(height, max(120 * metrics.expandedCardScale, laid.size.height) + inset + palette))
    }

    static func make(regions: [WorkspaceWidgetRegion], availableSize: CGSize,
                     metrics: ResolvedIslandMetrics, editing: Bool = false, chatHeightHint: CGFloat? = nil) -> Self {
        let width = finite(availableSize.width)
        let height = finite(availableSize.height)
        let inset: CGFloat = editing ? 7 : 0
        let palette: CGFloat = editing ? 54 + metrics.spacing(8) : 0
        let cardWidth = max(1, width - inset * 2)
        let cardHeight = max(1, height - inset - palette)
        // Outside editing the grid fills the shell width (no side gutters)
        // by scaling its unit; Compact stays square.
        let laid = fitted(regions, width: cardWidth, fillWidth: editing ? nil : cardWidth,
                          metrics: metrics, chatHeightHint: editing ? nil : chatHeightHint)
        let scroll = laid.size.height > cardHeight + 0.5
        // Editing is top-anchored: a prospective layout that grows the shell
        // adds space below and never shifts the cards the pointer is over.
        let originY = inset + (scroll || editing ? 0 : max(0, (cardHeight - laid.size.height) / 2))
        let originX = inset + max(0, (cardWidth - laid.size.width) / 2)
        let frames = laid.frames.map { WorkspaceWidgetFrame(id: $0.id, frame: $0.frame.offsetBy(dx: originX, dy: originY)) }
        return Self(frames: frames, contentSize: .init(width: width, height: max(height - palette, originY + laid.size.height)),
                    columns: laid.columns, rows: laid.rows, requiresScrolling: scroll)
    }

    private static func finite(_ value: CGFloat) -> CGFloat { value.isFinite ? max(1, value) : 1 }
}

/// Content-adaptive Agent Chat height. The chat cell's chrome (headers,
/// status footer, composer, paddings) is `cell - transcriptViewport`; the
/// preferred cell is that chrome plus the transcript's measured content
/// height. It is stable while the shell animates (cell and viewport shrink
/// together) and quantized so streaming deltas only publish on real growth.
enum AgentChatHeightPolicy {
    /// Readable floor for a near-empty conversation (header + a few lines +
    /// status + composer), before display scaling.
    static let minimumCellHeight: CGFloat = 200
    static let breathingRoom: CGFloat = 8
    static let quantum: CGFloat = 4

    static func preferredCellHeight(cellHeight: CGFloat, viewportHeight: CGFloat, contentHeight: CGFloat) -> CGFloat? {
        guard cellHeight.isFinite, viewportHeight.isFinite, contentHeight.isFinite,
              cellHeight > 0, viewportHeight > 0, contentHeight >= 0 else { return nil }
        let chrome = max(0, cellHeight - viewportHeight)
        let desired = chrome + contentHeight + breathingRoom
        return (desired / quantum).rounded(.up) * quantum
    }

    /// Publication threshold: sub-quantum jitter never republishes geometry.
    static func shouldPublish(previous: CGFloat?, next: CGFloat?) -> Bool {
        switch (previous, next) {
        case (nil, nil): return false
        case let (old?, new?): return abs(old - new) >= quantum
        default: return true
        }
    }
}
