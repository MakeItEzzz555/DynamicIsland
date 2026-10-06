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
    var onLayoutPreview: ((WorkspaceConfiguration?) -> Void)? = nil
    /// Drag in flight: the host keeps the shell from shrinking under the pointer.
    var onDragActive: ((Bool) -> Void)? = nil
    /// Same content-adaptive Chat height the shell resolver uses (Agents).
    var chatHeightHint: () -> CGFloat? = { nil }
    /// Semantic completion: the layout was saved and editing ended. The owner
    /// decides what follows (the island collapses through its normal
    /// children-exit sequence); the editor never touches shell state.
    var onApplyCompleted: (() -> Void)? = nil
    var content: (WorkspaceWidgetRegion, CGFloat) -> AnyView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandDisplayMetrics) private var displayMetrics
    @State private var draft = WorkspaceConfiguration.initial
    @State private var drag: WorkspaceEditorDrag?
    @State private var target: WorkspaceDropTarget?
    /// Hovered widget + insertion edge for the interior target glow.
    @State private var intent: WorkspaceDropIntent?
    @State private var measurements = WorkspaceEditorMeasurements()
    @State private var announcement = ""

    private var motion: Animation? { WorkspaceEditorMotion.reorder(reduceMotion: reduceMotion || !extraMotion) }
    private var configuration: WorkspaceConfiguration { editing ? draft : store.configuration }
    private var visibleConfiguration: WorkspaceConfiguration {
        // The prospective layout: neighbours move to exactly the result of a drop.
        guard let drag, let target else { return configuration }
        switch target {
        case .insert, .stack: return preview(configuration, drag: drag, target: target)
        case .combine, .invalid: return configuration
        }
    }

    var body: some View {
        let _ = AgentPerformanceProbe.count("workspace.editor.body")
        GeometryReader { geometry in
            workspace(size: geometry.size)
        }
        .coordinateSpace(name: WorkspaceEditorActionFrames.coordinateSpace)
        .animation(WorkspaceEditorMotion.chrome(opening: editing, reduceMotion: reduceMotion || !extraMotion), value: editing)
        .onAppear {
            draft = store.configuration
            if editing { onLayoutPreview?(draft) }
        }
        .onChange(of: editing) { _, active in
            drag = nil; target = nil
            if active { draft = store.configuration }
            onLayoutPreview?(active ? draft : nil)
        }
        .onChange(of: draft) { _, configuration in
            if editing { onLayoutPreview?(configuration) }
        }
        // The shell creates/reclaims space for the prospective layout while
        // dragging; cancelling returns it to the draft. Discrete per target.
        .onChange(of: target) { _, _ in
            if editing { onLayoutPreview?(visibleConfiguration) }
        }
        .onDisappear { onLayoutPreview?(nil); onDragActive?(false) }
        .onExitCommand(perform: editing ? { cancel() } : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(editing ? "Customize \(surface.rawValue) widgets" : "\(surface.rawValue) widgets")
        .accessibilityValue(announcement)
    }

    private func workspace(size: CGSize) -> some View {
        // Plain storage (no publication): the drop resolver reads the size the
        // committed layout is projected into right now.
        measurements.size = size
        let visibleRegions = regions(in: visibleConfiguration)
        let projection = WorkspaceWidgetLayoutProjection.make(regions: visibleRegions, availableSize: size,
            metrics: displayMetrics, editing: editing, chatHeightHint: chatHeightHint())
        let height = max(1, size.height - (editing ? WorkspaceEditorChrome.paletteHeight + displayMetrics.spacing(8) : 0))
        let canvas = widgetGrid(regions: visibleRegions, projection: projection)
        return VStack(spacing: displayMetrics.spacing(8)) {
            Group {
                if projection.requiresScrolling {
                    ScrollView(.vertical, showsIndicators: true) { canvas }
                } else { canvas }
            }
            .frame(height: height)
            if editing { palette }
        }
    }

    private func widgetGrid(regions: [WorkspaceWidgetRegion], projection: WorkspaceWidgetLayoutProjection) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(regions) { region in
                if let item = projection.frames.first(where: { $0.id == region.id }) {
                    card(region, width: item.frame.width, height: item.frame.height)
                        .position(x: item.frame.midX, y: item.frame.midY)
                }
            }
            if regions.isEmpty {
                Text(editing ? "Add an available widget from the palette" : "Customize to add an available widget")
                    .foregroundStyle(.secondary)
                    .frame(width: projection.contentSize.width, height: projection.contentSize.height)
            }
        }
        .frame(width: projection.contentSize.width, height: projection.contentSize.height, alignment: .topLeading)
        .background {
            if editing {
                GeometryReader { canvas in
                    Color.clear.preference(key: WorkspaceEditorFrameKey.self,
                        value: [WidgetID("__editor.canvas"): canvas.frame(in: .named("workspace-widget-editor"))])
                }
            }
        }
        .modifier(WorkspaceEditorDropModifier(enabled: editing, updated: updateTarget, dropped: commitDrop, exited: clearTarget))
        .coordinateSpace(name: "workspace-widget-editor")
        .onPreferenceChange(WorkspaceEditorFrameKey.self) { measured in measurements.frames = measured }
    }

    private func card(_ region: WorkspaceWidgetRegion, width: CGFloat, height: CGFloat) -> some View {
        let title: String = region.widgets.map { $0.kind.title }.joined(separator: " and ")
        let position: Int = (regions(in: configuration).firstIndex(where: { $0.id == region.id }) ?? 0) + 1
        let removeName: String = region.isStack ? "Remove Terminal from stack" : "Remove"
        let visual = cardVisual(region, title: title, width: width, height: height)
        return visual
            .contextMenu { if editing { arrangeMenu(region) } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("\(title) widget"))
            .accessibilityValue(Text("Position \(position), \(region.widgets.first?.size.title ?? "Standard") size"))
            .accessibilityAction(named: Text("Move left")) { shift(region, by: -1) }
            .accessibilityAction(named: Text("Move right")) { shift(region, by: 1) }
            .accessibilityAction(named: Text(removeName)) { remove(region) }
            .accessibilityAction(named: Text("Use compact size")) { resize(region, to: .compact) }
            .accessibilityAction(named: Text("Use standard size")) { resize(region, to: .standard) }
            .accessibilityAction(named: Text("Use large size")) { resize(region, to: .large) }
    }

    private func cardVisual(_ region: WorkspaceWidgetRegion, title: String, width: CGFloat, height: CGFloat) -> some View {
        let chatID: WidgetID = region.widgets.first(where: { $0.kind == .chat })?.id ?? region.id
        let stackedTarget: Bool = target == .combine(chat: chatID)
        let placeholder: Bool = isPlaceholder(region)
        let placement = WorkspaceWidgetPlacementContext(
            isSole: regions(in: visibleConfiguration).count == 1,
            size: CGSize(width: width, height: height),
            fillsRow: true,
            presentationSize: WorkspaceWidgetLayoutProjection.presentationSize(of: region))
        let layers = cardLayers(region, title: title, height: height, placeholder: placeholder)
            .environment(\.workspaceWidgetPlacement, placement)
            .transformEnvironment(\.timerRulerInteractionRegistration) { if editing { $0.enabled = false } }
            .frame(width: width, height: height, alignment: .top)
        let hovered = editing && intent?.hovered == region.id
        return layers
            .scaleEffect(hovered ? 0.975 : 1)
            .background { cardFill(placeholder: placeholder) }
            .overlay { cardOutline(placeholder: placeholder, stackedTarget: stackedTarget) }
            .overlay { targetGlow(region) }
            .overlay { combineHint(stackedTarget) }
            .overlay(alignment: .topTrailing) { badgeOverlay(region, title: title, placeholder: placeholder) }
            .overlay(alignment: .bottom) { sizeControlOverlay(region, title: title, placeholder: placeholder) }
            .background { frameReporter(region.id) }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WorkspaceEditorChrome.cornerRadius, style: .continuous)
    }

    private func isPlaceholder(_ region: WorkspaceWidgetRegion) -> Bool {
        guard editing else { return false }
        if drag == .existing(region.id) { return true }
        guard case .palette(let kind) = drag, region.widgets.first?.kind == kind else { return false }
        return !draft.widgets(on: surface).contains(where: { $0.kind == kind })
    }

    @ViewBuilder
    private func cardLayers(_ region: WorkspaceWidgetRegion, title: String, height: CGFloat, placeholder: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            content(region, height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(!editing)
                .opacity(placeholder ? 0.18 : 1)
                .clipShape(cardShape)
            if editing {
                // Input layers never animate: they exist exactly while editing,
                // so no invisible drag surface outlives Done/Cancel.
                dragSurfaces(region, title: title).transition(.identity)
            }
            if placeholder, case .palette(let kind) = drag { paletteLandingLabel(kind) }
        }
    }

    @ViewBuilder
    private func dragSurfaces(_ region: WorkspaceWidgetRegion, title: String) -> some View {
        // The whole card is the drag source; content stays visible and inert.
        WorkspaceNativeDragHandle(title: title, symbol: region.widgets.first?.kind.symbol ?? "square",
                                  payload: region.id.rawValue, began: { begin(.existing(region.id)) }, ended: finishDrag)
            .accessibilityHidden(true)
        if region.isStack, let terminal = region.widgets.first(where: { $0.kind == .terminal }) {
            WorkspaceNativeDragHandle(title: "Terminal", symbol: IslandWidget.terminal.symbol, payload: terminal.id.rawValue,
                                      style: .chip, began: { begin(.existing(terminal.id)) }, ended: finishDrag)
                .frame(width: 92, height: 24)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .accessibilityLabel("Drag Terminal out of stack")
        }
    }

    private func paletteLandingLabel(_ kind: IslandWidget) -> some View {
        Label("Add \(kind.title)", systemImage: kind.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WorkspaceEditorChrome.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cardFill(placeholder: Bool) -> some View {
        if placeholder { cardShape.fill(WorkspaceEditorChrome.accent.opacity(0.08)) }
    }

    @ViewBuilder
    private func cardOutline(placeholder: Bool, stackedTarget: Bool) -> some View {
        if editing {
            let emphasized = placeholder || stackedTarget
            let color: Color = emphasized ? WorkspaceEditorChrome.accent : .white.opacity(0.30)
            let style = StrokeStyle(lineWidth: emphasized ? 1.5 : 1, dash: stackedTarget ? [] : [5, 4])
            cardShape.strokeBorder(color, style: style)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Subtle interior glow on the hovered widget, strongest at the edge where
    /// the dragged widget will land. Stays inside the card's shape.
    @ViewBuilder
    private func targetGlow(_ region: WorkspaceWidgetRegion) -> some View {
        if editing, let intent, intent.hovered == region.id, let edge = intent.edge, edge != .center {
            let (start, end): (UnitPoint, UnitPoint) = switch edge {
            case .leading: (.leading, .trailing)
            case .trailing: (.trailing, .leading)
            case .top: (.top, .bottom)
            case .bottom: (.bottom, .top)
            case .center: (.center, .center)
            }
            ZStack {
                cardShape.fill(WorkspaceEditorChrome.accent.opacity(0.10))
                cardShape
                    .fill(LinearGradient(colors: [WorkspaceEditorChrome.accent.opacity(0.42), WorkspaceEditorChrome.accent.opacity(0)],
                                         startPoint: start, endPoint: UnitPoint(x: (start.x + end.x * 1.5) / 2.5, y: (start.y + end.y * 1.5) / 2.5)))
                cardShape.strokeBorder(WorkspaceEditorChrome.accent.opacity(0.75), lineWidth: 1.5)
            }
                .allowsHitTesting(false)
                .transition(.opacity)
                .id(edge.hashValue)
        }
    }

    @ViewBuilder
    private func combineHint(_ stackedTarget: Bool) -> some View {
        if editing && stackedTarget {
            Label("Combine Chat + Terminal", systemImage: "square.stack")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.85), in: Capsule())
                .overlay(Capsule().strokeBorder(WorkspaceEditorChrome.accent.opacity(0.6)))
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    @ViewBuilder
    private func badgeOverlay(_ region: WorkspaceWidgetRegion, title: String, placeholder: Bool) -> some View {
        if editing && !placeholder {
            removeBadge(region, title: title)
                .offset(x: 6, y: -6)
                .transition(reduceMotion || !extraMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func sizeControlOverlay(_ region: WorkspaceWidgetRegion, title: String, placeholder: Bool) -> some View {
        if editing && !placeholder && drag == nil {
            WorkspaceWidgetSizeControl(selection: WorkspaceWidgetLayoutProjection.presentationSize(of: region),
                                       widgetTitle: title) { resize(region, to: $0) }
                .padding(.bottom, 6)
                .transition(.opacity)
        }
    }

    private func frameReporter(_ id: WidgetID) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: WorkspaceEditorFrameKey.self, value: [id: geometry.frame(in: .named("workspace-widget-editor"))])
        }
    }

    private func removeBadge(_ region: WorkspaceWidgetRegion, title: String) -> some View {
        let locked = region.widgets.count == 1 && region.widgets.first?.kind == .chat
        return Button { remove(region) } label: {
            ZStack {
                Circle().fill(Color(red: 1, green: 0.27, blue: 0.23))
                Capsule().fill(.white).frame(width: 8, height: 2)
            }
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(.black.opacity(0.55), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .opacity(locked ? 0 : 1)
        .disabled(locked)
        .accessibilityLabel(region.isStack ? "Remove Terminal from stack" : "Remove \(title) widget")
        .help(region.isStack ? "Remove Terminal from stack" : "Remove \(title)")
    }

    private func remove(_ region: WorkspaceWidgetRegion) {
        guard !(region.widgets.count == 1 && region.widgets.first?.kind == .chat) else { return }
        let title = region.widgets.map { $0.kind.title }.joined(separator: " and ")
        modify(region.isStack ? "Removed Terminal from stack" : "Removed \(title)") { configuration in
            if region.isStack {
                for widget in region.widgets where widget.kind == .terminal { configuration.remove(widget.id) }
            } else {
                for widget in region.widgets { configuration.remove(widget.id) }
            }
        }
    }

    @ViewBuilder
    private func arrangeMenu(_ region: WorkspaceWidgetRegion) -> some View {
        Button("Move Left") { shift(region, by: -1) }
        Button("Move Right") { shift(region, by: 1) }
        Menu("Widget Size") {
            ForEach(WidgetPresentationSize.allCases, id: \.self) { size in
                Button {
                    resize(region, to: size)
                } label: {
                    if region.widgets.allSatisfy({ $0.size == size }) { Label(size.title, systemImage: "checkmark") }
                    else { Text(size.title) }
                }
            }
        }
        if surface == .agents, region.widgets.contains(where: { $0.kind == .terminal }), !region.isStack,
           draft.widgets(on: surface).contains(where: { $0.kind == .chat }) {
            Button("Combine with Chat") { modify("Combined Chat and Terminal") { $0.combineTerminalWithChat(on: surface) } }
        }
        if region.isStack {
            Button("Separate from Stack") { modify("Separated Chat and Terminal") { $0.separateStack(region.id) } }
        }
        if !(region.widgets.count == 1 && region.widgets.first?.kind == .chat) {
            Divider()
            Button(region.isStack ? "Remove Terminal" : "Remove", role: .destructive) { remove(region) }
        }
    }

    private var palette: some View {
        HStack(alignment: .center, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(eligibleWidgets.filter { $0.isEligible(on: surface) }) { kind in
                        paletteTile(kind, present: draft.widgets(on: surface).contains { $0.kind == kind })
                    }
                }
                .padding(.horizontal, 2)
            }
            HStack(spacing: 8) {
                Button {
                    withAnimation(motion) { draft.resetWidgets(on: surface) }
                    announcement = "Default layout restored"
                    WorkspaceEditorAccessibility.announce(announcement)
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6)).frame(width: 26, height: 26).contentShape(Circle())
                }
                .buttonStyle(.plain).help("Reset to Default Layout")
                .accessibilityLabel("Reset to Default Layout")
                .workspaceEditorAction("reset")
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).help("Cancel")
                .accessibilityLabel("Cancel widget changes")
                .workspaceEditorAction("cancel")
                Button(action: apply) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(WorkspaceEditorChrome.accent, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).help("Done")
                .accessibilityLabel("Save widget layout")
                .workspaceEditorAction("done")
            }
        }
        .frame(height: WorkspaceEditorChrome.paletteHeight)
        // Reveal animates in; on Done/Cancel the palette (and its drag
        // sources) leaves immediately while the shell itself shrinks.
        .transition(.asymmetric(insertion: reduceMotion || !extraMotion ? .opacity : .opacity.combined(with: .offset(y: 8)),
                                removal: .identity))
    }

    private func paletteTile(_ kind: IslandWidget, present: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [kind.paletteTint.opacity(0.95), kind.paletteTint.opacity(0.70)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Image(systemName: kind.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(width: 32, height: 32)
                if present {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, WorkspaceEditorChrome.accent)
                        .background(Circle().fill(.black).padding(1))
                        .offset(x: 4, y: 4)
                        .transition(reduceMotion || !extraMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }
            }
            Text(kind.title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(present ? 0.45 : 0.75))
                .lineLimit(1).truncationMode(.tail)
                .frame(width: 50)
        }
        .frame(width: 52)
        .opacity(present ? 0.6 : 1)
        .overlay {
            if !present && editing {
                // Click adds; dragging places a live preview where it drops.
                WorkspaceNativeDragHandle(title: kind.title, symbol: kind.symbol, payload: kind.rawValue,
                                          clicked: { modify("Added \(kind.title)") { $0.add(kind, on: surface) } },
                                          began: { begin(.palette(kind)) }, ended: finishDrag)
                    .accessibilityHidden(true)
                    .transition(.identity)
            }
        }
        .workspaceEditorAction("add.\(kind.rawValue)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add \(kind.title) widget")
        .accessibilityValue(present ? "Already added" : "Available")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !present { modify("Added \(kind.title)") { $0.add(kind, on: surface) } } }
        .help(present ? "\(kind.title) is already placed" : "Click or drag to add \(kind.title)")
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
        measurements.dragStartSize = measurements.size
        onDragActive?(true)
        drag = source
        target = nil
    }
    private func finishDrag() {
        drag = nil; target = nil; intent = nil; measurements.dragStartSize = .zero
        onDragActive?(false)
    }
    private func clearTarget() { withAnimation(motion) { target = nil; intent = nil } }
    private func cancel() { finishDrag(); editing = false; WorkspaceEditorAccessibility.announce("Widget changes cancelled") }
    /// Apply: commit once, end editing, then hand off to the owner (collapse).
    /// A second tap after editing ended is ignored, so it can never commit or
    /// request collapse twice.
    private func apply() {
        guard editing else { return }
        finishDrag()
        var isEditing = editing
        guard WorkspaceEditorApply.apply(draft: &draft, surface: surface, store: store,
                                         editing: &isEditing, completion: onApplyCompleted) else { return }
        editing = isEditing
        WorkspaceEditorAccessibility.announce("Widget layout saved")
    }
    /// Draft-only: neighbours and the shell preview the new grid at once;
    /// Apply persists, Cancel restores the saved size.
    private func resize(_ region: WorkspaceWidgetRegion, to size: WidgetPresentationSize) {
        guard editing, WorkspaceWidgetLayoutProjection.presentationSize(of: region) != size
                || !region.widgets.allSatisfy({ $0.size == size }) else { return }
        let message = "\(region.widgets.map { $0.kind.title }.joined(separator: " and ")) size \(size.title)"
        withAnimation(WorkspaceEditorMotion.resize(reduceMotion: reduceMotion || !extraMotion)) {
            draft.setSize(size, for: region.id)
        }
        announcement = message
        WorkspaceEditorAccessibility.announce(message)
    }
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
        // Slots come from the same projection that draws the committed draft
        // at the editor's *current* size. Frames measured at drag start went
        // stale as soon as the preview resized the shell (rows re-center), so
        // the pointer resolved against cards that were no longer there and
        // the target flickered back to nil: no glow, no prospective motion.
        let committed = regions(in: draft)
        let reference = measurements.dragStartSize == .zero ? measurements.size : measurements.dragStartSize
        let projection = WorkspaceWidgetLayoutProjection.make(regions: committed, availableSize: reference,
            metrics: displayMetrics, editing: editing)
        let location = WorkspaceDropResolver.dragReferencePoint(location, currentSize: measurements.size, startSize: reference)
        let slots = committed.compactMap { region -> WorkspaceDropSlot? in
            guard let frame = projection.frames.first(where: { $0.id == region.id })?.frame,
                  let kind = region.widgets.first?.kind else { return nil }
            return .init(id: region.id, frame: frame, kind: region.isStack ? .workspace : kind)
        }
        let bounds = slots.reduce(CGRect.null) { $0.union($1.frame) }.insetBy(dx: -12, dy: -12)
        let draggedKind: IslandWidget? = switch drag {
        case .palette(let kind): kind
        case .existing(let id): draft.widgets(on: surface).first(where: { $0.id == id })?.kind ?? (draft.regions(on: surface).first(where: { $0.id == id })?.isStack == true ? .chat : nil)
        }
        guard let draggedKind else { return false }
        let draggedID: WidgetID? = if case .existing(let id) = drag { id } else { nil }
        let resolved = WorkspaceDropResolver.resolveIntent(point: location, bounds: bounds, surface: surface,
                                                            slots: slots, draggedKind: draggedKind, draggedID: draggedID,
                                                            previous: intent)
        let next: WorkspaceDropTarget? = resolved.target == .invalid ? nil : resolved.target
        let nextIntent: WorkspaceDropIntent? = next == nil ? nil : resolved
        guard next != target || nextIntent != intent else { return next != nil }
        AgentPerformanceProbe.count("workspace.editor.target.changed")
        withAnimation(motion) { target = next; intent = nextIntent }
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
    /// Interactive reorder/resize use critically damped springs (no bounce).
    /// Unlike a timing curve, a spring retargeted mid-flight keeps its
    /// velocity, so neighbours glide continuously as the hover target changes
    /// (the iOS home-screen feel) instead of restarting from rest.
    static let reorderDuration = 0.32
    static let resizeDuration = 0.36
    static func reorder(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: reorderDuration, extraBounce: 0)
    }
    static func resize(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: resizeDuration, extraBounce: 0)
    }
    /// transitions.dev panel reveal: open 400 ms, close 350 ms (smooth-out,
    /// never bouncing a close). Reduce Motion applies chrome directly.
    static let chromeOpenDuration = 0.40
    static let chromeCloseDuration = 0.35
    /// Asymmetric springs (Droppy `expandOpen` / `expandClose` principle): the
    /// reveal is responsive, the dismissal (Done/Apply) is critically damped so
    /// editor chrome settles without wobble while the shell collapses.
    static func chrome(opening: Bool, reduceMotion: Bool) -> Animation? {
        if reduceMotion { return nil }
        return opening
            ? .spring(response: chromeOpenDuration, dampingFraction: 0.92)
            : .spring(response: chromeCloseDuration, dampingFraction: 0.98)
    }
}

