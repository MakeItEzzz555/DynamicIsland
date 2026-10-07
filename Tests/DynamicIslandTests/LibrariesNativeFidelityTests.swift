import XCTest
import SwiftUI
import AppKit
@testable import LibrariesNative
@testable import DynamicIsland

@MainActor
final class LibrariesNativeFidelityTests: XCTestCase {
    func testNineDistinctOrbEnginesAndIndependentScaleTuning() {
        XCTAssertEqual(OrbState.allCases.count, 9)
        XCTAssertEqual(Set(OrbState.allCases.map { $0.mode }).count, 9)
        for state in OrbState.allCases {
            let primary = resolvePreset(state, .px64), inline = resolvePreset(state, .px20)
            let large = orbFrame(primary, size: 64, t: 0.6), small = orbFrame(inline, size: 20, t: 0.6)
            XCTAssertFalse(large.dots.isEmpty); XCTAssertFalse(small.dots.isEmpty)
            XCTAssertNotEqual(primary.speed, inline.speed)
            XCTAssertNotEqual(large.dots.count, small.dots.count, "\(state): inline must be independently tuned")
            for dot in small.dots {
                XCTAssertTrue(dot.x.isFinite && dot.y.isFinite && dot.r.isFinite)
                XCTAssertGreaterThanOrEqual(dot.r, 0.25)
            }
        }
    }

    func testReferenceBodyRosterAndFacePlacementsAreDistinct() {
        XCTAssertEqual(LibrariesNative.BotAvatarType.allCases.count, 18)
        XCTAssertEqual(Set(botAvatarShapePaths.values).count, 18)
        for type in LibrariesNative.BotAvatarType.allCases {
            XCTAssertFalse(type.shapeCGPath.isEmpty)
            XCTAssertGreaterThan(type.shapeCGPath.boundingBox.width, 40)
            XCTAssertGreaterThan(type.shapeCGPath.boundingBox.height, 40)
            XCTAssertTrue(type.shapeCGPath.boundingBox.contains(CGPoint(x: type.preset.faceX, y: type.preset.faceY)))
        }
        XCTAssertEqual(LibrariesNative.BotAvatarType.triangle.preset.faceY, 61)
        XCTAssertEqual(LibrariesNative.BotAvatarType.cat.preset.faceY, 58)
        XCTAssertNotEqual(LibrariesNative.BotAvatarType.cat.paletteColor, LibrariesNative.BotAvatarType.circle.paletteColor)
    }

    func testSeededRigIsDeterministicAndCrossAnimatesState() {
        let a = BotAvatarSim(seed: 0.32), b = BotAvatarSim(seed: 0.32)
        for _ in 0..<60 { a.update(1/60); b.update(1/60) }
        XCTAssertEqual(a.pose.yaw, b.pose.yaw); XCTAssertEqual(a.pose.lookX, b.pose.lookX)
        a.setState(.working)
        XCTAssertEqual(a.pose.w[1], 0)
        for _ in 0..<20 { a.update(1/60) }
        XCTAssertGreaterThan(a.pose.w[1], 0); XCTAssertLessThan(a.pose.w[1], 1)
        for _ in 0..<40 { a.update(1/60) }
        XCTAssertEqual(a.pose.w[1], 1, accuracy: 0.001)
        a.setState(.sleeping)
        for _ in 0..<30 { a.update(1/60) }
        XCTAssertGreaterThan(a.pose.w[2], 0); XCTAssertLessThan(a.pose.w[2], 1)
        XCTAssertEqual(a.pose.w[0]+a.pose.w[1]+a.pose.w[2], 1, accuracy: 0.000001)
    }

