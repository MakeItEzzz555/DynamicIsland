import SwiftUI

/// The reference's compact Focus/Break timer: a travelling minute ruler under
/// a fixed pointer, with persistent presets and the existing monotonic timer.
struct FocusTimerView: View {
    @ObservedObject var timer: TimerController
    @ObservedObject var settings: AppSettings
    var onStarted: () -> Void = {}
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
    private var text: String { timer.remainingSeconds > 0 ? timer.displayText : "\(minutes.wrappedValue):00" }

    var body: some View {
        VStack(spacing: 7) {
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
            MinuteRuler(minutes: minutes)
                .frame(height: 42)
                .disabled(timer.isRunning)
                .opacity(timer.isRunning ? 0.65 : 1)
            HStack(spacing: 6) {
                control(timer.isRunning ? "pause.fill" : "play.fill", label: timer.isRunning ? "Pause timer" : "Start or resume timer", selected: true) {
                    if timer.isRunning { timer.pause() }
                    else if timer.remainingSeconds > 0 { timer.resume() }
                    else { timer.start(minutes: minutes.wrappedValue); onStarted() }
                }
                control(settings.timerSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", label: "Timer completion sound", selected: settings.timerSoundEnabled) {
                    settings.timerSoundEnabled.toggle()
                }
                control("stopwatch.fill", label: "Reset timer", selected: false) { timer.stop() }
                Spacer(minLength: 3)
                Text(text)
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityLabel("Timer, \(text)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
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

struct MinuteRuler: View {
    @Binding var minutes: Int
    @State private var dragOrigin: Int?
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let center = size.width / 2
                for minute in max(1, minutes - 40)...min(180, minutes + 40) {
                    let x = center + CGFloat(minute - minutes) * TimerRulerScale.pointsPerMinute
                    guard x >= 0, x <= size.width else { continue }
                    let major = minute.isMultiple(of: 5)
                    let distance = abs(x - center) / max(center, 1)
                    let opacity = max(0.12, 1 - distance * 0.85)
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: major ? 19 : 23))
                    tick.addLine(to: CGPoint(x: x, y: 33))
                    context.stroke(tick, with: .color((minute == minutes ? Color.white : Color.orange).opacity(opacity)), style: StrokeStyle(lineWidth: minute == minutes ? 2 : 1.3, lineCap: .round))
                    if major {
                        context.draw(Text("\(minute)").font(.system(size: 9, weight: .semibold)).foregroundColor(minute == minutes ? .white : .orange.opacity(opacity)), at: CGPoint(x: x, y: 9))
                    }
                }
                var pointer = Path()
                pointer.move(to: CGPoint(x: center, y: 36))
                pointer.addLine(to: CGPoint(x: center - 3, y: 41))
                pointer.addLine(to: CGPoint(x: center + 3, y: 41))
                pointer.closeSubpath()
                context.fill(pointer, with: .color(.orange))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                if dragOrigin == nil { dragOrigin = minutes }
                minutes = TimerRulerScale.dragged(from: dragOrigin!, translation: value.translation.width)
            }.onEnded { _ in dragOrigin = nil })
            .onTapGesture(coordinateSpace: .local) { location in
                minutes = TimerRulerScale.minutes(Double(minutes) + (location.x - geometry.size.width / 2) / TimerRulerScale.pointsPerMinute)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer duration")
        .accessibilityValue("\(minutes) minutes")
        .focusable()
        .onKeyPress(.leftArrow) { minutes = TimerRulerScale.minutes(Double(minutes - 1)); return .handled }
        .onKeyPress(.rightArrow) { minutes = TimerRulerScale.minutes(Double(minutes + 1)); return .handled }
        .accessibilityAdjustableAction { direction in
            minutes = TimerRulerScale.minutes(Double(minutes + (direction == .increment ? 1 : -1)))
        }
    }
}
