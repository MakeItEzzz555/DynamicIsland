import XCTest
@testable import DynamicIsland

@MainActor
final class AgentNotificationFeedbackTests: XCTestCase {
    private let allReasons: [AgentAttentionReason] = [
        .planReady, .completed, .approvalRequired, .userInputRequired, .failed, .interrupted,
    ]

    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func intent(_ event: String, _ reason: AgentAttentionReason, generation: UInt64 = 1,
                        age: TimeInterval = 1) -> AgentAttentionSoundIntent {
        AgentAttentionSoundIntent(
            generation: AgentAttentionGeneration(rawValue: generation),
            eventID: AgentEventID(rawValue: event),
            reason: reason,
            occurredAt: now.addingTimeInterval(-age)
        )
    }

    private func feedback(enabled: Bool = true, loads: Bool = true) -> (SystemAgentNotificationFeedback, () -> [AgentNotificationSound]) {
        var played: [AgentNotificationSound] = []
        let feedback = SystemAgentNotificationFeedback(
            policy: AgentNotificationFeedbackPolicy(completionSoundEnabled: enabled),
            now: { [now] in now },
            emit: { sound in played.append(sound); return loads })
        return (feedback, { played })
    }

    func testAgentNotchParityHasNoSoundForAnyReason() {
        for reason in allReasons {
            XCTAssertNil(AgentNotchSoundParity.sound(for: reason), "\(reason)")
        }
    }

    /// Product policy (2026-10-06): one chime per fresh completed task.
    func testFirstCompletedEventChimesOnceAndDuplicatesAreSilent() {
        let (feedback, played) = feedback()
        XCTAssertEqual(feedback.handle(intent("done-1", .completed)), .completionChime)
        XCTAssertNil(feedback.handle(intent("done-1", .completed, generation: 2)), "re-projection")
        XCTAssertNil(feedback.handle(intent("done-1", .completed, generation: 9)), "re-render / replay")
        XCTAssertEqual(feedback.handle(intent("done-2", .completed)), .completionChime, "a different completion")
        XCTAssertEqual(played(), [.completionChime, .completionChime])
        XCTAssertEqual(AgentNotificationSound.completionChime.systemSoundName, "Glass")
    }

    func testOnlyCompletionSoundsAndTheSettingSilencesIt() {
        let (feedback, played) = feedback()
        for reason in allReasons where reason != .completed {
            XCTAssertNil(feedback.handle(intent("evt-\(reason.rawValue)", reason)), "\(reason) stays silent")
        }
        let (disabled, disabledPlayed) = self.feedback(enabled: false)
        XCTAssertNil(disabled.handle(intent("done", .completed)))
        XCTAssertTrue(played().isEmpty); XCTAssertTrue(disabledPlayed().isEmpty)
        XCTAssertNil(SystemAgentNotificationFeedback(emit: { _ in XCTFail("default policy is off until settings sync"); return true })
            .handle(intent("x", .completed)))
    }

    func testRestoredOrReplayedHistoryCannotChime() {
        let (feedback, played) = feedback()
        XCTAssertNil(feedback.handle(intent("old", .completed, age: 3_600)), "recovered completion from an hour ago")
        XCTAssertNil(feedback.handle(intent("old", .completed, age: 1)), "and it cannot ding later either")
        XCTAssertTrue(played().isEmpty)
    }

    func testUnloadableSoundStaysSilentWithoutFallback() {
        let (feedback, played) = feedback(loads: false)
        XCTAssertNil(feedback.handle(intent("done", .completed)), "no beep fallback; reported as silent")
        XCTAssertEqual(played(), [.completionChime], "one attempt only")
    }

    func testSameEventIdentityIsAdmittedOnce() {
        var dedup = AgentNotificationSoundDeduplicator()
        XCTAssertTrue(dedup.admit(intent("e1", .approvalRequired)))
        XCTAssertFalse(dedup.admit(intent("e1", .approvalRequired)))
    }

    func testReprojectionWithNewGenerationDoesNotReplay() {
        var dedup = AgentNotificationSoundDeduplicator()
        XCTAssertTrue(dedup.admit(intent("e1", .completed, generation: 1)))
        XCTAssertFalse(dedup.admit(intent("e1", .completed, generation: 2)))
        XCTAssertFalse(dedup.admit(intent("e1", .completed, generation: 99)))
    }

    func testDistinctEventsAreEachAdmittedOnce() {
        var dedup = AgentNotificationSoundDeduplicator()
        XCTAssertTrue(dedup.admit(intent("e1", .approvalRequired)))
        XCTAssertTrue(dedup.admit(intent("e2", .approvalRequired)))
        XCTAssertTrue(dedup.admit(intent("e1", .completed)))
        XCTAssertFalse(dedup.admit(intent("e2", .approvalRequired)))
    }

    func testBoundedMemoryEvictsOldestDeterministically() {
        var dedup = AgentNotificationSoundDeduplicator(capacity: 2)
        XCTAssertTrue(dedup.admit(intent("a", .completed)))
        XCTAssertTrue(dedup.admit(intent("b", .completed)))
        XCTAssertTrue(dedup.admit(intent("c", .completed))) // evicts "a"
        XCTAssertFalse(dedup.admit(intent("b", .completed)))
        XCTAssertFalse(dedup.admit(intent("c", .completed)))
        XCTAssertTrue(dedup.admit(intent("a", .completed)))
    }

    func testPolicyIsConsultedOncePerEventIdentity() {
        let (feedback, played) = feedback()
        feedback.play(intent("e1", .completed, generation: 1))
        feedback.play(intent("e1", .completed, generation: 2))
        feedback.play(intent("e1", .completed, generation: 2))
        XCTAssertEqual(played(), [.completionChime])
    }
}
