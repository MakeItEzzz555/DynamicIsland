import CoreGraphics
import XCTest
@testable import DynamicIsland

/// Source parity: Droppy/DragMonitor.swift `detectJiggle` — 0.5 s window,
/// reversal when dot < -0.3, required reversals max(2, min(5, round(6 - s))),
/// minimum movement max(3, min(8, 9 - s * 1.25)). DynamicIsland difference:
/// exactly one trigger per drag generation (Droppy re-arms after 1 s).
final class BasketJiggleTests: XCTestCase {
    func testSourceBackedThresholds() {
        XCTAssertEqual(BasketJiggleDetector.timeWindow, 0.5)
        XCTAssertEqual(BasketJiggleDetector.requiredDirectionChanges(sensitivity: 1), 5)
        XCTAssertEqual(BasketJiggleDetector.requiredDirectionChanges(sensitivity: 2), 4)
        XCTAssertEqual(BasketJiggleDetector.requiredDirectionChanges(sensitivity: 3), 3)
        XCTAssertEqual(BasketJiggleDetector.requiredDirectionChanges(sensitivity: 4), 2)
        XCTAssertEqual(BasketJiggleDetector.requiredDirectionChanges(sensitivity: 5), 2)
        XCTAssertEqual(BasketJiggleDetector.minimumMovement(sensitivity: 1), 7.75, accuracy: 0.001)
        XCTAssertEqual(BasketJiggleDetector.minimumMovement(sensitivity: 5), 3.0, accuracy: 0.001)
        XCTAssertEqual(BasketJiggleDetector(sensitivity: 99).sensitivity, 5)
        XCTAssertEqual(BasketJiggleDetector(sensitivity: -3).sensitivity, 1)
    }

    /// Feeds an alternating left/right shake sampled every `step` seconds.
    private func shake(_ detector: inout BasketJiggleDetector, generation: Int, samples: Int,
                       start: TimeInterval = 0, step: TimeInterval = 0.1, amplitude: CGFloat = 40) -> Int {
        var triggers = 0
        for index in 0..<samples {
            let x: CGFloat = index.isMultiple(of: 2) ? 100 + amplitude : 100
            if detector.sample(CGPoint(x: x, y: 100), at: start + Double(index + 1) * step, generation: generation) {
                triggers += 1
            }
        }
        return triggers
    }

    func testRequiresActiveDragGeneration() {
        var detector = BasketJiggleDetector(sensitivity: 3)
        XCTAssertEqual(shake(&detector, generation: 1, samples: 10), 0, "no begun drag, no trigger")
    }

