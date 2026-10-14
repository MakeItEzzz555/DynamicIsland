import SwiftUI
import ServiceManagement

/// Original, offline artwork and interaction; never controls the user's player.
struct SettingsDemoPlayer: View {
    @State private var playing = false
    @State private var progress = 0.35
    @State private var output = "This Mac"
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "waveform").font(.system(size: 28))
                    .frame(width: 62, height: 62)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Northern Lights").font(.headline)
                    Text("DynamicIsland preview").font(.caption).opacity(0.7)
                }
                Spacer()
            }
            Slider(value: $progress, in: 0...1).controlSize(.small)
                .accessibilityLabel("Preview playback position")
                .accessibilityValue("\(Int(progress * 100)) percent")
            HStack(spacing: 22) {
                Button { progress = max(0, progress - 0.1) } label: { Image(systemName: "backward.fill") }
                    .accessibilityLabel("Seek backward in preview")
                Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                    .accessibilityLabel(playing ? "Pause preview" : "Play preview")
                Button { progress = min(1, progress + 0.1) } label: { Image(systemName: "forward.fill") }
                    .accessibilityLabel("Seek forward in preview")
                Menu {
                    Picker("Preview output", selection: $output) {
                        Text("This Mac").tag("This Mac")
                        Text("Preview headphones").tag("Preview headphones")
                    }
                } label: { Image(systemName: output == "This Mac" ? "laptopcomputer" : "headphones") }
                    .accessibilityLabel("Preview output: \(output)")
            }.buttonStyle(.borderless).font(.title3)
            Text("Interactive sample · No live playback").font(.caption2).opacity(0.7)
        }
        .foregroundStyle(.white).tint(.white)
        .padding(24).frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color.indigo, Color.blue.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Offline Now Playing preview")
    }
}

struct SettingsShortcutStrip: View {
    @ObservedObject var store: ShortcutsStore
    @State private var editing = false
    @State private var draft: [LauncherShortcut] = []
    @State private var dropTarget: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ForEach(Array(store.shortcuts.prefix(4))) { shortcut in
                    Button { beginEditing() } label: {
                        Image(systemName: shortcut.symbolName).font(.title3)
                            .frame(width: 42, height: 42).background(.white.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel("Edit \(shortcut.title)")
                }
                if store.shortcuts.count < 4 {
                    Button(action: beginEditing) { Image(systemName: "plus").frame(width: 42, height: 42) }
                        .accessibilityLabel("Add app shortcut")
                }
            }.buttonStyle(.borderless).foregroundStyle(.white)
            Text("Select a tile to edit. Preview tiles never launch an app.").font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .padding(24).frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 16) {
                Text("App shortcuts").font(.title2.bold())
                ScrollView {
                    ForEach(Array(draft.enumerated()), id: \.element.id) { index, shortcut in
                        VStack {
                            ShortcutEditorRow(shortcut: shortcut, onUpdate: { updated in
                                if let i = draft.firstIndex(where: { $0.id == updated.id }) { draft[i] = updated }
                            }, onRemove: { item in draft.removeAll { $0.id == item.id } })
                            HStack {
                                Image(systemName: "line.3.horizontal").frame(width: 28, height: 28)
                                    .draggable("dynamicisland-shortcut:" + shortcut.id.uuidString)
                                    .accessibilityLabel("Drag \(shortcut.title) to reorder")
                                Button("Move left") { draft.swapAt(index, index - 1) }.disabled(index == 0)
                                Button("Move right") { draft.swapAt(index, index + 1) }.disabled(index + 1 == draft.count)
                            }.accessibilityElement(children: .contain).accessibilityLabel("Reorder \(shortcut.title)")
                        }.padding(.bottom, 12)
                        .background(dropTarget == shortcut.id ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                        .dropDestination(for: String.self) { items, _ in
                            guard items.count == 1 else { return false }
                            var reordered = draft
                            guard SettingsShortcutReorder.move(items[0], before: shortcut.id, in: &reordered) else { return false }
                            withAnimation(WorkspaceEditorMotion.reorder(reduceMotion: reduceMotion)) { draft = reordered }
                            return true
                        } isTargeted: { targeted in dropTarget = targeted ? shortcut.id : nil }
                    }
                }
                Button("Add shortcut") { draft.append(LauncherShortcut(title: "New shortcut", target: "", symbolName: "link")) }
                HStack {
                    Spacer()
                    Button("Cancel") { editing = false }.keyboardShortcut(.cancelAction)
                    Button("Apply") { store.shortcuts = draft; editing = false }
                        .disabled(draft.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 600, height: 480)
        }
    }
    private func beginEditing() { draft = store.shortcuts; editing = true }
}

struct SettingsClipboardHistoryControls: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: ClipboardHistoryStore
    @State private var confirmingClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("History", value: settings.clipboardHistoryNoEntryLimit
                ? "\(history.entries.count) items saved"
                : "\(history.entries.count) saved · unpinned limit \(settings.clipboardHistoryMaximumItems)")
            Stepper("History limit: \(settings.clipboardHistoryMaximumItems)", value: $settings.clipboardHistoryMaximumItems, in: 10...200)
                .disabled(settings.clipboardHistoryNoEntryLimit)
            Toggle("No entry limit", isOn: $settings.clipboardHistoryNoEntryLimit)
            Picker("Keep unpinned entries for", selection: $settings.clipboardHistoryRetentionDays) {
                Text("Forever").tag(0)
                Text("1 day").tag(1)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                if ![0, 1, 7, 30].contains(settings.clipboardHistoryRetentionDays) {
                    Text("\(settings.clipboardHistoryRetentionDays) days").tag(settings.clipboardHistoryRetentionDays)
                }
            }
            Text("Favorites stay pinned first. Duplicate content updates its existing entry. Memory safety limits still apply with no entry limit.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Clear all except pinned…") { confirmingClear = true }
                .disabled(!history.entries.contains { !$0.isFavorite })
        }
        .disabled(!settings.clipboardHistoryEnabled)
        .confirmationDialog("Clear unpinned history?", isPresented: $confirmingClear) {
            Button("Clear unpinned items", role: .destructive) { history.clearHistoryExceptPinned() }
        } message: { Text("Pinned favorites and tags are preserved. This cannot be undone.") }
    }
}