    func testWorkingRigMovesAndClickJumpHasCrouchFlightLandingRecovery() {
        let sim = BotAvatarSim(seed: 0.21, state: .working)
        var workingY: [Double] = []
        for _ in 0..<150 { sim.update(1/60); workingY.append(sim.pose.y) }
        XCTAssertGreaterThan((workingY.max() ?? 0)-(workingY.min() ?? 0), 12)
        let click = BotAvatarSim(seed: 0.21)
        var jump = BotAvatarJumpConfig(); jump.every = 0; click.setJump(jump); click.poke()
        var poses: [BotAvatarPose] = []
        for _ in 0..<140 { click.update(1/60); poses.append(click.pose) }
        XCTAssertLessThan(poses.prefix(12).map(\.sy).min() ?? 1, 0.99, "anticipation")
        XCTAssertLessThan(poses.map(\.y).min() ?? 0, -20, "flight")
        XCTAssertGreaterThan(poses.map(\.sy).max() ?? 1, 1.03, "airborne stretch")
        XCTAssertLessThan(poses[60..<90].map(\.sy).min() ?? 1, 0.99, "landing")
        XCTAssertEqual(poses.last!.sy, 1, accuracy: 0.08, "recovery")
    }

    func testPauseOffscreenAndResumeNeverCatchUpOrDoubleTick() {
        let player = BotAvatarPlayer(seed: 0.8, state: .working)
        _ = player.frame(at: 0, state: .working, speed: 1, paused: false)
        let moving = player.frame(at: 0.03, state: .working, speed: 1, paused: false)
        let duplicate = player.frame(at: 0.03, state: .working, speed: 1, paused: false)
        XCTAssertEqual(moving.y, duplicate.y)
        let frozen = player.frame(at: 10, state: .working, speed: 1, paused: true)
        XCTAssertEqual(moving.y, frozen.y); XCTAssertNil(player.lastTimestamp)
        let resumed = player.frame(at: 100, state: .working, speed: 1, paused: false)
        XCTAssertEqual(frozen.y, resumed.y)
        let next = player.frame(at: 100.03, state: .working, speed: 1, paused: false)
        XCTAssertNotEqual(resumed.y, next.y)
    }

    func testAvatarIdentityIncludesProviderAndGenerationAndRosterIsBounded() throws {
        let fixture = try XCTUnwrap(AgentDashboardPreviewFactory.sessions().first)
        let original = AgentAvatarPlayers.player(for: fixture.id, state: .working)
        XCTAssertTrue(original === AgentAvatarPlayers.player(for: fixture.id, state: .working))
        var other = fixture.id
        other = AgentSessionInstanceID(sessionID: AgentSessionID(provider: .claude, nativeID: fixture.id.sessionID.nativeID), generation: fixture.id.generation)
        XCTAssertNotEqual(BotAvatarDeterminism.seed(for: fixture.id), BotAvatarDeterminism.seed(for: other))
        XCTAssertFalse(original === AgentAvatarPlayers.player(for: other, state: .working))
        for i in 0..<100 {
            let id = AgentSessionInstanceID(sessionID: AgentSessionID(provider: .codex, nativeID: "bounded-\(i)"), generation: .init(rawValue: 1))
            _ = AgentAvatarPlayers.player(for: id, state: .default)
        }
        XCTAssertLessThanOrEqual(AgentAvatarPlayers.count, AgentAvatarPlayers.capacity)
    }

    func testNativeFidelityConfigurationClampsPersistsAndResets() throws {
        let name = "NativeFidelityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        var f = BotAvatarFidelityConfiguration()
        f.yaw = .infinity; f.pitch = -999; f.whirlWidth = 999; f.jumpRiseTime = -2
        f.bodyColorHex = "invalid"; f.inkColorHex = "#123456"; f.jumpGroundEase = "bad"
        f.customBodyPath = String(repeating: "M", count: 9000)
        settings.agentVisualPreferences.avatar.fidelity = f
        let reloaded = AppSettings(defaults: defaults)
        let actual = try XCTUnwrap(reloaded.agentVisualPreferences.avatar.fidelity)
        XCTAssertEqual(actual.yaw, 0); XCTAssertEqual(actual.pitch, -180)
        XCTAssertEqual(actual.whirlWidth, 2); XCTAssertEqual(actual.jumpRiseTime, 0.05)
        XCTAssertNil(actual.bodyColorHex); XCTAssertEqual(actual.inkColorHex, "#123456")
        XCTAssertEqual(actual.jumpGroundEase, "pulse"); XCTAssertNil(actual.customBodyPath)
        reloaded.resetAgentVisualPreferences()
        XCTAssertEqual(AppSettings(defaults: defaults).agentVisualPreferences, .defaults)
    }

