import AppKit
import SwiftUI

/// Media-surface mixer. The System row moves the output device volume; app rows
/// move per-app gain through `ApplicationAudioDiscovery`. An app slider is only
/// enabled when moving it changes that app's real output.
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
        VStack(alignment: .leading, spacing: 7) {
            Label("App Volume", systemImage: "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
            switch size {
            case .compact: compact
            case .standard: mixer(limit: 2)
            case .large: ScrollView { mixer(limit: nil) }.scrollIndicators(.never)
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

    /// Icons only; a click mutes or restores that app. Sliders live in larger sizes.
    private var compact: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
            ForEach(rows.prefix(6)) { output in
                Button { toggleMute(output) } label: {
                    VStack(spacing: 2) {
                        AppVolumeIcon(output: output)
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

    private func mixer(limit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            systemRow
            Divider().overlay(.white.opacity(0.08))
            if rows.isEmpty {
                Text("No apps are playing audio").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(limit.map { Array(rows.prefix($0)) } ?? rows) { output in
                AppVolumeRow(name: output.name, icon: AnyView(AppVolumeIcon(output: output)),
                             level: output.gain ?? 1, enabled: output.controlAvailable,
                             onChange: { request($0, for: output) }, onMute: { toggleMute(output) })
            }
        }
    }

    private var systemRow: some View {
        AppVolumeRow(name: "System", icon: AnyView(Image(systemName: "speaker.wave.3.fill").frame(width: 20, height: 20)),
                     level: systemVolume ?? 0, enabled: systemVolume != nil && systemHUD != nil,
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
            Text(issue).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2)
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
    var body: some View {
        Group {
            if let url = output.applicationURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app.fill").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .opacity(output.activity == .idle ? 0.55 : 1)
        .accessibilityHidden(true)
    }
}

/// One native slider row. The slider keeps its own value while dragging so the
/// thumb never jumps back between the request and the verified update.
private struct AppVolumeRow: View {
    let name: String
    let icon: AnyView
    let level: Double
    let enabled: Bool
    let onChange: (Double) -> Void
    let onMute: () -> Void
    @State private var dragValue: Double?

    var body: some View {
        let shown = dragValue ?? level
        HStack(spacing: 6) {
            Button(action: onMute) {
                icon.overlay(alignment: .bottomTrailing) {
                    if shown == 0 {
                        Image(systemName: "speaker.slash.fill").font(.system(size: 7, weight: .bold))
                            .padding(1.5).background(.black.opacity(0.7), in: Circle())
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(shown == 0 ? "Unmute \(name)" : "Mute \(name)")
            Text(name).font(.system(size: 10, weight: .medium)).lineLimit(1).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { shown }, set: { dragValue = $0; onChange($0) }), in: 0...1) { editing in
                if !editing { dragValue = nil }
            }
            .controlSize(.mini)
            .disabled(!enabled)
            .accessibilityLabel("\(name) volume")
            .accessibilityValue("\(Int((shown * 100).rounded())) percent")
            Text("\(Int((shown * 100).rounded()))%")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .opacity(enabled ? 1 : 0.55)
        .help(enabled ? "" : "Turn on Per-App Volume to change this app")
    }
}
