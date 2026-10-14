import XCTest
@testable import DynamicIsland

final class MeetingPresenceTests: XCTestCase {
    private let time = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func evidence(_ seconds: Double, bundle: String = "fixture.meeting", running: Bool = true,
                          input: Bool? = true, confirmed: Bool = false, start: Date? = nil) -> MeetingPresenceEvidence {
        .init(bundleIdentifier: bundle, applicationRunning: running, audioInputActive: input,
              providerConfirmed: confirmed, authoritativeStartedAt: start, observedAt: time.addingTimeInterval(seconds))
    }
    func testPresenceAndUnknownInputCannotInventMeeting() {
        var reducer = MeetingPresenceReducer()
        for input in [nil, false] as [Bool?] {
            reducer.consume(evidence(0, input: input), now: time)
            XCTAssertEqual(reducer.presence.state, .notDetected)
            XCTAssertNil(reducer.presence.startedAt)
        }
    }
    func testSustainedAudioInputOnlyReachesLikelyNeverConfirmedOrElapsed() {
        var reducer = MeetingPresenceReducer()
        reducer.consume(evidence(0), now: time)
        XCTAssertEqual(reducer.presence.state, .possibleMeeting)
        reducer.consume(evidence(1), now: time.addingTimeInterval(1))
        XCTAssertEqual(reducer.presence.state, .possibleMeeting)
        reducer.consume(evidence(2), now: time.addingTimeInterval(2))
        XCTAssertEqual(reducer.presence.state, .likelyMeeting)
        XCTAssertEqual(reducer.presence.sources, [.coreAudioInput, .applicationPresence])
        XCTAssertNil(reducer.presence.startedAt)
        reducer.consume(evidence(3, input: false), now: time.addingTimeInterval(3))
        XCTAssertEqual(reducer.presence.state, .notDetected)
    }
    func testOnlyDirectProviderCanConfirmAndSupplyAuthoritativeStart() {
        var reducer = MeetingPresenceReducer()
        reducer.consume(evidence(0, input: nil, confirmed: true, start: time), now: time)
        XCTAssertEqual(reducer.presence.state, .confirmedMeeting)
        XCTAssertEqual(reducer.presence.sources, [.verifiedProvider, .applicationPresence])
        XCTAssertEqual(reducer.presence.startedAt, time)
        reducer.consume(evidence(1, input: nil, confirmed: true), now: time.addingTimeInterval(1))
        XCTAssertNil(reducer.presence.startedAt)
    }
    func testStaleOutOfOrderAndFutureEvidenceCannotKeepSessionAlive() {
        var reducer = MeetingPresenceReducer()
        reducer.consume(evidence(0), now: time)
        reducer.consume(evidence(-1, bundle: "wrong"), now: time)
        XCTAssertEqual(reducer.presence.bundleIdentifier, "fixture.meeting")
        reducer.consume(evidence(10), now: time)
        XCTAssertEqual(reducer.presence.state, .possibleMeeting)
        reducer.expire(now: time.addingTimeInterval(8.01))
        XCTAssertEqual(reducer.presence.state, .notDetected)
        reducer.consume(evidence(0), now: time.addingTimeInterval(9))
        XCTAssertEqual(reducer.presence.state, .notDetected)
    }
    func testApplicationSwitchRestartsDwellAndPermissionFailureClearsAuthority() {
        var reducer = MeetingPresenceReducer()
        reducer.consume(evidence(0), now: time)
        reducer.consume(evidence(2, bundle: "second"), now: time.addingTimeInterval(2))
        XCTAssertEqual(reducer.presence.state, .possibleMeeting)
        reducer.unavailable(reason: "Audio process activity unavailable", now: time.addingTimeInterval(3))
        XCTAssertEqual(reducer.presence.state, .unavailable)
        XCTAssertNil(reducer.presence.audioInputActive)
        reducer.consume(evidence(4, running: false), now: time.addingTimeInterval(4))
        XCTAssertEqual(reducer.presence.state, .notDetected)
    }
    @MainActor
    func testNativeProviderRequiresAllowedApplicationAndExactRunningPID() {
        let provider = MeetingPresenceProvider(running: { _, pid in pid == 42 }, now: { self.time })
        provider.consume(.success([.init(bundleIdentifier: "us.zoom.xos", pid: 41, inputActive: true)]))
        XCTAssertEqual(provider.presence.state, .notDetected)
        provider.consume(.success([.init(bundleIdentifier: "unknown.app", pid: 42, inputActive: true)]))
        XCTAssertEqual(provider.presence.state, .notDetected)
        provider.consume(.success([.init(bundleIdentifier: "us.zoom.xos", pid: 42, inputActive: true)]))
        XCTAssertEqual(provider.presence.state, .possibleMeeting)
        XCTAssertNil(provider.presence.startedAt)
        provider.consume(.failure(.readFailed(-1)))
        XCTAssertEqual(provider.presence.state, .unavailable)
        XCTAssertNil(provider.presence.audioInputActive)
        provider.stop()
        XCTAssertEqual(provider.presence.state, .notDetected)
        XCTAssertFalse(provider.enabled)
    }

    @MainActor
    func testDelayedAndOutOfOrderNativeResultsCannotCreateOrWithdrawFreshPresence() {
        let provider = MeetingPresenceProvider(running: { _, _ in true }, now: { self.time })
        let processes = [MeetingAudioProcess(bundleIdentifier: "us.zoom.xos", pid: 42, inputActive: true)]
        provider.consume(.success(processes), observedAt: time.addingTimeInterval(-9))
        XCTAssertEqual(provider.presence.state, .notDetected)
        provider.consume(.success(processes), observedAt: time)
        XCTAssertEqual(provider.presence.state, .possibleMeeting)
        provider.consume(.failure(.readFailed(-1)), observedAt: time.addingTimeInterval(-1))
        XCTAssertEqual(provider.presence.state, .possibleMeeting)
        provider.consume(.success(processes), observedAt: time.addingTimeInterval(1))
        XCTAssertEqual(provider.presence.observedAt, time)
        provider.stop()
    }

}
