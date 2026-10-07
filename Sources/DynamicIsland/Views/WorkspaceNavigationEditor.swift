import SwiftUI

/// Navigation is a separate field of the same versioned layout transaction.
/// Hiding Timer here never changes any Timer widget placement.
struct WorkspaceNavigationEditor: View {
    @ObservedObject var store: WorkspaceCustomizationStore
    let eligiblePages: [ExpandedIslandPage]
    @Binding var editing: Bool
    var extraMotion = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = WorkspaceConfiguration.initial
    @State private var dragged: ExpandedIslandPage?
    @State private var target: ExpandedIslandPage?
    @State private var targetActive = false
    @State private var measurements = WorkspaceNavigationMeasurements()
    @State private var frozenFrames: [ExpandedIslandPage: CGRect] = [:]
    @State private var announcement = ""

    private var motion: Animation? { WorkspaceEditorMotion.reorder(reduceMotion: reduceMotion || !extraMotion) }
    private var visible: [ExpandedIslandPage] {
        draft.navigation.order.filter { eligiblePages.contains($0) && !draft.navigation.hidden.contains($0) }
    }
    private var shown: [ExpandedIslandPage] {
        guard let dragged, targetActive else { return visible }
        var navigation = draft.navigation
        navigation.setVisible(dragged, visible: true)
        navigation.move(dragged, before: target)
        return navigation.order.filter { eligiblePages.contains($0) && !navigation.hidden.contains($0) }
    }

