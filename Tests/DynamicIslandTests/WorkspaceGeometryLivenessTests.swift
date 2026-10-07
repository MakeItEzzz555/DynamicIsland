import Combine
import XCTest
@testable import DynamicIsland

/// Regression (2026-10-06): entering Agents edit mode with a connected Chat
/// showed a pitch-black shell for ~1.5 s. The preview subscriber read the
/// store in willSet (still nil), so edit geometry took the committed-layout
/// children-exit handoff instead of following the shell live.
@MainActor
final class WorkspaceGeometryLivenessTests: XCTestCase {
    func testPublishedSubscribersRunBeforeTheStoreHoldsTheNewValue() {
        let store = IslandLayoutStore()
        var storedDuringDelivery: Bool?
        var emitted: Bool?
        let subscription = store.$workspaceLayoutPreview.dropFirst().sink { preview in
            emitted = preview != nil
            storedDuringDelivery = store.workspaceLayoutPreview != nil
        }
        store.setWorkspaceLayoutPreview(.initial, surface: .agents)
        subscription.cancel()
        XCTAssertEqual(emitted, true)
        XCTAssertEqual(storedDuringDelivery, false, "why liveness must use the emitted value")
    }

    func testEditEntryIsLiveEvenWhenTheStoreIsReadTooEarly() {
        var liveness = WorkspaceGeometryLiveness()
        liveness.previewChanged(isPresent: true)
        // The check may run before or after the store holds the preview.
        XCTAssertTrue(liveness.consume(previewPresent: true))
        XCTAssertTrue(liveness.consume(previewPresent: true), "every check while editing is live")
    }

    func testTheChangeThatEndsEditingIsLiveThenCommittedChangesUseTheHandoff() {
        var liveness = WorkspaceGeometryLiveness()
        liveness.previewChanged(isPresent: true)
        _ = liveness.consume(previewPresent: true)
        liveness.previewChanged(isPresent: false)
        XCTAssertTrue(liveness.consume(previewPresent: false), "Apply/Cancel geometry follows the shell")
        XCTAssertFalse(liveness.consume(previewPresent: false), "later committed changes use children exit")
    }

}
