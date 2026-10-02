import XCTest
@testable import DynamicIsland

final class AgentVisualEffectsTests: XCTestCase {
    func testDomainStateToOrbStateMapping() {
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.idle), .breathing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.thinking), .solving)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.planning), .weaving)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.working), .working)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.runningTool), .shaping)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.runningCommand), .working)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.waitingForApproval), .breathing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.waitingForUser), .breathing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.planReady), .composing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.completed), .breathing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.failed), .breathing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.interrupted), .breathing)
    }

    func testVoicePhaseToOrbStateMapping() {
        XCTAssertEqual(AgentOrbStateMapper.state(for: VoiceTranscriptionPhase.idle), .breathing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: VoiceTranscriptionPhase.preparing), .connecting)
        XCTAssertEqual(AgentOrbStateMapper.state(for: VoiceTranscriptionPhase.recording(startedAt: Date())), .listening)
        XCTAssertEqual(AgentOrbStateMapper.state(for: VoiceTranscriptionPhase.transcribing), .composing)
    }

    func testDeterministicAvatarSelectionIsStableAndGenerationScoped() {
        let first = AgentSessionInstanceID(
            sessionID: AgentSessionID(provider: .codex, nativeID: "thread-123"),
            generation: AgentSessionGeneration(rawValue: 1)
        )
        let same = AgentSessionInstanceID(
            sessionID: AgentSessionID(provider: .codex, nativeID: "thread-123"),
            generation: AgentSessionGeneration(rawValue: 1)
        )
        let nextGeneration = AgentSessionInstanceID(
            sessionID: AgentSessionID(provider: .codex, nativeID: "thread-123"),
            generation: AgentSessionGeneration(rawValue: 2)
        )

        XCTAssertEqual(BotAvatarDeterminism.type(for: first), BotAvatarDeterminism.type(for: same))
        XCTAssertTrue(BotAvatarType.allCases.contains(BotAvatarDeterminism.type(for: nextGeneration)))
    }

    func testVisualPreferencesClampInvalidValues() {
        var preferences = AgentVisualPreferences.defaults
        preferences.orbSpeed = .infinity
        preferences.avatar.size = -100
        preferences.avatar.saturation = 99
        preferences.voice.threshold = -1
        preferences.voice.strength = 4
        preferences.metal.glowGain = -2

        let normalized = preferences.normalized()

        XCTAssertEqual(normalized.orbSpeed, 1)
        XCTAssertEqual(normalized.avatar.size, 18)
        XCTAssertEqual(normalized.avatar.saturation, 2.5)
        XCTAssertEqual(normalized.voice.threshold, 0)
        XCTAssertEqual(normalized.voice.strength, 1)
        XCTAssertEqual(normalized.metal.glowGain, 0)
    }

    func testVoiceBeamInputChainGatesAndScalesLevel() {
        var config = VoiceBeamConfiguration()
        config.threshold = 0.2
        config.sensitivity = 2
        config.idle = 0.05

        XCTAssertEqual(config.reactiveLevel(0.1), 0.05, accuracy: 0.0001)
        XCTAssertGreaterThan(config.reactiveLevel(0.6), 0.5)
        XCTAssertLessThanOrEqual(config.reactiveLevel(1), 1)
    }

    func testVoiceEnvelopeUsesAttackAndRelease() {
        var config = VoiceBeamConfiguration()
        config.threshold = 0
        config.idle = 0
        config.attack = 0.05
        config.release = 0.5

        let envelope = VoiceBeamEnvelope()
        XCTAssertEqual(envelope.sample(rawLevel: 0, timestamp: 0, configuration: config), 0, accuracy: 0.0001)
        let attackValue = envelope.sample(rawLevel: 1, timestamp: 0.05, configuration: config)
        XCTAssertGreaterThan(attackValue, 0.5)
        let releaseValue = envelope.sample(rawLevel: 0, timestamp: 0.10, configuration: config)
        XCTAssertGreaterThan(releaseValue, 0.4)
        XCTAssertLessThan(releaseValue, attackValue)
    }

    @MainActor
    func testVisualPreferencesPersistAndResetWithoutTouchingDomainSettings() {
        let suite = "AgentVisualEffectsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        let originalActivityEnabled = first.agentActivityEnabled
        var preferences = first.agentVisualPreferences
        preferences.indicatorStyle = .avatar
        preferences.avatar.type = .cat
        preferences.voice.variant = .ocean
        preferences.metal.preset = .gold
        first.agentVisualPreferences = preferences

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.agentVisualPreferences.indicatorStyle, .avatar)
        XCTAssertEqual(second.agentVisualPreferences.avatar.type, .cat)
        XCTAssertEqual(second.agentVisualPreferences.voice.variant, .ocean)
        XCTAssertEqual(second.agentVisualPreferences.metal.preset, .gold)
        XCTAssertEqual(second.agentActivityEnabled, originalActivityEnabled)

        second.resetAgentVisualPreferences()
        XCTAssertEqual(second.agentVisualPreferences, .defaults)
        XCTAssertEqual(second.agentActivityEnabled, originalActivityEnabled)
    }
}
