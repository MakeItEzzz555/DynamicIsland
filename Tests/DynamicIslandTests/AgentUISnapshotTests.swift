import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentUISnapshotTests: XCTestCase {
    private let now = Date()

    func testRenderAgentUIReviewSnapshots() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_AGENT_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_AGENT_SNAPSHOT_DIR to render review screenshots.")
        }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let working = session(provider: .codex, nativeID: "working", project: "DynamicIsland", state: .runningTool, progress: 0.56)
        let approval = session(provider: .codex, nativeID: "approval", project: "storefront", state: .waitingForApproval, progress: 0.43)
        let claude = session(provider: .claude, nativeID: "claude", project: "design-system", state: .thinking, progress: nil)
        let completed = session(provider: .codex, nativeID: "completed", project: "DynamicIsland", state: .completed, progress: 0.82)

        try renderCompact(
            name: "01-normal-compact",
            profile: .normal,
            content: AnyView(Color.clear),
            output: output
        )

        let routinePresentation = try XCTUnwrap(AgentCompactPresentation.make(sessions: [working]))
        let routineProfile = try XCTUnwrap(AgentCollapsedShellPresentation.routine(sessions: [working], enabled: true))
        try renderCompact(
            name: "02-routine-agent-compact",
            profile: routineProfile,
            content: AnyView(AgentCompactOverviewView(presentation: routinePresentation)),
            output: output
        )

        try renderCompact(
            name: "03-compact-attention",
            profile: .agentAttention(leftContentWidth: 92, rightContentWidth: 118),
            content: AnyView(
                HStack(spacing: 12) {
                    AgentCompactAttentionLeadingView(provider: .codex, project: "storefront")
                    Spacer(minLength: 20)
                    AgentCompactAttentionTrailingView(text: "Approval needed", accent: .orange)
                }
            ),
            glowColor: .orange,
            output: output
        )

        try renderCompactState(name: "16-collapsed-working", session: working, output: output)
        try renderCompactState(
            name: "17-collapsed-plan-ready",
            session: session(provider: .codex, nativeID: "plan", project: "DynamicIsland", state: .planReady, progress: nil),
            output: output
        )
        try renderCompactState(name: "18-collapsed-completed", session: completed, output: output)
        try renderCompactState(
            name: "19-collapsed-failed",
            session: session(provider: .codex, nativeID: "failed", project: "DynamicIsland", state: .failed, progress: nil),
            output: output
        )

        XCTAssertNil(AgentCollapsedShellPresentation.routine(sessions: [completed], enabled: true))
        try renderCompact(
            name: "04-completed-retraction",
            profile: .normal,
            content: AnyView(Color.clear),
            output: output
        )

        try renderDashboard(name: "05-expanded-single-session", sessions: [working], output: output)
        try renderDashboard(name: "06-expanded-multi-session", sessions: [approval, working, claude], output: output)
        try renderDashboard(name: "07-multiple-project-groups", sessions: [working, approval, claude], output: output)
        try renderDashboard(name: "08-attention-row", sessions: [approval, claude], showsUsage: false, output: output)
        try renderDashboard(name: "09-usage-gauges", sessions: [working, approval], output: output)
        try renderDiagnostics(output: output)
        try renderStandbyDashboard(output: output)
        try renderSyntheticDashboardFixture(output: output)
        try renderWorkspaceDashboard(
            name: "13-active-recent-workspace",
            sessions: [approval, working, claude, completed],
            selectedSessionID: working.id,
            output: output
        )
        try renderWorkspaceDashboard(
            name: "23-agents-workspace-inline-usage",
            sessions: [approval, working, claude, completed],
            selectedSessionID: working.id,
            width: 946,
            output: output
        )
        try renderWorkspaceDashboard(
            name: "14-selected-attention-workspace",
            sessions: [approval, working, completed],
            selectedSessionID: nil,
            output: output
        )
        let longWorkspace = (0..<9).map { index in
            session(
                provider: index.isMultiple(of: 3) ? .claude : .codex,
                nativeID: "long-\(index)",
                project: index < 6 ? "DynamicIsland" : "storefront",
                state: index == 8 ? .completed : (index.isMultiple(of: 2) ? .runningTool : .thinking),
                progress: index.isMultiple(of: 2) ? Double(index + 1) / 10 : nil
            )
        }
        try renderWorkspaceDashboard(
            name: "15-long-scroll-workspace",
            sessions: longWorkspace,
            selectedSessionID: longWorkspace[2].id,
            output: output
        )
        try renderStandaloneConsole(
            name: "20-expanded-plan-ready",
            session: session(provider: .codex, nativeID: "plan-expanded", project: "DynamicIsland", state: .planReady, progress: nil),
            mode: .observed,
            output: output
        )
        try renderStandaloneConsole(
            name: "21-managed-console",
            session: working,
            mode: .interactive(canInterrupt: true),
            output: output
        )
        try renderSessionLauncher(
            sessions: [approval, working, claude] + longWorkspace,
            output: output
        )
    }

    private func renderCompactState(
        name: String,
        session: AgentSession,
        output: URL
    ) throws {
        let accent = AgentVisualStyle.accent(for: session.state)
        try renderCompact(
            name: name,
            profile: .agentRoutine(leftContentWidth: 100, rightContentWidth: 108),
            content: AnyView(
                HStack(spacing: 12) {
                    AgentCompactRoutineLeadingView(session: session)
                    Spacer(minLength: 20)
                    AgentCompactAttentionTrailingView(
                        text: AgentSessionPresentation.stateLabel(session.state),
                        accent: accent,
                        symbol: AgentSessionPresentation.stateSymbol(session.state)
                    )
                }
            ),
            glowColor: accent,
            output: output
        )
    }

    private func renderStandaloneConsole(
        name: String,
        session: AgentSession,
        mode: AgentConsoleMode,
        output: URL
    ) throws {
        let approvals = AgentApprovalController()
        let interactionState: AgentManagedInteractionState = switch mode {
        case .observed:
            .observed
        case .interactive(let canInterrupt):
            canInterrupt ? .working(canInterrupt: true) : .ready
        }
        let view = AgentEmbeddedConsoleView(
            session: session,
            mode: mode,
            interactionState: interactionState,
            maximumActivityEntries: 6,
            transcriptEntries: [],
            workspaceSessions: [session],
            approvalControl: approvals,
            onSelectSession: { _ in },
            onSubmit: { _ in true },
            onInterrupt: {}
        )
        .padding(14)
        .background(Color(red: 0.025, green: 0.027, blue: 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(12)
        .background(Color(red: 0.055, green: 0.06, blue: 0.12))

        try renderHosted(
            view,
            size: CGSize(width: 820, height: 440),
            to: output.appendingPathComponent(name + ".png")
        )
    }

    private func renderSessionLauncher(
        sessions: [AgentSession],
        output: URL
    ) throws {
        let approvals = AgentApprovalController()
        let managed = makeManagedControl(approvals: approvals)
        let view = AgentSessionLauncherView(
            sessions: sessions,
            managedControl: managed,
            flow: AgentNewSessionFlow(),
            onSelectSession: { _ in },
            onStarted: { _ in },
            onDismiss: {}
        )
        .frame(width: 520, height: 300, alignment: .top)
        .padding(18)
        .background(Color(red: 0.025, green: 0.027, blue: 0.055))

        try renderHosted(
            view,
            size: CGSize(width: 556, height: 336),
            to: output.appendingPathComponent("22-in-island-session-launcher.png")
        )
    }

    private func renderCompact(
        name: String,
        profile: CollapsedPresentationProfile,
        content: AnyView,
        glowColor: Color = .cyan,
        output: URL
    ) throws {
        let size = CGSize(
            width: profile.kind == .normal
                ? 190
                : max(300, 190 + profile.widthDelta + profile.minimumFloatingWidth),
            height: 44 + profile.heightDelta
        )
        let settings = AppSettings()
        let view = ZStack {
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.04, blue: 0.10), Color(red: 0.13, green: 0.055, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            IslandSurface(
                settings: settings,
                isExpanded: false,
                visualProgress: 0,
                collapsedPresentationProfile: profile,
                collapsedGlowColor: glowColor
            ) {
                content.padding(.horizontal, profile.horizontalContentInset)
            }
            .notchIntegrated(true)
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width + 48, height: size.height + 34)
        try render(view, size: CGSize(width: size.width + 48, height: size.height + 34), to: output.appendingPathComponent(name + ".png"))
    }

    private func renderDashboard(
        name: String,
        sessions: [AgentSession],
        showsUsage: Bool = true,
        output: URL
    ) throws {
        let view = VStack(spacing: 0) {
            AgentDashboardStack(
                sessions: sessions,
                showsUsage: showsUsage,
                approvalControl: AgentApprovalController(),
                layout: AgentDashboardLayoutProjection.make(width: 792),
                reduceMotion: false
            )
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
            .padding(14)
            .background(Color(red: 0.025, green: 0.027, blue: 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(12)
            .background(Color(red: 0.055, green: 0.06, blue: 0.12))
        try render(view, size: CGSize(width: 820, height: 440), to: output.appendingPathComponent(name + ".png"))
    }

    func testRenderNewSessionWorkflowSnapshots() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_AGENT_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_AGENT_SNAPSHOT_DIR to render review screenshots.")
        }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let folder = output.appendingPathComponent("render-project", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let store = AgentEventStore()
        let approvals = AgentApprovalController()
        let claude = ClaudeInteractiveProvider(
            client: try ClaudeCodeStreamingClient(executableURL: URL(fileURLWithPath: "/usr/bin/true")),
            catalog: SnapshotEmptyClaudeCatalog()
        )
        let managed = AgentManagedSessionController(
            providers: [claude],
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: approvals
        )
        await managed.refreshPersistentSnapshot()
        _ = managed.selectNewSessionModel("opus", for: .claude)

        func dashboard(_ sessions: [AgentSession]) -> some View {
            AgentDashboardContentView(
                sessions: sessions,
                showsUsage: false,
                approvalControl: approvals,
                managedControl: managed,
                availableHeight: 440
            )
            .padding(14)
            .background(Color(red: 0.025, green: 0.027, blue: 0.055))
        }

        try renderHosted(dashboard([]), size: CGSize(width: 820, height: 440),
                         to: output.appendingPathComponent("30-empty-new-session.png"))

        let flow = AgentNewSessionFlow()
        flow.present(.newSession, provider: .claude, folder: folder.path)
        let launcher = AgentSessionLauncherView(
            sessions: [],
            managedControl: managed,
            flow: flow,
            onSelectSession: { _ in },
            onStarted: { _ in },
            onDismiss: {}
        )
        .frame(width: 780, alignment: .top)
        .padding(18)
        .background(Color(red: 0.025, green: 0.027, blue: 0.055))
        try renderHosted(launcher, size: CGSize(width: 816, height: 400),
                         to: output.appendingPathComponent("31-new-session-launcher.png"))

        guard case .success(let started) = await managed.startManagedSession(provider: .claude, cwd: folder.path) else {
            return XCTFail("start failed")
        }
        try renderHosted(dashboard(store.sessions), size: CGSize(width: 820, height: 440),
                         to: output.appendingPathComponent("32-new-session-composer.png"))
        XCTAssertEqual(managed.selectedSessionID, started.instance)
        managed.stop()

        // Provider buttons with each provider selected (no refresh, so no
        // provider process is launched).
        let codex = CodexAppServerProvider(client: try CodexAppServerClient())
        let twoProviders = AgentManagedSessionController(
            providers: [claude, codex],
            coordinator: AgentIngestionCoordinator(eventStore: AgentEventStore()),
            eventStore: AgentEventStore(),
            approvals: approvals
        )
        for provider in [AgentProvider.claude, .codex] {
            twoProviders.selectProvider(provider)
            let header = AgentProviderButtons(managedControl: twoProviders)
                .padding(14)
                .background(Color(red: 0.025, green: 0.027, blue: 0.055))
            try renderHosted(header, size: CGSize(width: 260, height: 56),
                             to: output.appendingPathComponent("33-provider-\(provider.stableName)-selected.png"))
        }
    }

    private func renderStandbyDashboard(output: URL) throws {
        let approvals = AgentApprovalController()
        let managed = makeManagedControl(approvals: approvals)
        let view = AgentDashboardContentView(
            sessions: [],
            showsUsage: true,
            approvalControl: approvals,
            managedControl: managed,
            availableHeight: 440
        )
        .padding(14)
        .background(Color(red: 0.025, green: 0.027, blue: 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(12)
        .background(Color(red: 0.055, green: 0.06, blue: 0.12))

        try render(
            view,
            size: CGSize(width: 820, height: 440),
            to: output.appendingPathComponent("11-standby-dashboard.png")
        )
    }

    private func renderWorkspaceDashboard(
        name: String,
        sessions: [AgentSession],
        selectedSessionID: AgentSessionInstanceID?,
        width: CGFloat = 820,
        output: URL
    ) throws {
        let approvals = AgentApprovalController()
        let managed = makeManagedControl(approvals: approvals)
        let view = AgentDashboardContentView(
            sessions: sessions,
            showsUsage: true,
            approvalControl: approvals,
            managedControl: managed,
            availableHeight: 440,
            initialSelectedSessionID: selectedSessionID
        )
        .padding(14)
        .background(Color(red: 0.025, green: 0.027, blue: 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(12)
        .background(Color(red: 0.055, green: 0.06, blue: 0.12))

        try renderHosted(
            view,
            size: CGSize(width: width, height: 480),
            to: output.appendingPathComponent(name + ".png")
        )
    }

    private func makeManagedControl(
        approvals: AgentApprovalController
    ) -> AgentManagedSessionController {
        let store = AgentEventStore()
        return AgentManagedSessionController(
            provider: nil,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: approvals
        )
    }

    private func renderSyntheticDashboardFixture(output: URL) throws {
        let view = VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Synthetic screenshot fixture", systemImage: "camera.fill")
                    .foregroundStyle(.orange)
                Text("Test-only data; unavailable in the application.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.system(size: 9, weight: .semibold))

            AgentDashboardStack(
                sessions: AgentDashboardPreviewFactory.sessions(now: now),
                showsUsage: true,
                approvalControl: AgentApprovalController(),
                layout: AgentDashboardLayoutProjection.make(width: 792),
                reduceMotion: false
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(red: 0.025, green: 0.027, blue: 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(12)
        .background(Color(red: 0.055, green: 0.06, blue: 0.12))

        try render(
            view,
            size: CGSize(width: 820, height: 520),
            to: output.appendingPathComponent("12-synthetic-dashboard-fixture.png")
        )
    }

    private func renderDiagnostics(output: URL) throws {
        let diagnostics = AgentIntegrationDiagnostics(
            state: .active,
            lastAcceptedEventAt: Date().addingTimeInterval(-4),
            acceptedCount: 124,
            rejectedCount: 0,
            droppedCount: 0,
            schemaMismatchCount: 0,
            lastError: nil
        )
        let view = VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Codex", systemImage: "terminal")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
            }
            Text("Receiving events · 4s ago")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            AgentSourceHealthRow(provider: .codex, diagnostics: diagnostics)
            HStack {
                Spacer()
                Text("Reconfigure…")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Remove")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .font(.system(size: 10, weight: .semibold))
        }
        .padding(16)
        .frame(width: 620, alignment: .leading)
        .foregroundStyle(.white)
        .background(Color(red: 0.055, green: 0.058, blue: 0.075))
        .preferredColorScheme(.dark)
        try render(view, size: CGSize(width: 620, height: 190), to: output.appendingPathComponent("10-diagnostics-settings.png"))
    }

    private func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let data = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: data),
              let png = representation.representation(using: .png, properties: [:]) else {
            XCTFail("Could not render \(url.lastPathComponent)")
            return
        }
        try png.write(to: url, options: .atomic)
    }

    private func renderHosted<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let hostingView = NSHostingView(
            rootView: view
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not allocate hosted render for \(url.lastPathComponent)")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            XCTFail("Could not render \(url.lastPathComponent)")
            return
        }
        try png.write(to: url, options: .atomic)
    }

    private func session(
        provider: AgentProvider,
        nativeID: String,
        project: String,
        state: AgentState,
        progress: Double?
    ) -> AgentSession {
        let usage: AgentUsage
        let capabilities: AgentCapabilities
        if let progress {
            usage = AgentUsage(samples: [
                .contextUsed: AgentUsageSample(
                    value: progress * 100,
                    limit: 100,
                    unit: .tokens,
                    scope: "session",
                    source: "structured snapshot fixture",
                    observedAt: now
                )
            ])
            capabilities = AgentCapabilities(evidence: [
                .contextUsage: AgentCapabilityEvidence(
                    authority: .lifecycle,
                    source: "snapshot fixture",
                    observedAt: now
                )
            ])
        } else {
            usage = AgentUsage()
            capabilities = AgentCapabilities()
        }

        let correlation = AgentCorrelationID(rawValue: nativeID + "-operation")
        let activity = AgentActivity(
            id: AgentEventID(rawValue: nativeID + "-activity"),
            kind: state == .waitingForApproval ? .approval : .tool,
            title: state == .waitingForApproval ? "Improve the checkout flow" : title(for: state),
            summary: state == .waitingForApproval ? "Apply the checkout schema migration" : nil,
            status: state == .completed ? .completed : .active,
            correlationID: correlation,
            timestamp: now.addingTimeInterval(-6)
        )
        let approval: [AgentCorrelationID: AgentApproval] = state == .waitingForApproval
            ? [correlation: AgentApproval(
                requestID: correlation,
                summary: "Apply the checkout schema migration",
                operationCorrelationID: correlation,
                requestedAt: now.addingTimeInterval(-6),
                resolvedAt: nil,
                expiresAt: nil,
                state: .pending
            )]
            : [:]
        let tools: [AgentCorrelationID: AgentTool] = state == .runningTool
            ? Dictionary(uniqueKeysWithValues: (0..<3).map { index in
                let id = AgentCorrelationID(rawValue: nativeID + "-bash-\(index)")
                return (id, AgentTool(
                    correlationID: id,
                    name: "bash",
                    category: "shell",
                    summary: nil,
                    status: .active,
                    startedAt: now.addingTimeInterval(Double(-8 + index)),
                    completedAt: nil,
                    success: nil
                ))
            })
            : [:]

        return AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: provider, nativeID: nativeID),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .terminal,
            state: state,
            project: AgentProjectContext(
                displayName: project,
                repositoryIdentity: "makeit/\(project.lowercased())",
                gitBranch: project == "storefront" ? "checkout" : "main",
                model: provider == .codex ? "gpt-5.6-sol" : "claude-sonnet"
            ),
            capabilities: capabilities,
            usage: usage,
            tools: tools,
            commands: [:],
            approvals: approval,
            subagents: [:],
            recentActivity: [activity],
            startedAt: now.addingTimeInterval(-300),
            endedAt: state.isTerminal ? now.addingTimeInterval(-6) : nil,
            lastUpdatedAt: now.addingTimeInterval(-6)
        )
    }

    private func title(for state: AgentState) -> String {
        switch state {
        case .runningTool: "Polish the agent dashboard"
        case .thinking: "Plan component refinements"
        case .completed: "Dashboard refinement complete"
        default: AgentSessionPresentation.stateLabel(state)
        }
    }
}

private struct SnapshotEmptyClaudeCatalog: ClaudeSessionCataloging {
    func recentSessions(limit: Int) throws -> [ClaudeCatalogEntry] { [] }
    func session(nativeSessionID: String) throws -> ClaudeCatalogEntry? { nil }
}
