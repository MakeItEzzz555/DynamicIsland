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

/// Measurable layout capabilities. The one place widget kinds describe their
/// size needs; the workspace projection decides placement from these traits,
/// never from widget-name conditionals in views.
struct WidgetLayoutTraits: Equatable {
    /// Comfortable size in a multi-widget composition.
    var preferred: CGSize
    /// Smallest readable size; controls keep their hit targets.
    var minimum: CGSize
    /// Size when the widget is alone on its surface (centered composition).
    var solo: CGSize
    /// May grow taller than `preferred` to share a row's height.
    var fillsHeight: Bool
    /// May share a column with another stackable widget beside a taller one.
    var stackable: Bool
    /// A short full-width strip (usage gauges): consecutive band widgets form
    /// their own centered row and never stretch to a neighbour's height, so
    /// they never force the primary row to wrap.
    var band = false
}

extension IslandWidget {
    var layoutTraits: WidgetLayoutTraits {
        switch self {
        case .media: .init(preferred: .init(width: 360, height: 220), minimum: .init(width: 260, height: 180), solo: .init(width: 330, height: 176), fillsHeight: true, stackable: false)
        case .files, .clipboard: .init(preferred: .init(width: 260, height: 210), minimum: .init(width: 200, height: 170), solo: .init(width: 300, height: 210), fillsHeight: true, stackable: false)
        case .timer: .init(preferred: .init(width: 360, height: 160), minimum: .init(width: 280, height: 150), solo: .init(width: 360, height: 160), fillsHeight: true, stackable: true)
        case .calendar: .init(preferred: .init(width: 320, height: 240), minimum: .init(width: 260, height: 200), solo: .init(width: 320, height: 240), fillsHeight: true, stackable: false)
        case .shortcuts: .init(preferred: .init(width: 240, height: 120), minimum: .init(width: 180, height: 100), solo: .init(width: 260, height: 140), fillsHeight: false, stackable: true)
        case .activities: .init(preferred: .init(width: 260, height: 140), minimum: .init(width: 190, height: 110), solo: .init(width: 280, height: 180), fillsHeight: true, stackable: true)
        case .workspace: .init(preferred: .init(width: 340, height: 240), minimum: .init(width: 260, height: 180), solo: .init(width: 340, height: 240), fillsHeight: true, stackable: false)
        // Minimums match the readable widths the native Agents split already
        // uses on small displays (~420 / ~300 pt), so a compact screen keeps
        // Chat and Terminal side by side instead of wrapping into tall rows.
        case .chat: .init(preferred: .init(width: 700, height: 360), minimum: .init(width: 420, height: 300), solo: .init(width: 700, height: 360), fillsHeight: true, stackable: false)
        case .terminal: .init(preferred: .init(width: 500, height: 320), minimum: .init(width: 300, height: 240), solo: .init(width: 500, height: 320), fillsHeight: true, stackable: false)
        case .feed: .init(preferred: .init(width: 330, height: 320), minimum: .init(width: 230, height: 220), solo: .init(width: 330, height: 320), fillsHeight: true, stackable: false)
        case .agentUsage: .init(preferred: .init(width: 420, height: 72), minimum: .init(width: 340, height: 64), solo: .init(width: 420, height: 72), fillsHeight: false, stackable: false, band: true)
        case .codexUsage, .claudeUsage: .init(preferred: .init(width: 210, height: 72), minimum: .init(width: 180, height: 64), solo: .init(width: 220, height: 72), fillsHeight: false, stackable: false, band: true)
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
             .init(kind: .feed, surface: .agents, order: 2)],
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

// MARK: - Composition-derived content requirements

struct WorkspaceWidgetFrame: Equatable, Identifiable {
    let id: WidgetID
    let frame: CGRect
}

/// Content requirements are shared by the editor and the existing island shell
/// resolver. This projection never owns screen anchoring or shell state.
///
/// Rules (from `WidgetLayoutTraits`, never widget names):
/// - a widget alone on its surface uses its centered `solo` composition size;
/// - explicit columns (`stacksBelowPrevious`) and two small stackable widgets
///   beside a taller anchor share one column instead of stretching;
/// - every unit in a row receives the row height; widgets that can fill
///   height do so, others keep their preferred height centered in the row;
/// - column members split the row height in proportion to their preference;
/// - consecutive `band` widgets (usage) form their own centered strip row, so
///   removing every band widget reserves no strip height at all.
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
        let fillsHeight: Bool
        let stackable: Bool
        let band: Bool
    }
    /// One horizontal slot: a single region or a vertical column of regions.
    private struct Unit {
        var members: [Requirement]
        var band: Bool { members.allSatisfy(\.band) }
        func preferred(gap: CGFloat) -> CGSize {
            .init(width: members.map(\.preferred.width).max() ?? 1,
                  height: members.map(\.preferred.height).reduce(0, +) + CGFloat(max(0, members.count - 1)) * gap)
        }
        func minimum(gap: CGFloat) -> CGSize {
            .init(width: members.map(\.minimum.width).max() ?? 1,
                  height: members.map(\.minimum.height).reduce(0, +) + CGFloat(max(0, members.count - 1)) * gap)
        }
    }

