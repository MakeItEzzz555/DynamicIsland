import LibrariesNative
import SwiftUI
import XCTest
@testable import DynamicIsland

/// ImageRenderer measures snapshot construction and rasterization, including
/// the avatar's frozen-pose simulation replay. It does not measure the retained
/// live renderer, display cadence or GPU frame pacing. Keep correctness checks
/// in ordinary CI; opt into wall-time measurements on a known benchmark host.
@MainActor
final class DecorationFrameCostTests: XCTestCase {
    func testAnimationFrameGeometryRemainsFinite() {
        for state in OrbState.allCases {
            for size in OrbSize.allCases {
                let preset = resolvePreset(state, size)
                for time in [0.0, 0.6, 1.6] {
                    let frame = orbFrame(preset, size: Double(size.rawValue), t: time)
                    XCTAssertFalse(frame.dots.isEmpty)
                    for dot in frame.dots {
                        XCTAssertTrue([dot.x, dot.y, dot.z, dot.r, dot.white, dot.a].allSatisfy(\.isFinite))
                        XCTAssertGreaterThan(dot.r, 0)
                    }
                    for line in frame.lines {
                        XCTAssertTrue([line.x1, line.y1, line.x2, line.y2, line.white, line.a, line.w].allSatisfy(\.isFinite))
                    }
                }
            }
        }
        for state in BotAvatarState.allCases {
            let player = BotAvatarPlayer(seed: 0.5, state: state)
            for frame in 0..<240 {
                let pose = player.frame(at: Double(frame) / 120, state: state, speed: 1, paused: false)
                let values = [pose.yaw, pose.pitch, pose.roll, pose.x, pose.y, pose.sx, pose.sy,
                              pose.eyeOpen, pose.blinkL, pose.blinkR, pose.lookX, pose.lookY,
                              pose.breath, pose.laugh, pose.whirl, pose.whirlAngle,
                              pose.w.x, pose.w.y, pose.w.z]
                XCTAssertTrue(values.allSatisfy(\.isFinite))
                XCTAssertGreaterThan(pose.sx, 0)
                XCTAssertGreaterThan(pose.sy, 0)
                XCTAssertEqual(pose.w.x + pose.w.y + pose.w.z, 1, accuracy: 0.000001)
            }
        }
    }

    func testDecorationsRasterizeAtRequestedDimensions() throws {
        func check(_ view: some View) throws {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, 68)
            XCTAssertEqual(image.height, 68)
            XCTAssertGreaterThan(image.bytesPerRow, 0)
        }
        var avatar = BotAvatarConfiguration()
        avatar.size = 34
        for time in [0.0, 0.6, 1.6] {
            for state in AgentOrbVisualState.allCases {
                try check(AgentOrbView(state: state, size: 34, frozenTime: time))
            }
            try check(BotAvatarView(sessionID: nil, configuration: avatar, state: .working, frozenTime: time))
        }
    }

    private func averageSnapshotMilliseconds(frames: Int = 120, _ view: (Double) -> some View) throws -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        for frame in 0..<frames {
            let renderer = ImageRenderer(content: view(Double(frame) / 120))
            renderer.scale = 2
            _ = try XCTUnwrap(renderer.cgImage)
        }
        return (ProcessInfo.processInfo.systemUptime - start) * 1000 / Double(frames)
    }

    func testMeasureSnapshotRasterizationCost() throws {
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_DECORATION_PERF"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_DECORATION_PERF=1 on a known host to measure snapshot rasterization cost.")
        }
        var worst = 0.0
        for state in AgentOrbVisualState.allCases {
            let ms = try averageSnapshotMilliseconds { t in AgentOrbView(state: state, size: 34, frozenTime: 0.6 + t) }
            worst = max(worst, ms)
        }
        var avatar = BotAvatarConfiguration()
        avatar.size = 34
        let avatarMS = try averageSnapshotMilliseconds { t in
            BotAvatarView(sessionID: nil, configuration: avatar, state: .working, frozenTime: 1.0 + t)
        }
        print(String(format: "SNAPSHOTCOST orb worst=%.2f ms avatar=%.2f ms (120 snapshots each at 2x; includes renderer allocation and frozen-pose replay; not display frame pacing)", worst, avatarMS))
        XCTAssertTrue(worst.isFinite && worst > 0)
        XCTAssertTrue(avatarMS.isFinite && avatarMS > 0)
    }
}
