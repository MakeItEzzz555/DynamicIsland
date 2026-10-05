import Foundation
import Combine
import CoreGraphics

enum IslandWidget: String, CaseIterable, Codable, Identifiable {
    case media, files, clipboard, timer, calendar, shortcuts, activities, chat, terminal, feed, workspace
    func isEligible(on surface: WorkspaceSurface) -> Bool {
        switch surface {
        case .media: return ![.chat, .terminal, .feed].contains(self)
        case .agents: return [.chat, .terminal, .feed, .timer].contains(self)
        }
    }

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
        }
    }
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
    var scale: CGFloat { switch self { case .compact: 0.85; case .standard: 1; case .large: 1.15 } }
}

struct WidgetPlacement: Codable, Equatable, Identifiable {
    var id: WidgetID
    var kind: IslandWidget
    var surface: WorkspaceSurface
    var order: Int
    var isVisible: Bool
    var groupID: WidgetID?
    var size: WidgetPresentationSize
    init(id: WidgetID? = nil, kind: IslandWidget, surface: WorkspaceSurface,
         order: Int, isVisible: Bool = true, groupID: WidgetID? = nil, size: WidgetPresentationSize = .standard) {
        self.id = id ?? WidgetID("\(surface.rawValue).\(kind.rawValue)")
        self.kind = kind; self.surface = surface; self.order = order
        self.isVisible = isVisible; self.groupID = groupID; self.size = size
    }
    private enum CodingKeys: String, CodingKey { case id, kind, surface, order, isVisible, groupID, size }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(IslandWidget.self, forKey: .kind)
        let surface = try values.decode(WorkspaceSurface.self, forKey: .surface)
        self.init(id: try values.decodeIfPresent(WidgetID.self, forKey: .id), kind: kind,
                  surface: surface, order: try values.decodeIfPresent(Int.self, forKey: .order) ?? 0,
                  isVisible: try values.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true,
                  groupID: try values.decodeIfPresent(WidgetID.self, forKey: .groupID),
                  size: (try? values.decode(WidgetPresentationSize.self, forKey: .size)) ?? .standard)
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
    static let currentVersion = 1
    var schemaVersion = currentVersion
    var placements: [WidgetPlacement]
    var groups: [WidgetGroup]
    var navigation: NavigationTabConfiguration
    var customizedSurfaces: [WorkspaceSurface]

