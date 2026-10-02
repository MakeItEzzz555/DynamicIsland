import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentVisualSnapshotTests: XCTestCase {
    func testRenderAgentVisualEffectsReviewSnapshot() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_AGENT_VISUAL_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_AGENT_VISUAL_SNAPSHOT_DIR to render review screenshot.")
        }

        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var avatar = BotAvatarConfiguration()
        avatar.type = .cat
        avatar.hat = .beanie
        avatar.headphones = true
        avatar.whirl = 1

        let view = VStack(alignment: .leading, spacing: 20) {
            Text("Agent Presence")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 18) {
                ForEach(AgentOrbVisualState.allCases) { state in
                    VStack(spacing: 5) {
                        AgentOrbView(state: state, size: 64, paused: true)
                        Text(state.displayName)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }

            HStack(spacing: 26) {
                BotAvatarView(
                    sessionID: nil,
                    configuration: avatar,
                    state: .working,
                    overrideType: .cat
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("VoiceBeam — listening")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    VoiceBeamView(
                        level: { 0.68 },
                        processing: false,
                        configuration: VoiceBeamConfiguration(),
                        height: 28
                    )
                    .frame(width: 280)
                    .background(Color.black, in: Capsule())

                    Text("VoiceBeam — processing")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    VoiceBeamView(
                        level: { 0.42 },
                        processing: true,
                        configuration: VoiceBeamConfiguration(),
                        height: 28
                    )
                    .frame(width: 280)
                    .background(Color.black, in: Capsule())
                }

                VStack(spacing: 8) {
                    MetalSendButton(
                        configuration: MetalSendConfiguration(),
                        isEnabled: true,
                        action: {}
                    )
                    Text("Metal Send")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .padding(28)
        .frame(width: 820, height: 320, alignment: .topLeading)
        .background(Color(red: 0.025, green: 0.027, blue: 0.055))

        try render(view, size: CGSize(width: 820, height: 320), to: output.appendingPathComponent("agent-visual-effects.png"))

        let matrix = VStack(spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(90)), count: 6)) {
                ForEach(BotAvatarType.allCases) { type in
                    VStack {
                        BotAvatarView(sessionID: nil, configuration: avatar, state: .idle, overrideType: type, paused: true)
                        Text(type.displayName).font(.caption2)
                    }.frame(height: 62)
                }
            }
            HStack(spacing: 14) {
                ForEach(VoiceBeamColorVariant.allCases) { variant in
                    VStack {
                        VoiceBeamView(level: { 0.7 }, configuration: VoiceBeamConfiguration(variant: variant, animationEnabled: false), height: 30)
                        Text(variant.displayName).font(.system(size: 8))
                    }.frame(width: 65)
                }
            }
            HStack(spacing: 60) {
                ForEach(MetalSendPreset.allCases) { preset in
                    VStack {
                        MetalSendButton(configuration: MetalSendConfiguration(preset: preset), isEnabled: true, action: {})
                        Text(preset.displayName).font(.caption2)
                    }
                }
                MetalSendButton(configuration: MetalSendConfiguration(), isEnabled: false, action: {})
            }
        }.padding(24).foregroundStyle(.white).background(Color.black)
        try render(matrix, size: CGSize(width: 680, height: 400), to: output.appendingPathComponent("avatars-palettes-send.png"))

        let suite = "AgentAppearanceSnapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let before = settings.agentActivityEnabled
        try render(AgentAppearanceSettingsView(settings: settings).padding(24).preferredColorScheme(.dark), size: CGSize(width: 700, height: 1600), to: output.appendingPathComponent("appearance-settings.png"))
        XCTAssertEqual(settings.agentActivityEnabled, before)
    }

    private func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            XCTFail("Unable to create bitmap representation")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Unable to encode PNG")
            return
        }
        try data.write(to: url, options: .atomic)
    }
}
