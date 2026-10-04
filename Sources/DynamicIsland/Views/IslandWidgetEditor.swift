import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Layout is a local edit transaction. Native drags move a lightweight label;
/// their cancelled/outside drop never changes the transaction or feature state.
struct IslandWidgetEditor: View {
    @ObservedObject var store: WorkspaceCustomizationStore
    let surface: WorkspaceSurface
    @Binding var editing: Bool
    let eligibleWidgets: [IslandWidget]
    var extraMotion = true
    var content: (WorkspaceWidgetRegion, CGFloat) -> AnyView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = WorkspaceConfiguration.initial
    @State private var drag: WorkspaceEditorDrag?
    @State private var target: WorkspaceDropTarget?
    @State private var measurements = WorkspaceEditorMeasurements()
    @State private var dragFrames: [WidgetID: CGRect] = [:]
    @State private var announcement = ""

    private var motion: Animation? { WorkspaceEditorMotion.reorder(reduceMotion: reduceMotion || !extraMotion) }
    private var configuration: WorkspaceConfiguration { editing ? draft : store.configuration }
    private var visibleConfiguration: WorkspaceConfiguration {
        guard let drag, let target, case .insert = target else { return configuration }
        return preview(configuration, drag: drag, target: target)
    }

    var body: some View {
        let _ = AgentPerformanceProbe.count("workspace.editor.body")
        GeometryReader { geometry in
            workspace(size: geometry.size)
        }
        .coordinateSpace(name: WorkspaceEditorActionFrames.coordinateSpace)
        .animation(WorkspaceEditorMotion.resize(reduceMotion: reduceMotion || !extraMotion), value: editing)
        .onAppear { draft = store.configuration }
        .onChange(of: editing) { _, active in
            drag = nil; target = nil; dragFrames = [:]
            if active { draft = store.configuration }
        }
        .onExitCommand(perform: editing ? { cancel() } : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(editing ? "Customize \(surface.rawValue) widgets" : "\(surface.rawValue) widgets")
        .accessibilityValue(announcement)
    }

    private func workspace(size: CGSize) -> some View {
        let visibleRegions = regions(in: visibleConfiguration)
        let height = max(0, size.height - (editing ? 70 : 0))
        let gaps = CGFloat(max(visibleRegions.count - 1, 0)) * 8
        let width = max(180, (size.width - gaps) / CGFloat(max(1, min(visibleRegions.count, 3))))
        return VStack(spacing: 8) {
            widgetStrip(regions: visibleRegions, width: width, height: height, availableWidth: size.width)
            if editing { palette }
        }
    }

    private func widgetStrip(regions: [WorkspaceWidgetRegion], width: CGFloat, height: CGFloat, availableWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(regions) { region in card(region, width: width, height: height) }
                if regions.isEmpty {
                    Text(editing ? "Add an available widget from the palette" : "Customize to add an available widget")
                        .foregroundStyle(.secondary)
                        .frame(width: max(0, availableWidth - 2), height: height)
                }
            }
            .padding(.horizontal, 1)
            .frame(minWidth: max(0, availableWidth - 2), alignment: .leading)
            .frame(height: height, alignment: .top)
            .background {
                if editing {
                    GeometryReader { canvas in
                        Color.clear.preference(key: WorkspaceEditorFrameKey.self,
                            value: [WidgetID("__editor.canvas"): canvas.frame(in: .named("workspace-widget-editor"))])
                    }
                }
            }
            .modifier(WorkspaceEditorDropModifier(enabled: editing, updated: updateTarget, dropped: commitDrop, exited: clearTarget))
        }
        .coordinateSpace(name: "workspace-widget-editor")
        .onPreferenceChange(WorkspaceEditorFrameKey.self) { measured in
            // Plain bounded measurements do not publish native layout changes.
            measurements.frames = measured
        }
    }

    private func card(_ region: WorkspaceWidgetRegion, width: CGFloat, height: CGFloat) -> some View {
        let title = region.widgets.map { $0.kind.title }.joined(separator: " and ")
        let stackedTarget = target == .combine(chat: region.widgets.first(where: { $0.kind == .chat })?.id ?? region.id)
        return VStack(spacing: editing ? 5 : 0) {
            if editing {
                HStack(spacing: 5) {
                    WorkspaceNativeDragHandle(title: title, payload: region.id.rawValue, began: {
                        begin(.existing(region.id))
                    }, ended: finishDrag)
                    .frame(width: max(48, region.isStack ? (width - 72) / 2 : width - 72), height: 25)
                    .accessibilityLabel("Drag \(title) widget")
                    if region.isStack, let terminal = region.widgets.first(where: { $0.kind == .terminal }) {
                        WorkspaceNativeDragHandle(title: "Terminal ↗", payload: terminal.id.rawValue, began: {
                            begin(.existing(terminal.id))
                        }, ended: finishDrag)
                        .frame(width: max(48, (width - 72) / 2), height: 25)
                        .accessibilityLabel("Drag Terminal out of stack")
                    }
                    menu(region)
                    Button { modify(region.isStack ? "Removed Terminal from stack" : "Removed \(title)") { configuration in
                        for widget in region.widgets { configuration.remove(widget.id) }
                    } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                        .buttonStyle(.plain).frame(width: 24, height: 24)
                        .disabled(region.widgets.count == 1 && region.widgets.first?.kind == .chat)
                        .accessibilityLabel(region.isStack ? "Remove Terminal from stack" : "Remove \(title) widget")
                }
            }
            if case .palette(let kind) = drag, region.widgets.first?.kind == kind,
               !draft.widgets(on: surface).contains(where: { $0.kind == kind }) {
                Label("Add \(kind.title) here", systemImage: kind.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .allowsHitTesting(false)
            } else {
                content(region, max(0, height - (editing ? 30 : 0)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(!editing)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .clipped()
        .opacity(editing && drag == .existing(region.id) ? 0.55 : 1)
        .overlay {
            if editing {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(stackedTarget ? Color.blue : .white.opacity(0.25), style: StrokeStyle(lineWidth: stackedTarget ? 2 : 1, dash: stackedTarget ? [] : [4, 4]))
                    .allowsHitTesting(false)
                if stackedTarget {
                    Label("Combine Chat + Terminal", systemImage: "square.stack")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(8).background(.black.opacity(0.85), in: Capsule())
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .leading) {
            if editing, case .insert(_, let before) = target, before == region.id {
                RoundedRectangle(cornerRadius: 2).fill(.blue)
                    .frame(width: 3).padding(.vertical, 12).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            if editing, case .insert(_, nil) = target, regions(in: visibleConfiguration).last?.id == region.id {
                RoundedRectangle(cornerRadius: 2).fill(.blue)
                    .frame(width: 3).padding(.vertical, 12).allowsHitTesting(false)
            }
        }
        .background {
            if editing {
                GeometryReader { geometry in
                    Color.clear.preference(key: WorkspaceEditorFrameKey.self, value: [region.id: geometry.frame(in: .named("workspace-widget-editor"))])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) widget")
        .accessibilityValue("Position \((regions(in: configuration).firstIndex(where: { $0.id == region.id }) ?? 0) + 1)")
        .accessibilityAction(named: "Move left") { shift(region, by: -1) }
        .accessibilityAction(named: "Move right") { shift(region, by: 1) }
    }

    private func menu(_ region: WorkspaceWidgetRegion) -> some View {
        Menu {
            Button("Move left") { shift(region, by: -1) }
            Button("Move right") { shift(region, by: 1) }
            if surface == .agents, region.widgets.contains(where: { $0.kind == .terminal }), !region.isStack,
               draft.widgets(on: surface).contains(where: { $0.kind == .chat }) {
                Button("Combine with Chat") { modify("Combined Chat and Terminal") { $0.combineTerminalWithChat(on: surface) } }
            }
            if region.isStack {
                Button("Separate from Stack") { modify("Separated Chat and Terminal") { $0.separateStack(region.id) } }

            }
        } label: { Image(systemName: "ellipsis.circle").frame(width: 24, height: 24) }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Arrange \(region.widgets.map { $0.kind.title }.joined(separator: " and "))")
    }

    private var palette: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(eligibleWidgets.filter { $0.isEligible(on: surface) }) { kind in
                        let present = draft.widgets(on: surface).contains { $0.kind == kind }
                        VStack(spacing: 2) {
                            Button { modify("Added \(kind.title)") { $0.add(kind, on: surface) } } label: {
                                Label(kind.title, systemImage: present ? "checkmark.circle.fill" : kind.symbol)
                                    .font(.system(size: 10, weight: .medium)).lineLimit(1)
                            }
                            .buttonStyle(.plain).disabled(present)
                            .accessibilityLabel("Add \(kind.title) widget")
                            .accessibilityValue(present ? "Already added" : "Available")
                            .workspaceEditorAction("add.\(kind.rawValue)")
                            if !present {
                                WorkspaceNativeDragHandle(title: "Drag to add", payload: kind.rawValue, began: {
                                    begin(.palette(kind))
                                }, ended: finishDrag).frame(width: 70, height: 20)
                            }
                        }
                        .padding(6).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Button {
                withAnimation(motion) { draft.resetWidgets(on: surface) }
                announcement = "Default layout restored"
                WorkspaceEditorAccessibility.announce(announcement)
            } label: { Image(systemName: "arrow.counterclockwise").frame(width: 24, height: 24) }
            .buttonStyle(.plain).accessibilityLabel("Reset to Default Layout")
            .workspaceEditorAction("reset")
            Button("Cancel", action: cancel).buttonStyle(.plain)
                .accessibilityLabel("Cancel widget changes")
                .workspaceEditorAction("cancel")
            Button("Done") {
                finishDrag()
                draft.markCustomized(surface)
                store.commit(draft)
                editing = false
                WorkspaceEditorAccessibility.announce("Widget layout saved")
            }.buttonStyle(.borderedProminent).controlSize(.small)
                .accessibilityLabel("Save widget layout")
                .workspaceEditorAction("done")
        }
        .frame(height: 62)
        .transition(.opacity)
    }

    private func regions(in configuration: WorkspaceConfiguration) -> [WorkspaceWidgetRegion] {
        configuration.regions(on: surface).compactMap { region in
            let visible = region.widgets.filter { eligibleWidgets.contains($0.kind) }
            guard !visible.isEmpty else { return nil }
            return WorkspaceWidgetRegion(id: visible.count > 1 ? region.id : visible[0].id, widgets: visible)
        }
    }

    private func preview(_ configuration: WorkspaceConfiguration, drag: WorkspaceEditorDrag,
                         target: WorkspaceDropTarget) -> WorkspaceConfiguration {
        let id: WidgetID? = if case .existing(let id) = drag { id } else { nil }
        let kind: IslandWidget? = if case .palette(let kind) = drag { kind } else { nil }
        return WorkspaceDropResolver.applying(target, to: configuration, draggedID: id, paletteKind: kind) ?? configuration
    }
    private func begin(_ source: WorkspaceEditorDrag) {
        dragFrames = measurements.frames
        drag = source
        target = nil
    }
    private func finishDrag() { drag = nil; target = nil; dragFrames = [:] }
    private func clearTarget() { withAnimation(motion) { target = nil } }
    private func cancel() { finishDrag(); editing = false; WorkspaceEditorAccessibility.announce("Widget changes cancelled") }
    private func shift(_ region: WorkspaceWidgetRegion, by offset: Int) {
        guard editing else { return }
        modify("Moved \(region.widgets.map { $0.kind.title }.joined(separator: " and "))") { $0.shift(region.id, by: offset) }
    }
    private func modify(_ message: String, _ change: (inout WorkspaceConfiguration) -> Void) {
        guard editing else { return }
        withAnimation(motion) { change(&draft) }
        announcement = message
        WorkspaceEditorAccessibility.announce(message)
    }
    private func updateTarget(_ location: CGPoint) -> Bool {
        guard editing, let drag else { return false }
        let measured = dragFrames.isEmpty ? measurements.frames : dragFrames
        let slots = regions(in: draft).compactMap { region -> WorkspaceDropSlot? in
            guard let frame = measured[region.id], let kind = region.widgets.first?.kind else { return nil }
            return .init(id: region.id, frame: frame, kind: region.isStack ? .workspace : kind)
        }
        let bounds = measured.values.reduce(CGRect.null) { $0.union($1) }
        let draggedKind: IslandWidget? = switch drag {
        case .palette(let kind): kind
        case .existing(let id): draft.widgets(on: surface).first(where: { $0.id == id })?.kind ?? (draft.regions(on: surface).first(where: { $0.id == id })?.isStack == true ? .chat : nil)
        }
        guard let draggedKind else { return false }
        let resolved = WorkspaceDropResolver.resolve(point: location, bounds: bounds, surface: surface,
                                                      slots: slots, draggedKind: draggedKind, previous: target)
        let next: WorkspaceDropTarget? = resolved == .invalid ? nil : resolved
        guard next != target else { return next != nil }
        AgentPerformanceProbe.count("workspace.editor.target.changed")
        withAnimation(motion) { target = next }
        return next != nil
    }
    private func commitDrop(_ location: CGPoint) -> Bool {
        guard updateTarget(location), let drag, let target else { finishDrag(); return false }
        withAnimation(motion) { draft = preview(draft, drag: drag, target: target) }
        announcement = "Widget placement updated"
        WorkspaceEditorAccessibility.announce(announcement)
        finishDrag()
        return true
    }
}

/// Shared semantic tokens translated from transitions.dev resize/tabs guidance.
enum WorkspaceEditorMotion {
    static let reorderDuration = 0.25
    static let resizeDuration = 0.30
    static func reorder(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: reorderDuration)
    }
    static func resize(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: resizeDuration)
    }
}

enum WorkspaceEditorDrag: Equatable {
    case existing(WidgetID)
    case palette(IslandWidget)
}
private final class WorkspaceEditorMeasurements { var frames: [WidgetID: CGRect] = [:] }

private struct WorkspaceEditorFrameKey: PreferenceKey {
    static var defaultValue: [WidgetID: CGRect] { [:] }
    static func reduce(value: inout [WidgetID: CGRect], nextValue: () -> [WidgetID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct WorkspaceEditorDropModifier: ViewModifier {
    let enabled: Bool
    let updated: (CGPoint) -> Bool
    let dropped: (CGPoint) -> Bool
    let exited: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [WorkspaceNativeDragHandle.type], delegate: WorkspaceEditorDrop(updated: updated, dropped: dropped, exited: exited))
        } else { content }
    }
}
private struct WorkspaceEditorDrop: DropDelegate {
    let updated: (CGPoint) -> Bool
    let dropped: (CGPoint) -> Bool
    let exited: () -> Void
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [WorkspaceNativeDragHandle.type.identifier]) }
    func dropEntered(info: DropInfo) { _ = updated(info.location) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: updated(info.location) ? .move : .cancel) }
    func dropExited(info: DropInfo) { exited() }
    func performDrop(info: DropInfo) -> Bool { dropped(info.location) }
}

/// An AppKit source gives a real end/cancel callback, unlike onDrag alone.
/// No global event monitor, live renderer snapshot or orphan drag state.
struct WorkspaceNativeDragHandle: NSViewRepresentable {
    static let type = UTType(exportedAs: "app.dynamicisland.workspace-widget")
    let title: String
    let payload: String
    var began: () -> Void
    var ended: () -> Void
    func makeNSView(context: Context) -> WorkspaceNativeDragView { WorkspaceNativeDragView() }
    func updateNSView(_ view: WorkspaceNativeDragView, context: Context) {
        view.title = title; view.payload = payload; view.began = began; view.ended = ended
        view.setAccessibilityLabel(title)
        view.needsDisplay = true
    }
    static func dismantleNSView(_ view: WorkspaceNativeDragView, coordinator: ()) {
        view.began = {}; view.ended = {}
    }
}
final class WorkspaceNativeDragView: NSView, NSDraggingSource {
    var title = ""
    var payload = ""
    var began: () -> Void = {}
    var ended: () -> Void = {}
    private var down: NSEvent?
    private var dragging = false
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        ("⠿ " + title).draw(in: bounds.insetBy(dx: 3, dy: 5), withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.8)])
    }
    override func mouseDown(with event: NSEvent) { down = event; dragging = false }
    override func mouseDragged(with event: NSEvent) {
        guard let down, !dragging else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 16 else { return }
        dragging = true
        began()
        let item = NSPasteboardItem()
        item.setString(payload, forType: NSPasteboard.PasteboardType(WorkspaceNativeDragHandle.type.identifier))
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        let image = NSImage(size: NSSize(width: 150, height: 32))
        image.lockFocus()
        NSColor.black.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 150, height: 32), xRadius: 9, yRadius: 9).fill()
        title.draw(at: NSPoint(x: 10, y: 10), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white])
        image.unlockFocus()
        dragItem.setDraggingFrame(NSRect(origin: convert(down.locationInWindow, from: nil), size: image.size), contents: image)
        let session = beginDraggingSession(with: [dragItem], event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
    override func mouseUp(with event: NSEvent) { down = nil }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false; down = nil
        let completion = ended
        DispatchQueue.main.async { completion() }
    }
}

/// Deterministic native-layout fixtures use the actual button rectangles.
struct WorkspaceEditorActionFrames: PreferenceKey {
    static let coordinateSpace = "workspace-editor-actions"
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
private extension View {
    func workspaceEditorAction(_ action: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: WorkspaceEditorActionFrames.self,
                                       value: [action: geometry.frame(in: .named(WorkspaceEditorActionFrames.coordinateSpace))])
            }
        }
    }
}

@MainActor
enum WorkspaceEditorAccessibility {
    /// AppKit requires announcementRequested on the application element.
    /// This uses normal accessibility notifications, never accessibility permissions.
    static func announce(_ message: String) {
        guard let application = NSApp else { return }
        NSAccessibility.post(element: application, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
