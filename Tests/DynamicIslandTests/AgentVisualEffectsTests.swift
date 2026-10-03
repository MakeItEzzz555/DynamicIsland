import XCTest
@testable import DynamicIsland

final class AgentVisualEffectsTests: XCTestCase {
    func testDomainStateToOrbStateMapping() {
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.idle), .breathing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.thinking), .solving)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.planning), .shaping)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.working), .working)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentState.runningTool), .working)
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
        let assignments = (0..<100).map { value in
            BotAvatarDeterminism.type(for: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: .codex, nativeID: "thread-\(value)"),
                generation: AgentSessionGeneration(rawValue: 1)
            ))
        }
        XCTAssertEqual(Set(assignments).count, 18, "Must hash identity, not a constant seed")
        XCTAssertNotEqual(BotAvatarDeterminism.type(for: first), BotAvatarDeterminism.type(for: nextGeneration))
    }

    func testUnstructuredActivityTextCannotChooseOrbState() throws {
        var session = try XCTUnwrap(AgentDashboardPreviewFactory.sessions().first)
        // Display text must never masquerade as provider evidence.
        for domain in [AgentState.thinking, .planning, .working, .runningTool, .runningCommand] {
            session.state = domain
            session.tools = [:]; session.commands = [:]; session.processingActivities = [:]
            for title in ["Searching web", "Connecting", "Generating answer", "Write file"] {
                session.recentActivity = [AgentActivity(id: AgentEventID(rawValue: "hint"), kind: .tool, title: title, summary: title, status: .active, correlationID: nil, timestamp: Date())]
                XCTAssertEqual(AgentOrbStateMapper.state(for: session), AgentOrbStateMapper.state(for: domain))
            }
        }
        for domain in [AgentState.idle, .waitingForApproval, .waitingForUser, .planReady, .completed, .failed, .interrupted] {
            session.state = domain
            session.processingActivities = [AgentCorrelationID(rawValue: "underlying"): AgentProcessingActivity(kind: .searching, startedAt: Date())]
            XCTAssertEqual(AgentOrbStateMapper.state(for: session), AgentOrbStateMapper.state(for: domain))
            XCTAssertFalse(AgentVisualMotion.animates(domain))
        }
        session.state = .working; session.processingActivities = [:]
        session.recentActivity = [AgentActivity(id: AgentEventID(rawValue: "old"), kind: .tool, title: "Searching", summary: nil, status: .completed, correlationID: nil, timestamp: Date())]
        XCTAssertEqual(AgentOrbStateMapper.state(for: session), .working)
    }

    func testVoiceLifecycleMappingsAndMotionPolicy() {
        XCTAssertEqual(AgentOrbStateMapper.state(for: VoiceTranscriptionPhase.requestingPermission), .connecting)
        XCTAssertEqual(AgentOrbStateMapper.state(for: VoiceTranscriptionPhase.stopping), .connecting)
        XCTAssertEqual(AgentOrbStateMapper.state(for: VoiceTranscriptionPhase.failed("denied")), .breathing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: VoiceTranscriptionPhase.completed(VoiceTranscript(text: "done", createdAt: Date(), wasOnDevice: true))), .breathing)
        XCTAssertFalse(AgentVisualMotion.paused(reduceMotion: false, visible: true, active: true))
        XCTAssertTrue(AgentVisualMotion.paused(reduceMotion: true, visible: true, active: true))
        XCTAssertTrue(AgentVisualMotion.paused(reduceMotion: false, visible: false, active: true))
        XCTAssertTrue(AgentVisualMotion.paused(reduceMotion: false, visible: true, active: false))
        XCTAssertTrue(AgentVisualMotion.paused(reduceMotion: false, visible: true, active: true, enabled: false))
    }

    func testProcessingBeamIgnoresMicAndFocusesWhileTravelling() {
        let c = VoiceBeamConfiguration()
        let silent = VoiceBeamGeometry.make(width: 200, height: 20, level: 0, processing: true, time: 0, configuration: c)
        let loud = VoiceBeamGeometry.make(width: 200, height: 20, level: 1, processing: true, time: 0, configuration: c)
        let listening = VoiceBeamGeometry.make(width: 200, height: 20, level: 1, processing: false, time: 0, configuration: c)
        XCTAssertEqual(silent, loud)
        XCTAssertLessThan(silent.width, listening.width)
        XCTAssertLessThan(silent.bloom, listening.bloom)
        XCTAssertNotEqual(silent.centerX, VoiceBeamGeometry.make(width: 200, height: 20, level: 0, processing: true, time: 1, configuration: c).centerX)
        XCTAssertEqual(listening.centerX, 100)
    }

    func testManagedConnectingAndSubmissionRemainPresentationOnly() throws {
        let session = try XCTUnwrap(AgentDashboardPreviewFactory.sessions().first)
        let original = session
        for interaction in [AgentManagedInteractionState.connecting, .checkingAttachment, .stopping] {
            XCTAssertEqual(AgentOrbStateMapper.state(for: interaction, session: session), .connecting)
        }
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentManagedInteractionState.submitting, session: session), .composing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentManagedInteractionState.ready, session: session), .breathing)
        XCTAssertEqual(AgentOrbStateMapper.state(for: AgentManagedInteractionState.failed("offline"), session: session), .breathing)
        XCTAssertEqual(session, original)
    }

    func testAdvancedClampingAndInvalidAccessoryColors() {
        var c = BotAvatarAdvancedConfiguration()
        c.shadow = -1; c.lightAngle = .infinity; c.furLength = 9
        c.density = -2; c.curl = .nan; c.jumpDuration = 0; c.spin = 99
        let normalized = c.normalized()
        XCTAssertEqual(normalized.shadow, 0)
        XCTAssertEqual(normalized.lightAngle, 225)
        XCTAssertEqual(normalized.furLength, 1)
        XCTAssertEqual(normalized.density, 0)
        XCTAssertEqual(normalized.curl, 0.25)
        XCTAssertEqual(normalized.jumpDuration, 0.3)
        XCTAssertEqual(normalized.spin, 2)
        var avatar = BotAvatarConfiguration()
        for invalid in ["", "red", "#GGGGGG", "-12345", "#12345678"] {
            avatar.accessoryColorHex = invalid
            XCTAssertEqual(avatar.normalized().accessoryColorHex, "#222222")
        }
        XCTAssertEqual(VoiceBeamConfiguration().reactiveLevel(.nan), 0.08)
    }

    func testCheckpointJSONRemainsCompatible() throws {
        let original = try XCTUnwrap(AgentVisualPreferences.defaults.encoded())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var avatar = try XCTUnwrap(json["avatar"] as? [String: Any])
        avatar.removeValue(forKey: "advanced")
        avatar.removeValue(forKey: "automaticShape")
        json["avatar"] = avatar
        let decoded = try JSONDecoder().decode(AgentVisualPreferences.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.avatar.details, BotAvatarAdvancedConfiguration())
        XCTAssertEqual(decoded, .defaults)
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
        preferences.avatar.details.curl = 0.8
        preferences.avatar.details.jumpHeight = 0.2
        preferences.avatar.automaticShape = false
        first.agentVisualPreferences = preferences

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.agentVisualPreferences.indicatorStyle, .avatar)
        XCTAssertEqual(second.agentVisualPreferences.avatar.type, .cat)
        XCTAssertEqual(second.agentVisualPreferences.voice.variant, .ocean)
        XCTAssertEqual(second.agentVisualPreferences.metal.preset, .gold)
        XCTAssertEqual(second.agentVisualPreferences.avatar.details.curl, 0.8)
        XCTAssertEqual(second.agentVisualPreferences.avatar.details.jumpHeight, 0.2)
        XCTAssertEqual(second.agentVisualPreferences.avatar.automaticShape, false)
        XCTAssertEqual(second.agentActivityEnabled, originalActivityEnabled)

        second.resetAgentVisualPreferences()
        XCTAssertEqual(second.agentVisualPreferences, .defaults)
        XCTAssertEqual(second.agentActivityEnabled, originalActivityEnabled)
    }
}
