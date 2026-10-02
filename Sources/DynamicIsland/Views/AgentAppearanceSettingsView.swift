import SwiftUI

struct AgentAppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var orbPreviewState: AgentOrbVisualState = .working
    @State private var avatarAdvanced = false
    @State private var voiceAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
            Divider()
            presenceControls
            Divider()
            avatarControls
            Divider()
            voiceControls
            Divider()
            sendControls

            HStack {
                Spacer()
                Button("Reset appearance") {
                    settings.resetAgentVisualPreferences()
                }
            }
        }
    }

    private var preview: some View {
        HStack(spacing: 18) {
            VStack(spacing: 5) {
                AgentOrbView(
                    state: orbPreviewState,
                    size: 48,
                    speed: settings.agentVisualPreferences.orbSpeed
                )
                Text("Orb")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 5) {
                BotAvatarView(
                    sessionID: nil,
                    configuration: settings.agentVisualPreferences.avatar,
                    state: .working,
                    overrideType: settings.agentVisualPreferences.avatar.type
                )
                Text("Avatar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Voice")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                VoiceBeamView(
                    level: { 0.48 },
                    processing: false,
                    configuration: settings.agentVisualPreferences.voice,
                    height: 28
                )
                .frame(width: 150)
                .background(Color.black.opacity(0.55), in: Capsule())
            }

            Spacer()

            VStack(spacing: 5) {
                MetalSendButton(
                    configuration: settings.agentVisualPreferences.metal,
                    isEnabled: true,
                    action: {}
                )
                Text("Send")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .environment(\.agentVisualPreferences, settings.agentVisualPreferences)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent appearance preview")
    }

    private var presenceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agent Presence")
                .font(.system(size: 12, weight: .semibold))

            Picker("Indicator", selection: visualBinding(\.indicatorStyle)) {
                ForEach(AgentPresenceIndicatorStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }

            Picker("Orb preview state", selection: $orbPreviewState) {
                ForEach(AgentOrbVisualState.allCases) { state in
                    Text(state.displayName).tag(state)
                }
            }

            settingsSlider(
                "Orb speed",
                value: visualBinding(\.orbSpeed),
                range: 0.25...2,
                format: "%.2fx"
            )
        }
    }

    private var avatarControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bot Avatar")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle("Enabled", isOn: visualBinding(\.avatar.enabled))
                    .labelsHidden()
            }

            Picker("Shape", selection: visualBinding(\.avatar.type)) {
                ForEach(BotAvatarType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            Picker("Face", selection: visualBinding(\.avatar.face)) {
                ForEach(BotAvatarFace.allCases) { face in
                    Text(face.displayName).tag(face)
                }
            }
            Picker("Shading", selection: visualBinding(\.avatar.shading)) {
                ForEach(BotAvatarShading.allCases) { shading in
                    Text(shading.displayName).tag(shading)
                }
            }

            settingsSlider("Size", value: visualBinding(\.avatar.size), range: 18...72, format: "%.0f pt")
            settingsSlider("Animation speed", value: visualBinding(\.avatar.speed), range: 0.25...2, format: "%.2fx")
            settingsSlider("Brightness", value: visualBinding(\.avatar.brightness), range: 0.5...1.5, format: "%.2f")
            settingsSlider("Saturation", value: visualBinding(\.avatar.saturation), range: 0.5...2.5, format: "%.2f")

            Toggle("Interactive pointer response", isOn: visualBinding(\.avatar.interactive))
            settingsSlider("Head turn", value: visualBinding(\.avatar.turn), range: 0...2, format: "%.2f")

            DisclosureGroup("Accessories & motion", isExpanded: $avatarAdvanced) {
                VStack(alignment: .leading, spacing: 9) {
                    Picker("Hat", selection: visualBinding(\.avatar.hat)) {
                        ForEach(BotAvatarHat.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    Picker("Glasses", selection: visualBinding(\.avatar.glasses)) {
                        ForEach(BotAvatarGlasses.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    Toggle("Headphones", isOn: visualBinding(\.avatar.headphones))
                    Toggle("Bow tie", isOn: visualBinding(\.avatar.bowTie))
                    TextField("Accessory color (#RRGGBB)", text: visualBinding(\.avatar.accessoryColorHex))
                        .textFieldStyle(.roundedBorder)
                    settingsSlider("Whirl", value: visualBinding(\.avatar.whirl), range: 0...2, format: "%.2f")
                    settingsSlider("Motion strength", value: visualBinding(\.avatar.motionStrength), range: 0...2, format: "%.2f")
                }
                .padding(.top, 7)
            }
        }
    }

    private var voiceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice Visualization")
                .font(.system(size: 12, weight: .semibold))

            Picker("Color", selection: visualBinding(\.voice.variant)) {
                ForEach(VoiceBeamColorVariant.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            settingsSlider("Sensitivity", value: visualBinding(\.voice.sensitivity), range: 0.25...3, format: "%.2f")
            settingsSlider("Gate threshold", value: visualBinding(\.voice.threshold), range: 0...0.4, format: "%.2f")
            settingsSlider("Strength", value: visualBinding(\.voice.strength), range: 0...1, format: "%.2f")
            Toggle("Animate voice beam", isOn: visualBinding(\.voice.animationEnabled))

            DisclosureGroup("Advanced voice response", isExpanded: $voiceAdvanced) {
                VStack(alignment: .leading, spacing: 9) {
                    settingsSlider("Attack", value: visualBinding(\.voice.attack), range: 0.02...0.8, format: "%.2fs")
                    settingsSlider("Release", value: visualBinding(\.voice.release), range: 0.05...1.5, format: "%.2fs")
                    settingsSlider("Reach", value: visualBinding(\.voice.reach), range: 0.4...2.5, format: "%.2f")
                    settingsSlider("Spread", value: visualBinding(\.voice.spread), range: 0.4...2.5, format: "%.2f")
                    settingsSlider("Flow", value: visualBinding(\.voice.flow), range: 0...2.5, format: "%.2f")
                    settingsSlider("Bend", value: visualBinding(\.voice.bend), range: 0...2.5, format: "%.2f")
                    settingsSlider("Idle intensity", value: visualBinding(\.voice.idle), range: 0...0.5, format: "%.2f")
                }
                .padding(.top, 7)
            }
        }
    }

    private var sendControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send Button")
                .font(.system(size: 12, weight: .semibold))
            Toggle("Metal effect", isOn: visualBinding(\.metal.enabled))
            Picker("Preset", selection: visualBinding(\.metal.preset)) {
                ForEach(MetalSendPreset.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            settingsSlider("Strength", value: visualBinding(\.metal.strength), range: 0...1, format: "%.2f")
            Toggle("Glow", isOn: visualBinding(\.metal.glowEnabled))
            settingsSlider("Glow gain", value: visualBinding(\.metal.glowGain), range: 0...2, format: "%.2f")
            Toggle("Inner rim", isOn: visualBinding(\.metal.innerShadow))
            Toggle("Animate metal", isOn: visualBinding(\.metal.animationEnabled))
        }
    }

    private func visualBinding<Value>(_ keyPath: WritableKeyPath<AgentVisualPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { settings.agentVisualPreferences[keyPath: keyPath] },
            set: { value in
                var copy = settings.agentVisualPreferences
                copy[keyPath: keyPath] = value
                settings.agentVisualPreferences = copy
            }
        )
    }

    private func settingsSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