enum SettingsResetScope {
    case all, shell, modules
    var title: String {
        switch self { case .all: "Reset preferences?"; case .shell: "Reset Shell & Motion?"; case .modules: "Reset module preferences?" }
    }
}

struct SettingsLoginItemRow: View {
    @ObservedObject var settings: AppSettings
    @State private var status: SMAppService.Status?
    @State private var refreshGeneration = 0
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: $settings.launchAtLoginEnabled)
            Text(statusLabel).font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            if status == .requiresApproval || status == .notFound || error != nil {
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        .task(id: refreshGeneration) {
            let current = await LaunchAtLoginController.statusReader.read()
            guard !Task.isCancelled else { return }
            status = current; error = LaunchAtLoginController.lastError
        }
        .onChange(of: settings.launchAtLoginEnabled) { _, _ in refreshGeneration += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshGeneration += 1 }
    }
    private var statusLabel: String {
        guard let status else { return "Checking macOS login item…" }
        return switch status {
        case .enabled: "Enabled in macOS"
        case .notRegistered: "Not enabled in macOS"
        case .requiresApproval: "Approval required in Login Items settings"
        case .notFound: "Login item is unavailable in this build"
        @unknown default: "Login item status is unavailable"
        }
    }
}

enum SettingsShortcutReorder {
    static func move(_ payload: String, before destination: UUID, in shortcuts: inout [LauncherShortcut]) -> Bool {
        let prefix = "dynamicisland-shortcut:"
        guard payload.hasPrefix(prefix), let source = UUID(uuidString: String(payload.dropFirst(prefix.count))), source != destination,
              let sourceIndex = shortcuts.firstIndex(where: { $0.id == source }),
              shortcuts.contains(where: { $0.id == destination }) else { return false }
        let shortcut = shortcuts.remove(at: sourceIndex)
        guard let destinationIndex = shortcuts.firstIndex(where: { $0.id == destination }) else { return false }
        shortcuts.insert(shortcut, at: destinationIndex)
        return true
    }
}