    func testNativeMaterialAndFurControlsReachRenderer() {
        var config = BotAvatarConfiguration()
        var a = config.details; a.furLength = 0.8; a.roundness = 0.2; a.density = 0.9
        config.advanced = a
        var f = BotAvatarFidelityConfiguration(); f.backLight = 0.4; f.shine = 1.2; f.jumpGroundTime = 0.7; f.whirlTilt = 1.7
        config.fidelity = f
        let draw = config.nativeDraw(type: .cat)
        XCTAssertEqual(draw.shading, .fabric)
        XCTAssertEqual(draw.fur.length, 6.4, accuracy: 0.001)
        XCTAssertEqual(draw.roundness, 0.2); XCTAssertEqual(draw.backLight, 0.4); XCTAssertEqual(draw.shine, 1.2)
        XCTAssertEqual(draw.whirl.tilt, 1.7); XCTAssertEqual(config.nativeJump.groundTime, 0.7)
    }

    func testMalformedCustomPathFailsClosedWithoutHanging() {
        for path in ["M0 0 Z1", "M0", "M1e999 0L1 1Z", "M0 0K1 1", "M0 0L"] {
            XCTAssertTrue(botAvatarCGPath(path).isEmpty, path)
        }
        XCTAssertFalse(botAvatarCGPath("M10 10L90 10L50 90Z").isEmpty)
    }

    func testFleeceTextureUsesTheAsymmetricBodyCoordinateSystem() throws {
        let cfg = BotAvatarDrawConfig(type: .triangle)
        let image = try XCTUnwrap(bakeFibres(cfg))
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        // Inspect alpha away from the soft fringe: the triangle's lower flanks
        // are wide, while its upper flanks are outside the actual path.
        func alpha(_ designX: Double, _ designY: Double) -> Int {
            let x = Int((designX+8)/116*Double(image.width))
            let y = Int((designY+8)/116*Double(image.height))
            return Int(bytes[y*image.bytesPerRow+x*4+3])
        }
        var lower = 0, upper = 0
        for y in 12...28 { for x in 20...30 { upper += alpha(Double(x), Double(y)); lower += alpha(Double(x), Double(100-y)) } }
        XCTAssertGreaterThan(lower, 500)
        XCTAssertLessThan(upper, lower/4, "A reflected fibre film floats above the triangle.")
    }

    func testStaticStatePolicyPreservesAttentionAndIdentity() {
        XCTAssertEqual(AgentAvatarStateMapper.state(.idle), .default)
        XCTAssertEqual(AgentAvatarStateMapper.state(.completed), .sleeping)
        XCTAssertEqual(AgentAvatarStateMapper.state(.waitingForApproval), .default)
        XCTAssertEqual(AgentAvatarStateMapper.state(.working), .working)
        XCTAssertEqual(BotAvatarPose.rest(.sleeping).w[2], 1)
        XCTAssertEqual(BotAvatarPose.rest(.working).whirl, 0)
    }
    func testTurnChangesIdleGazeWithoutDisablingPointerAndSeedOverrideIsStable() throws {
        let still = BotAvatarSim(seed: 0.32), turning = BotAvatarSim(seed: 0.32)
        var jump = BotAvatarJumpConfig.defaults; jump.every = 0
        still.setJump(jump); turning.setJump(jump); still.setTurn(0)
        for _ in 0..<120 { still.update(1/60); turning.update(1/60) }
        XCTAssertEqual(still.pose.yaw, 0, accuracy: 0.001)
        XCTAssertGreaterThan(abs(turning.pose.yaw), 0.1)
        still.setPointer(x: 1, y: 0, strength: 1)
        for _ in 0..<90 { still.update(1/60) }
        XCTAssertGreaterThan(still.pose.yaw, 0.1, "turn=0 suppresses idle turning, not pointer awareness")
        let id = try XCTUnwrap(AgentDashboardPreviewFactory.sessions().first?.id)
        let first = AgentAvatarPlayers.player(for: id, state: .working, seed: 0.12)
        XCTAssertTrue(first === AgentAvatarPlayers.player(for: id, state: .working, seed: 0.12))
        XCTAssertTrue(first === AgentAvatarPlayers.player(for: id, state: .working, seed: 0.78))
        let expected = BotAvatarSim(seed: 0.78, state: .working)
        first.simulation.update(1/60); expected.update(1/60)
        XCTAssertEqual(first.simulation.pose.lookX, expected.pose.lookX)
        XCTAssertEqual(first.simulation.pose.y, expected.pose.y)
    }

