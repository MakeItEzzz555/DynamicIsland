import XCTest
@testable import DynamicIsland

/// Camera widget: registration, persistence, size grammar and the pure
/// capture-state resolver. Live capture itself is native acceptance work.
final class CameraWidgetTests: XCTestCase {
    private func resolve(
        sample: Bool = false, enabled: Bool = true, permission: CameraPermissionState = .authorized,
        phase: CameraPreviewPhase = .idle, session: Bool = false, devices: Bool = true
    ) -> CameraWidgetContent {
        .resolve(isSample: sample, isEnabled: enabled, permission: permission,
                 phase: phase, hasSession: session, hasDevices: devices)
    }

    func testOnlyARunningSessionShowsFrames() {
        XCTAssertEqual(resolve(phase: .running(deviceID: "a"), session: true), .live)
        // Running without a session object must not claim live frames.
        XCTAssertEqual(resolve(phase: .running(deviceID: "a"), session: false), .starting)
        XCTAssertEqual(resolve(phase: .starting), .starting)
    }

    func testAppearingNeverImpliesCaptureEachStateOffersOneExplicitAction() {
        XCTAssertEqual(resolve(permission: .notDetermined), .needsPermission)
        XCTAssertEqual(resolve(permission: .notDetermined).actionTitle, "Allow")
        XCTAssertEqual(resolve(), .ready)
        XCTAssertEqual(resolve().actionTitle, "Start")
        XCTAssertEqual(resolve(permission: .denied), .denied)
        XCTAssertEqual(resolve(permission: .restricted).actionTitle, "Open Settings")
        XCTAssertEqual(resolve(phase: .failed("Camera disconnected")), .failed("Camera disconnected"))
        XCTAssertEqual(resolve(phase: .failed("x")).actionTitle, "Retry")
        XCTAssertEqual(resolve(devices: false), .noCamera)
        XCTAssertNil(resolve(devices: false).actionTitle)
        XCTAssertEqual(resolve(phase: .stopping), .ready)
    }

    func testDisabledAndSampleWinOverEverything() {
        XCTAssertEqual(resolve(enabled: false, phase: .running(deviceID: "a"), session: true), .disabled)
        XCTAssertNil(resolve(enabled: false).actionTitle)
        // The Settings/editor sample never shows the shared session.
        XCTAssertEqual(resolve(sample: true, phase: .running(deviceID: "a"), session: true), .sample)
        XCTAssertNil(resolve(sample: true).actionTitle)
    }

    func testCameraIsAMediaSurfaceWidgetOnly() {
        XCTAssertTrue(IslandWidget.camera.isEligible(on: .media))
        XCTAssertFalse(IslandWidget.camera.isEligible(on: .agents))
        XCTAssertFalse(IslandWidget.camera.isBand)
        XCTAssertEqual(IslandWidget.camera.title, "Camera")
    }

    func testPlacementPersistsEverySizeAndUnknownKindsStayLossy() throws {
        for size in WidgetPresentationSize.allCases {
            let config = WorkspaceConfiguration(placements: [
                .init(kind: .camera, surface: .media, order: 0, size: size),
                .init(kind: .media, surface: .media, order: 1),
            ])
            let decoded = try JSONDecoder().decode(WorkspaceConfiguration.self, from: JSONEncoder().encode(config))
            XCTAssertEqual(decoded.placement(kind: .camera, on: .media)?.size, size)
        }
        // A build that does not know a kind drops that placement only.
        let json = #"{"schemaVersion":2,"placements":[{"kind":"hologram","surface":"media","order":0},{"kind":"camera","surface":"media","order":1,"size":"large"}]}"#
        let decoded = try JSONDecoder().decode(WorkspaceConfiguration.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.placements.map(\.kind), [.camera])
    }

    func testSizeGrammarIsTheSharedOneStandardIsTwoCompactWidthsSameHeight() {
        let grid = WidgetGridMetrics.make(surface: .media, metrics: .fallback)
        let compact = grid.size(for: .compact, kinds: [.camera])
        let standard = grid.size(for: .standard, kinds: [.camera])
        let large = grid.size(for: .large, kinds: [.camera])
        XCTAssertEqual(compact.width, compact.height, accuracy: 0.001)
        XCTAssertEqual(standard.height, compact.height, accuracy: 0.001)
        XCTAssertEqual(standard.width, grid.length(2), accuracy: 0.001)
        XCTAssertEqual(large.width, standard.width, accuracy: 0.001)
        XCTAssertEqual(large.height, grid.length(2), accuracy: 0.001)
    }
}
