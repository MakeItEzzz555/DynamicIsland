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
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shown, id: \.self) { page in
                        HStack(spacing: 3) {
                            WorkspaceNativeDragHandle(title: page.title, payload: "tab.\(page.rawValue)", began: { begin(page) }, ended: finish)
                                .frame(width: 78, height: 27)
                                .accessibilityLabel("Drag \(page.title) tab")
                            Menu {
                                Button("Move left") { shift(page, by: -1) }
                                Button("Move right") { shift(page, by: 1) }
                                if page != .island { Button("Hide tab") { hide(page) } }
                            } label: { Image(systemName: "ellipsis").frame(width: 18, height: 24) }
                            .menuStyle(.borderlessButton).fixedSize()
                            .accessibilityLabel("Arrange \(page.title) tab")
                            if page != .island {
                                Button { hide(page) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                                    .buttonStyle(.plain).frame(width: 20, height: 24)
                                    .accessibilityLabel("Hide \(page.title) tab")
                            }
                        }
                        .padding(.horizontal, 4)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).allowsHitTesting(false) }
                        .overlay(alignment: .leading) {
                            if targetActive, target == page {
                                RoundedRectangle(cornerRadius: 2).fill(.blue).frame(width: 3).allowsHitTesting(false)
                            }
                        }
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: WorkspaceNavigationFrames.self, value: [page: geometry.frame(in: .named("workspace-navigation-editor"))])
                            }
                        }
                        .accessibilityValue("Position \((visible.firstIndex(of: page) ?? 0) + 1)")
                        .accessibilityAction(named: "Move left") { shift(page, by: -1) }
                        .accessibilityAction(named: "Move right") { shift(page, by: 1) }
                    }
                }
                .onDrop(of: [WorkspaceNativeDragHandle.type], delegate: NavigationEditorDrop(updated: update, dropped: drop, exited: { targetActive = false; target = nil }))
            }
            .coordinateSpace(name: "workspace-navigation-editor")
            .onPreferenceChange(WorkspaceNavigationFrames.self) { value in
                measurements.frames = value
            }
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(eligiblePages.filter { $0 != .messages && draft.navigation.hidden.contains($0) }, id: \.self) { page in
                            HStack(spacing: 3) {
                                Button { add(page) } label: { Label(page.title, systemImage: "plus") }
                                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                                    .accessibilityLabel("Add \(page.title) tab")
                                WorkspaceNativeDragHandle(title: "Drag", payload: "tab.\(page.rawValue)", began: { begin(page) }, ended: finish)
                                    .frame(width: 42, height: 20)
                            }.padding(.horizontal, 5)
                        }
                    }
                }
                Button("Reset tabs") {
                    withAnimation(motion) { draft.navigation = .initial }
                    announcement = "Default tabs restored"
                    WorkspaceEditorAccessibility.announce(announcement)
                }.buttonStyle(.plain).font(.system(size: 10))
                Button("Cancel") { finish(); editing = false; WorkspaceEditorAccessibility.announce("Tab changes cancelled") }.buttonStyle(.plain).font(.system(size: 10))
                    .accessibilityLabel("Cancel tab changes")
                Button("Done") { finish(); store.commit(draft); editing = false; WorkspaceEditorAccessibility.announce("Tab layout saved") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .accessibilityLabel("Save tab layout")
            }
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
