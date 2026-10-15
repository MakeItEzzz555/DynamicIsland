import AgentBridgeShared
import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentOrbLifecycleTests: XCTestCase {
    func testPermissionArrivalResolutionAndResumeNeverDuplicateTheSession() throws {
        let store = AgentEventStore()
        let id = AgentTestFixture.sessionID(.claude, "orb-owner")
        var offset: TimeInterval = 0
        for generation in 1...3 {
            func ingest(_ type: AgentEventType, correlation: String? = nil, payload: AgentEventPayload = .none) throws {
                offset += 1
                XCTAssertEqual(store.ingest(AgentTestFixture.event("orb-\(offset)", sessionID: id,
                    generation: UInt64(generation), type: type, offset: offset,
                    correlationID: correlation, payload: payload)), .applied)
                let expected = try XCTUnwrap(store.session(for: .init(sessionID: id,
                    generation: .init(rawValue: UInt64(generation)))))
                let presentation = AgentCompactPresentation.make(sessions: store.sessions)
                if expected.state == .idle {
                    XCTAssertNil(presentation, "An older generation cannot own the orb during resume")
                } else {
                    XCTAssertEqual(presentation?.sessions.map(\.id), [expected.id])
                    XCTAssertEqual(presentation?.overflowCount, 0)
                    XCTAssertEqual(AgentOrbStateMapper.state(for: try XCTUnwrap(presentation?.sessions.first)),
                                   AgentOrbStateMapper.state(for: expected))
                }
            }
            try ingest(.sessionStarted, payload: .sessionMetadata(.init(project: nil)))
            try ingest(.thinkingStarted)
            try ingest(.approvalRequested, correlation: "permission", payload: .approvalRequest(
                AgentApprovalRequest(summary: "Synthetic permission", operationCorrelationID: nil, expiresAt: nil)))
            XCTAssertEqual(AgentCompactPresentation.make(sessions: store.sessions)?.sessions.first?.state, .waitingForApproval)
            try ingest(.approvalResolved, correlation: "permission", payload: .approvalResolution(.init(state: .approved)))
            try ingest(.agentWorking)
        }
        XCTAssertEqual(store.sessions.count, 3, "Historical generations remain available to the Feed")
        XCTAssertEqual(store.activeSessions.count, 1)
    }

    func testNativeRootRendersCurrentIdentityAcrossPermissionExpansionAndCollapse() async throws {
        try await exerciseNativeRoot(reducedMotion: false)
    }

    func testReducedMotionKeepsTheSamePermissionAndOrbOwnership() async throws {
        try await exerciseNativeRoot(reducedMotion: true)
    }

    private func exerciseNativeRoot(reducedMotion: Bool) async throws {
        _ = NSApplication.shared
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        settings.reduceExtraMotion = reducedMotion
        settings.mediaEnabled = false
        let modules = NativeIslandFixtureModules.make(settings: settings, providers: [OrbFixtureProvider()])
        defer { modules.agentApprovalControl.cancelAll(); modules.agentManagedControl.stop() }
        guard case .success = await modules.agentManagedControl.startManagedSession(provider: .claude, cwd: "/tmp") else {
            return XCTFail("Inert managed fixture could not start")
        }
        modules.navigation.showAgents()
        let state = IslandStateStore(), layout = IslandLayoutStore()
        let panelFrame = CGRect(x: 0, y: 0, width: 1_000, height: 650)
        let screen = ScreenSnapshot(frame: panelFrame, visibleFrame: panelFrame,
            safeAreaInsets: NSEdgeInsets(), auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
        let root = IslandRootView(settings: settings, islandState: state, layoutStore: layout,
            escapeRouter: IslandEscapeRouter(), modules: modules, rendersExpandedVisualContent: true,
            onRequestExpand: { state.expand() }, onRequestCollapse: { state.collapse() }, onOpenSettings: {})
            .environment(\.isSettingsPreview, true)
            .environment(\.settingsPreviewReduceMotion, reducedMotion)
            .environment(\.nativeVisualSnapshotTime, 1.35)
        let host = NSHostingView(rootView: root)
        let window = IslandOverlayPanel(contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        let id = AgentTestFixture.sessionID(.claude, "native-orb-owner")
        let output = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_ORB_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        var offset = Date().timeIntervalSince(AgentTestFixture.baseDate)
        for generation in 1...2 {
            var permissionTask: Task<AgentBridgePermissionDecision?, Never>?
            var permissionKey: AgentApprovalControlKey?
            for (name, type, payload, correlation) in [
                ("start", AgentEventType.sessionStarted, AgentEventPayload.sessionMetadata(.init(project: nil)), Optional<String>.none),
                ("thinking", .thinkingStarted, .none, nil),
                ("permission", .approvalRequested, .approvalRequest(AgentApprovalRequest(
                    summary: "Synthetic permission", operationCorrelationID: nil, expiresAt: nil)), "permission"),
                ("resolved", .approvalResolved, .approvalResolution(.init(state: .approved)), "permission"),
                ("working", .agentWorking, .none, nil)
            ] {
                offset += 1
                XCTAssertEqual(modules.agentEvents.ingest(AgentTestFixture.event("native-\(offset)", sessionID: id,
                    generation: UInt64(generation), type: type, offset: offset,
                    correlationID: correlation, payload: payload)), .applied)
                if type == .sessionStarted {
                    offset += 1
                    XCTAssertEqual(modules.agentEvents.ingest(AgentTestFixture.event("capabilities-\(offset)", sessionID: id,
                        generation: UInt64(generation), type: .capabilitiesUpdated, offset: offset,
                        payload: .capabilities(AgentTestFixture.capabilities([.approvalControl])))), .applied)
                }
                if type == .approvalRequested {
                    let key = AgentApprovalControlKey(session: .init(sessionID: id, generation: .init(rawValue: UInt64(generation))),
                        requestID: AgentTestFixture.correlation("permission"))
                    let request = AgentApprovalControlRequest(key: key, summary: "Synthetic managed permission", expiresAt: .distantFuture)
                    permissionKey = key
                    permissionTask = Task { await modules.agentApprovalControl.request(request, maximumWait: nil) }
                    let deadline = ContinuousClock.now + .seconds(1)
                    while modules.agentApprovalControl.pendingRequests[key] == nil, ContinuousClock.now < deadline { await Task.yield() }
                    XCTAssertEqual(AgentCompactPermission.current(sessions: modules.agentEvents.sessions,
                        approvals: modules.agentApprovalControl, managed: modules.agentManagedControl)?.request.key, key,
                        "The actual controller-owned permission branch must mount")
                } else if type == .approvalResolved, let key = permissionKey {
                    XCTAssertEqual(modules.agentApprovalControl.resolve(session: key.session, requestID: key.requestID, decision: .allow), .accepted)
                    let decision = await permissionTask?.value
                    XCTAssertEqual(decision, .allow)
                    modules.agentApprovalControl.confirmDelivery(key)
                    XCTAssertNil(AgentCompactPermission.current(sessions: modules.agentEvents.sessions,
                        approvals: modules.agentApprovalControl, managed: modules.agentManagedControl))
                }
                let profile = type == .approvalRequested
                    ? CollapsedPresentationProfile.agentPermission(hovered: false, reduceMotion: reducedMotion)
                    : AgentCollapsedShellPresentation.routine(sessions: modules.agentEvents.sessions, enabled: true) ?? .normal
                let geometry = NotchGeometryService().geometry(for: screen, collapsedSize: CGSize(width: 216, height: 34),
                    expandedSize: CGSize(width: 760, height: 446), collapsedActivityProfile: nil,
                    collapsedPresentationProfile: profile)
                layout.updateLocal(panelFrame: panelFrame, collapsedScreenFrame: geometry.collapsedFrame,
                    expandedScreenFrame: geometry.expandedFrame, hasHardwareNotch: false, hardwareNotchWidth: 0,
                    collapsedLeftRegionWidth: 0, collapsedNotchCoreWidth: 0, collapsedRightRegionWidth: 0,
                    collapsedPresentationProfile: profile)
                for (transition, expanded) in [false, true, false].enumerated() {
                    // The fixture supplies the shell-completion edge normally owned by OverlayWindowController.
                    layout.isShellMorphing = true
                    layout.isCollapseShellOnly = !expanded
                    if expanded { state.expand() } else { state.collapse() }
                    try await Task.sleep(for: .milliseconds(40))
                    layout.isShellMorphing = false
                    layout.isCollapseShellOnly = false
                    try await Task.sleep(for: .milliseconds(output == nil ? 40 : 500))
                    host.layoutSubtreeIfNeeded()
                    let presentation = AgentCompactPresentation.make(sessions: modules.agentEvents.sessions)
                    if type == .sessionStarted {
                        XCTAssertNil(presentation)
                    } else {
                        let compact = try XCTUnwrap(presentation)
                        XCTAssertEqual(compact.sessions.count, 1, "\(name), expanded=\(expanded)")
                        XCTAssertEqual(compact.sessions.first?.id.generation.rawValue, UInt64(generation))
                        XCTAssertEqual(AgentCompactOrbMetrics.trailingWidth(for: compact), AgentCompactOrbMetrics.providerIcon)
                        let renderer = ImageRenderer(content: AgentCompactRoutineTrailingView(presentation: compact)
                            .fixedSize().environment(\.nativeVisualSnapshotTime, 1.35))
                        let trailing = try XCTUnwrap(renderer.cgImage)
                        XCTAssertLessThanOrEqual(trailing.width, Int(AgentCompactOrbMetrics.providerIcon + AgentCompactOrbMetrics.providerIconGap),
                            "Rendered trailing content must contain only the provider icon, with no historical orb")
                    }
                    if let output, type != .sessionStarted {
                        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        try png.write(to: output.appendingPathComponent("\(reducedMotion ? "reduced" : "normal")-generation-\(generation)-\(name)-\(transition)-\(expanded ? "expanded" : "collapsed").png"))
                    }
                }
            }
        }
        XCTAssertFalse(modules.productivity.camera.isRunning)
    }
}

private struct OrbFixtureProvider: AgentInteractiveProvider {
    let provider = AgentProvider.claude
    let interactiveCapabilities: Set<AgentInteractiveCapability> = [.startSession, .resolveApprovals]
    let modelSelectionScope: AgentModelSelectionScope? = nil
    func events() async -> AsyncStream<AgentInteractiveProviderEvent> { AsyncStream { _ in } }
    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] { [] }
    func inspectSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor? { nil }
    func readAccountUsage() async throws -> AgentUsage { AgentUsage() }
    func readTranscript(nativeSessionID: String, limit: Int) async throws -> [AgentManagedTranscriptEntry] { [] }
    func listModels() async throws -> [AgentManagedModelDescriptor] { [] }
    func startSession(cwd: String?, model: String?) async throws -> AgentManagedSessionDescriptor {
        .init(provider: provider, nativeSessionID: "native-orb-owner", cwd: "/tmp", model: nil, acceptsDirectInput: true)
    }
    func resumeSession(nativeSessionID: String, cwd: String?) async throws -> AgentManagedSessionDescriptor {
        try await startSession(cwd: cwd, model: nil)
    }
    func submit(prompt: String, nativeSessionID: String, model: String?) async throws -> AgentManagedTurnDescriptor {
        .init(nativeSessionID: nativeSessionID, turnID: "inert")
    }
    func interrupt(nativeSessionID: String, turnID: String) async throws {}
    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {}
    func stop() async {}
}
