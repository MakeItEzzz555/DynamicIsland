import AppKit
import SwiftUI

/// Media-surface mixer. The System row moves the output device volume; app rows
/// move per-application gain through `ApplicationAudioDiscovery`, one row per
/// application (its helper processes are grouped under it). An app slider is
/// only enabled when moving it changes that app's real output.
struct AppVolumeWidgetView: View {
    @ObservedObject var discovery: ApplicationAudioDiscovery
    @ObservedObject var settings: AppSettings
    /// Nil in Settings previews: the System row is then read-only.
    let systemHUD: SystemHUDController?

    @Environment(\.workspaceWidgetPlacement) private var placement
    @State private var systemVolume: Double?
    @State private var levelsBeforeMute: [String: Double] = [:]

    private var size: WidgetPresentationSize { placement.presentationSize }
    private var enabled: Bool { settings.perAppVolumeEnabled }
    private var rows: [ApplicationAudioOutput] {
        discovery.outputs.sorted { ($0.activity == .idle ? 1 : 0, $0.name) < ($1.activity == .idle ? 1 : 0, $1.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            switch size {
            case .compact: compact
            case .standard: mixer(limit: 2, pillHeight: 26, spacing: 4)
            case .large: ScrollView { mixer(limit: nil, pillHeight: 32, spacing: 6) }.scrollIndicators(.never)
            }
            Spacer(minLength: 0)
            footer
        }
        .foregroundStyle(.white).padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .task(id: enabled) {
            systemVolume = SystemHUDController.readSystemVolume()?.value
            // Listeners drive updates while gain is on; read-only mode refreshes while visible.
            repeat {
                try? await discovery.refresh()
                if enabled { break }
                try? await Task.sleep(for: .seconds(2))
            } while !Task.isCancelled
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label("App Volume", systemImage: "speaker.wave.2.fill").font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            // Stays until the feature has passed real-hardware listening acceptance. The
            // square size has no room for it; its enable button and help keep the label.
            if size != .compact {
                Text("Experimental").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 1.5).background(.white.opacity(0.08), in: Capsule())
            }
        }
    }

    /// Icons only; a click mutes or restores that app. Sliders live in larger sizes.
    private var compact: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
            ForEach(rows.prefix(6)) { output in
                Button { toggleMute(output) } label: {
                    VStack(spacing: 2) {
                        AppVolumeIcon(output: output, side: 20)
                            .overlay(alignment: .bottomTrailing) {
                                if (output.gain ?? 1) == 0 {
                                    Image(systemName: "speaker.slash.fill").font(.system(size: 8, weight: .bold))
                                        .padding(2).background(.black.opacity(0.7), in: Circle())
                                }
                            }
                        Text(output.controlAvailable ? percent(output.gain ?? 1) : "–")
                            .font(.system(size: 8, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!output.controlAvailable)
                .help(output.controlAvailable ? "\(output.name): \(percent(output.gain ?? 1)). Click to mute or restore." : output.name)
                .accessibilityLabel(output.name)
                .accessibilityValue(output.controlAvailable ? percent(output.gain ?? 1) : "Volume control off")
            }
        }
    }

    private func mixer(limit: Int?, pillHeight: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            systemRow(height: pillHeight)
            if rows.isEmpty {
                Text("No apps are playing audio").font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 4)
            }
            ForEach(limit.map { Array(rows.prefix($0)) } ?? rows) { output in
                AppVolumePill(name: output.name, icon: AnyView(AppVolumeIcon(output: output, side: pillHeight - 8)),
                              level: output.gain ?? 1, enabled: output.controlAvailable, style: .app, height: pillHeight,
                              onChange: { request($0, for: output) }, onMute: { toggleMute(output) })
                    .help(output.controlAvailable ? "" : "Turn on Per-App Volume to change this app")
            }
        }
    }

    private func systemRow(height: CGFloat) -> some View {
        AppVolumePill(name: "System", icon: AnyView(Image(systemName: "speaker.wave.3.fill").font(.system(size: height * 0.42, weight: .semibold))
                        .frame(width: height - 8, height: height - 8)),
                      level: systemVolume ?? 0, enabled: systemVolume != nil && systemHUD != nil, style: .system, height: height,
                      onChange: { value in systemVolume = systemHUD?.setOutputVolume(value)?.value ?? systemVolume },
                      onMute: {
                          let current = systemVolume ?? 0
                          if current > 0 { levelsBeforeMute["system"] = current }
                          let next = current > 0 ? 0 : levelsBeforeMute.removeValue(forKey: "system") ?? 0.5
                          systemVolume = systemHUD?.setOutputVolume(next)?.value ?? systemVolume
                      })
            .help("Output device volume; affects every app")
    }

    @ViewBuilder
    private var footer: some View {
        if let issue = discovery.routingIssue {
            Text(issue).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        } else if !enabled {
            Button { settings.perAppVolumeEnabled = true } label: {
                Text("Turn On Per-App Volume (Experimental)").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(.cyan)
            .help("Routes an app below 100% through DynamicIsland. macOS asks for System Audio Recording the first time.")
        }
    }

    private func request(_ level: Double, for output: ApplicationAudioOutput) {
        Task { _ = await discovery.requestGain(level, application: output.identity) }
    }

    private func toggleMute(_ output: ApplicationAudioOutput) {
        let key = output.bundleIdentifier ?? "\(output.identity.processObjectIDs)"
        let current = output.gain ?? 1
        if current == 0 {
            request(levelsBeforeMute.removeValue(forKey: key) ?? 1, for: output)
        } else {
            levelsBeforeMute[key] = current
            request(0, for: output)
        }
    }

    private func percent(_ level: Double) -> String { "\(Int((level * 100).rounded()))%" }
}

