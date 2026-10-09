import AgentBridgeShared
import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Development-only production-view review. Provider inputs and terminal output
/// are deterministic fixtures, never evidence of live provider acceptance.
@MainActor
final class AgentWorkspaceSnapshotTests: XCTestCase {
    private let fixtureDate = AgentTestFixture.baseDate

    func testRenderAgentsWorkspaceReview() async throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR for the native workspace review harness.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cases = [
            "01-codex-idle", "02-codex-solving", "03-codex-searching", "04-codex-command",
            "05-codex-approval", "06-codex-composing", "07-claude-working", "08-concurrent-providers",
            "09-feed-pending", "10-feed-denied", "11-feed-approved", "12-feed-history",
            "13-terminal", "14-right-workspace-expanded", "15-chat-mode", "16-compact-active",
            "17-expanded-active", "18-reduce-motion", "19-six-usage-indicators", "20-narrow-width",
            "21-feed-delivering", "22-feed-failed", "23-light-theme"
        ]
        for name in cases {
            let fixture = try await makeFixture()
            defer { fixture.controller.stop(); fixture.approvals.cancelAll(); fixture.terminal.terminate() }
            let isClaude = name == "07-claude-working"
            let owner = isClaude ? AgentProvider.claude : .codex
            let activeID = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == owner }?.id)
            fixture.controller.selectProvider(owner)
            fixture.controller.selectSession(activeID)
            var approvalWaiter: Task<AgentBridgePermissionDecision?, Never>?
            defer { approvalWaiter?.cancel() }

            if name.contains("approval") || name.contains("feed-pending") || name.contains("feed-denied") ||
                name.contains("feed-approved") || name.contains("feed-delivering") || name.contains("feed-failed") {
                emit(fixture, session: activeID, type: .approvalRequested, correlation: "turn/request", offset: 10,
                     payload: .approvalRequest(.init(summary: "Run the repository validation command", operationCorrelationID: nil, expiresAt: nil)))
                let key = AgentApprovalControlKey(session: activeID, requestID: AgentTestFixture.correlation("turn/request"))
                approvalWaiter = Task {
                    await fixture.approvals.request(.init(key: key, summary: "Run the repository validation command", expiresAt: .distantFuture), maximumWait: nil)
                }
                for _ in 0..<500 where fixture.approvals.pendingRequests[key] == nil { await Task.yield() }
                XCTAssertNotNil(fixture.approvals.pendingRequests[key])
                if name.contains("denied") || name.contains("approved") || name.contains("delivering") || name.contains("failed") {
                    let denied = name.contains("denied")
                    XCTAssertEqual(fixture.approvals.resolve(session: activeID, requestID: key.requestID, decision: denied ? .deny : .allow), .accepted)
                    _ = await approvalWaiter?.value
                    if name.contains("delivering") {
                        XCTAssertEqual(fixture.feed.items.first?.approvalPresentation(delivery: fixture.approvals.deliveryState(for: key)), .submitting)
                    } else if name.contains("failed") {
                        fixture.approvals.failDelivery(key, reason: "Fixture transport did not acknowledge this decision")
                    } else {
                        // Explicit simulated provider acknowledgement, separate
                        // from selecting a decision in the approval controller.
                        fixture.approvals.confirmDelivery(key)
                        emit(fixture, session: activeID, type: .approvalResolved, correlation: key.requestID.rawValue, offset: 11,
                             payload: .approvalResolution(.init(state: denied ? .denied : .approved)))
                    }
                }
            } else if name != "01-codex-idle" && name != "19-six-usage-indicators" {
                let kind: AgentProcessingKind = name.contains("search") ? .searching : name.contains("compos") ? .composing : .reasoning
                if name.contains("command") || isClaude {
                    emit(fixture, session: activeID, type: .commandStarted, correlation: "command", offset: 10,
                         payload: .command(.init(executable: "swift", success: nil, exitCode: nil, processingKind: .executing)))
                } else {
                    emit(fixture, session: activeID, type: .agentWorking, correlation: "processing", offset: 10,
                         payload: .activity(.init(title: nil, summary: nil, processingKind: kind, processingStatus: .active)))
                }
            }
            if name == "08-concurrent-providers" || name == "12-feed-history" {
                let claudeID = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == .claude }?.id)
                emit(fixture, session: claudeID, type: .toolStarted, correlation: "claude-tool", offset: 12,
                     payload: .tool(.init(name: "Read", category: "read", summary: nil, success: nil, processingKind: .listening)))
                if name == "12-feed-history" {
                    emit(fixture, session: claudeID, type: .toolCompleted, correlation: "claude-tool", offset: 13,
                         payload: .tool(.init(name: "Read", category: "read", summary: nil, success: true)))
                    emit(fixture, session: claudeID, type: .taskCompleted, offset: 14, payload: .terminal(.init(summary: nil)))
                    emit(fixture, session: activeID, type: .commandStarted, correlation: "validation", offset: 15,
                         payload: .command(.init(executable: "swift", success: nil, exitCode: nil)))
                }
            }
            if name == "13-terminal" {
                fixture.presentation.interact(.terminal)
                try fixture.terminal.run(command: "swift test --filter AgentWorkspace")
                await Task.yield()
                XCTAssertEqual(fixture.presentation.mode, .terminal)
                XCTAssertEqual(fixture.presentation.interactionMode, .terminal)
                XCTAssertEqual(fixture.runner.startCount, 1)
            }
            if name == "14-right-workspace-expanded" { fixture.presentation.toggleEmphasis() }
            if name == "15-chat-mode" { fixture.presentation.interact(.terminal); fixture.presentation.interact(.chat); fixture.presentation.select(.feed) }
            let reduceMotion = name == "18-reduce-motion"
            let width: CGFloat = name == "20-narrow-width" ? 560 : 960
            let size = CGSize(width: width, height: 510)
            let selected = try XCTUnwrap(fixture.store.session(for: activeID))
            if name == "16-compact-active" {
                try await hosted(compact(selected), size: CGSize(width: 410, height: 70), reduceMotion: false, light: false,
                                 to: output.appendingPathComponent(name + ".png"))
            } else if name == "19-six-usage-indicators" {
                // Provider-grouped quota usage; Context is not presented.
                let groups = AgentWorkspaceUsageProjection.providerGroups(accountUsage: fixture.controller.accountUsageByProvider, now: fixtureDate)
                XCTAssertEqual(groups[.codex]?.map(\.kind), [.fiveHour, .week])
                XCTAssertEqual(groups[.claude]?.map(\.kind), [.fiveHour, .week])
                try await hosted(AgentWorkspaceUsageStrip(managedControl: fixture.controller).padding(20), size: CGSize(width: 700, height: 120),
                                 reduceMotion: false, light: false, to: output.appendingPathComponent(name + ".png"))
            } else {
                let columns = AgentWorkspaceColumns.make(width: width - 28, emphasized: fixture.presentation.isEmphasized)
                XCTAssertGreaterThan(columns.chat, 0)
                XCTAssertGreaterThan(columns.workspace, 0)
                XCTAssertLessThanOrEqual(columns.chat + columns.workspace + columns.gap, width - 28 + 0.001)
                let view = AgentDashboardContentView(
                    sessions: fixture.store.sessions, accountUsage: fixture.controller.accountUsage, showsUsage: true,
                    approvalControl: fixture.approvals, managedControl: fixture.controller, availableHeight: size.height - 28,
                    initialSelectedSessionID: activeID, contentVisible: true, reduceMotion: reduceMotion,
                    transcriptPresentationReady: true, transcriptLoadDelay: 0,
                    workspaceFeed: fixture.feed, workspacePresentation: fixture.presentation, terminal: fixture.terminal
                ).padding(14)
                try await hosted(view, size: size, reduceMotion: reduceMotion, light: name == "23-light-theme",
                                 to: output.appendingPathComponent(name + ".png"))
            }
        }
        try """
        Evidence: PASS — automated/fixture
        23 deterministic production-view workspace review scenarios.
        Native providers, approval acknowledgements, usage and terminal traffic are fixture inputs.
        Native NSHostingView/window snapshots exercise actual workspace view hierarchy.
        Metal-backed BorderBeam pixel fidelity is NOT VERIFIED by bitmapImageRepForCachingDisplay;
        use the dedicated native GPU/offscreen Beam reference harness for shader parity.
        Reduce Motion here is view-input/fixture coverage, not actual macOS-setting acceptance.
        These snapshots do not establish live provider or human-interaction acceptance.
        """.write(to: output.appendingPathComponent("EVIDENCE.txt"), atomically: true, encoding: .utf8)
    }



    func testPlainReturnSubmitsAgentPromptFromNativeEditor() async throws {
        let fixture = try await makeFixture()
        defer {
            fixture.controller.stop()
            fixture.approvals.cancelAll()
            fixture.terminal.terminate()
        }

        let selected = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == .codex })
        fixture.controller.selectProvider(.codex)
        fixture.controller.selectSession(selected.id)

        let size = CGSize(width: 900, height: 480)
        let view = AgentDashboardContentView(
            sessions: fixture.store.sessions,
            accountUsage: fixture.controller.accountUsage,
            showsUsage: true,
            approvalControl: fixture.approvals,
            managedControl: fixture.controller,
            availableHeight: 460,
            initialSelectedSessionID: selected.id,
            contentVisible: true,
            reduceMotion: true,
            transcriptPresentationReady: true,
            transcriptLoadDelay: 0,
            workspaceFeed: fixture.feed,
            workspacePresentation: fixture.presentation,
            terminal: fixture.terminal
        )
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer {
            window.makeFirstResponder(nil)
            window.orderOut(nil)
            window.contentView = nil
        }

        for _ in 0..<10 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(4))
            hosting.layoutSubtreeIfNeeded()
        }
        let editor = try XCTUnwrap(Self.findPromptEditor(in: hosting))
        XCTAssertTrue(window.makeFirstResponder(editor))
        editor.insertText("plain return sends", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(8))

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
        editor.keyDown(with: event)

        for _ in 0..<20 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        fixture.controller.flushTranscriptPublications()
        XCTAssertTrue(
            fixture.controller.transcript(for: selected).contains {
                $0.role == .user && $0.text == "plain return sends"
            }
        )
    }

    func testNativeTranscriptKeepsLatestVisibleDuringStreamingAndRespectsHistoryScroll() async throws {
        let fixture = try await makeFixture()
        defer { fixture.controller.stop(); fixture.approvals.cancelAll(); fixture.terminal.terminate() }
        let session = try XCTUnwrap(fixture.store.sessions.first)
        let state = TranscriptViewportFixtureState()
        state.entries = (0..<8).map { index in
            AgentManagedTranscriptEntry(id: "viewport-\(index)", nativeSessionID: session.id.sessionID.nativeID,
                turnID: "viewport-turn", role: .agent,
                text: (0..<12).map { "History \(index) line \($0)" }.joined(separator: "\n"), timestamp: fixtureDate.addingTimeInterval(Double(index)))
        }
        let root = TranscriptViewportFixtureView(state: state, session: session, approvals: fixture.approvals)
        var hosting = NSHostingView(rootView: root.frame(width: 440, height: 300))
        hosting.frame = CGRect(x: 0, y: 0, width: 440, height: 300)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while Self.findTranscriptScrollView(in: hosting) == nil, ContinuousClock.now < deadline {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(5))
        }
        var scroll = try XCTUnwrap(Self.findTranscriptScrollView(in: hosting))
        func tailMarker(in view: NSView) -> AgentTranscriptTailMarker.Marker? {
            if let marker = view as? AgentTranscriptTailMarker.Marker { return marker }
            for child in view.subviews { if let marker = tailMarker(in: child) { return marker } }
            return nil
        }
        func distanceFromBottom() -> CGFloat {
            guard let document = scroll.documentView, let marker = tailMarker(in: hosting) else { return .greatestFiniteMagnitude }
            return marker.convert(marker.bounds, to: document).maxY - scroll.contentView.bounds.maxY
        }
        func waitForBottom() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            // The actual message is the anchor. Padding and the measuring
            // sentinel follow it, so document-bottom equality is not required.
            while (distanceFromBottom() > AgentTranscriptFollowState.nearBottomThreshold || distanceFromBottom() < -1), ContinuousClock.now < deadline {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertLessThanOrEqual(distanceFromBottom(), AgentTranscriptFollowState.nearBottomThreshold,
                                     "Latest response must remain within the near-bottom viewport")
            XCTAssertGreaterThanOrEqual(distanceFromBottom(), -1, "The viewport must not overshoot below actual content")
        }
        func waitForContentGrowth(from previousHeight: CGFloat, line: UInt = #line) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while (scroll.documentView?.bounds.height ?? 0) == previousHeight, ContinuousClock.now < deadline {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertNotEqual(scroll.documentView?.bounds.height ?? 0, previousHeight,
                              "Observe layout changing; a lazy document estimate may shrink as text is realized", line: line)
        }
        try await waitForBottom()
        for index in 0..<6 {
            let previousHeight = scroll.documentView?.bounds.height ?? 0
            var latest = try XCTUnwrap(state.entries.last)
            latest = AgentManagedTranscriptEntry(id: latest.id, nativeSessionID: latest.nativeSessionID,
                turnID: latest.turnID, role: latest.role, text: latest.text + "\nStreamed line \(index)", timestamp: latest.timestamp)
            state.entries[state.entries.count - 1] = latest
            try await waitForContentGrowth(from: previousHeight)
            try await waitForBottom()
        }
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        hosting.layoutSubtreeIfNeeded()
        // Wait for the measured viewport to report this actual user-owned scroll.
        for _ in 0..<8 { await Task.yield(); hosting.layoutSubtreeIfNeeded() }
        let historyOffset = scroll.contentView.bounds.origin.y
        let historyHeight = scroll.documentView?.bounds.height ?? 0
        state.entries.append(AgentManagedTranscriptEntry(id: "viewport-next", nativeSessionID: session.id.sessionID.nativeID,
            turnID: "viewport-next-turn", role: .agent, text: "New response while reading history", timestamp: fixtureDate.addingTimeInterval(10)))
        try await waitForContentGrowth(from: historyHeight)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, historyOffset, accuracy: 8,
                       "Streaming must not yank a reader away from history")
        if let document = scroll.documentView {
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, document.bounds.maxY - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        }
        for _ in 0..<8 { await Task.yield(); hosting.layoutSubtreeIfNeeded() }
        let resumedHeight = scroll.documentView?.bounds.height ?? 0
        state.entries.append(AgentManagedTranscriptEntry(id: "viewport-resumed", nativeSessionID: session.id.sessionID.nativeID,
            turnID: "viewport-resumed-turn", role: .agent, text: "Following resumed\nLatest response", timestamp: fixtureDate.addingTimeInterval(11)))
        try await waitForContentGrowth(from: resumedHeight)
        try await waitForBottom()

        func remount() async throws {
            window.contentView = nil
            hosting = NSHostingView(rootView: root.frame(width: 440, height: 300))
            hosting.frame = CGRect(x: 0, y: 0, width: 440, height: 300)
            window.contentView = hosting
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while Self.findTranscriptScrollView(in: hosting) == nil, ContinuousClock.now < deadline {
                hosting.layoutSubtreeIfNeeded(); await Task.yield()
            }
            scroll = try XCTUnwrap(Self.findTranscriptScrollView(in: hosting))
            try await waitForBottom()
            XCTAssertEqual(distanceFromBottom(), 0, accuracy: 1,
                           "The realized latest row, rather than estimated document space, owns following")
        }
        try await remount()
        window.contentView = nil
        state.entries.append(AgentManagedTranscriptEntry(id: "arrived-while-collapsed", nativeSessionID: session.id.sessionID.nativeID,
            turnID: "collapsed-turn", role: .agent, text: String(repeating: "New actual latest\n", count: 16), timestamp: fixtureDate.addingTimeInterval(12)))
        try await remount()
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 50))
        scroll.reflectScrolledClipView(scroll.contentView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        for _ in 0..<8 { await Task.yield(); hosting.layoutSubtreeIfNeeded() }
        let savedReading = scroll.contentView.bounds.origin.y
        XCTAssertFalse(AgentTranscriptViewportStore.shared.position(for: session.id).followingLatest)
        window.contentView = nil
        hosting = NSHostingView(rootView: root.frame(width: 440, height: 300))
        hosting.frame = CGRect(x: 0, y: 0, width: 440, height: 300)
        window.contentView = hosting
        for _ in 0..<20 { await Task.yield(); hosting.layoutSubtreeIfNeeded() }
        scroll = try XCTUnwrap(Self.findTranscriptScrollView(in: hosting))
        XCTAssertEqual(scroll.contentView.bounds.origin.y, savedReading, accuracy: 1, "History intent survives unmount")

        // Three substantially different tall responses expose lazy document
        // estimates that a document-bottom-only assertion can falsely accept.
        func latestText(in view: NSView) -> AgentStreamingTextView? {
            if let text = view as? AgentStreamingTextView { return text }
            for child in view.subviews { if let text = latestText(in: child) { return text } }
            return nil
        }
        for index in 0..<3 {
            var saved = AgentTranscriptViewportStore.shared.position(for: session.id)
            saved.followingLatest = true
            AgentTranscriptViewportStore.shared.save(saved, for: session.id)
            state.entries.append(AgentManagedTranscriptEntry(id: "tall-response-\(index)", nativeSessionID: session.id.sessionID.nativeID,
                turnID: "tall-turn-\(index)", role: .agent,
                text: (0..<(60 + index * 20)).map { "\($0). Long response words wrap accurately without an empty viewport." }.joined(separator: "\n"), timestamp: fixtureDate.addingTimeInterval(Double(100 + index))))
            window.contentView = nil
            hosting = NSHostingView(rootView: root.frame(width: 440, height: 300))
            hosting.frame = CGRect(x: 0, y: 0, width: 440, height: 300)
            window.contentView = hosting
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            var distance = CGFloat.greatestFiniteMagnitude
            repeat {
                hosting.layoutSubtreeIfNeeded(); await Task.yield()
                if let text = latestText(in: hosting), let nativeScroll = Self.findTranscriptScrollView(in: hosting), let document = nativeScroll.documentView,
                   let manager = text.layoutManager, let container = text.textContainer {
                    let inkEnd = manager.usedRect(for: container).maxY
                    let end = text.convert(CGPoint(x: 0, y: inkEnd), to: document).y
                    distance = end - nativeScroll.contentView.bounds.maxY
                }
            } while (distance > 8 || distance < -24) && ContinuousClock.now < deadline
            XCTAssertGreaterThanOrEqual(distance, -24, "The actual latest glyphs, not estimated blank document space, must be visible")
            XCTAssertLessThanOrEqual(distance, 8, "A tall remounted response must restore its actual text end")
        }
    }

    private static func findTranscriptScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let scroll = findTranscriptScrollView(in: child) { return scroll }
        }
        return nil
    }

    func testLongApprovalContextWrapsWithoutTruncationAndPreservesExactRequest() async throws {
        let fixture = try await makeFixture()
        defer { fixture.controller.stop(); fixture.approvals.cancelAll(); fixture.terminal.terminate() }
        let summary = (1...12).map { "Validation step \($0): read the selected repository without changing its files." }.joined(separator: "\n")
        for provider in [AgentProvider.codex, .claude] {
            let session = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == provider })
            let key = AgentApprovalControlKey(session: session.id, requestID: AgentTestFixture.correlation("long-context-\(provider.stableName)"))
            let request = AgentApprovalControlRequest(key: key, summary: summary, expiresAt: .distantFuture)
            for width: CGFloat in [240, 440] {
                let hosting = NSHostingView(rootView: AgentConsoleApprovalRow(request: request, session: session,
                    approvalControl: fixture.approvals).frame(width: width).fixedSize(horizontal: false, vertical: true))
                hosting.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
                let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                window.orderFrontRegardless()
                defer { window.orderOut(nil); window.contentView = nil }
                for _ in 0..<8 { await Task.yield(); hosting.layoutSubtreeIfNeeded() }
                XCTAssertGreaterThan(hosting.fittingSize.height, 220, "All twelve context lines must be readable instead of truncated at three")
                XCTAssertEqual(hosting.fittingSize.width, width, accuracy: 1, "Context must wrap within its assigned width")
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("dynamicisland-approval-\(provider.stableName)-\(Int(width)).png"))
                XCTAssertEqual(request.key, key)
                XCTAssertNil(fixture.approvals.deliveryState(for: key), "Layout must never deliver a decision")
            }
        }
    }


    func testTerminalReturnSendsInputToOnePersistentNativeShell() async throws {
        let fixture = try await makeFixture()
        defer {
            fixture.controller.stop()
            fixture.approvals.cancelAll()
            fixture.terminal.terminate()
        }
        let selected = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == .codex })
        fixture.presentation.select(.terminal)

        let size = CGSize(width: 440, height: 300)
        let view = AgentWorkspaceTerminalView(
            controller: fixture.terminal,
            session: selected,
            isVisible: true,
            focusRequest: fixture.presentation.terminalFocusRequest,
            layoutStore: nil
        )
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer {
            window.makeFirstResponder(nil)
            window.orderOut(nil)
            window.contentView = nil
        }

        for _ in 0..<10 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(4))
            hosting.layoutSubtreeIfNeeded()
        }
        let terminal = try XCTUnwrap(Self.findInteractiveTerminal(in: hosting))
        XCTAssertTrue(terminal === fixture.terminal.terminalView)
        XCTAssertTrue(window.makeFirstResponder(terminal))
        XCTAssertEqual(fixture.runner.startCount, 1, "Visibility starts exactly one persistent shell before typing")
        let transcriptBefore = fixture.controller.transcript(for: selected)
        terminal.insertText("printf terminal-enter-ok", replacementRange: NSRange(location: NSNotFound, length: 0))
        let enter = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        terminal.keyDown(with: enter)
        XCTAssertEqual(fixture.runner.startCount, 1, "Return cannot create a second shell")
        XCTAssertTrue(fixture.terminal.isRunning)
        XCTAssertEqual(String(decoding: fixture.runner.handle.input, as: UTF8.self), "printf terminal-enter-ok\r")
        XCTAssertEqual(fixture.runner.handle.input.last, 13, "Native Enter belongs to PTY input")
        XCTAssertEqual(fixture.controller.transcript(for: selected), transcriptBefore,
            "Terminal Return must never submit an agent prompt")
        XCTAssertEqual(fixture.terminal.processID, fixture.runner.handle.processID)

    }

    func testCurrentNativeTerminalHostReclaimsOrphanAndRejectsRetiredHost() async throws {
        _ = NSApplication.shared
        let runner = WorkspaceSnapshotTerminalRunner()
        let controller = TerminalSessionController(liveActivities: LiveActivityStore(),
            capabilities: IslandCapabilityRegistry(), runner: runner, workingDirectoryPath: "/tmp")
        defer { controller.terminate() }
        let size = CGSize(width: 420, height: 220)
        func terminal(_ request: Int) -> AnyView {
            AnyView(NativeTerminalHost(controller: controller, initialDirectory: "/tmp",
                isVisible: true, focusRequest: request).frame(width: size.width, height: size.height))
        }
        let current = NSHostingView(rootView: terminal(0))
        let transient = NSHostingView(rootView: AnyView(EmptyView()))
        let currentWindow = NSWindow(contentRect: CGRect(origin: CGPoint(x: -5000, y: -5000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let transientWindow = NSWindow(contentRect: CGRect(origin: CGPoint(x: -6000, y: -5000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        for window in [currentWindow, transientWindow] { window.isReleasedWhenClosed = false }
        defer {
            for window in [currentWindow, transientWindow] {
                window.makeFirstResponder(nil)
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
        }
        current.frame = CGRect(origin: .zero, size: size)
        currentWindow.contentView = current
        currentWindow.orderFrontRegardless()
        let initialDeadline = ContinuousClock.now + .seconds(2)
        while (controller.terminalView.superview == nil || !controller.isRunning), ContinuousClock.now < initialDeadline {
            try await Task.sleep(for: .milliseconds(3))
            current.layoutSubtreeIfNeeded()
        }
        let currentMount = try XCTUnwrap(controller.terminalView.superview as? TerminalMountView)
        XCTAssertTrue(currentMount.isDescendant(of: current))
        XCTAssertTrue(currentMount.wasVisible)
        XCTAssertTrue(controller.isRunning)

        transient.rootView = terminal(1)
        transient.frame = CGRect(origin: .zero, size: size)
        transientWindow.contentView = transient
        transientWindow.orderFrontRegardless()
        let claimDeadline = ContinuousClock.now + .seconds(2)
        while controller.terminalView.superview === currentMount
                || controller.terminalView.superview?.isDescendant(of: transient) != true,
              ContinuousClock.now < claimDeadline {
            try await Task.sleep(for: .milliseconds(3))
            transient.layoutSubtreeIfNeeded()
        }
        let transientMount = try XCTUnwrap(controller.terminalView.superview as? TerminalMountView)
        XCTAssertFalse(transientMount === currentMount)
        XCTAssertTrue(transientMount.isDescendant(of: transient))

        current.rootView = terminal(2)
        let ownedUpdateDeadline = ContinuousClock.now + .seconds(2)
        while currentMount.focusRequest != 2, ContinuousClock.now < ownedUpdateDeadline {
            try await Task.sleep(for: .milliseconds(3))
            current.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(currentMount.focusRequest, 2, "the original visible host received a routine update")
        XCTAssertTrue(controller.terminalView.superview === transientMount,
                      "a routine update must not steal an emulator claimed by another host")

        // An unexpected native detach leaves the current lease authoritative.
        // The retired host must not reclaim even though the emulator is orphaned.
        controller.terminalView.removeFromSuperview()
        XCTAssertNil(controller.terminalView.superview)
        current.rootView = terminal(3)
        let staleDeadline = ContinuousClock.now + .seconds(2)
        while currentMount.focusRequest != 3, ContinuousClock.now < staleDeadline {
            try await Task.sleep(for: .milliseconds(3))
            current.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(currentMount.focusRequest, 3)
        XCTAssertNil(controller.terminalView.superview, "an older lease cannot claim an orphan")

        transient.rootView = terminal(4)
        let reclaimDeadline = ContinuousClock.now + .seconds(2)
        while transientMount.focusRequest != 4, ContinuousClock.now < reclaimDeadline {
            try await Task.sleep(for: .milliseconds(3))
            transient.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(transientMount.focusRequest, 4)
        XCTAssertTrue(controller.terminalView.superview === transientMount)
        XCTAssertTrue(transientMount.isDescendant(of: transient))

        current.rootView = AnyView(EmptyView())
        let removalDeadline = ContinuousClock.now + .seconds(2)
        while currentMount.terminal != nil, ContinuousClock.now < removalDeadline {
            try await Task.sleep(for: .milliseconds(3))
            current.layoutSubtreeIfNeeded()
        }
        XCTAssertNil(currentMount.terminal)
        XCTAssertTrue(controller.terminalView.superview === transientMount)
        XCTAssertEqual(runner.startCount, 1)
        XCTAssertTrue(controller.isRunning)
    }

    func testOlderNativeTerminalHostCannotStealFromNewerOwnerOnLateVisibilityUpdate() async throws {
        _ = NSApplication.shared
        let runner = WorkspaceSnapshotTerminalRunner()
        let controller = TerminalSessionController(liveActivities: LiveActivityStore(),
            capabilities: IslandCapabilityRegistry(), runner: runner, workingDirectoryPath: "/tmp")
        defer { controller.terminate() }
        let size = CGSize(width: 420, height: 220)
        func terminal(visible: Bool, request: Int) -> AnyView {
            AnyView(NativeTerminalHost(controller: controller, initialDirectory: "/tmp",
                isVisible: visible, focusRequest: request).frame(width: size.width, height: size.height))
        }
        func findMount(in view: NSView) -> TerminalMountView? {
            if let mount = view as? TerminalMountView { return mount }
            for child in view.subviews { if let mount = findMount(in: child) { return mount } }
            return nil
        }
        let older = NSHostingView(rootView: terminal(visible: false, request: 0))
        let newer = NSHostingView(rootView: AnyView(EmptyView()))
        let olderWindow = NSWindow(contentRect: CGRect(origin: CGPoint(x: -5000, y: -5000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let newerWindow = NSWindow(contentRect: CGRect(origin: CGPoint(x: -6000, y: -5000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        for window in [olderWindow, newerWindow] { window.isReleasedWhenClosed = false }
        defer {
            for window in [olderWindow, newerWindow] {
                window.makeFirstResponder(nil)
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
        }
        older.frame = CGRect(origin: .zero, size: size)
        olderWindow.contentView = older
        olderWindow.orderFrontRegardless()
        let olderDeadline = ContinuousClock.now + .seconds(2)
        while findMount(in: older) == nil, ContinuousClock.now < olderDeadline {
            try await Task.sleep(for: .milliseconds(3))
            older.layoutSubtreeIfNeeded()
        }
        let olderMount = try XCTUnwrap(findMount(in: older))
        XCTAssertFalse(olderMount.wasVisible)
        XCTAssertTrue(olderMount.isHidden)
        XCTAssertNil(controller.terminalView.superview)

        newer.rootView = terminal(visible: true, request: 1)
        newer.frame = CGRect(origin: .zero, size: size)
        newerWindow.contentView = newer
        newerWindow.orderFrontRegardless()
        let newerDeadline = ContinuousClock.now + .seconds(2)
        while (controller.terminalView.superview?.isDescendant(of: newer) != true || !controller.isRunning),
              ContinuousClock.now < newerDeadline {
            try await Task.sleep(for: .milliseconds(3))
            newer.layoutSubtreeIfNeeded()
        }
        let newerMount = try XCTUnwrap(controller.terminalView.superview as? TerminalMountView)
        XCTAssertTrue(newerMount.isDescendant(of: newer))
        XCTAssertTrue(newerMount.wasVisible)
        XCTAssertEqual(newerMount.focusRequest, 1)
        XCTAssertTrue(controller.isRunning)

        // A retiring tree can receive one last visibility update after a
        // newer tree has claimed the shared emulator. Its identity is older
        // even though this is the first visible update of its native host.
        older.rootView = terminal(visible: true, request: 2)
        let lateUpdateDeadline = ContinuousClock.now + .seconds(2)
        while olderMount.focusRequest != 2, ContinuousClock.now < lateUpdateDeadline {
            try await Task.sleep(for: .milliseconds(3))
            older.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(olderMount.focusRequest, 2, "the retained older native host received its late update")
        XCTAssertTrue(olderMount.wasVisible)
        XCTAssertTrue(olderMount.isDescendant(of: older))
        XCTAssertTrue(controller.terminalView.superview === newerMount,
                      "an older host's first visible update must not steal from the newer owner")

        older.rootView = AnyView(EmptyView())
        let dismantleDeadline = ContinuousClock.now + .seconds(2)
        while olderMount.superview != nil, ContinuousClock.now < dismantleDeadline {
            try await Task.sleep(for: .milliseconds(3))
            older.layoutSubtreeIfNeeded()
        }
        XCTAssertFalse(olderMount.wasVisible, "the older host passed through dismantleNSView")
        XCTAssertNil(olderMount.terminal)
        XCTAssertTrue(newerMount.isDescendant(of: newer))
        XCTAssertEqual(newerMount.focusRequest, 1, "recovery must not depend on another update of the current tree")
        XCTAssertTrue(controller.terminalView.superview === newerMount,
                      "late teardown must leave the stable current host owning its emulator")
        XCTAssertEqual(runner.startCount, 1)
        XCTAssertTrue(controller.isRunning)
    }

    func testRapidAgentsMountUnmountWithFocusedNativeEditorAndTerminalSwitching() async throws {
        let fixture = try await makeFixture()
        defer {
            fixture.controller.stop()
            fixture.approvals.cancelAll()
            fixture.terminal.terminate()
        }

        let selected = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == .codex })
        fixture.controller.selectProvider(.codex)
        fixture.controller.selectSession(selected.id)

        let state = AgentWorkspaceMountStressState()
        let size = CGSize(width: 960, height: 510)
        let root = AgentWorkspaceMountStressHarness(
            state: state,
            sessions: fixture.store.sessions,
            controller: fixture.controller,
            approvals: fixture.approvals,
            feed: fixture.feed,
            presentation: fixture.presentation,
            terminal: fixture.terminal,
            selectedID: selected.id
        )
        .frame(width: size.width, height: size.height)
        .environment(\.nativeVisualSnapshotTime, 1.35)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -5000, y: -5000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer {
            window.makeFirstResponder(nil)
            window.orderOut(nil)
            window.contentView = nil
        }

        for _ in 0..<8 {
            await Task.yield()
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(5))
        }

        for cycle in 0..<48 {
            if cycle.isMultiple(of: 2) {
                fixture.presentation.select(.terminal)
            } else {
                fixture.presentation.select(.feed)
            }
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(3))

            if cycle.isMultiple(of: 2) {
                let mountDeadline = ContinuousClock.now + .seconds(5)
                while Self.findInteractiveTerminal(in: hosting) == nil, ContinuousClock.now < mountDeadline {
                    await Task.yield()
                    try await Task.sleep(for: .milliseconds(1))
                    hosting.layoutSubtreeIfNeeded()
                }
                let terminal = try XCTUnwrap(Self.findInteractiveTerminal(in: hosting),
                    "Cycle \(cycle), Agents mounted: \(state.showsAgents), workspace: \(fixture.presentation.mode), emulator owner: \(String(describing: fixture.terminal.terminalView.superview))")
                XCTAssertTrue(terminal === fixture.terminal.terminalView)
                XCTAssertTrue(window.makeFirstResponder(terminal))
                terminal.insertText("stress-\(cycle)", replacementRange: NSRange(location: NSNotFound, length: 0))
            } else if let editor = Self.findPromptEditor(in: hosting) {
                XCTAssertTrue(window.makeFirstResponder(editor))
            }

            state.generation &+= 1
            state.showsAgents = false
            try await Task.sleep(for: .milliseconds(4))
            hosting.layoutSubtreeIfNeeded()

            state.generation &+= 1
            state.showsAgents = true
            try await Task.sleep(for: .milliseconds(4))
            hosting.layoutSubtreeIfNeeded()
        }

        for _ in 0..<8 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(4))
            hosting.layoutSubtreeIfNeeded()
        }

        XCTAssertTrue(state.showsAgents)
        XCTAssertNotNil(Self.findPromptEditor(in: hosting))
        XCTAssertEqual(fixture.presentation.mode, .feed, "The final odd cycle intentionally leaves Feed visible")
        XCTAssertEqual(fixture.runner.startCount, 1, "Hidden Terminal must retain its one shell after remounts")
        XCTAssertTrue(fixture.terminal.isRunning)
        // A newly mounted hidden page deliberately does not claim the native
        // emulator. Verify continuity by revealing Terminal, rather than
        // requiring offscreen rendering while Feed is selected.
        fixture.presentation.select(.terminal)
        let revealDeadline = ContinuousClock.now + .seconds(2)
        while Self.findInteractiveTerminal(in: hosting) == nil, ContinuousClock.now < revealDeadline {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(1))
            hosting.layoutSubtreeIfNeeded()
        }
        let resumedTerminal = try XCTUnwrap(Self.findInteractiveTerminal(in: hosting))
        XCTAssertTrue(resumedTerminal === fixture.terminal.terminalView)
        XCTAssertTrue(window.makeFirstResponder(resumedTerminal))
        XCTAssertEqual(fixture.runner.startCount, 1, "48 focus/page remounts and final reveal must preserve one shell")
        XCTAssertTrue(fixture.terminal.isRunning)
        XCTAssertEqual(fixture.terminal.processID, fixture.runner.handle.processID)
        XCTAssertTrue(String(decoding: fixture.runner.handle.input, as: UTF8.self).contains("stress-46"))
    }

    func testIntegratedComposerRegionsAtNormalAndNarrowWidths() async throws {
        let fixture = try await makeFixture()
        defer { fixture.controller.stop(); fixture.approvals.cancelAll(); fixture.terminal.terminate() }
        let session = try XCTUnwrap(fixture.store.sessions.first)
        fixture.controller.selectSession(session.id)
        final class Frames { var value: [String: CGRect] = [:] }
        for width: CGFloat in [560, 360, 240] {
            let frames = Frames()
            let controls = AgentCLIControlBar(sessions: fixture.store.sessions, managedControl: fixture.controller,
                approvalControl: fixture.approvals,
                projectOptions: AgentProjectFilter.options(for: fixture.store.sessions, locations: .empty, activeManagedSessionIDs: fixture.controller.activeManagedSessionIDs),
                launcherOpen: false, onToggleLauncher: {})
            let view = AgentEmbeddedConsoleView(session: session, mode: .interactive(canInterrupt: true),
                interactionState: .ready, showsOperationalTraffic: false, showsActivityOrb: false,
                transcriptEntries: fixture.controller.transcript(for: session), approvalControl: fixture.approvals,
                onSelectSession: { _ in }, onSubmit: { _ in true }, onInterrupt: {}, composerControls: AnyView(controls))
                .frame(width: width, height: 330)
                .onPreferenceChange(AgentComposerLayoutFrames.self) { frames.value = $0 }
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: width, height: 330)
            for _ in 0..<15 {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(5))
            }
            if width == 560 { XCTAssertNotNil(frames.value["controls.named"], "normal composer must show named controls") }
            let container = try XCTUnwrap(frames.value["composer"])
            let strip = try XCTUnwrap(frames.value["controls"])
            let editor = try XCTUnwrap(frames.value["editor"])
            let transcript = try XCTUnwrap(frames.value["transcript"])
            XCTAssertTrue(container.insetBy(dx: -1, dy: -1).contains(strip), "width \(width): \(strip), \(container)")
            XCTAssertTrue(container.insetBy(dx: -1, dy: -1).contains(editor))
            XCTAssertLessThanOrEqual(strip.maxY, editor.minY)
            XCTAssertLessThanOrEqual(strip.height, 36, "controls must stay on one integrated line")
            XCTAssertGreaterThan(transcript.height, 200)
            XCTAssertTrue(CGRect(x: 0, y: 0, width: width, height: 330).contains(container), "width \(width): composer \(container), strip \(strip)")
        }
        XCTAssertEqual(AgentWorkspaceUsageStrip.diameter(for: 900), 48)
        XCTAssertEqual(AgentWorkspaceUsageStrip.rowHeight(for: 900), 64) // 48pt rings + caption; provider identity beside rings
    }

    func testCompactPermissionExactOwnershipOneShotAndAcknowledgement() async throws {
        let fixture = try await makeFixture()
        defer { fixture.controller.stop(); fixture.approvals.cancelAll(); fixture.terminal.terminate() }
        let session = try XCTUnwrap(fixture.store.sessions.first)
        let request = AgentApprovalControlRequest(key: .init(session: session.id, requestID: .init(rawValue: "compact-exact")),
            summary: "Read a test-owned file", expiresAt: AgentTestFixture.baseDate.addingTimeInterval(600))
        let waiter = Task { await fixture.approvals.request(request, maximumWait: nil) }
        for _ in 0..<100 where fixture.approvals.pendingRequests[request.key] == nil { await Task.yield() }
        let permission = try XCTUnwrap(AgentCompactPermission.current(sessions: fixture.store.sessions, approvals: fixture.approvals, managed: fixture.controller))
        XCTAssertEqual(permission.request.key, request.key)
        var observed = session
        observed.capabilities = AgentCapabilities()
        XCTAssertNil(AgentCompactPermission.current(sessions: [observed], approvals: fixture.approvals, managed: fixture.controller))
        let selection = fixture.controller.selectedSessionID
        XCTAssertEqual(permission.decide(.deny, approvals: fixture.approvals), .accepted)
        let decision = await waiter.value
        XCTAssertEqual(decision, .deny)
        XCTAssertEqual(fixture.controller.selectedSessionID, selection)
        XCTAssertEqual(permission.decide(.allow, approvals: fixture.approvals), .missing)
        XCTAssertNotNil(AgentCompactPermission.current(sessions: fixture.store.sessions, approvals: fixture.approvals, managed: fixture.controller))
        XCTAssertEqual(fixture.approvals.deliveryState(for: request.key), .submitting(.deny))
        fixture.approvals.failDelivery(request.key, reason: "Test transport failure")
        XCTAssertNotNil(AgentCompactPermission.current(sessions: fixture.store.sessions, approvals: fixture.approvals, managed: fixture.controller))
        XCTAssertEqual(permission.decide(.allow, approvals: fixture.approvals), .missing)
        fixture.approvals.confirmDelivery(request.key)
        XCTAssertNil(AgentCompactPermission.current(sessions: fixture.store.sessions, approvals: fixture.approvals, managed: fixture.controller))
    }

    func testCompactPermissionButtonsKeepFixedFramesDuringHoverAndDelivery() async throws {
        let fixture = try await makeFixture()
        defer { fixture.controller.stop(); fixture.approvals.cancelAll(); fixture.terminal.terminate() }
        let session = try XCTUnwrap(fixture.store.sessions.first)
        let request = AgentApprovalControlRequest(key: .init(session: session.id, requestID: .init(rawValue: "compact-layout")),
            summary: "Read harmless fixture context " + String(repeating: "long context ", count: 20),
            expiresAt: AgentTestFixture.baseDate.addingTimeInterval(600))
        let waiter = Task { await fixture.approvals.request(request, maximumWait: nil) }
        for _ in 0..<100 where fixture.approvals.pendingRequests[request.key] == nil { await Task.yield() }
        let permission = try XCTUnwrap(AgentCompactPermission.current(sessions: fixture.store.sessions, approvals: fixture.approvals, managed: fixture.controller))
        final class Frames { var value: [String: CGRect] = [:]; var expansions = 0 }
        var baseline: [String: CGRect] = [:]
        for (index, size) in [CGSize(width: 360, height: 102), CGSize(width: 380, height: 110), CGSize(width: 360, height: 102)].enumerated() {
            let frames = Frames()
            let root = AgentCompactPermissionView(permission: permission, approvals: fixture.approvals, topBandHeight: 29)
                .frame(width: size.width, height: size.height)
                .coordinateSpace(name: AgentComposerActionFrameKey.coordinateSpace)
                .onPreferenceChange(AgentComposerLayoutFrames.self) { frames.value = $0 }
                .onTapGesture { frames.expansions += 1 }
            let host = NSHostingView(rootView: root)
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.orderOut(nil); window.contentView = nil }
            for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(5)) }
            for title in ["approve", "deny"] {
                let frame = try XCTUnwrap(frames.value[title])
                XCTAssertEqual(frame.size, CGSize(width: 78, height: 28))
                XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frame))
                XCTAssertGreaterThanOrEqual(frame.minY, 50, "buttons must clear physical notch")
                let centered = frame.offsetBy(dx: -size.width / 2, dy: 0)
                if index == 0 { baseline[title] = centered }
                else { XCTAssertEqual(centered, baseline[title], "hover/delivery cannot move controls") }
            }
            if index == 0 {
                let approve = try XCTUnwrap(frames.value["approve"])
                let point = CGPoint(x: approve.midX, y: size.height - approve.midY)
                for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = try XCTUnwrap(NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0))
                    window.sendEvent(event)
                    try await Task.sleep(for: .milliseconds(20))
                }
                XCTAssertEqual(fixture.approvals.deliveryState(for: request.key), .submitting(.allow))
                XCTAssertEqual(frames.expansions, 0, "button owns the click")
            }
            if index == 1 { fixture.approvals.failDelivery(request.key, reason: "Not confirmed") }
            if let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR"] {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await hosted(root, size: size, reduceMotion: false, light: false,
                    to: directory.appendingPathComponent("compact-permission-\(index).png"))
            }
        }
        let decision = await waiter.value
        XCTAssertEqual(decision, .allow)
    }

    private static func findPromptEditor(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView, text.accessibilityLabel() == "Agent prompt" {
            return text
        }
        for child in view.subviews {
            if let found = findPromptEditor(in: child) { return found }
        }
        return nil
    }

    private static func findInteractiveTerminal(in view: NSView) -> InteractiveTerminalView? {
        if let terminal = view as? InteractiveTerminalView { return terminal }
        for child in view.subviews {
            if let terminal = findInteractiveTerminal(in: child) { return terminal }
        }
        return nil
    }

    private func compact(_ session: AgentSession) -> some View {
        HStack(spacing: 12) {
            AgentCompactRoutineLeadingView(session: session)
            Spacer(minLength: 35)
            AgentCompactAttentionTrailingView(text: AgentSessionPresentation.stateLabel(session.state), accent: .cyan)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(.black, in: RoundedRectangle(cornerRadius: 17, style: .continuous)).padding(10)
    }

    private func hosted<V: View>(_ view: V, size: CGSize, reduceMotion: Bool, light: Bool, to url: URL) async throws {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(light ? Color(red: 0.92, green: 0.93, blue: 0.95) : Color(red: 0.025, green: 0.027, blue: 0.055))
            .environment(\.nativeVisualSnapshotTime, 1.35)
            .environment(\.colorScheme, light ? .light : .dark))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        // Snapshot settling is not a wall-clock state-transition assertion.
        for _ in 0..<6 { await Task.yield(); hosting.layoutSubtreeIfNeeded() }
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1_000)
        XCTAssertEqual(hosting.bounds.size, size)
        try png.write(to: url, options: .atomic)
    }

    private struct Fixture {
        let store: AgentEventStore
        let feed: AgentWorkspaceFeedStore
        let approvals: AgentApprovalController
        let controller: AgentManagedSessionController
        let presentation: AgentWorkspacePresentation
        let terminal: TerminalSessionController
        let runner: WorkspaceSnapshotTerminalRunner
    }

    private func makeFixture() async throws -> Fixture {
        let store = AgentEventStore()
        let feed = AgentWorkspaceFeedStore()
        store.appliedEventObserver = { [weak feed] event, session in feed?.handleApplied(event, session: session) }
        let approvals = AgentApprovalController(now: { AgentTestFixture.baseDate })
        let controller = AgentManagedSessionController(providers: [WorkspaceSnapshotProvider(provider: .codex), WorkspaceSnapshotProvider(provider: .claude)],
            coordinator: AgentIngestionCoordinator(eventStore: store), eventStore: store, approvals: approvals)
        controller.startObserving()
        await controller.refreshPersistentSnapshot()
        for session in store.sessions {
            controller.connect(session)
            for _ in 0..<1_000 where !controller.isManaged(session) { await Task.yield() }
            XCTAssertTrue(controller.isManaged(session))
            await controller.refreshTranscript(for: session)
        }
        controller.flushTranscriptPublications()
        let runner = WorkspaceSnapshotTerminalRunner()
        let terminal = TerminalSessionController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry(), runner: runner,
                                                 workingDirectoryPath: "/tmp", now: { AgentTestFixture.baseDate })
        return Fixture(store: store, feed: feed, approvals: approvals, controller: controller,
                       presentation: AgentWorkspacePresentation(), terminal: terminal, runner: runner)
    }

    private func emit(_ fixture: Fixture, session: AgentSessionInstanceID, type: AgentEventType,
                      correlation: String? = nil, offset: Double, payload: AgentEventPayload) {
        XCTAssertEqual(fixture.store.ingest(AgentTestFixture.event("fixture-\(type.stableName)-\(offset)", sessionID: session.sessionID,
            generation: session.generation.rawValue, type: type, offset: offset, correlationID: correlation, payload: payload)), .applied)
    }
}