enum WorkspaceEditorDrag: Equatable {
    case existing(WidgetID)
    case palette(IslandWidget)
}
/// Apply semantics, independent of the view: commit the draft exactly once,
/// end editing, then run the owner's completion exactly once.
enum WorkspaceEditorApply {
    @MainActor @discardableResult
    static func apply(draft: inout WorkspaceConfiguration, surface: WorkspaceSurface,
                      store: WorkspaceCustomizationStore, editing: inout Bool,
                      completion: (() -> Void)?) -> Bool {
        guard editing else { return false }
        draft.markCustomized(surface)
        store.commit(draft)
        editing = false
        completion?()
        return true
    }
}

/// Owner-provided follow-up for a saved layout (the island collapses).
struct WorkspaceApplyCompletion {
    let action: () -> Void
}
private struct WorkspaceApplyCompletionKey: EnvironmentKey {
    static var defaultValue: WorkspaceApplyCompletion? { nil }
}
extension EnvironmentValues {
    var workspaceApplyCompletion: WorkspaceApplyCompletion? {
        get { self[WorkspaceApplyCompletionKey.self] }
        set { self[WorkspaceApplyCompletionKey.self] = newValue }
    }
}

private final class WorkspaceEditorMeasurements {
    var frames: [WidgetID: CGRect] = [:]
    var size: CGSize = .zero
    /// Editor size when the current drag began (the resolver's reference frame).
    var dragStartSize: CGSize = .zero
}

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
    enum Style { case surface, chip }
    let title: String
    var symbol: String = "square"
    let payload: String
    var style: Style = .surface
    var clicked: (() -> Void)? = nil
    var began: () -> Void
    var ended: () -> Void
    func makeNSView(context: Context) -> WorkspaceNativeDragView { WorkspaceNativeDragView() }
    func updateNSView(_ view: WorkspaceNativeDragView, context: Context) {
        let restyled = view.style != style || view.title != title
        view.title = title; view.symbol = symbol; view.payload = payload; view.style = style
        view.clicked = clicked; view.began = began; view.ended = ended
        view.setAccessibilityLabel(title)
        if restyled { view.needsDisplay = true }
    }
    static func dismantleNSView(_ view: WorkspaceNativeDragView, coordinator: ()) {
        view.began = {}; view.ended = {}; view.clicked = nil
    }
}
final class WorkspaceNativeDragView: NSView, NSDraggingSource {
    var title = ""
    var symbol = "square"
    var payload = ""
    var style: WorkspaceNativeDragHandle.Style = .surface
    var clicked: (() -> Void)?
    var began: () -> Void = {}
    var ended: () -> Void = {}
    private var down: NSEvent?
    private var dragging = false
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: clicked == nil ? .openHand : .pointingHand) }
    override func draw(_ dirtyRect: NSRect) {
        // A full-card surface is invisible; only the stack's Terminal chip draws.
        guard style == .chip else { return }
        let chip = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor.black.withAlphaComponent(0.78).setFill()
        let path = NSBezierPath(roundedRect: chip, xRadius: chip.height / 2, yRadius: chip.height / 2)
        path.fill()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 1
        path.stroke()
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.9)]
        let label = NSAttributedString(string: title, attributes: attributes)
        var x = chip.minX + 9
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) {
            let tinted = image.tinted(.white.withAlphaComponent(0.9))
            tinted.draw(in: NSRect(x: x, y: chip.midY - 6, width: 12, height: 12))
            x += 16
        }
        label.draw(at: NSPoint(x: x, y: chip.midY - label.size().height / 2))
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
        let image = Self.dragImage(title: title, symbol: symbol)
        let origin = convert(down.locationInWindow, from: nil)
        dragItem.setDraggingFrame(NSRect(x: origin.x - image.size.width / 2, y: origin.y - image.size.height / 2,
                                         width: image.size.width, height: image.size.height), contents: image)
        let session = beginDraggingSession(with: [dragItem], event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { down = nil }
        guard down != nil, !dragging, let clicked else { return }
        // Click (no drag): deliver after the AppKit event finishes.
        DispatchQueue.main.async { clicked() }
    }
    /// Lightweight proxy: icon + title pill. The live renderer never follows the pointer.
    static func dragImage(title: String, symbol: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let label = NSAttributedString(string: title, attributes: attributes)
        let width = min(220, ceil(label.size().width) + 48)
        let size = NSSize(width: width, height: 36)
        return NSImage(size: size, flipped: false) { rect in
            let pill = rect.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11)
            NSColor(white: 0.08, alpha: 0.94).setFill(); path.fill()
            NSColor.white.withAlphaComponent(0.22).setStroke(); path.lineWidth = 1; path.stroke()
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold)) {
                image.tinted(.white).draw(in: NSRect(x: 12, y: rect.midY - 8, width: 16, height: 16))
            }
            label.draw(at: NSPoint(x: 36, y: rect.midY - label.size().height / 2))
            return true
        }
    }
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