    func testShakeTriggersExactlyOncePerGeneration() {
        var detector = BasketJiggleDetector(sensitivity: 3)
        detector.beginDrag(generation: 1, at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(shake(&detector, generation: 1, samples: 20), 1)
        XCTAssertEqual(shake(&detector, generation: 1, samples: 20, start: 5), 0, "same shake/generation never re-triggers")
    }

    func testSlowDirectionChangesOutsideWindowDoNotTrigger() {
        var detector = BasketJiggleDetector(sensitivity: 3)
        detector.beginDrag(generation: 1, at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(shake(&detector, generation: 1, samples: 12, step: 0.4), 0)
    }

    func testStraightDragAndSubThresholdTremorDoNotTrigger() {
        var detector = BasketJiggleDetector(sensitivity: 3)
        detector.beginDrag(generation: 1, at: .zero)
        var fired = false
        for index in 1...20 {
            fired = fired || detector.sample(CGPoint(x: CGFloat(index) * 30, y: 0), at: Double(index) * 0.05, generation: 1)
        }
        XCTAssertFalse(fired)
        XCTAssertEqual(shake(&detector, generation: 1, samples: 20, start: 2, amplitude: 2), 0, "2 pt tremor is below minimum movement")
    }

    func testSensitivityChangesRequiredReversals() {
        var easy = BasketJiggleDetector(sensitivity: 5)
        easy.beginDrag(generation: 1, at: CGPoint(x: 100, y: 100))
        // 3 samples = 2 reversals → enough at sensitivity 5.
        XCTAssertEqual(shake(&easy, generation: 1, samples: 3), 1)

        var hard = BasketJiggleDetector(sensitivity: 1)
        hard.beginDrag(generation: 1, at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(shake(&hard, generation: 1, samples: 3), 0)
    }

    func testStaleGenerationAndResetAreIgnored() {
        var detector = BasketJiggleDetector(sensitivity: 3)
        detector.beginDrag(generation: 2, at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(shake(&detector, generation: 1, samples: 10), 0, "samples from an old drag are ignored")
        detector.endDrag()
        XCTAssertEqual(shake(&detector, generation: 2, samples: 10), 0, "cancelled/ended drag cannot trigger")
        detector.beginDrag(generation: 3, at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(shake(&detector, generation: 3, samples: 10), 1, "a new generation re-arms")
    }
}

@MainActor
final class BasketDragMonitorTests: XCTestCase {
    final class Probe: BasketDragProbe {
        var isPrimaryButtonDown = false
        var pointerLocation = CGPoint(x: 100, y: 100)
        var dragPasteboardChangeCount = 0
        var dragPasteboardHasFiles = true
        var now: TimeInterval = 0
    }

    private func makeMonitor(_ probe: Probe, sensitivity: Int = 3) -> (BasketDragMonitor, () -> [Int], () -> [Int]) {
        var jiggles: [Int] = []
        var ends: [Int] = []
        let monitor = BasketDragMonitor(
            probe: probe,
            sensitivity: { sensitivity },
            onJiggle: { generation, _ in jiggles.append(generation) },
            onDragEnded: { ends.append($0) }
        )
        return (monitor, { jiggles }, { ends })
    }

    private func shake(_ monitor: BasketDragMonitor, _ probe: Probe, samples: Int) {
        for index in 0..<samples {
            probe.now += 0.1
            probe.pointerLocation.x = index.isMultiple(of: 2) ? 160 : 100
            monitor.tick()
        }
    }

    func testOrdinaryMouseMovementWithoutFileDragNeverTriggers() {
        let probe = Probe()
        let (monitor, jiggles, _) = makeMonitor(probe)
        probe.isPrimaryButtonDown = true // click-drag with no new drag pasteboard
        shake(monitor, probe, samples: 20)
        XCTAssertEqual(jiggles(), [])
        XCTAssertFalse(monitor.isDragging)
    }

    func testUnsupportedDragPayloadDoesNotTrigger() {
        let probe = Probe()
        let (monitor, jiggles, _) = makeMonitor(probe)
        probe.dragPasteboardHasFiles = false
        probe.isPrimaryButtonDown = true
        probe.dragPasteboardChangeCount = 7
        shake(monitor, probe, samples: 20)
        XCTAssertEqual(jiggles(), [])
    }

    func testFileDragShakeTriggersOnceThenEndResets() {
        let probe = Probe()
        let (monitor, jiggles, ends) = makeMonitor(probe)
        probe.isPrimaryButtonDown = true
        probe.dragPasteboardChangeCount = 1
        monitor.tick()
        XCTAssertTrue(monitor.isDragging)
        let generation = monitor.generation
        shake(monitor, probe, samples: 30)
        XCTAssertEqual(jiggles(), [generation])

        probe.isPrimaryButtonDown = false
        monitor.tick()
        XCTAssertFalse(monitor.isDragging)
        XCTAssertEqual(ends(), [generation])

        // Same pasteboard change count + mouse down again = not a new file drag.
        probe.isPrimaryButtonDown = true
        shake(monitor, probe, samples: 20)
        XCTAssertEqual(jiggles(), [generation])

        // A genuinely new drag is a new generation and can trigger again.
        probe.isPrimaryButtonDown = false
        monitor.tick()
        probe.isPrimaryButtonDown = true
        probe.dragPasteboardChangeCount = 2
        monitor.tick()
        XCTAssertGreaterThan(monitor.generation, generation)
        shake(monitor, probe, samples: 30)
        XCTAssertEqual(jiggles().count, 2)
    }

    func testSuppressedDragDoesNotTrigger() {
        let probe = Probe()
        let (monitor, jiggles, _) = makeMonitor(probe)
        monitor.isSuppressed = { true } // e.g. a drag-out from our own Basket
        probe.isPrimaryButtonDown = true
        probe.dragPasteboardChangeCount = 1
        monitor.tick()
        shake(monitor, probe, samples: 30)
        XCTAssertEqual(jiggles(), [])
    }

    func testStopTearsDownTimerAndEndsActiveDragExactlyOnce() {
        let probe = Probe()
        let (monitor, _, ends) = makeMonitor(probe)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)

        probe.isPrimaryButtonDown = true
        probe.dragPasteboardChangeCount = 1
        monitor.tick()
        XCTAssertTrue(monitor.isDragging)
        let generation = monitor.generation

        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertFalse(monitor.isDragging)
        XCTAssertEqual(ends(), [generation])

        monitor.stop()
        XCTAssertEqual(ends(), [generation], "teardown must be idempotent and never double-end a drag")
    }
}
