import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentComposerDraftAcknowledgmentTests: XCTestCase {
    @MainActor private final class State: ObservableObject {
        @Published var visible = true
    }
    @MainActor private final class Submission {
        var pending: CheckedContinuation<Bool, Never>?
        func send(_ value: String) async -> Bool {
            await withCheckedContinuation { pending = $0 }
        }
        func finish(_ accepted: Bool) {
            let continuation = pending
            pending = nil
            continuation?.resume(returning: accepted)
        }
    }
    private struct Root: View {
        @ObservedObject var state: State
        let session: AgentSession
        let managed: AgentManagedSessionController
        let approvals: AgentApprovalController
        let submission: Submission
        var body: some View {
            Group {
                if state.visible {
                    AgentEmbeddedConsoleView(session: session, mode: .interactive(canInterrupt: false),
                        interactionState: .ready, showsOperationalTraffic: false, showsActivityOrb: false,
                        approvalControl: approvals, onSelectSession: { _ in },
                        onSubmit: submission.send, onInterrupt: {},
                        loadDraft: managed.composerDraft(for:), saveDraft: managed.setComposerDraft(_:for:))
                } else { Color.clear }
            }
            .frame(width: 600, height: 250)
            .environment(\.nativeVisualSnapshotTime, 1.35)
        }
    }

    func testAcceptedSubmissionPreservesDraftEditedBeforeUnmount() async throws {
        try await exercise(accepted: true, edit: true, replaceBeforeEditing: false)
    }
    func testAcceptedOldSubmissionPreservesReplacementComposerDraft() async throws {
        try await exercise(accepted: true, edit: true, replaceBeforeEditing: true)
    }
    func testAcceptedUnchangedSubmissionClearsExactStoredDraft() async throws {
        try await exercise(accepted: true, edit: false, replaceBeforeEditing: false)
    }
    func testRejectedSubmissionPreservesEditedDraft() async throws {
        try await exercise(accepted: false, edit: true, replaceBeforeEditing: false)
    }

    private func editor(in view: NSView) -> AgentPromptTextView? {
        if let editor = view as? AgentPromptTextView { return editor }
        return view.subviews.lazy.compactMap { self.editor(in: $0) }.first
    }
    private func settle(_ host: NSView) async {
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
    private func exercise(accepted: Bool, edit: Bool, replaceBeforeEditing: Bool) async throws {
        _ = NSApplication.shared
        let events = AgentEventStore()
        let native = AgentTestFixture.sessionID(.codex, "draft-ack-\(UUID())")
        events.ingest(AgentTestFixture.event("start", sessionID: native, type: .sessionStarted, offset: 0,
            payload: .sessionMetadata(.init(project: AgentTestFixture.project(path: "/tmp")))))
        let session = try XCTUnwrap(events.sessions.first)
        let approvals = AgentApprovalController()
        let managed = AgentManagedSessionController(provider: nil,
            coordinator: AgentIngestionCoordinator(eventStore: events), eventStore: events, approvals: approvals)
        managed.setComposerDraft("first", for: session.id)
        let state = State(), submission = Submission()
        let host = NSHostingView(rootView: Root(state: state, session: session, managed: managed,
                                               approvals: approvals, submission: submission))
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 600, height: 250),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            submission.finish(false)
            window.makeFirstResponder(nil); window.contentView = nil; window.orderOut(nil)
            managed.stop(); approvals.cancelAll()
        }
        await settle(host)
        let first = try XCTUnwrap(editor(in: host))
        XCTAssertEqual(first.string, "first")
        XCTAssertEqual(first.submitHandler?(), true)
        await settle(host)
        XCTAssertNotNil(submission.pending)
        if replaceBeforeEditing {
            state.visible = false; await settle(host)
            state.visible = true; await settle(host)
            XCTAssertFalse(editor(in: host) === first)
        }
        if edit {
            let current = try XCTUnwrap(editor(in: host))
            current.insertText("next", replacementRange: NSRange(location: 0, length: current.string.utf16.count))
            await settle(host)
            XCTAssertEqual(current.string, "next")
        }
        state.visible = false; await settle(host)
        XCTAssertEqual(managed.composerDraft(for: session.id), edit ? "next" : "first")
        submission.finish(accepted); await settle(host)
        let expected = edit ? "next" : (accepted ? "" : "first")
        XCTAssertEqual(managed.composerDraft(for: session.id), expected)
        state.visible = true; await settle(host)
        XCTAssertEqual(try XCTUnwrap(editor(in: host)).string, expected)
    }
}
