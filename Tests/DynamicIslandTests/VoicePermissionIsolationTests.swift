import Foundation
import Speech
import XCTest
@testable import DynamicIsland

/// Regression for the production crash (EXC_BREAKPOINT in
/// `SystemVoicePermissionProvider.requestSpeech()`): TCC delivers the Speech
/// authorization callback on a background queue. A callback that inherits
/// main-actor isolation trips Swift's runtime executor check and kills the app.
@MainActor
final class VoicePermissionIsolationTests: XCTestCase {
    func testSpeechAuthorizationCallbackFromBackgroundQueueDoesNotTrap() async {
        let provider = SystemVoicePermissionProvider(speechAuthorizationRequest: { reply in
            DispatchQueue.global(qos: .default).async { reply(.authorized) }
        })
        let state = await provider.requestSpeech()
        XCTAssertEqual(state, .authorized)
    }

    func testDeniedSpeechAuthorizationFromBackgroundQueueMapsToDenied() async {
        let provider = SystemVoicePermissionProvider(speechAuthorizationRequest: { reply in
            DispatchQueue.global(qos: .userInitiated).async { reply(.denied) }
        })
        let state = await provider.requestSpeech()
        XCTAssertEqual(state, .denied)
    }
}

/// Real Speech framework path. When authorization is already determined the
/// system answers without a prompt, on a background queue — exactly the
/// production crash condition. Skipped while undetermined (would prompt).
@MainActor
final class VoicePermissionRealCallbackTests: XCTestCase {
    func testRealSpeechAuthorizationRequestDoesNotTrap() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        print("SPEECH-AUTH status=\(status.rawValue)")
        guard status != .notDetermined else {
            throw XCTSkip("Speech authorization is undetermined for this process; requesting would prompt.")
        }
        let state = await SystemVoicePermissionProvider().requestSpeech()
        XCTAssertEqual(state, SystemVoicePermissionProvider.map(status))
    }
}
