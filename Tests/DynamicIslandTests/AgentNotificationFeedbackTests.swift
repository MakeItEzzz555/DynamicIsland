import XCTest
@testable import DynamicIsland

@MainActor
final class AgentNotificationFeedbackTests: XCTestCase {
    private let allReasons: [AgentAttentionReason] = [
        .planReady, .completed, .approvalRequired, .userInputRequired, .failed, .interrupted,
    ]

    private func intent(_ event: String, _ reason: AgentAttentionReason, generation: UInt64 = 1) -> AgentAttentionSoundIntent {
        AgentAttentionSoundIntent(
            generation: AgentAttentionGeneration(rawValue: generation),
            eventID: AgentEventID(rawValue: event),
            reason: reason
        )
    }

    func testAgentNotchParityHasNoSoundForAnyReason() {
        for reason in allReasons {
            XCTAssertNil(AgentNotchSoundParity.sound(for: reason), "\(reason)")
        }
    }

    func testProductionFeedbackIsSilentForApprovalAndCompletion() {
        let feedback = SystemAgentNotificationFeedback()
        for reason in allReasons {
            XCTAssertNil(feedback.handle(intent("evt-\(reason.rawValue)", reason)))
        }
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

    func testFeedbackConsultsParityOncePerEventIdentity() {
        var lookups: [AgentAttentionReason] = []
        let feedback = SystemAgentNotificationFeedback(soundForReason: { reason in
            lookups.append(reason)
            return AgentNotchSoundParity.sound(for: reason)
        })
        feedback.play(intent("e1", .approvalRequired, generation: 1))
        feedback.play(intent("e1", .approvalRequired, generation: 2))
        feedback.play(intent("e1", .approvalRequired, generation: 2))
        feedback.play(intent("e2", .completed, generation: 3))
        XCTAssertEqual(lookups, [.approvalRequired, .completed])
    }
}