    static let initial = Self(
        placements: IslandWidgetLayout.initial.widgets.enumerated().map {
            WidgetPlacement(kind: $0.element, surface: .media, order: $0.offset)
        } + [.init(kind: .chat, surface: .agents, order: 0), .init(kind: .feed, surface: .agents, order: 1)],
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
        placements.removeAll { ids.contains($0.id) }
        let insertion = targetMember.flatMap { targetID in placements.firstIndex { $0.id == targetID && $0.surface == surface } } ?? placements.endIndex
        var moved = moving
        for index in moved.indices { moved[index].surface = surface }
        placements.insert(contentsOf: moved, at: insertion)
        for index in placements.indices { placements[index].order = index }
        if let groupIndex = groups.firstIndex(where: { $0.id == id }) { groups[groupIndex].surface = surface }
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
        return decoded.normalized()
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
    case combine(chat: WidgetID)
    case invalid
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
            var combineFrame = chat.frame.insetBy(dx: min(30, chat.frame.width * 0.2), dy: min(20, chat.frame.height * 0.15))
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

// MARK: - Composition-derived content requirements

struct WorkspaceWidgetFrame: Equatable, Identifiable {
    let id: WidgetID
    let frame: CGRect
}

/// Content requirements are shared by the editor and the existing island shell
/// resolver. This projection never owns screen anchoring or shell state.
struct WorkspaceWidgetLayoutProjection: Equatable {
    let frames: [WorkspaceWidgetFrame]
    let contentSize: CGSize
    let columns: Int
    let rows: Int
    let requiresScrolling: Bool

    private struct Requirement {
        let region: WorkspaceWidgetRegion
        let preferred: CGSize
        let minimum: CGSize
    }
    private static func requirements(_ regions: [WorkspaceWidgetRegion], metrics: ResolvedIslandMetrics) -> [Requirement] {
        regions.map { region in
            let sizes = region.widgets.map { widget -> (CGSize, CGSize) in
                let preferred: CGSize
                let minimum: CGSize
                switch widget.kind {
                case .media: preferred = .init(width: 360, height: 220); minimum = .init(width: 260, height: 180)
                case .files, .clipboard: preferred = .init(width: 260, height: 210); minimum = .init(width: 200, height: 170)
                case .timer: preferred = .init(width: 360, height: 160); minimum = .init(width: 280, height: 150)
                case .calendar: preferred = .init(width: 320, height: 240); minimum = .init(width: 260, height: 200)
                case .shortcuts: preferred = .init(width: 240, height: 180); minimum = .init(width: 180, height: 140)
                case .activities: preferred = .init(width: 260, height: 200); minimum = .init(width: 190, height: 150)
                case .workspace: preferred = .init(width: 340, height: 240); minimum = .init(width: 260, height: 180)
                case .chat: preferred = .init(width: 700, height: 360); minimum = .init(width: 480, height: 300)
                case .terminal: preferred = .init(width: 500, height: 320); minimum = .init(width: 360, height: 240)
                case .feed: preferred = .init(width: 330, height: 320); minimum = .init(width: 230, height: 220)
                }
                let scale = metrics.expandedCardScale * widget.size.scale
                // Compact sizing preserves the minimum readable controls.
                let minScale = metrics.expandedCardScale * max(1, widget.size.scale)
                return (.init(width: max(preferred.width * scale, minimum.width * minScale),
                              height: max(preferred.height * scale, minimum.height * minScale)),
                        .init(width: minimum.width * minScale, height: minimum.height * minScale))
            }
            let stackHeader: CGFloat = region.isStack ? 30 * metrics.spacingScale : 0
            return Requirement(region: region,
                preferred: .init(width: sizes.map { $0.0.width }.max() ?? 1, height: (sizes.map { $0.0.height }.max() ?? 1) + stackHeader),
                minimum: .init(width: sizes.map { $0.1.width }.max() ?? 1, height: (sizes.map { $0.1.height }.max() ?? 1) + stackHeader))
        }
    }
    private static func packedRows(_ requirements: [Requirement], width: CGFloat, gap: CGFloat) -> [[Requirement]] {
        var rows: [[Requirement]] = []
        var current: [Requirement] = []
        var used: CGFloat = 0
        for requirement in requirements {
            let next = min(requirement.minimum.width, width)
            if !current.isEmpty, used + gap + next > width {
                rows.append(current); current = []; used = 0
            }
            used += (current.isEmpty ? 0 : gap) + next
            current.append(requirement)
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
    static func preferredContentSize(regions: [WorkspaceWidgetRegion], maximumSize: CGSize,
                                     metrics: ResolvedIslandMetrics, editing: Bool = false) -> CGSize {
        let width = finite(maximumSize.width)
        let height = finite(maximumSize.height)
        let gap = metrics.spacing(8)
        let inset: CGFloat = editing ? 7 : 0
        let palette: CGFloat = editing ? 54 + gap : 0
        let rows = packedRows(requirements(regions, metrics: metrics), width: max(1, width - inset * 2), gap: gap)
        let preferredWidth = rows.map { $0.reduce(0) { $0 + $1.preferred.width } + CGFloat(max(0, $0.count - 1)) * gap }.max() ?? 0
        let preferredHeight = rows.reduce(CGFloat.zero) { $0 + ($1.map(\.preferred.height).max() ?? 0) } + CGFloat(max(0, rows.count - 1)) * gap
        // An empty enabled-feature projection remains a readable recovery surface.
        return .init(width: min(width, max(260 * metrics.expandedCardScale, preferredWidth) + inset * 2),
                     height: min(height, max(120 * metrics.expandedCardScale, preferredHeight) + inset + palette))
    }
    static func make(regions: [WorkspaceWidgetRegion], availableSize: CGSize,
                     metrics: ResolvedIslandMetrics, editing: Bool = false) -> Self {
        let width = finite(availableSize.width)
        let height = finite(availableSize.height)
        let gap = metrics.spacing(8)
        let inset: CGFloat = editing ? 7 : 0
        let palette: CGFloat = editing ? 54 + gap : 0
        let cardWidth = max(1, width - inset * 2)
        let cardHeight = max(1, height - inset - palette)
        let rows = packedRows(requirements(regions, metrics: metrics), width: cardWidth, gap: gap)
        let preferredHeights = rows.map { $0.map(\.preferred.height).max() ?? 0 }
        let minimumHeights = rows.map { $0.map(\.minimum.height).max() ?? 0 }
        let totalGap = CGFloat(max(0, rows.count - 1)) * gap
        let minimumHeight = minimumHeights.reduce(0, +) + totalGap
        let preferredHeight = preferredHeights.reduce(0, +) + totalGap
        let scroll = minimumHeight > cardHeight
        let actualHeight = scroll ? preferredHeight : min(preferredHeight, cardHeight)
        let extraHeight = max(0, actualHeight - minimumHeight)
        let heightSlack = max(0, preferredHeight - minimumHeight)
        var y: CGFloat = inset + (scroll ? 0 : max(0, (cardHeight - actualHeight) / 2))
        var frames: [WorkspaceWidgetFrame] = []
        for (index, row) in rows.enumerated() {
            let rowHeight = scroll ? preferredHeights[index] : minimumHeights[index] + (heightSlack > 0 ? extraHeight * (preferredHeights[index] - minimumHeights[index]) / heightSlack : 0)
            let gaps = CGFloat(max(0, row.count - 1)) * gap
            let minimumWidths = row.map { min($0.minimum.width, cardWidth) }
            let preferredWidths = row.map { min($0.preferred.width, cardWidth) }
            let minimumWidth = minimumWidths.reduce(0, +)
            let preferredWidth = preferredWidths.reduce(0, +)
            let usable = max(0, cardWidth - gaps)
            let rowWidth = min(preferredWidth, usable)
            let extra = max(0, rowWidth - minimumWidth)
            let slack = max(0, preferredWidth - minimumWidth)
            var x = inset + max(0, (cardWidth - rowWidth - gaps) / 2)
            for (column, requirement) in row.enumerated() {
                let itemWidth = minimumWidths[column] + (slack > 0 ? extra * (preferredWidths[column] - minimumWidths[column]) / slack : 0)
                frames.append(.init(id: requirement.region.id, frame: .init(x: x, y: y, width: itemWidth, height: rowHeight)))
                x += itemWidth + gap
            }
            y += rowHeight + gap
        }
        return Self(frames: frames, contentSize: .init(width: width, height: max(height - palette, y - gap)),
                    columns: rows.map(\.count).max() ?? 0, rows: rows.count, requiresScrolling: scroll)
    }
    private static func finite(_ value: CGFloat) -> CGFloat { value.isFinite ? max(1, value) : 1 }
}
