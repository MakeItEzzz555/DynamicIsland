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
    private var minutes: Binding<Int> {
        Binding(get: { TimerRulerScale.minutes(Double(mode == .focus ? focusMinutes : breakMinutes)) }, set: {
            if mode == .focus { focusMinutes = TimerRulerScale.minutes(Double($0)) }
            else { breakMinutes = TimerRulerScale.minutes(Double($0)) }
        })
    }
    private var snapshot: TimerTimingSnapshot { timer.timingSnapshot }

    var body: some View {
        VStack(spacing: 6) {
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
            }
            TimerRuler(snapshot: snapshot, now: { [timer] in timer.clockNow }, minutes: minutes)
                .frame(height: TimerRulerScale.rulerHeight)
            HStack(spacing: 6) {
                control(timer.isRunning ? "pause.fill" : "play.fill", label: timer.isRunning ? "Pause timer" : "Start or resume timer", selected: true) {
                    if timer.isRunning { timer.pause() }
                    else if case .paused = snapshot.phase { timer.resume() }
                    else { timer.start(minutes: minutes.wrappedValue); onStarted() }
                }
                control(settings.timerSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", label: "Timer completion sound", selected: settings.timerSoundEnabled) {
                    settings.timerSoundEnabled.toggle()
                }
                control("stopwatch.fill", label: "Reset timer", selected: false) { timer.stop() }
                Spacer(minLength: 3)
                TimerCountdownLabel(snapshot: snapshot, now: { [timer] in timer.clockNow }, selectedMinutes: minutes.wrappedValue)
            }
        }
        .padding(showsPanel ? 12 : 4)
        .frame(maxWidth: .infinity)
        .background {
            if showsPanel { RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.035)) }
        }
        .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.15), value: storedMode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus and break timer")
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
    let selectedMinutes: Int
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let interval = TimerCountdownPresentation.frameInterval(snapshot: snapshot, displayScale: displayScale)
        TimelineView(.animation(minimumInterval: interval ?? 1, paused: interval == nil)) { _ in
            let text = TimerCountdownPresentation.isCountingDown(snapshot)
                ? TimerCountdownPresentation.displayText(remaining: TimerCountdownPresentation.remainingSeconds(snapshot, now: now()))
                : "\(selectedMinutes):00"
            Text(text)
                .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.75)
                .contentTransition(.identity)
                .accessibilityLabel("Timer, \(text)")
        }
    }
}

/// One Canvas, bounded tick count, no per-tick views. The redraw loop exists
/// only while counting down and visible; otherwise the ruler is static.
struct TimerRuler: View {
    let snapshot: TimerTimingSnapshot
    let now: () -> Duration
    @Binding var minutes: Int
    @State private var dragOrigin: Int?
    @State private var visible = false
    @Environment(\.displayScale) private var displayScale

    private var countingDown: Bool { TimerCountdownPresentation.isCountingDown(snapshot) }

    var body: some View {
        let interval = TimerCountdownPresentation.frameInterval(snapshot: snapshot, displayScale: displayScale)
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: interval ?? 1, paused: interval == nil || !visible)) { _ in
                let value = TimerCountdownPresentation.rulerValue(snapshot: snapshot, now: now(), selectedMinutes: minutes)
                Canvas { context, size in draw(in: &context, size: size, value: value) }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3).onChanged { change in
                guard !countingDown else { return }
                if dragOrigin == nil { dragOrigin = minutes }
                minutes = TimerRulerScale.dragged(from: dragOrigin ?? minutes, translation: change.translation.width)
            }.onEnded { _ in dragOrigin = nil })
            .onTapGesture(coordinateSpace: .local) { location in
                guard !countingDown else { return }
                minutes = TimerRulerScale.minutes(Double(minutes) + (location.x - geometry.size.width / 2) / TimerRulerScale.pointsPerMinute)
            }
        }
        .background { NativeVisualVisibility { visible = $0 }.allowsHitTesting(false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(countingDown ? "Timer countdown" : "Timer duration")
        .accessibilityValue(TimerCountdownPresentation.accessibilityValue(snapshot: snapshot, now: now(), selectedMinutes: minutes))
        .focusable(!countingDown)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            guard !countingDown else { return .ignored }
            minutes = TimerRulerScale.minutes(Double(minutes - 1)); return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !countingDown else { return .ignored }
            minutes = TimerRulerScale.minutes(Double(minutes + 1)); return .handled
        }
        .accessibilityAdjustableAction { direction in
            guard !countingDown else { return }
            minutes = TimerRulerScale.minutes(Double(minutes + (direction == .increment ? 1 : -1)))
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, value: Double) {
        let center = size.width / 2
        let baseline = TimerRulerScale.tickBaseline
        let lowerBound = countingDown ? 0 : 1
        let selected = countingDown ? nil : minutes
        for minute in TimerRulerScale.visibleMinutes(value: value, width: size.width, lowerBound: lowerBound) {
            let x = TimerRulerScale.x(forMinute: minute, value: value, center: center)
            guard x >= -1, x <= size.width + 1 else { continue }
            let tick = TimerRulerScale.tick(forMinute: minute)
            let distance = abs(x - center) / max(center, 1)
            // Elapsed time (right of the pointer) recedes while counting down.
            let elapsed = countingDown && x > center + 0.5
            let opacity = max(0.10, 1 - distance * 0.85) * (elapsed ? 0.45 : 1)
            let isSelected = minute == selected
            var path = Path()
            path.move(to: CGPoint(x: x, y: baseline - tick.height))
            path.addLine(to: CGPoint(x: x, y: baseline))
            context.stroke(path, with: .color((isSelected ? Color.white : Color.orange).opacity(opacity)),
                           style: StrokeStyle(lineWidth: isSelected ? 2 : (tick.labelled ? 1.6 : 1.2), lineCap: .round))
            if tick.labelled {
                context.draw(Text("\(minute)").font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .orange.opacity(opacity)),
                             at: CGPoint(x: x, y: 7))
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
            line.move(to: CGPoint(x: center, y: baseline - TimerRulerScale.majorTickHeight - 2))
            line.addLine(to: CGPoint(x: center, y: baseline + 1))
            context.stroke(line, with: .color(.white.opacity(0.92)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}