/// The production editor keeps its own draft transaction. Sample widgets cannot
/// start a provider, a file operation or playback; only explicit Done saves layout.
struct SettingsWorkspaceLayoutPreview: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: WorkspaceCustomizationStore
    let dependencies: SettingsPreviewDependencies
    let navigation: SettingsNavigationStore
    @StateObject private var transaction = WorkspaceCustomizationStore(defaults: SettingsPreviewDefaults())
    @State private var editing = false
    @State private var showingEditor = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IslandShellSettingsPreview(settings: settings, dependencies: dependencies)
            Button("Edit Custom Shelf…") {
                transaction.commit(store.configuration)
                editing = true; showingEditor = true
            }.background(SettingsNativeControlAnchor(identifier: "settings.workspace-editor", navigation: navigation)).accessibilityHint("Open the production widget editor; Cancel preserves the current layout")
        }
        .sheet(isPresented: $showingEditor, onDismiss: { editing = false }) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Customize Shelf").font(.title2.bold())
                Text("Drag to arrange horizontally or vertically. Use each widget’s Arrange menu for keyboard controls. Done saves; Cancel discards.")
                    .font(.caption).foregroundStyle(.secondary)
                IslandWidgetEditor(store: transaction, surface: .media, editing: $editing,
                    eligibleWidgets: WorkspaceWidgetAvailability.eligible(on: .media, settings: settings),
                    extraMotion: !settings.reduceExtraMotion,
                    onApplyCompleted: { store.commit(transaction.configuration); showingEditor = false }) { region, height in
                        let presentation = SettingsPreviewPresentation(settings: settings, configuration: transaction.configuration)
                        return AnyView(GeometryReader { geometry in
                            SettingsPreviewWidgetGrid(settings: settings, dependencies: dependencies,
                                presentation: presentation, regionOverride: region,
                                sizeOverride: CGSize(width: geometry.size.width, height: height))
                                .disabled(true).allowsHitTesting(false)
                        })
                    }
                    .frame(height: 360)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
            }.padding(24).frame(width: 720, height: 470)
            .onChange(of: editing) { _, active in if !active { showingEditor = false } }
        }
    }
}

struct SettingsWidgetIconsPreview: View {
    @ObservedObject var settings: AppSettings
    let configure: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ForEach(ExpandedIslandPage.allCases.filter { page in
                    switch page { case .island: true; case .tray: settings.showTrayTab; case .timer: settings.showTimerTab; case .stats: settings.showStatsTab; case .tools: settings.showToolsTab; case .agents: settings.showAgentsTab; case .messages: false }
                }, id: \.self) { page in
                    Button(action: configure) { Image(systemName: page.symbolName).font(.title3).frame(width: 36, height: 36) }
                        .accessibilityLabel("Configure \(page.title) icon")
                }
            }.buttonStyle(.borderless).foregroundStyle(.white)
            Text("Widget icons · Select to configure visibility and navigation").font(.caption).foregroundStyle(.white.opacity(0.8))
        }.padding(24).frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsAnimationSpeedChoices: View {
    @Binding var selection: AnimationPreset
    private let order: [AnimationPreset] = [.slow, .normal, .subtle, .instant]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Animation speed")
            HStack(spacing: 8) {
                ForEach(order) { preset in
                    Button { selection = preset } label: {
                        VStack(spacing: 8) {
                            Image(systemName: symbol(preset)).font(.title2)
                            Text(preset.displayName).font(.caption)
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(selection == preset ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selection == preset ? Color.accentColor : .secondary.opacity(0.2), lineWidth: selection == preset ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel("\(preset.displayName) animation speed")
                        .accessibilityAddTraits(selection == preset ? .isSelected : [])
                }
            }
        }
    }
    private func symbol(_ preset: AnimationPreset) -> String {
        switch preset { case .slow: "tortoise.fill"; case .normal: "figure.walk"; case .subtle: "dog.fill"; case .instant: "hare.fill" }
    }
}
