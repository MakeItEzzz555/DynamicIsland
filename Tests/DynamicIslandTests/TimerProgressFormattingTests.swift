import XCTest
@testable import DynamicIsland

final class TimerProgressFormattingTests: XCTestCase {
    func testProgressClampsBounds() {
        XCTAssertEqual(TimerProgressFormatting.progress(remainingSeconds: -10, totalSeconds: 100), 0)
        XCTAssertEqual(TimerProgressFormatting.progress(remainingSeconds: 50, totalSeconds: 100), 0.5)
        XCTAssertEqual(TimerProgressFormatting.progress(remainingSeconds: 140, totalSeconds: 100), 1)
    }

    func testProgressIsFullWhenTotalIsUnavailable() {
        XCTAssertEqual(TimerProgressFormatting.progress(remainingSeconds: 0, totalSeconds: 0), 1)
    }

    func testColorStageTracksRemainingProgress() {
        XCTAssertEqual(TimerProgressFormatting.colorStage(progress: 0.9), .high)
        XCTAssertEqual(TimerProgressFormatting.colorStage(progress: 0.35), .mid)
        XCTAssertEqual(TimerProgressFormatting.colorStage(progress: 0.1), .low)
    }
}