@MainActor
private final class AgentWorkspaceMountStressState: ObservableObject {
    @Published var showsAgents = true
    @Published var generation = 0
}

@MainActor
private final class TranscriptViewportFixtureState: ObservableObject {
    @Published var entries: [AgentManagedTranscriptEntry] = []
}

private struct TranscriptViewportFixtureView: View {
    @ObservedObject var state: TranscriptViewportFixtureState
    let session: AgentSession
    let approvals: AgentApprovalController

    var body: some View {
        AgentEmbeddedConsoleView(session: session, showsOperationalTraffic: false, showsActivityOrb: false,
            transcriptEntries: state.entries, approvalControl: approvals,
            onSelectSession: { _ in }, onSubmit: { _ in false }, onInterrupt: {})
            .environment(\.nativeVisualSnapshotTime, 1.35)
    }
}

private struct AgentWorkspaceMountStressHarness: View {
    @ObservedObject var state: AgentWorkspaceMountStressState
    let sessions: [AgentSession]
    let controller: AgentManagedSessionController
    let approvals: AgentApprovalController
    let feed: AgentWorkspaceFeedStore
    let presentation: AgentWorkspacePresentation
    let terminal: TerminalSessionController
    let selectedID: AgentSessionInstanceID

    var body: some View {
        ZStack {
            if state.showsAgents {
                AgentDashboardContentView(
                    sessions: sessions,
                    accountUsage: controller.accountUsage,
                    showsUsage: true,
                    approvalControl: approvals,
                    managedControl: controller,
                    availableHeight: 482,
                    initialSelectedSessionID: selectedID,
                    contentVisible: true,
                    reduceMotion: false,
                    transcriptPresentationReady: true,
                    transcriptLoadDelay: 0,
                    workspaceFeed: feed,
                    workspacePresentation: presentation,
                    terminal: terminal
                )
                .id("agents-\(state.generation)")
            } else {
                Color.black.opacity(0.01)
                    .id("other-\(state.generation)")
            }
        }
        .animation(.easeOut(duration: 0.01), value: state.showsAgents)
    }
}

