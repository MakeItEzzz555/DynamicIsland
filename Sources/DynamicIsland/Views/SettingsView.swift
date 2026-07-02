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
