import AgentBridgeShared
import Combine
import AppKit
import Darwin
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Opt-in measurement harness for the Agents page (DYNAMIC_ISLAND_AGENT_PERF=1).
///
/// Hosts the production `AgentActivityDashboardView` in a real window with a
/// large two-provider workspace and drives it through the production
/// `AgentManagedSessionController` with fake providers that stream real
/// provider events. For each scenario it records main-thread CPU time (the
/// work that can stall the island), wall time, and the DEBUG
/// `AgentPerformanceProbe` counters (view body evaluations, controller
/// publications, projection durations, visible rows).
///
/// Set DYNAMIC_ISLAND_AGENT_PERF_REPORT=<path> to write the JSON report.
@MainActor
final class AgentsPerformanceHarnessTests: XCTestCase {
    func testMeasureAgentsPage() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DYNAMIC_ISLAND_AGENT_PERF"] == "1" else {
            throw XCTSkip("Set DYNAMIC_ISLAND_AGENT_PERF=1 to measure the Agents page.")
        }
        let codex = PerfFakeProvider(provider: .codex, sessionCount: 24)
        let claude = PerfFakeProvider(provider: .claude, sessionCount: 12)
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
        controller.selectProvider(.codex)
        let codexSessions = store.sessions.filter { $0.id.sessionID.provider == .codex }
        XCTAssertGreaterThanOrEqual(codexSessions.count, 10)
        // Managed (composer) selected session with a full retained transcript.
        let selected = try XCTUnwrap(codexSessions.first)
        controller.connect(selected)
        for _ in 0..<200 where !controller.isManaged(selected) {
            try await Task.sleep(for: .milliseconds(5))
        }
        controller.selectSession(selected.id)
        await controller.refreshTranscript(for: selected)
        XCTAssertEqual(controller.transcript(for: selected).count, 80)

        let defaults = UserDefaults(suiteName: "AgentsPerf-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.agentUsageMetricsEnabled = true
        let host = PerfHost(size: CGSize(width: 820, height: 430))
        let projects = AgentProjectProjectionStore()
        let layoutStore = IslandLayoutStore()
        func page(visible: Bool) -> AnyView {
            AnyView(AgentActivityDashboardView(
                settings: settings,
                agentEvents: store,
                projects: projects,
                approvalControl: approvals,
                managedControl: controller,
                layoutStore: layoutStore,
                availableHeight: 410,
                contentVisible: visible,
                isContentRemoving: false
            ))
        }

        var report: [String: Any] = [:]
        var sinks: [AnyCancellable] = []
        func track<O: ObservableObject>(_ object: O, _ name: StaticString) where O.ObjectWillChangePublisher == ObservableObjectPublisher {
            sinks.append(object.objectWillChange.sink { _ in
                MainActor.assumeIsolated { AgentPerformanceProbe.countDynamic("publish.\(name)") }
            })
        }
        track(store, "agentEvents")
        track(layoutStore, "layoutStore")
        track(approvals, "approvals")
        track(settings, "settings")
        track(projects, "projects")
        defer { sinks.removeAll() }

        // 1. Enter Agents: request -> chrome -> transcript visible.
        AgentPerformanceProbe.reset()
        let enter = try await measure(host) {
            host.show(page(visible: true))
        } until: {
            AgentPerformanceProbe.snapshot().marks["agents.transcript.gate.open"] != nil
        }
        let enterMarks = AgentPerformanceProbe.snapshot().marks
        report["enter"] = enter.json(probe: AgentPerformanceProbe.snapshot(), marks: [
            "chromeVisibleAfterRequest": delta(enterMarks, "agents.enter.requested", "agents.chrome.visible"),
            "transcriptAllowedAfterRequest": delta(enterMarks, "agents.enter.requested", "agents.transcript.allowed"),
            "transcriptVisibleAfterRequest": delta(enterMarks, "agents.enter.requested", "agents.transcript.gate.open")
        ])

        // 2. Streaming: 200 small deltas into the selected session.
        AgentPerformanceProbe.reset()
        let turn = "perf-turn"
        await codex.yield(.turnStarted(.init(nativeSessionID: selected.id.sessionID.nativeID, turnID: turn)))
        try await Task.sleep(for: .milliseconds(20))
        AgentPerformanceProbe.reset()
        // Paced like a real provider (~200 tokens/s for 1 s), so every
        // delta lands in its own run-loop turn and coalescing is honest.
        let deltas = 200
        let streaming = try await measure(host) {
            for index in 0..<deltas {
                await codex.yield(.transcriptDelta(
                    nativeSessionID: selected.id.sessionID.nativeID,
                    turnID: turn,
                    itemID: "stream-item",
                    delta: "token\(index) "
                ))
                try await Task.sleep(for: .milliseconds(5))
                if index.isMultiple(of: 4) { await host.settle() }
            }
        } until: {
            AgentPerformanceProbe.snapshot().counters["agents.stream.delta"] ?? 0 >= deltas
        }
        report["streaming"] = streaming.json(probe: AgentPerformanceProbe.snapshot(), marks: [:], parameters: ["deltas": deltas])

        // 2b. Typing 40 characters into the real composer text view.
        AgentPerformanceProbe.reset()
        let typing = try await measure(host) {
            guard let editor = host.firstTextView() else { return XCTFail("composer text view not found") }
            host.window.makeFirstResponder(editor)
            for character in "Refactor the transcript window please." {
                editor.insertText(String(character), replacementRange: editor.selectedRange())
                await host.settle()
            }
        } until: { true }
        report["typing"] = typing.json(probe: AgentPerformanceProbe.snapshot(), marks: [:], parameters: ["keystrokes": 38])

        // 3. Session switch (x10).
        AgentPerformanceProbe.reset()
        let others = Array(codexSessions.dropFirst().prefix(10))
        let switching = try await measure(host) {
            for session in others {
                controller.selectSession(session.id)
                await host.settle()
            }
            controller.selectSession(selected.id)
        } until: { true }
        report["sessionSwitch"] = switching.json(probe: AgentPerformanceProbe.snapshot(), marks: [:], parameters: ["switches": others.count + 1])

        // 4. Provider switch (x10).
        AgentPerformanceProbe.reset()
        let providerSwitch = try await measure(host) {
            for index in 0..<10 {
                controller.selectProvider(index.isMultiple(of: 2) ? .claude : .codex)
                await host.settle()
            }
        } until: { true }
        report["providerSwitch"] = providerSwitch.json(probe: AgentPerformanceProbe.snapshot(), marks: [:], parameters: ["switches": 10])
        controller.selectProvider(.codex)
        controller.selectSession(selected.id)
        await host.settle()

        // 5. Background usage refresh while the page is open (x10).
        AgentPerformanceProbe.reset()
        let usage = try await measure(host) {
            for _ in 0..<10 {
                await controller.refreshPersistentSnapshot()
                await host.settle()
            }
        } until: { true }
        report["snapshotRefresh"] = usage.json(probe: AgentPerformanceProbe.snapshot(), marks: [:], parameters: ["refreshes": 10])

        // 6. Leave Agents -> next page.
        AgentPerformanceProbe.reset()
        let leave = try await measure(host) {
            host.show(AnyView(Color.black))
        } until: { true }
        report["leave"] = leave.json(probe: AgentPerformanceProbe.snapshot(), marks: [:])

        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let text = String(decoding: data, as: UTF8.self)
        print("AGENTS-PERF-REPORT\n\(text)")
        if let path = environment["DYNAMIC_ISLAND_AGENT_PERF_REPORT"] {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: Measurement

    private struct Measurement {
        let wall: TimeInterval
        let mainThreadCPU: TimeInterval

        func json(
            probe: AgentPerformanceProbe.Snapshot,
            marks: [String: Double?],
            parameters: [String: Int] = [:]
        ) -> [String: Any] {
            var result: [String: Any] = [
                "wallMs": (wall * 1000).rounded(toPlaces: 1),
                "mainThreadCPUms": (mainThreadCPU * 1000).rounded(toPlaces: 1),
                "counters": probe.counters,
                "gauges": probe.gauges
            ]
            result["durations"] = probe.durations.mapValues {
                [
                    "count": $0.count,
                    "totalMs": ($0.total * 1000).rounded(toPlaces: 2),
                    "maxMs": ($0.maximum * 1000).rounded(toPlaces: 2)
                ] as [String: Any]
            }
            result["marks"] = marks.compactMapValues { $0.map { ($0 * 1000).rounded(toPlaces: 1) } }
            result["parameters"] = parameters
            return result
        }
    }

    private func measure(
        _ host: PerfHost,
        _ action: () async throws -> Void,
        until done: () -> Bool,
        line: Int = #line
    ) async throws -> Measurement {
        progress("AGENTS-PERF scenario at line \(line) start counters=\(AgentPerformanceProbe.snapshot().counters)")
        defer { progress("AGENTS-PERF scenario at line \(line) end counters=\(AgentPerformanceProbe.snapshot().counters)") }
        let wallStart = ContinuousClock.now
        let cpuStart = Self.threadCPU()
        try await action()
        for iteration in 0..<400 {
            await host.settle()
            if done() { break }
            if iteration.isMultiple(of: 100) {
                progress("AGENTS-PERF line \(line) iteration \(iteration) counters=\(AgentPerformanceProbe.snapshot().counters)")
            }
        }
        await host.settle()
        let cpu = Self.threadCPU() - cpuStart
        let wall = ContinuousClock.now - wallStart
        return Measurement(
            wall: TimeInterval(wall.components.seconds) + TimeInterval(wall.components.attoseconds) / 1e18,
            mainThreadCPU: cpu
        )
    }

    private func delta(_ marks: [String: TimeInterval], _ from: String, _ to: String) -> Double? {
        guard let start = marks[from], let end = marks[to] else { return nil }
        return end - start
    }

    private static func threadCPU() -> TimeInterval {
        var time = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        return TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1e9
    }
}

private func progress(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

/// A real window + hosting view, rendered on every settle.
@MainActor
private final class PerfHost {
    let window: NSWindow
    let hosting: NSHostingView<AnyView>

    init(size: CGSize) {
        hosting = NSHostingView(rootView: AnyView(Color.black))
        hosting.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
    }

    func firstTextView() -> NSTextView? {
        func search(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.isEditable { return text }
            for child in view.subviews {
                if let found = search(child) { return found }
            }
            return nil
        }
        return search(hosting)
    }

    func show(_ view: AnyView) {
        hosting.rootView = AnyView(view.environment(\.colorScheme, .dark))
    }

    /// One frame: let SwiftUI process pending updates, then lay out and draw.
    func settle() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
    }
}

/// Fake interactive provider with a realistic large workspace.
private actor PerfFakeProvider: AgentInteractiveProvider {
    nonisolated let provider: AgentProvider
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability> = [
        .startSession, .resumeSession, .submitPrompt, .interrupt, .resolveApprovals,
        .accountUsage, .contextUsage, .streamMessages, .streamToolActivity, .loadHistory
    ]
    nonisolated let modelSelectionScope: AgentModelSelectionScope? = nil
    private let sessionCount: Int
    private let stream: AsyncStream<AgentInteractiveProviderEvent>
    private let continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation

    init(provider: AgentProvider, sessionCount: Int) {
        self.provider = provider
        self.sessionCount = sessionCount
        var continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func yield(_ event: AgentInteractiveProviderEvent) { continuation.yield(event) }

    func events() async -> AsyncStream<AgentInteractiveProviderEvent> { stream }

    private func descriptor(_ index: Int) -> AgentManagedSessionDescriptor {
        AgentManagedSessionDescriptor(
            provider: provider,
            nativeSessionID: "\(provider.stableName)-perf-\(index)",
            cwd: "/tmp/perf/project-\(index % 6)",
            model: "perf-model",
            acceptsDirectInput: true
        )
    }

    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] {
        (0..<sessionCount).map {
            AgentDiscoveredSessionDescriptor(
                session: descriptor($0),
                runtimeState: .idle,
                updatedAt: Date(timeIntervalSince1970: 1_790_000_000 - Double($0) * 60)
            )
        }
    }

    func inspectSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor? {
        guard let index = Int(nativeSessionID.split(separator: "-").last ?? "") else { return nil }
        return descriptor(index)
    }

    func readAccountUsage() async throws -> AgentUsage {
        let now = Date()
        return AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): AgentUsageSample(
                value: 37, limit: 100, unit: .fraction, scope: "5h", source: "perf", observedAt: now
            ),
            AgentUsageKey(metric: .quotaUsed, scope: "weekly"): AgentUsageSample(
                value: 62, limit: 100, unit: .fraction, scope: "weekly", source: "perf", observedAt: now
            )
        ])
    }

    func readTranscript(nativeSessionID: String, limit: Int) async throws -> [AgentManagedTranscriptEntry] {
        let roles: [AgentManagedTranscriptRole] = [.user, .agent, .command, .tool, .agent]
        let paragraph = String(repeating: "The agent explains the change in detail and lists the affected files. ", count: 6)
        return (0..<min(limit, 80)).map {
            AgentManagedTranscriptEntry(
                id: "\(nativeSessionID)-entry-\($0)",
                nativeSessionID: nativeSessionID,
                turnID: "turn-\($0 / 5)",
                role: roles[$0 % roles.count],
                text: "\($0): \(paragraph)",
                timestamp: Date(timeIntervalSince1970: 1_790_000_000 + Double($0))
            )
        }
    }

    func listModels() async throws -> [AgentManagedModelDescriptor] { [] }

    func startSession(cwd: String?, model: String?) async throws -> AgentManagedSessionDescriptor { descriptor(999) }

    func resumeSession(nativeSessionID: String, cwd: String?) async throws -> AgentManagedSessionDescriptor {
        guard let index = Int(nativeSessionID.split(separator: "-").last ?? "") else {
            throw CodexAppServerError.invalidResponse("perf")
        }
        return descriptor(index)
    }

    func submit(prompt: String, nativeSessionID: String, model: String?) async throws -> AgentManagedTurnDescriptor {
        AgentManagedTurnDescriptor(nativeSessionID: nativeSessionID, turnID: "turn-submitted")
    }

    func interrupt(nativeSessionID: String, turnID: String) async throws {}
    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {}
    func stop() async { continuation.finish() }
}