    private static func requirements(_ regions: [WorkspaceWidgetRegion], metrics: ResolvedIslandMetrics,
                                     chatHeightHint: CGFloat? = nil) -> [Requirement] {
        let solo = regions.count == 1
        return regions.map { region in
            let requirement = baseRequirement(region, solo: solo, metrics: metrics)
            // Content-adaptive Chat: the measured cell height (chrome + actual
            // transcript) replaces the static preferred height, bounded by a
            // readable floor and the trait height (the previous fixed size).
            guard let hint = chatHeightHint, hint.isFinite, region.widgets.contains(where: { $0.kind == .chat }) else { return requirement }
            let floor = AgentChatHeightPolicy.minimumCellHeight * metrics.expandedCardScale
            let height = min(requirement.preferred.height, max(floor, hint))
            return Requirement(region: region,
                               preferred: .init(width: requirement.preferred.width, height: height),
                               minimum: .init(width: requirement.minimum.width, height: min(requirement.minimum.height, height)),
                               fillsHeight: requirement.fillsHeight, stackable: requirement.stackable, band: requirement.band)
        }
    }

    private static func baseRequirement(_ region: WorkspaceWidgetRegion, solo: Bool, metrics: ResolvedIslandMetrics) -> Requirement {
        let sizes = region.widgets.map { widget -> (CGSize, CGSize) in
            let traits = widget.kind.layoutTraits
            let preferred = solo && !region.isStack ? traits.solo : traits.preferred
            let minimum = CGSize(width: min(traits.minimum.width, preferred.width), height: min(traits.minimum.height, preferred.height))
            let scale = metrics.expandedCardScale * widget.size.scale
            // Compact sizing preserves the minimum readable controls.
            let minScale = metrics.expandedCardScale * max(1, widget.size.scale)
            return (.init(width: max(preferred.width * scale, minimum.width * minScale),
                          height: max(preferred.height * scale, minimum.height * minScale)),
                    .init(width: minimum.width * minScale, height: minimum.height * minScale))
        }
        let stackHeader: CGFloat = region.isStack ? 30 * metrics.spacingScale : 0
        let traits = region.widgets.map(\.kind.layoutTraits)
        return Requirement(region: region,
            preferred: .init(width: sizes.map { $0.0.width }.max() ?? 1, height: (sizes.map { $0.0.height }.max() ?? 1) + stackHeader),
            minimum: .init(width: sizes.map { $0.1.width }.max() ?? 1, height: (sizes.map { $0.1.height }.max() ?? 1) + stackHeader),
            fillsHeight: region.isStack || traits.allSatisfy(\.fillsHeight),
            stackable: !region.isStack && traits.allSatisfy(\.stackable),
            band: !region.isStack && traits.allSatisfy(\.band))
    }