    var body: some View {
        let _ = AgentPerformanceProbe.count("workspace.navigation.editor.body")
        VStack(alignment: .leading, spacing: 10) {
            tabStrip
            palette
        }
        .onAppear { draft = store.configuration }
        .onChange(of: editing) { _, value in
            finish()
            if value { draft = store.configuration }
        }
        .onExitCommand { finish(); editing = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Customize navigation tabs")
        .accessibilityValue(announcement)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shown, id: \.self) { page in tabPill(page) }
            }
            .padding(.top, WorkspaceEditorChrome.badgeInset)
            .padding(.trailing, WorkspaceEditorChrome.badgeInset)
            .padding(.leading, 2)
            .onDrop(of: [WorkspaceNativeDragHandle.type], delegate: NavigationEditorDrop(updated: update, dropped: drop, exited: { withAnimation(motion) { targetActive = false; target = nil } }))
        }
        .coordinateSpace(name: "workspace-navigation-editor")
        .onPreferenceChange(WorkspaceNavigationFrames.self) { value in
            measurements.frames = value
        }
    }

    private func tabPill(_ page: ExpandedIslandPage) -> some View {
        let isDragged = dragged == page && targetActive
        let pill = Capsule(style: .continuous)
        return HStack(spacing: 6) {
            Image(systemName: page.symbolName).font(.system(size: 11, weight: .semibold))
            Text(page.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(isDragged ? 0.35 : 0.9))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(pill.fill(isDragged ? WorkspaceEditorChrome.accent.opacity(0.10) : .white.opacity(0.08)))
        .overlay {
            pill.strokeBorder(isDragged ? WorkspaceEditorChrome.accent : .white.opacity(0.30),
                              style: StrokeStyle(lineWidth: isDragged ? 1.5 : 1, dash: [4, 3]))
                .allowsHitTesting(false)
        }
        .overlay {
            WorkspaceNativeDragHandle(title: page.title, symbol: page.symbolName, payload: "tab.\(page.rawValue)",
                                      began: { begin(page) }, ended: finish)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .leading) {
            if targetActive, target == page, dragged != page {
                Capsule().fill(WorkspaceEditorChrome.accent).frame(width: 3, height: 22)
                    .offset(x: -6).allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if page != .island && !isDragged {
                Button { hide(page) } label: {
                    ZStack {
                        Circle().fill(Color(red: 1, green: 0.27, blue: 0.23))
                        Capsule().fill(.white).frame(width: 7, height: 2)
                    }
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.black.opacity(0.55), lineWidth: 1.5))
                    .contentShape(Circle().inset(by: -4))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .accessibilityLabel("Hide \(page.title) tab")
                .help("Hide \(page.title) tab")
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: WorkspaceNavigationFrames.self, value: [page: geometry.frame(in: .named("workspace-navigation-editor"))])
            }
        }
        .contextMenu {
            Button("Move Left") { shift(page, by: -1) }
            Button("Move Right") { shift(page, by: 1) }
            if page != .island { Divider(); Button("Hide Tab", role: .destructive) { hide(page) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(page.title) tab"))
        .accessibilityValue(Text("Position \((visible.firstIndex(of: page) ?? 0) + 1)"))
        .accessibilityAction(named: Text("Move left")) { shift(page, by: -1) }
        .accessibilityAction(named: Text("Move right")) { shift(page, by: 1) }
    }

    private var hiddenPages: [ExpandedIslandPage] {
        eligiblePages.filter { $0 != .messages && draft.navigation.hidden.contains($0) }
    }

    private var palette: some View {
        HStack(alignment: .center, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(hiddenPages, id: \.self) { page in hiddenTile(page) }
                    if hiddenPages.isEmpty {
                        Text("All tabs are shown").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            .padding(.leading, 4)
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    withAnimation(motion) { draft.navigation = .initial }
                    announcement = "Default tabs restored"
                    WorkspaceEditorAccessibility.announce(announcement)
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6)).frame(width: 26, height: 26).contentShape(Circle())
                }
                .buttonStyle(.plain).help("Reset tabs").accessibilityLabel("Reset tabs")
                Button { finish(); editing = false; WorkspaceEditorAccessibility.announce("Tab changes cancelled") } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).help("Cancel").accessibilityLabel("Cancel tab changes")
                Button { finish(); store.commit(draft); editing = false; WorkspaceEditorAccessibility.announce("Tab layout saved") } label: {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(WorkspaceEditorChrome.accent, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).help("Done").accessibilityLabel("Save tab layout")
            }
        }
        .frame(height: WorkspaceEditorChrome.paletteHeight)
    }

    private func hiddenTile(_ page: ExpandedIslandPage) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay { Image(systemName: page.symbolName).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9)) }
                    .frame(width: 32, height: 32)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, WorkspaceEditorChrome.accent)
                    .background(Circle().fill(.black).padding(1))
                    .offset(x: 4, y: 4)
            }
            Text(page.title).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                .lineLimit(1).frame(width: 50)
        }
        .frame(width: 52)
        .overlay {
            WorkspaceNativeDragHandle(title: page.title, symbol: page.symbolName, payload: "tab.\(page.rawValue)",
                                      clicked: { add(page) }, began: { begin(page) }, ended: finish)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add \(page.title) tab")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { add(page) }
        .help("Click or drag to add the \(page.title) tab")
    }

    private func begin(_ page: ExpandedIslandPage) { dragged = page; target = page; targetActive = false; frozenFrames = measurements.frames }
    private func finish() { dragged = nil; target = nil; targetActive = false; frozenFrames = [:] }
    private func shift(_ page: ExpandedIslandPage, by delta: Int) {
        withAnimation(motion) { draft.navigation.shift(page, by: delta) }
        announcement = "Moved \(page.title) tab"
        WorkspaceEditorAccessibility.announce(announcement)
    }
    private func hide(_ page: ExpandedIslandPage) {
        withAnimation(motion) { draft.navigation.setVisible(page, visible: false) }
        announcement = "Hidden \(page.title) tab"
        WorkspaceEditorAccessibility.announce(announcement)
    }
    private func add(_ page: ExpandedIslandPage) {
        withAnimation(motion) { draft.navigation.setVisible(page, visible: true) }
        announcement = "Added \(page.title) tab"
        WorkspaceEditorAccessibility.announce(announcement)
    }
    private func update(_ point: CGPoint) -> Bool {
        guard dragged != nil else { return false }
        let measured = frozenFrames.isEmpty ? measurements.frames : frozenFrames
        let slots = visible.compactMap { page -> WorkspaceDropSlot? in
            guard let frame = measured[page] else { return nil }
            return .init(id: WidgetID("tab.\(page.rawValue)"), frame: frame, kind: .media)
        }
        let bounds = slots.reduce(CGRect.null) { $0.union($1.frame) }
        let previous: WorkspaceDropTarget? = targetActive ? .insert(surface: .media, before: target.map { WidgetID("tab.\($0.rawValue)") }) : nil
        let resolved = WorkspaceDropResolver.resolve(point: point, bounds: bounds, surface: .media,
                                                      slots: slots, draggedKind: .media, previous: previous)
        guard case .insert(_, let before) = resolved else { return false }
        let next = before.flatMap { id in visible.first { WidgetID("tab.\($0.rawValue)") == id } }
        if next != target || !targetActive {
            withAnimation(motion) { target = next; targetActive = true }
        }
        return true
    }
    private func drop(_ point: CGPoint) -> Bool {
        guard update(point), let dragged else { finish(); return false }
        withAnimation(motion) {
            draft.navigation.setVisible(dragged, visible: true)
            draft.navigation.move(dragged, before: target)
        }
        announcement = "\(dragged.title) tab placement updated"
        WorkspaceEditorAccessibility.announce(announcement)
        finish()
        return true
    }
}

private final class WorkspaceNavigationMeasurements { var frames: [ExpandedIslandPage: CGRect] = [:] }

private struct WorkspaceNavigationFrames: PreferenceKey {
    static var defaultValue: [ExpandedIslandPage: CGRect] { [:] }
    static func reduce(value: inout [ExpandedIslandPage: CGRect], nextValue: () -> [ExpandedIslandPage: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
private struct NavigationEditorDrop: DropDelegate {
    let updated: (CGPoint) -> Bool
    let dropped: (CGPoint) -> Bool
    let exited: () -> Void
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [WorkspaceNativeDragHandle.type.identifier]) }
    func dropEntered(info: DropInfo) { _ = updated(info.location) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: updated(info.location) ? .move : .cancel) }
    func dropExited(info: DropInfo) { exited() }
    func performDrop(info: DropInfo) -> Bool { dropped(info.location) }
}