    func testPlayerSpeedActuallyMultipliesAnimationAtThirtyFPS() {
        let slow = BotAvatarPlayer(seed: 0.7, state: .working)
        let fast = BotAvatarPlayer(seed: 0.7, state: .working)
        for n in 0...9 {
            _ = slow.frame(at: Double(n)/30, state: .working, speed: 1, paused: false)
            _ = fast.frame(at: Double(n)/30, state: .working, speed: 2, paused: false)
        }
        XCTAssertNotEqual(slow.simulation.pose.y, fast.simulation.pose.y)
        let reference = BotAvatarSim(seed: 0.7, state: .working)
        for _ in 0..<36 { reference.update(1/60) }
        XCTAssertEqual(fast.simulation.pose.y, reference.pose.y, accuracy: 0.000001)
    }

    func testVisibleHostAndRenderResourcesReleaseAfterTeardown() async throws {
        weak var weakHost: NativeVisualVisibility.Probe?
        weak var weakRender: BotAvatarRenderState?
        var host: NativeVisualVisibility.Probe? = NativeVisualVisibility.Probe { _ in }
        weakHost = host
        let window = NSWindow(contentRect: CGRect(x: 40,y: 40,width: 40,height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host?.refresh()
        host?.stop(); window.contentView = nil; window.close(); host = nil
        // Pending visibility delivery holds a weak reference, not the host.
        await Task.yield()
        XCTAssertNil(weakHost)
        var state: BotAvatarRenderState? = .init(); weakRender = state; state = nil
        XCTAssertNil(weakRender)
    }

    func testReferenceEngineFrameBudgetAndMaterialCachesAreBounded() {
        var timings: [Double] = []
        var dots = 0
        for state in OrbState.allCases {
            for size in OrbSize.allCases {
                let preset = resolvePreset(state, size)
                for n in 0..<120 {
                    let start = ProcessInfo.processInfo.systemUptime
                    let frame = orbFrame(preset, size: Double(size.rawValue), t: Double(n)/30*preset.speed)
                    timings.append(ProcessInfo.processInfo.systemUptime-start)
                    dots += frame.dots.count
                }
            }
        }
        timings.sort()
        print("NATIVE-FIDELITY engine frames=\(timings.count) dots=\(dots) meanMs=\(timings.reduce(0,+)/Double(timings.count)*1000) p99Ms=\(timings[Int(Double(timings.count)*0.99)]*1000)")
        XCTAssertGreaterThan(dots, 100_000)
        XCTAssertLessThanOrEqual(BotAvatarMaterialDiagnostics.cachedFormCount, 48)
        XCTAssertLessThanOrEqual(BotAvatarMaterialDiagnostics.pendingFormCount, 8)
        XCTAssertLessThanOrEqual(BotAvatarFabricDiagnostics.textureCount, 24)
        XCTAssertLessThan(BotAvatarFabricDiagnostics.maximumTextureBytes, 4*1024*1024)
    }

}
