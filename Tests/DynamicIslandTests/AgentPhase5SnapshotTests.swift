import AgentBridgeShared
import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Review renders for the Phase 5 Agents surface (DYNAMIC_ISLAND_AGENT_SNAPSHOT_DIR).
/// Every image is the production view hosted in a real NSHostingView, driven
/// by the production controllers; nothing is mocked at the view layer.
@MainActor
final class AgentPhase5SnapshotTests: XCTestCase {
    func testRenderPhase5AgentSnapshots() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_AGENT_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_AGENT_SNAPSHOT_DIR to render review screenshots.")
        }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let codex = SnapshotProvider(provider: .codex, usedFiveHour: 37, usedWeek: 62)
        let claude = SnapshotProvider(provider: .claude, usedFiveHour: 81, usedWeek: 44)
        let store = AgentEventStore()
        let approvals = AgentApprovalController()
        let controller = AgentManagedSessionController(
            providers: [codex, claude],
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: approvals
        )
        controller.startObserving()
        defer { controller.stop() }
        await controller.refreshPersistentSnapshot()
        let codexSession = try XCTUnwrap(store.sessions.first { $0.id.sessionID.provider == .codex })
        controller.connect(codexSession)
        for _ in 0..<200 where !controller.isManaged(codexSession) { try await Task.sleep(for: .milliseconds(5)) }
        controller.selectSession(codexSession.id)
        await controller.refreshTranscript(for: codexSession)
        controller.flushTranscriptPublications()

        let recorder = AgentActivityRecorder(log: AgentActivityLog(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)")
        ))

        func dashboard(width: CGFloat, ready: Bool = true, reduceMotion: Bool = false) -> some View {
            AgentDashboardContentView(
                sessions: store.sessions,
                accountUsage: controller.accountUsage,
                showsUsage: true,
                approvalControl: approvals,
                managedControl: controller,
                activityRecorder: recorder,
                availableHeight: 400,
                reduceMotion: reduceMotion,
                transcriptPresentationReady: ready,
                transcriptLoadDelay: 0
            )
        }

        controller.selectProvider(.codex)
        controller.selectSession(codexSession.id)
        try await hosted(dashboard(width: 760), width: 760, name: "p5-01-codex-selected-long-transcript", output: output)
        try await hosted(dashboard(width: 760, ready: false), width: 760, name: "p5-02-transcript-loading", output: output)
        try await hosted(dashboard(width: 480), width: 480, name: "p5-03-narrow-width", output: output)
        try await hosted(dashboard(width: 900), width: 900, name: "p5-04-wide-inline-gauges", output: output)

        recorder.setRecording(true)
        try await hosted(dashboard(width: 760), width: 760, name: "p5-05-recording-enabled", output: output)
        recorder.setRecording(false)

        controller.selectProvider(.claude)
        try await hosted(dashboard(width: 760), width: 760, name: "p5-06-claude-selected", output: output)
        try await hosted(
            dashboard(width: 760, reduceMotion: true),
            width: 760, name: "p5-07-reduce-motion", output: output
        )
        controller.selectProvider(.codex)

        // Usage gauges on their own (standard and narrow metrics).
        let indicators = AgentUsageIndicatorPresentation.make(
            provider: .codex, accountUsage: controller.accountUsage, selectedSession: codexSession
        )
        try await hosted(
            VStack(spacing: 14) {
                AgentUsageIndicatorRow(indicators: indicators, spacing: 18, metrics: .standard)
                AgentUsageIndicatorRow(indicators: indicators, spacing: 10, metrics: .narrow)
            }.padding(16),
            width: 420, height: 150, name: "p5-08-usage-gauges", output: output
        )

        // Approval row: pending -> submitting -> failed.
        let key = AgentApprovalControlKey(session: codexSession.id, requestID: AgentCorrelationID(rawValue: "req-1"))
        let request = AgentApprovalControlRequest(key: key, summary: "Command approval: git", expiresAt: .distantFuture)
        let waiting = Task { await approvals.request(request, maximumWait: nil) }
        while approvals.pendingRequests.isEmpty { await Task.yield() }
        func row() -> some View {
            AgentConsoleApprovalRow(request: request, session: codexSession, approvalControl: approvals).padding(12)
        }
        try await hosted(row(), width: 560, height: 130, name: "p5-09-approval-pending", output: output)
        _ = approvals.resolve(session: key.session, requestID: key.requestID, decision: .allow)
        _ = await waiting.value
        try await hosted(row(), width: 560, height: 130, name: "p5-10-approval-submitting", output: output)
        approvals.failDelivery(key, reason: "The turn ended before Codex confirmed the decision.")
        try await hosted(row(), width: 560, height: 130, name: "p5-11-approval-failed", output: output)

        // Resolved approval history in the console timeline.
        var resolved = codexSession
        resolved.approvals[AgentCorrelationID(rawValue: "req-2")] = AgentApproval(
            requestID: AgentCorrelationID(rawValue: "req-2"),
            summary: "Command approval: git",
            operationCorrelationID: nil,
            requestedAt: Date().addingTimeInterval(-20),
            resolvedAt: Date(),
            expiresAt: nil,
            state: .approved
        )
        try await hosted(
            AgentEmbeddedConsoleView(
                session: resolved,
                mode: .interactive(canInterrupt: false),
                interactionState: .ready,
                maximumActivityEntries: 6,
                transcriptEntries: Array(controller.transcript(for: codexSession).suffix(4)),
                approvalControl: approvals,
                onSelectSession: { _ in },
                onSubmit: { _ in true },
                onInterrupt: {}
            ),
            width: 620, height: 320, name: "p5-12-approval-resolved-history", output: output
        )
    }

    private func hosted<V: View>(
        _ view: V,
        width: CGFloat,
        height: CGFloat = 440,
        name: String,
        output: URL
    ) async throws {
        let size = CGSize(width: width, height: height)
        let hosting = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(red: 0.025, green: 0.027, blue: 0.055))
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(25))
            hosting.layoutSubtreeIfNeeded()
        }
        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return XCTFail("render \(name)")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
        window.orderOut(nil)
    }
}

