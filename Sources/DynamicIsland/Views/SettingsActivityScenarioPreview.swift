import SwiftUI

enum SettingsActivityPreviewMode: String, CaseIterable, Identifiable {
    case multi = "Multi", highAlert = "High Alert"
    var id: Self { self }
    var scenario: LiveActivityLayoutPreviewScenario { self == .multi ? .mediaBatteryTimer : .permissionHover }
}

struct SettingsActivityScenarioPreview: View {
    @ObservedObject var settings: AppSettings
    var dependencies: SettingsPreviewDependencies?
    @State private var scenario: LiveActivityLayoutPreviewScenario = .mediaBatteryTimer
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ForEach(SettingsActivityPreviewMode.allCases) { mode in
                    Button {
                        scenario = mode.scenario
                    } label: {
                        Label(mode.rawValue, systemImage: mode == .multi ? "square.stack.3d.up" : "exclamationmark.shield")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.bordered)
                        .tint(scenario == mode.scenario ? .accentColor : .secondary)
                        .accessibilityAddTraits(scenario == mode.scenario ? [.isSelected] : [])
                        .accessibilityHint("Switches this sample preview; does not start a live activity")
                }
            }
            LiveActivityLayoutSettingsPreview(settings: settings, dependencies: dependencies, scenarioSelection: $scenario)
            Text("Sample scenarios only. Multi uses the saved sidecar rules; High Alert shows a sample permission approval through the production presentation.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SettingsExternalDisplayChoices: View {
    @Binding var selection: ExternalDisplayVisibility
    var navigation: SettingsNavigationStore? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On external displays").font(.callout)
            HStack(spacing: 10) {
                ForEach(ExternalDisplayVisibility.allCases) { choice in
                    Button { selection = choice } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 7).fill(.blue.gradient).frame(height: 66)
                                if choice != .never {
                                    Capsule().fill(.black.opacity(choice == .whenActive ? 0.65 : 1))
                                        .frame(width: 44, height: 9).padding(.top, 4)
                                }
                            }
                            Text(choice.title).font(.caption)
                        }.padding(6).frame(maxWidth: .infinity)
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selection == choice ? Color.accentColor : .clear, lineWidth: 2))
                    }.buttonStyle(.plain).accessibilityLabel(choice.title)
                        .accessibilityAddTraits(selection == choice ? [.isSelected] : [])
                        .background {
                            if let navigation {
                                SettingsNativeControlAnchor(identifier: "settings.external-display." + choice.rawValue, navigation: navigation)
                            }
                        }
                }
            }
        }
    }
}