/// Shared reference-style edit chrome tokens.
enum WorkspaceEditorChrome {
    static let accent = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let cornerRadius: CGFloat = 16
    static let paletteHeight: CGFloat = 54
    static let badgeInset: CGFloat = 7
}

extension IslandWidget {
    /// Palette tile tint, app-icon style.
    var paletteTint: Color {
        switch self {
        case .media: Color(red: 1.0, green: 0.27, blue: 0.42)
        case .files: Color(red: 0.16, green: 0.55, blue: 1.0)
        case .clipboard: Color(red: 0.15, green: 0.72, blue: 0.80)
        case .timer: Color(red: 1.0, green: 0.58, blue: 0.10)
        case .calendar: Color(red: 0.95, green: 0.25, blue: 0.22)
        case .shortcuts: Color(red: 0.98, green: 0.74, blue: 0.10)
        case .activities: Color(red: 0.56, green: 0.36, blue: 0.98)
        case .chat: Color(red: 0.30, green: 0.47, blue: 1.0)
        case .terminal: Color(white: 0.32)
        case .feed: Color(red: 0.20, green: 0.75, blue: 0.45)
        case .workspace: Color(white: 0.4)
        case .agentUsage: Color(red: 0.36, green: 0.62, blue: 1.0)
        case .codexUsage: Color(red: 0.22, green: 0.58, blue: 0.95)
        case .claudeUsage: Color(red: 0.86, green: 0.47, blue: 0.30)
        }
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}


/// What the workspace layout allocated to one widget. Widgets use it to
/// compose for their real cell (e.g. a centered solo composition) instead of
/// assuming the multi-widget footprint.
struct WorkspaceWidgetPlacementContext: Equatable {
    var isSole = false
    var size: CGSize = .zero
    /// The widget owns an exact grid cell (distribute content over it).
    var fillsRow = false
    /// Semantic size class: each widget composes a dedicated layout per class
    /// (Compact square summary, Standard functional, Large expanded).
    var presentationSize: WidgetPresentationSize = .standard
}

private struct WorkspaceWidgetPlacementKey: EnvironmentKey {
    static let defaultValue = WorkspaceWidgetPlacementContext()
}

extension EnvironmentValues {
    var workspaceWidgetPlacement: WorkspaceWidgetPlacementContext {
        get { self[WorkspaceWidgetPlacementKey.self] }
        set { self[WorkspaceWidgetPlacementKey.self] = newValue }
    }
}

/// Edit-mode size picker: three glyphs drawn at their grid aspect
/// (1x1, 2x1, 2x2). The current size is filled; labels are spoken.
struct WorkspaceWidgetSizeControl: View {
    let selection: WidgetPresentationSize
    let widgetTitle: String
    let onSelect: (WidgetPresentationSize) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WidgetPresentationSize.allCases, id: \.self) { size in
                let selected = size == selection
                Button { onSelect(size) } label: {
                    glyph(size, selected: selected)
                        .frame(width: 26, height: 20)
                        .background(selected ? Color.white.opacity(0.22) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(size.title)
                .accessibilityValue(selected ? "Selected" : "")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .help("\(size.title) size")
            }
        }
        .padding(2)
        .background(.black.opacity(0.62), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(widgetTitle) size")
    }

    private func glyph(_ size: WidgetPresentationSize, selected: Bool) -> some View {
        let span = size.span
        let unit: CGFloat = 5, gap: CGFloat = 1
        let width = CGFloat(span.columns) * unit + CGFloat(span.columns - 1) * gap
        let height = CGFloat(span.rows) * unit + CGFloat(span.rows - 1) * gap
        return RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(selected ? Color.white : Color.white.opacity(0.45))
            .frame(width: width, height: height)
    }
}