private actor SnapshotProvider: AgentInteractiveProvider {
    nonisolated let provider: AgentProvider
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability> = [
        .startSession, .resumeSession, .submitPrompt, .interrupt, .resolveApprovals,
        .accountUsage, .contextUsage, .streamMessages, .streamToolActivity, .loadHistory
    ]
    nonisolated let modelSelectionScope: AgentModelSelectionScope? = nil
    private let usedFiveHour: Double
    private let usedWeek: Double
    private let stream: AsyncStream<AgentInteractiveProviderEvent>
    private let continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation

    init(provider: AgentProvider, usedFiveHour: Double, usedWeek: Double) {
        self.provider = provider
        self.usedFiveHour = usedFiveHour
        self.usedWeek = usedWeek
        var continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func events() async -> AsyncStream<AgentInteractiveProviderEvent> { stream }

    private func descriptor(_ index: Int) -> AgentManagedSessionDescriptor {
        AgentManagedSessionDescriptor(
            provider: provider,
            nativeSessionID: "\(provider.stableName)-snap-\(index)",
            cwd: ["/tmp/storefront", "/tmp/DynamicIsland", "/tmp/design-system"][index % 3],
            model: provider == .codex ? "gpt-5.6" : "sonnet",
            acceptsDirectInput: true
        )
    }

    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] {
        (0..<4).map {
            AgentDiscoveredSessionDescriptor(session: descriptor($0), runtimeState: .idle, updatedAt: Date().addingTimeInterval(-Double($0) * 90))
        }
    }

    func inspectSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor? {
        Int(nativeSessionID.split(separator: "-").last ?? "").map(descriptor)
    }

    func readAccountUsage() async throws -> AgentUsage {
        AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): AgentUsageSample(value: usedFiveHour, limit: 100, unit: .fraction, scope: "5h", source: "codex-account-rate-limits", observedAt: Date()),
            AgentUsageKey(metric: .quotaUsed, scope: "weekly"): AgentUsageSample(value: usedWeek, limit: 100, unit: .fraction, scope: "weekly", source: "codex-account-rate-limits", observedAt: Date())
        ])
    }

    func readTranscript(nativeSessionID: String, limit: Int) async throws -> [AgentManagedTranscriptEntry] {
        let roles: [AgentManagedTranscriptRole] = [.user, .agent, .command, .agent]
        return (0..<40).map {
            AgentManagedTranscriptEntry(
                id: "\(nativeSessionID)-\($0)", nativeSessionID: nativeSessionID, turnID: "turn-\($0 / 4)",
                role: roles[$0 % roles.count],
                text: $0 % 4 == 2 ? "swift test --filter Agents" : "Step \($0): updated the transcript window and verified the console stays pinned to the latest output.",
                timestamp: Date().addingTimeInterval(Double($0) - 60)
            )
        }
    }

    func listModels() async throws -> [AgentManagedModelDescriptor] { [] }
    func startSession(cwd: String?, model: String?) async throws -> AgentManagedSessionDescriptor { descriptor(0) }
    func resumeSession(nativeSessionID: String, cwd: String?) async throws -> AgentManagedSessionDescriptor {
        guard let index = Int(nativeSessionID.split(separator: "-").last ?? "") else { throw CodexAppServerError.invalidResponse("snap") }
        return descriptor(index)
    }
    func submit(prompt: String, nativeSessionID: String, model: String?) async throws -> AgentManagedTurnDescriptor {
        AgentManagedTurnDescriptor(nativeSessionID: nativeSessionID, turnID: "turn")
    }
    func interrupt(nativeSessionID: String, turnID: String) async throws {}
    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {}
    func stop() async { continuation.finish() }
}