    private static func units(_ requirements: [Requirement], gap: CGFloat) -> [Unit] {
        var units: [Unit] = []
        for requirement in requirements {
            if requirement.region.stacksBelowPrevious, !units.isEmpty { units[units.count - 1].members.append(requirement) }
            else { units.append(Unit(members: [requirement])) }
        }
        // Two adjacent small stackable widgets form a column when a taller
        // anchor exists and the column fits within its height.
        guard let anchor = units.filter({ $0.members.count == 1 && !$0.members[0].stackable })
            .map({ $0.preferred(gap: gap).height }).max() else { return units }
        var index = 0
        while index + 1 < units.count {
            let a = units[index], b = units[index + 1]
            if a.members.count == 1, b.members.count == 1, a.members[0].stackable, b.members[0].stackable,
               !b.members[0].region.stacksBelowPrevious,
               a.members[0].preferred.height + gap + b.members[0].preferred.height <= anchor + 1 {
                units[index].members.append(b.members[0])
                units.remove(at: index + 1)
            }
            index += 1
        }
        return units
    }

    private static func packedRows(_ units: [Unit], width: CGFloat, gap: CGFloat) -> [[Unit]] {
        var rows: [[Unit]] = []
        var current: [Unit] = []
        var used: CGFloat = 0
        for unit in units {
            let next = min(unit.minimum(gap: gap).width, width)
            // Band strips (usage) and primary widgets never share a row.
            if !current.isEmpty, used + gap + next > width || current[0].band != unit.band {
                rows.append(current); current = []; used = 0
            }
            used += (current.isEmpty ? 0 : gap) + next
            current.append(unit)
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    static func preferredContentSize(regions: [WorkspaceWidgetRegion], maximumSize: CGSize,
                                     metrics: ResolvedIslandMetrics, editing: Bool = false,
                                     chatHeightHint: CGFloat? = nil) -> CGSize {
        let width = finite(maximumSize.width)
        let height = finite(maximumSize.height)
        let gap = metrics.spacing(8)
        let inset: CGFloat = editing ? 7 : 0
        let palette: CGFloat = editing ? 54 + gap : 0
        let rows = packedRows(units(requirements(regions, metrics: metrics, chatHeightHint: editing ? nil : chatHeightHint), gap: gap),
                              width: max(1, width - inset * 2), gap: gap)
        let preferredWidth = rows.map { $0.reduce(0) { $0 + $1.preferred(gap: gap).width } + CGFloat(max(0, $0.count - 1)) * gap }.max() ?? 0
        let preferredHeight = rows.reduce(CGFloat.zero) { $0 + ($1.map { $0.preferred(gap: gap).height }.max() ?? 0) } + CGFloat(max(0, rows.count - 1)) * gap
        // An empty enabled-feature projection remains a readable recovery surface.
        return .init(width: min(width, max(260 * metrics.expandedCardScale, preferredWidth) + inset * 2),
                     height: min(height, max(120 * metrics.expandedCardScale, preferredHeight) + inset + palette))
    }

    static func make(regions: [WorkspaceWidgetRegion], availableSize: CGSize,
                     metrics: ResolvedIslandMetrics, editing: Bool = false, chatHeightHint: CGFloat? = nil) -> Self {
        let width = finite(availableSize.width)
        let height = finite(availableSize.height)
        let gap = metrics.spacing(8)
        let inset: CGFloat = editing ? 7 : 0
        let palette: CGFloat = editing ? 54 + gap : 0
        let cardWidth = max(1, width - inset * 2)
        let cardHeight = max(1, height - inset - palette)
        let rows = packedRows(units(requirements(regions, metrics: metrics, chatHeightHint: editing ? nil : chatHeightHint), gap: gap),
                              width: cardWidth, gap: gap)
        let preferredHeights = rows.map { $0.map { $0.preferred(gap: gap).height }.max() ?? 0 }
        let minimumHeights = rows.map { $0.map { $0.minimum(gap: gap).height }.max() ?? 0 }
        let totalGap = CGFloat(max(0, rows.count - 1)) * gap
        let minimumHeight = minimumHeights.reduce(0, +) + totalGap
        let preferredHeight = preferredHeights.reduce(0, +) + totalGap
        let scroll = minimumHeight > cardHeight
        let actualHeight = scroll ? preferredHeight : min(preferredHeight, cardHeight)
        let extraHeight = max(0, actualHeight - minimumHeight)
        let heightSlack = max(0, preferredHeight - minimumHeight)
        // Editing is top-anchored: a prospective layout that grows the shell
        // adds space below and never shifts the cards the pointer is over.
        var y: CGFloat = inset + (scroll || editing ? 0 : max(0, (cardHeight - actualHeight) / 2))
        var frames: [WorkspaceWidgetFrame] = []
        for (index, row) in rows.enumerated() {
            let rowHeight = scroll ? preferredHeights[index] : minimumHeights[index] + (heightSlack > 0 ? extraHeight * (preferredHeights[index] - minimumHeights[index]) / heightSlack : 0)
            let gaps = CGFloat(max(0, row.count - 1)) * gap
            let minimumWidths = row.map { min($0.minimum(gap: gap).width, cardWidth) }
            let preferredWidths = row.map { min($0.preferred(gap: gap).width, cardWidth) }
            let minimumWidth = minimumWidths.reduce(0, +)
            let preferredWidth = preferredWidths.reduce(0, +)
            let usable = max(0, cardWidth - gaps)
            // Outside editing, primary rows always span the shell: when the
            // shell is wider than the content (e.g. the notch-safe header sets
            // its minimum width), widgets absorb the surplus in proportion to
            // their preferred width instead of leaving empty side gutters.
            // Band strips (usage) stay centered; editing keeps drag geometry.
            let fillsWidth = !editing && !row.allSatisfy(\.band) && usable > preferredWidth
            let rowWidth = fillsWidth ? usable : min(preferredWidth, usable)
            let extra = max(0, rowWidth - minimumWidth)
            let slack = max(0, preferredWidth - minimumWidth)
            var x = inset + max(0, (cardWidth - rowWidth - gaps) / 2)
            for (column, unit) in row.enumerated() {
                let unitWidth = fillsWidth
                    ? preferredWidths[column] + (rowWidth - preferredWidth) * preferredWidths[column] / max(1, preferredWidth)
                    : minimumWidths[column] + (slack > 0 ? extra * (preferredWidths[column] - minimumWidths[column]) / slack : 0)
                frames += memberFrames(unit, x: x, y: y, width: unitWidth, height: rowHeight, gap: gap)
                x += unitWidth + gap
            }
            y += rowHeight + gap
        }
        return Self(frames: frames, contentSize: .init(width: width, height: max(height - palette, y - gap)),
                    columns: rows.map(\.count).max() ?? 0, rows: rows.count, requiresScrolling: scroll)
    }

    private static func memberFrames(_ unit: Unit, x: CGFloat, y: CGFloat, width: CGFloat,
                                     height: CGFloat, gap: CGFloat) -> [WorkspaceWidgetFrame] {
        if unit.members.count == 1 {
            let member = unit.members[0]
            // Fill the shared row height when the widget can compose taller;
            // otherwise keep its preferred height, centered in the row.
            let itemHeight = member.fillsHeight ? height : min(height, member.preferred.height)
            return [.init(id: member.region.id, frame: .init(x: x, y: y + (height - itemHeight) / 2, width: width, height: itemHeight))]
        }
        let available = max(0, height - CGFloat(unit.members.count - 1) * gap)
        let total = max(1, unit.members.map(\.preferred.height).reduce(0, +))
        var cursor = y
        return unit.members.map { member in
            let itemHeight = max(member.minimum.height.rounded(.down) > available ? available / CGFloat(unit.members.count) : 0,
                                 available * member.preferred.height / total)
            defer { cursor += itemHeight + gap }
            return .init(id: member.region.id, frame: .init(x: x, y: cursor, width: width, height: itemHeight))
        }
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
