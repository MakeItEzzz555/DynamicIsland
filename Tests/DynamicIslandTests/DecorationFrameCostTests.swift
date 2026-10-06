import SwiftUI
import XCTest
@testable import DynamicIsland

/// ProMotion budget: a decoration frame must render well inside 8.33 ms
/// (120 Hz). ImageRenderer rasterizes on the CPU, so this is a conservative
/// upper bound on the per-frame work the 120 Hz cadence asks for.
@MainActor
final class DecorationFrameCostTests: XCTestCase {
    private func averageFrameMilliseconds(frames: Int = 120, _ view: (Double) -> some View) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        for frame in 0..<frames {
            let renderer = ImageRenderer(content: view(Double(frame) / 120))
            renderer.scale = 2
            _ = renderer.cgImage
        }
        return (CFAbsoluteTimeGetCurrent() - start) * 1000 / Double(frames)
    }

    func testOrbAndAvatarFramesFitTheProMotionBudget() {
        var worst = 0.0
        for state in AgentOrbVisualState.allCases {
            let ms = averageFrameMilliseconds { t in AgentOrbView(state: state, size: 34, frozenTime: 0.6 + t) }
            worst = max(worst, ms)
        }
        var avatar = BotAvatarConfiguration()
        avatar.size = 34
        let avatarMS = averageFrameMilliseconds { t in
            BotAvatarView(sessionID: nil, configuration: avatar, state: .working, frozenTime: 1.0 + t)
        }
        print(String(format: "FRAMECOST orb worst=%.2f ms avatar=%.2f ms (budget 8.33 ms)", worst, avatarMS))
        XCTAssertLessThan(worst, 8.33 / 2, "orb frame stays well inside a 120 Hz frame")
        XCTAssertLessThan(avatarMS, 8.33 / 2, "avatar frame stays well inside a 120 Hz frame")
    }
}