private actor WorkspaceSnapshotProvider: AgentInteractiveProvider {
    nonisolated let provider: AgentProvider
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability> = [.resumeSession, .submitPrompt, .interrupt, .resolveApprovals,
        .accountUsage, .contextUsage, .streamMessages, .streamToolActivity, .loadHistory, .selectModel, .selectReasoningEffort]
    nonisolated let modelSelectionScope: AgentModelSelectionScope? = .turnAndSubsequent
    private let stream: AsyncStream<AgentInteractiveProviderEvent>
    private let continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation

    init(provider: AgentProvider) {
        self.provider = provider
        let pair = AsyncStream<AgentInteractiveProviderEvent>.makeStream()
        stream = pair.stream; continuation = pair.continuation
    }
    private var descriptor: AgentManagedSessionDescriptor {
        .init(provider: provider, nativeSessionID: "\(provider.stableName)-workspace-fixture", cwd: "/tmp",
              model: provider == .codex ? "gpt-fixture" : "claude-fixture", acceptsDirectInput: true)
    }
    func events() async -> AsyncStream<AgentInteractiveProviderEvent> { stream }
    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] {
        [.init(session: descriptor, runtimeState: .idle, updatedAt: AgentTestFixture.baseDate)]
    }
    func inspectSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor? { descriptor.nativeSessionID == nativeSessionID ? descriptor : nil }
    func readAccountUsage() async throws -> AgentUsage {
        AgentUsage(scopedSamples: Dictionary(uniqueKeysWithValues: [("5h", provider == .codex ? 28.0 : 41.0), ("weekly", provider == .codex ? 35.0 : 57.0)].map { scope, used in
            (.init(metric: .quotaUsed, scope: scope), .init(value: used, limit: 100, unit: .fraction, scope: scope,
                source: "\(provider.stableName)-account-rate-limits", observedAt: AgentTestFixture.baseDate))
        }))
    }
    func readTranscript(nativeSessionID: String, limit: Int) async throws -> [AgentManagedTranscriptEntry] {
        [.init(id: "user", nativeSessionID: nativeSessionID, turnID: "fixture-turn", role: .user,
               text: "Inspect the workspace, search its files and validate the implementation.", timestamp: AgentTestFixture.baseDate),
         .init(id: "agent", nativeSessionID: nativeSessionID, turnID: "fixture-turn", role: .agent,
               text: "I’ll inspect the native workspace and preserve exact session ownership while checking the focused tests.", timestamp: AgentTestFixture.baseDate.addingTimeInterval(1))]
    }
    func listModels() async throws -> [AgentManagedModelDescriptor] {
        [.init(id: descriptor.model!, model: descriptor.model!, displayName: provider == .codex ? "Codex fixture" : "Claude fixture", description: nil, isDefault: true,
               supportedReasoningEfforts: [.init(id: "medium", description: "Balanced"), .init(id: "high", description: "Detailed")], defaultReasoningEffort: "medium")]
    }
    func startSession(cwd: String?, model: String?) async throws -> AgentManagedSessionDescriptor { descriptor }
    func resumeSession(nativeSessionID: String, cwd: String?) async throws -> AgentManagedSessionDescriptor { descriptor }
    func submit(prompt: String, nativeSessionID: String, model: String?) async throws -> AgentManagedTurnDescriptor { .init(nativeSessionID: nativeSessionID, turnID: "fixture-turn") }
    func interrupt(nativeSessionID: String, turnID: String) async throws {}
    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {}
    func stop() async { continuation.finish() }
}

private final class WorkspaceSnapshotTerminalHandle: TerminalProcessHandle {
    var isRunning = true
    var processID: Int32? { isRunning ? 42_001 : nil }
    private(set) var input: [UInt8] = []
    func send(data: [UInt8]) { input.append(contentsOf: data) }
    func terminate() { isRunning = false }
}
private final class WorkspaceSnapshotTerminalRunner: TerminalProcessRunning {
    var startCount = 0
    let handle = WorkspaceSnapshotTerminalHandle()
    func start(command: String, shellPath: String, workingDirectory: URL?, onOutput: @escaping @Sendable (String) -> Void,
               onExit: @escaping @Sendable (Int32) -> Void) throws -> TerminalProcessHandle {
        startCount += 1
        onOutput("\u{001B}[32mFixture terminal\u{001B}[0m\n$ swift test --filter AgentWorkspace\nOperational terminal output stays owned by one controller.\n")
        return handle
    }
}
