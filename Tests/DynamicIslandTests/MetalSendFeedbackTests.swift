import XCTest
@testable import DynamicIsland

/// One Send button for every Agent Chat size. Regression (2026-10-06): the
/// press style ignored `hovering`, so Compact/Large chats had no hover.
final class MetalSendFeedbackTests: XCTestCase {
    func testHoverLiftsAndBrightensPressContracts() {
        let idle = MetalSendFeedback.resolve(hovering: false, pressed: false, enabled: true, reduceMotion: false)
        let hover = MetalSendFeedback.resolve(hovering: true, pressed: false, enabled: true, reduceMotion: false)
        let press = MetalSendFeedback.resolve(hovering: true, pressed: true, enabled: true, reduceMotion: false)
        XCTAssertEqual(idle, MetalSendFeedback(scale: 1, brightness: 0, opacity: 1))
        XCTAssertNotEqual(hover, idle, "hover produces a visible change")
        XCTAssertTrue((1.03...1.06).contains(hover.scale))
        XCTAssertGreaterThan(hover.brightness, idle.brightness)
        XCTAssertTrue((0.94...0.97).contains(press.scale))
    }

    func testDisabledIsInertAndReduceMotionNeverScales() {
        for hovering in [false, true] { for pressed in [false, true] {
            XCTAssertEqual(MetalSendFeedback.resolve(hovering: hovering, pressed: pressed, enabled: false, reduceMotion: false),
                           MetalSendFeedback(scale: 1, brightness: 0, opacity: 1))
            let reduced = MetalSendFeedback.resolve(hovering: hovering, pressed: pressed, enabled: true, reduceMotion: true)
            XCTAssertEqual(reduced.scale, 1, "no scaling movement with Reduce Motion")
        } }
        XCTAssertGreaterThan(MetalSendFeedback.resolve(hovering: true, pressed: false, enabled: true, reduceMotion: true).brightness, 0,
                             "Reduce Motion keeps a brightness response")
    }

    /// Source guard: every chat size uses the single MetalSendButton.
    func testOneSendButtonImplementation() throws {
        let views = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/DynamicIsland/Views")
        let files = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil)
        let uses = try files.filter { $0.lastPathComponent != "AgentAppearanceSettingsView.swift" }.map {
            try String(contentsOf: $0, encoding: .utf8).components(separatedBy: "MetalSendButton(").count - 1
        }.reduce(0, +)
        XCTAssertEqual(uses, 1, "the composer owns the only Send button; sizes do not duplicate it")
    }
}
