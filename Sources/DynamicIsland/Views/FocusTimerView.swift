import AppKit
import SwiftUI

/// The reference's compact Focus/Break timer: a travelling minute ruler under
/// a fixed pointer. Idle, the ruler picks a duration; while counting down it
/// slides toward zero from the controller's timing snapshot, so moving,
/// hiding or remounting the widget never resets or desynchronizes it.
struct FocusTimerView: View {
    @ObservedObject var timer: TimerController
    @ObservedObject var settings: AppSettings
    var onStarted: () -> Void = {}
    /// Standalone surfaces keep a subtle panel; widget grids provide their own.
    var showsPanel = true
    @AppStorage("focusTimerMode") private var storedMode = FocusTimerMode.focus.rawValue
    @AppStorage("focusTimerMinutes") private var focusMinutes = 25
    @AppStorage("breakTimerMinutes") private var breakMinutes = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var mode: FocusTimerMode { FocusTimerMode(rawValue: storedMode) ?? .focus }
    @AppStorage("focusTimerSeconds") private var focusSeconds = 0
    @AppStorage("breakTimerSeconds") private var breakSeconds = 0
    @State private var previewSeconds: Int?
    @State private var resolution: TimerRulerResolution = .seconds
    @State private var dragging = false
    private var selectedSeconds: Binding<Int> {
        Binding(get: {
            previewSeconds ?? TimerDurationSelection.restored(seconds: mode == .focus ? focusSeconds : breakSeconds,
                legacyMinutes: mode == .focus ? focusMinutes : breakMinutes)
        }, set: { previewSeconds = TimerDurationSelection.seconds(Double($0)) })
    }
    private func commitSelection(_ value: Int) {
        let seconds = TimerDurationSelection.seconds(Double(value))
        if mode == .focus { focusSeconds = seconds } else { breakSeconds = seconds }
        previewSeconds = nil
    }
    private var snapshot: TimerTimingSnapshot { timer.timingSnapshot }
    @Environment(\.workspaceWidgetPlacement) private var widgetPlacement
    /// In a shared row taller than the timer's own composition, distribute
    /// the three rows so the controls align with the neighbours' bottoms.
    private var distributesRows: Bool { !showsPanel && widgetPlacement.fillsRow }

    var body: some View {
        VStack(spacing: distributesRows ? 0 : 6) {
            HStack(spacing: 5) {
                ForEach(FocusTimerMode.allCases) { item in
                    Button(item.title) { storedMode = item.rawValue }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(item == mode ? Color.orange : Color.white.opacity(0.6))
                        .padding(.horizontal, 10).frame(height: 23)
                        .background(item == mode ? Color.orange.opacity(0.18) : Color.white.opacity(0.08), in: Capsule())
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(item == mode ? .isSelected : [])
                }
                Spacer(minLength: 3)
                Button {
                    resolution = resolution.next
                } label: {
                    Label(resolution.title, systemImage: resolution == .seconds ? "plus.magnifyingglass"
                        : resolution == .minutes ? "magnifyingglass" : "minus.magnifyingglass")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5).frame(height: 23)
                }
                .buttonStyle(.plain).disabled(dragging)
                .accessibilityLabel("Change timer ruler zoom")
                .accessibilityValue("\(resolution.title) per tick")
            }
            if distributesRows { Spacer(minLength: 6) }
            TimerRuler(snapshot: snapshot, now: { [timer] in timer.clockNow }, seconds: selectedSeconds,
                       resolution: resolution, extraMotion: !settings.reduceExtraMotion, onCommit: commitSelection, onDragging: { dragging = $0 })
                .id(mode)
                .frame(height: TimerRulerScale.rulerHeight)
            if distributesRows { Spacer(minLength: 6) }
            HStack(spacing: 6) {
                control(timer.isRunning ? "pause.fill" : "play.fill", label: timer.isRunning ? "Pause timer" : "Start or resume timer", selected: true) {
                    if timer.isRunning { timer.pause() }
                    else if case .paused = snapshot.phase { timer.resume() }
                    else { let value = selectedSeconds.wrappedValue; commitSelection(value); timer.start(seconds: value); onStarted() }
                }
                control(settings.timerSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", label: "Timer completion sound", selected: settings.timerSoundEnabled) {
                    settings.timerSoundEnabled.toggle()
                }
                control("stopwatch.fill", label: "Reset timer", selected: false) { timer.stop() }
                Spacer(minLength: 3)
                TimerCountdownLabel(snapshot: snapshot, now: { [timer] in timer.clockNow }, selectedSeconds: selectedSeconds.wrappedValue)
            }
        }
        .padding(showsPanel ? 12 : 4)
        .frame(maxWidth: .infinity, maxHeight: distributesRows ? .infinity : nil)
        .background {
            if showsPanel { RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.035)) }
        }
        .animation(reduceMotion || settings.reduceExtraMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.15), value: storedMode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus and break timer")
        .onAppear {
            if focusSeconds <= 0 { focusSeconds = TimerDurationSelection.restored(seconds: focusSeconds, legacyMinutes: focusMinutes) }
            if breakSeconds <= 0 { breakSeconds = TimerDurationSelection.restored(seconds: breakSeconds, legacyMinutes: breakMinutes) }
        }
        .onChange(of: storedMode) { _, _ in previewSeconds = nil; dragging = false }
    }

    private func control(_ symbol: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.orange : Color.white.opacity(0.65))
                .frame(width: 28, height: 28)
                .background(selected ? Color.orange.opacity(0.18) : Color.white.opacity(0.09), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// Seconds label driven by the same snapshot and cadence as the ruler.
private struct TimerCountdownLabel: View {
    let snapshot: TimerTimingSnapshot
    let now: () -> Duration
    let selectedSeconds: Int
    @State private var visible = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let interval = TimerCountdownPresentation.frameInterval(snapshot: snapshot, displayScale: displayScale)
        TimelineView(.animation(minimumInterval: interval ?? 1, paused: interval == nil || !visible)) { _ in
            let text = TimerCountdownPresentation.isCountingDown(snapshot)
                ? TimerCountdownPresentation.displayText(remaining: TimerCountdownPresentation.remainingSeconds(snapshot, now: now()))
                : TimerCountdownPresentation.displayText(remaining: Double(selectedSeconds))
            Text(text)
                .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.75)
                .contentTransition(.identity)
                .accessibilityLabel("Timer, \(text)")
        }
        .background { NativeVisualVisibility { visible = $0 }.allowsHitTesting(false) }
    }
}