private struct AppVolumeIcon: View {
    let output: ApplicationAudioOutput
    let side: CGFloat
    var body: some View {
        Group {
            if let url = output.applicationURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app.fill").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .opacity(output.activity == .idle ? 0.55 : 1)
        .accessibilityHidden(true)
    }
}

/// A horizontal pill slider: icon and name at the left, the exact percentage at
/// the right, and a filled track that is the real level. The whole pill is the
/// drag target (press anywhere to jump there, then scrub); pressing the icon
/// without moving mutes or restores. The pill keeps its own value while the
/// pointer is down so the fill is glued to it, then follows the model again.
struct AppVolumePill: View {
    enum Style { case app, system }

    let name: String
    let icon: AnyView
    let level: Double
    let enabled: Bool
    let style: Style
    let height: CGFloat
    let onChange: (Double) -> Void
    let onMute: () -> Void

    @State private var dragValue: Double?
    @State private var pressedIcon = false
    @State private var scrubbing = false
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.timerRulerInteractionRegistration) private var interactionRegistration
    @State private var interactionOwner = UUID()
    @State private var measuredFrame = CGRect.zero

    /// Presses inside this leading zone (the icon) toggle mute unless they turn into a drag.
    private var iconZone: CGFloat { height + 2 }
    private static let keyStep = 0.05

    var body: some View {
        let shown = dragValue ?? level
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(trackColor)
                Rectangle().fill(fillColor).frame(width: proxy.size.width * shown)
                    .animation(fillAnimation, value: shown)
                content(shown)
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(outline, lineWidth: focused ? 1.5 : 1))
            .contentShape(Capsule())
            .scaleEffect(x: 1, y: dragValue != nil && !reduceMotion ? 1.06 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: dragValue != nil)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag($0, width: proxy.size.width) }
                .onEnded { _ in endDrag() })
        }
        .frame(height: height)
        // Own horizontal drags: the island's swipe/scroll navigation skips registered control frames.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(IslandCanvasCoordinateSpace.name)) } action: { frame in
            measuredFrame = frame
            DispatchQueue.main.async { interactionRegistration.report(interactionOwner, interactionRegistration.enabled ? frame : nil) }
        }
        .onChange(of: interactionRegistration.enabled) { _, on in interactionRegistration.report(interactionOwner, on ? measuredFrame : nil) }
        .onDisappear { interactionRegistration.report(interactionOwner, nil) }
        .opacity(enabled ? 1 : 0.55)
        .onHover { hovering = enabled && $0 }
        .focusable(enabled)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .downArrow, .upArrow, .home, .end]) { press in
            guard enabled else { return .ignored }
            switch press.key {
            case .leftArrow, .downArrow: step(-1)
            case .rightArrow, .upArrow: step(1)
            case .home: set(0)
            default: set(1)
            }
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) volume")
        .accessibilityValue("\(Int((shown * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: shown == 0 ? "Unmute" : "Mute") { if enabled { onMute() } }
    }

    private func content(_ shown: Double) -> some View {
        HStack(spacing: 6) {
            icon
                .overlay(alignment: .bottomTrailing) {
                    if shown == 0 {
                        Image(systemName: "speaker.slash.fill").font(.system(size: 7, weight: .bold))
                            .padding(1.5).background(.black.opacity(0.75), in: Circle())
                    }
                }
            Text(name).font(.system(size: height > 28 ? 12 : 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text("\(Int((shown * 100).rounded()))%")
                .font(.system(size: height > 28 ? 12 : 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
        }
        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5) // legible over the fill edge
        .padding(.leading, 4).padding(.trailing, 10)
        .allowsHitTesting(false)
    }

    // MARK: Look

    private var trackColor: Color {
        let base = style == .system ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.08)
        return hovering ? base.opacity(1.3) : base
    }
    private var fillColor: Color {
        let level = hovering || dragValue != nil ? 1.0 : 0.85
        return (style == .system ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.26)).opacity(level)
    }
    private var outline: Color {
        focused ? Color.accentColor : .white.opacity(hovering ? 0.22 : 0.10)
    }
    /// Direct manipulation is 1:1; only model-driven moves (mute, keys, external) glide.
    private var fillAnimation: Animation? { reduceMotion || dragValue != nil ? nil : .smooth(duration: 0.22) }

    // MARK: Input

    private func drag(_ value: DragGesture.Value, width: CGFloat) {
        guard enabled, width > 0 else { return }
        if !pressedIcon && !scrubbing { pressedIcon = value.startLocation.x < iconZone }
        if pressedIcon && !scrubbing {
            guard abs(value.translation.width) >= 4 else { return } // still a possible mute tap
        }
        scrubbing = true
        set(Self.level(atX: value.location.x, width: width))
    }

    private func endDrag() {
        if pressedIcon && !scrubbing && enabled { onMute() }
        pressedIcon = false; scrubbing = false; dragValue = nil
    }

    private func set(_ value: Double) {
        dragValue = value
        onChange(value)
    }

    private func step(_ direction: Double) {
        let next = min(max(((dragValue ?? level) + direction * Self.keyStep) * 20, 0), 20).rounded() / 20
        onChange(next)
    }

    /// Pointer x → level; the last 1.5% at either end snaps to 0% / 100%.
    static func level(atX x: CGFloat, width: CGFloat) -> Double {
        let fraction = Double(min(max(x / max(width, 1), 0), 1))
        return fraction < 0.015 ? 0 : fraction > 0.985 ? 1 : fraction
    }
}
