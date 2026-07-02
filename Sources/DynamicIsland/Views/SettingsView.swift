import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shortcuts: ShortcutsStore

    var body: some View {
        Form {
            Section("Overlay") {
                Toggle("Enable overlay", isOn: $settings.overlayEnabled)
                Toggle("Launch at login", isOn: Binding {
                    settings.launchAtLogin
                } set: { enabled in
                    settings.launchAtLogin = enabled
                    LaunchAtLoginController.setEnabled(enabled)
                })
                LabeledContent("Island size") {
                    Slider(value: $settings.islandScale, in: 0.82...1.22)
                        .frame(width: 220)
                }
                LabeledContent("Hover delay") {
                    Slider(value: $settings.hoverDelay, in: 0.0...0.6)
                        .frame(width: 220)
                }
                LabeledContent("Auto-collapse") {
                    Slider(value: $settings.autoCollapseDelay, in: 1.0...10.0)
                        .frame(width: 220)
                }
                LabeledContent("Animation") {
                    Slider(value: $settings.animationIntensity, in: 0.62...0.95)
                        .frame(width: 220)
                }
            }

            Section("Modules") {
                Toggle("Media", isOn: $settings.mediaEnabled)
                Toggle("File Shelf", isOn: $settings.fileShelfEnabled)
                Toggle("Shortcuts", isOn: $settings.shortcutsEnabled)
            }

            Section("Shortcuts") {
                ForEach(shortcuts.shortcuts) { shortcut in
                    ShortcutEditorRow(
                        shortcut: shortcut,
                        onUpdate: shortcuts.update,
                        onRemove: shortcuts.remove
                    )
                }
                Button {
                    shortcuts.addDefault()
                } label: {
                    Label("Add Shortcut", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .padding(18)
        .frame(width: 500, height: 520)
    }
}

struct ShortcutEditorRow: View {
    @State var shortcut: LauncherShortcut
    let onUpdate: (LauncherShortcut) -> Void
    let onRemove: (LauncherShortcut) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Title", text: binding(\.title))
                TextField("SF Symbol", text: binding(\.symbolName))
                    .frame(width: 120)
                Button {
                    onRemove(shortcut)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove shortcut")
            }
            TextField("Path or URL", text: binding(\.target))
        }
    }

    private func binding(_ keyPath: WritableKeyPath<LauncherShortcut, String>) -> Binding<String> {
        Binding {
            shortcut[keyPath: keyPath]
        } set: { newValue in
            shortcut[keyPath: keyPath] = newValue
            onUpdate(shortcut)
        }
    }
}