/// One Canvas, bounded tick count, no per-tick views. The redraw loop exists
/// only while counting down and visible; otherwise the ruler is static.
struct TimerRuler: View {
    let snapshot: TimerTimingSnapshot
    let now: () -> Duration
    @Binding var seconds: Int
    var resolution: TimerRulerResolution = .seconds
    var extraMotion = true
    var onCommit: (Int) -> Void = { _ in }
    var onDragging: (Bool) -> Void = { _ in }
    var tickFeedback: () -> Void = { TimerRulerNativeFeedback.perform() }
    @Environment(\.timerRulerInteractionRegistration) private var interactionRegistration
    @State private var interactionOwner = UUID()
    @State private var measuredFrame = TimerRulerMeasuredFrame()
    @State private var drag: TimerRulerDragSelection?
    @State private var dragValue: Double?
    @State private var wheelTranslation: Double = 0
    @State private var ownership = TimerRulerInputOwnership()
    @State private var visible = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var countingDown: Bool { TimerCountdownPresentation.isCountingDown(snapshot) }

    var body: some View {
        let interval = TimerCountdownPresentation.frameInterval(snapshot: snapshot, displayScale: displayScale, resolution: resolution)
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: interval ?? 1, paused: interval == nil || !visible)) { _ in
                let value = TimerRulerInteractionGeometry.presentedValue(
                    countingDown: countingDown,
                    countdownSeconds: countingDown ? TimerCountdownPresentation.rulerSeconds(snapshot: snapshot, now: now(), selectedSeconds: seconds) : 0,
                    dragValue: dragValue, selectedSeconds: seconds)
                Canvas { context, size in draw(in: &context, size: size, value: value) }
            }
            .background {
                TimerRulerWheelInput(enabled: visible && !countingDown && interactionRegistration.enabled,
                    began: wheelBegan, changed: wheelChanged, finished: wheelFinished).allowsHitTesting(false)
                Color.clear.preference(key: TimerRulerInteractionFrameKey.self,
                    value: geometry.frame(in: .named(IslandCanvasCoordinateSpace.name)))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3).onChanged { change in
                guard !countingDown, interactionRegistration.enabled else { return }
                if ownership.source != .pointer {
                    guard abs(change.translation.width) >= abs(change.translation.height) * 1.3 else { return }
                    if ownership.begin(.pointer, newGesture: true, hasSession: drag != nil) { settleSession() }
                    drag = TimerRulerDragSelection(seconds: seconds, resolution: resolution)
                    onDragging(true)
                }
                guard var session = drag else { return }
                let update = session.update(translation: change.translation.width)
                drag = session
                dragValue = update.value
                if seconds != update.selectedSeconds { seconds = update.selectedSeconds }
                // One haptic per input event: a fast flick can cross dozens of
                // ticks and must not queue dozens of feedback requests.
                if !update.crossedTicks.isEmpty { tickFeedback() }
            }.onEnded { _ in
                guard drag != nil, ownership.source == .pointer else { return }
                onCommit(seconds)
                drag = nil
                ownership.end()
                onDragging(false)
                withAnimation(reduceMotion || !extraMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.15)) { dragValue = nil }
            })
            .onTapGesture(coordinateSpace: .local) { location in
                guard !countingDown, interactionRegistration.enabled else { return }
                select(Double(seconds) + Double((location.x - geometry.size.width / 2) / resolution.pointsPerSecond))
            }
        }
        .onPreferenceChange(TimerRulerInteractionFrameKey.self) { frame in
            guard frame != measuredFrame.frame else { return }
            measuredFrame.frame = frame
            DispatchQueue.main.async { interactionRegistration.report(interactionOwner, visible ? frame : nil) }
        }
        .background { NativeVisualVisibility { active in
            visible = active
            DispatchQueue.main.async { interactionRegistration.report(interactionOwner, active ? measuredFrame.frame : nil) }
        }.allowsHitTesting(false) }
        .onChange(of: countingDown) { _, _ in cancelDrag() }
        .onChange(of: interactionRegistration.enabled) { _, enabled in
            guard !enabled else { return }
            if !countingDown, let drag { seconds = drag.originSeconds }
            cancelDrag()
        }
        .onDisappear {
            visible = false
            cancelDrag()
            DispatchQueue.main.async { interactionRegistration.report(interactionOwner, nil) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(countingDown ? "Timer countdown" : "Timer duration")
        .accessibilityValue(TimerCountdownPresentation.accessibilityValue(snapshot: snapshot, now: now(), selectedSeconds: seconds))
        .focusable(!countingDown && interactionRegistration.enabled)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            guard !countingDown, interactionRegistration.enabled else { return .ignored }
            select(Double(seconds - resolution.stepSeconds)); return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !countingDown, interactionRegistration.enabled else { return .ignored }
            select(Double(seconds + resolution.stepSeconds)); return .handled
        }
        .accessibilityAdjustableAction { direction in
            guard !countingDown, interactionRegistration.enabled else { return }
            select(Double(seconds + (direction == .increment ? 1 : -1) * resolution.stepSeconds))
        }
    }

    /// A new physical wheel gesture never continues an older session.
    private func wheelBegan() {
        guard visible, !countingDown, interactionRegistration.enabled else { return }
        if ownership.begin(.wheel, newGesture: true, hasSession: drag != nil) { settleSession() }
    }
    private func wheelChanged(_ translation: Double) {
        guard visible, !countingDown, interactionRegistration.enabled else { return }
        if ownership.source != .wheel, ownership.begin(.wheel, newGesture: true, hasSession: drag != nil) { settleSession() }
        if drag == nil {
            drag = TimerRulerDragSelection(seconds: seconds, resolution: resolution)
            wheelTranslation = 0
            onDragging(true)
        }
        wheelTranslation += translation
        guard var session = drag else { return }
        let update = session.update(translation: wheelTranslation)
        drag = session; dragValue = update.value
        if seconds != update.selectedSeconds { seconds = update.selectedSeconds }
        if !update.crossedTicks.isEmpty { tickFeedback() }
    }
    private func wheelFinished(_ cancelled: Bool) {
        guard let session = drag, ownership.source == .wheel else { return }
        if cancelled { seconds = session.originSeconds }
        else { onCommit(seconds) }
        cancelDrag()
    }
    private func select(_ value: Double) {
        let selected = TimerDurationSelection.seconds(value)
        if !TimerRulerInteractionGeometry.crossedTicks(from: Double(seconds), to: Double(selected), resolution: resolution).isEmpty { tickFeedback() }
        seconds = selected
        onCommit(selected)
    }
    private func cancelDrag() {
        drag = nil; dragValue = nil; wheelTranslation = 0
        ownership.end()
        onDragging(false)
    }
    /// Commits whatever the previous session selected (always within bounds)
    /// and clears it, so the next gesture starts from that committed value.
    private func settleSession() {
        guard drag != nil else { return }
        onCommit(seconds)
        drag = nil; dragValue = nil; wheelTranslation = 0
    }
    private func draw(in context: inout GraphicsContext, size: CGSize, value: Double) {
        let center = size.width / 2
        let baseline = TimerRulerScale.tickBaseline
        for tickIndex in TimerRulerInteractionGeometry.visibleTicks(valueSeconds: value, width: size.width, resolution: resolution) {
            let x = TimerRulerInteractionGeometry.x(forTick: tickIndex, valueSeconds: value, center: center, resolution: resolution)
            guard x >= -1, x <= size.width + 1 else { continue }
            let tick = TimerRulerInteractionGeometry.tick(tickIndex, resolution: resolution)
            let distance = abs(x - center) / max(center, 1)
            let elapsed = countingDown && x > center + 0.5
            let opacity = max(0.10, 1 - distance * 0.85) * (elapsed ? 0.45 : 1)
            let selected = !countingDown && abs(x - center) < 0.25
            var path = Path()
            path.move(to: CGPoint(x: x, y: baseline - tick.height))
            path.addLine(to: CGPoint(x: x, y: baseline))
            context.stroke(path, with: .color((selected ? Color.white : Color.orange).opacity(opacity)),
                style: StrokeStyle(lineWidth: selected ? 2 : (tick.labelled ? 1.6 : 1.2), lineCap: .round))
            if tick.labelled {
                let label = resolution.label(forTick: tickIndex)
                context.draw(Text(label).font(.system(size: 9, weight: .semibold))
                    .foregroundColor(selected ? .white : .orange.opacity(opacity)), at: CGPoint(x: x, y: 6))
            }
        }
        var pointer = Path()
        pointer.move(to: CGPoint(x: center, y: baseline + 3))
        pointer.addLine(to: CGPoint(x: center - 3.5, y: baseline + 9))
        pointer.addLine(to: CGPoint(x: center + 3.5, y: baseline + 9))
        pointer.closeSubpath()
        context.fill(pointer, with: .color(.orange))
        if countingDown {
            var line = Path()
            line.move(to: CGPoint(x: center, y: baseline - 34))
            line.addLine(to: CGPoint(x: center, y: baseline + 1))
            context.stroke(line, with: .color(.white.opacity(0.92)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

@MainActor
enum TimerRulerNativeFeedback {
    /// Public AppKit alignment feedback, supported on haptic-capable hardware.
    /// https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager/feedbackpattern/alignment
    static func perform() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

/// A non-hit-testing native bridge observes only horizontal wheel events over
/// the visible ruler. Click-drag, buttons and text selection remain SwiftUI-owned.
struct TimerRulerWheelInput: NSViewRepresentable {
    var enabled: Bool
    var began: () -> Void = {}
    var changed: (Double) -> Void
    var finished: (Bool) -> Void
    func makeNSView(context: Context) -> WheelView { WheelView() }
    func updateNSView(_ view: WheelView, context: Context) {
        view.enabled = enabled; view.began = began; view.changed = changed; view.finished = finished
    }
    static func dismantleNSView(_ view: WheelView, coordinator: ()) {
        view.stop(); view.began = {}; view.changed = { _ in }; view.finished = { _ in }
    }
    final class WheelView: NSView {
        var enabled = false
        var began: () -> Void = {}
        var changed: (Double) -> Void = { _ in }
        var finished: (Bool) -> Void = { _ in }
        private let lifetime = TimerRulerWheelMonitor()
        private var tracking = false
        private var ownedMomentum = false
        var hasWheelMonitor: Bool { lifetime.token != nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            lifetime.token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // NSEvent intentionally has unavailable Sendable conformance.
                // Assert the documented app-local main-thread callback using a
                // Void return, then return its event outside the generic boundary.
                var result: NSEvent? = event
                MainActor.assumeIsolated {
                    if let self { result = self.filter(event) }
                }
                return result
            }
        }
        func stop() { lifetime.clear(); tracking = false; ownedMomentum = false }
        private func filter(_ event: NSEvent) -> NSEvent? {
            guard enabled, let window, event.window === window, !isHiddenOrHasHiddenAncestor else { return event }
            if event.phase.contains(.began), !tracking { ownedMomentum = false }
            if !event.momentumPhase.isEmpty {
                let consume = ownedMomentum
                if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                    ownedMomentum = false
                }
                return consume ? nil : event
            }
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            guard tracking || inside else { return event }
            if tracking && (event.phase.contains(.ended) || event.phase.contains(.cancelled)) {
                tracking = false
                let cancelled = event.phase.contains(.cancelled)
                let callback = finished
                DispatchQueue.main.async { callback(cancelled) }
                return nil
            }
            guard abs(event.scrollingDeltaX) > 0.05,
                  abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) * 1.3 else { return event }
            let starts = !tracking
            tracking = true; ownedMomentum = true
            let delta = event.hasPreciseScrollingDeltas
                ? TimerRulerInteractionGeometry.acceleratedWheelDelta(event.scrollingDeltaX)
                : event.scrollingDeltaX * 9 // a mouse-wheel notch moves one tick
            let update = changed
            let finish = finished
            let begin = began
            let discrete = event.phase.isEmpty
            // FIFO main-queue order keeps began -> changed -> finished for one
            // sequence ahead of any later sequence's callbacks.
            DispatchQueue.main.async {
                if starts { begin() }
                update(delta)
                if discrete { finish(false) }
            }
            if discrete { tracking = false }
            return nil
        }
    }
}
private final class TimerRulerWheelMonitor: @unchecked Sendable {
    var token: Any?
    func clear() { if let token { NSEvent.removeMonitor(token) }; token = nil }
    deinit { clear() }
}
