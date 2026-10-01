import Foundation
import ScreenCaptureKit
import XCTest
@testable import DynamicIsland

/// Regression for "permission granted but nothing works": with an ad-hoc
/// signed build, TCC keeps the old entry (shown ON in System Settings) but
/// it no longer matches the rebuilt binary, so preflight stays false and
/// CGRequestScreenCaptureAccess returns false without a prompt. The flow
/// must surface a truthful, actionable state instead of a dead button.
@MainActor
private final class FakeScreenCaptureAuthorization: ScreenCaptureAuthorizing {
    var preflightResult = false
    var requestResult = false
    var contentError: Error = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
    var requests = 0
    var contentFetches = 0

    func preflight() -> Bool { preflightResult }
    func request() -> Bool {
        requests += 1
        return requestResult
    }
    func shareableContent() async throws -> SCShareableContent {
        contentFetches += 1
        throw contentError
    }
}

@MainActor
final class ScreenRecordingAccessTests: XCTestCase {
    func testAccessStateMatrix() {
        typealias C = ScreenRecordingController
        XCTAssertEqual(C.accessState(preflight: false, contentAvailable: true, requestAttempted: false), .granted,
                       "ScreenCaptureKit succeeding is authoritative even when the preflight cache is stale")
        XCTAssertEqual(C.accessState(preflight: false, contentAvailable: false, requestAttempted: false), .notGranted)
        XCTAssertEqual(C.accessState(preflight: false, contentAvailable: false, requestAttempted: true), .notActive)
        XCTAssertEqual(C.accessState(preflight: true, contentAvailable: false, requestAttempted: false), .notActive,
                       "preflight says yes but capture is refused: the grant is not active for this process")
        XCTAssertEqual(C.accessState(preflight: false, contentAvailable: nil, requestAttempted: false), .notGranted)
        XCTAssertEqual(C.accessState(preflight: false, contentAvailable: nil, requestAttempted: true), .notActive)
    }

    func testOpeningSetupNeverPromptsAndReportsNotGranted() async {
        let auth = FakeScreenCaptureAuthorization()
        let controller = makeController(auth)
        await controller.prepareTargets(requestPermission: false)
        XCTAssertEqual(auth.requests, 0)
        XCTAssertEqual(auth.contentFetches, 0)
        XCTAssertEqual(controller.accessState, .notGranted)
        XCTAssertFalse(controller.statusText.isEmpty)
    }

    func testAllowThatSilentlyReturnsFalseBecomesNotActiveWithRecoveryText() async {
        let auth = FakeScreenCaptureAuthorization()
        let controller = makeController(auth, adHoc: true)
        await controller.prepareTargets(requestPermission: true)
        XCTAssertEqual(auth.requests, 1)
        XCTAssertEqual(controller.accessState, .notActive)
        XCTAssertTrue(controller.statusText.contains("Relaunch"), controller.statusText)
        XCTAssertTrue(controller.statusText.contains("ad-hoc"), "rebuilt ad-hoc builds need the entry re-added")
        XCTAssertTrue(controller.displays.isEmpty)
    }

    func testStaleGrantWherePreflightIsTrueButCaptureIsRefusedIsNotActive() async {
        let auth = FakeScreenCaptureAuthorization()
        auth.preflightResult = true
        let controller = makeController(auth)
        await controller.prepareTargets(requestPermission: false)
        XCTAssertEqual(auth.contentFetches, 1)
        XCTAssertEqual(controller.accessState, .notActive)
    }

    func testStartWithoutActivePermissionFailsVisiblyAndNeverReportsRecording() async {
        let auth = FakeScreenCaptureAuthorization()
        let controller = makeController(auth)
        await controller.startDisplay(1)
        XCTAssertEqual(controller.phase, .failed)
        XCTAssertEqual(controller.accessState, .notActive)
        XCTAssertTrue(controller.statusText.contains("isn't active"), controller.statusText)
        XCTAssertFalse(controller.isActuallyCapturing)
    }

    func testNonPermissionContentFailureIsReportedAsCaptureFailure() async {
        let auth = FakeScreenCaptureAuthorization()
        auth.preflightResult = true
        auth.contentError = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.noCaptureSource.rawValue)
        let controller = makeController(auth)
        await controller.prepareTargets(requestPermission: false)
        XCTAssertEqual(controller.accessState, .granted)
        XCTAssertFalse(controller.statusText.isEmpty)
    }

    private func makeController(_ auth: FakeScreenCaptureAuthorization, adHoc: Bool = false) -> ScreenRecordingController {
        ScreenRecordingController(
            liveActivities: LiveActivityStore(),
            capabilities: IslandCapabilityRegistry(),
            authorization: auth,
            isAdHocSigned: adHoc
        )
    }
}
