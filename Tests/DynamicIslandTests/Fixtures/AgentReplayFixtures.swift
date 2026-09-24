import Foundation
@testable import DynamicIsland

enum AgentTestFixture {
    static let baseDate = Date(timeIntervalSince1970: 2_000_000_000)

    static func sessionID(_ provider: AgentProvider, _ nativeID: String) -> AgentSessionID {
        AgentSessionID(provider: provider, nativeID: nativeID)
    }

    static func generation(_ value: UInt64) -> AgentSessionGeneration {
        AgentSessionGeneration(rawValue: value)
    }

    static func correlation(_ value: String) -> AgentCorrelationID {
        AgentCorrelationID(rawValue: value)
    }

    static func event(
        _ name: String,
        sessionID: AgentSessionID,
        generation: UInt64 = 1,
        source: AgentSource = .terminal,
        type: AgentEventType,
        offset: TimeInterval,
        correlationID: String? = nil,
        providerOffset: TimeInterval? = nil,
        authority: AgentEvidenceAuthority = .lifecycle,
        payload: AgentEventPayload = .none,
        schemaVersion: Int = AgentEvent.normalizedSchemaVersion
    ) -> AgentEvent {
        AgentEvent(
            schemaVersion: schemaVersion,
            eventID: AgentEventID(rawValue: name),
            sessionID: sessionID,
            generation: self.generation(generation),
            source: source,
            type: type,
            providerTimestamp: providerOffset.map { baseDate.addingTimeInterval($0) },
            receivedTimestamp: baseDate.addingTimeInterval(offset),
            correlationID: correlationID.map(correlation),
            sequence: UInt64(max(0, Int(offset))),
            authority: authority,
            origin: .replay,
            payload: payload
        )
    }

    static func project(
        name: String = "DynamicIsland",
        path: String = "/Users/example/DynamicIsland",
        model: String? = nil
    ) -> AgentProjectContext {
        AgentProjectContext(
            displayName: name,
            workingDirectory: path,
            repositoryIdentity: "example/dynamic-island",
            gitBranch: "feature/agent-activity",
            gitCommit: "abc123",
            model: model
        )
    }

    static func capabilities(
        _ values: Set<AgentCapability>,
        observedAt: Date = baseDate
    ) -> AgentCapabilities {
        AgentCapabilities(evidence: Dictionary(uniqueKeysWithValues: values.map { capability in
            (
                capability,
                AgentCapabilityEvidence(
                    authority: .lifecycle,
                    source: "normalized-fixture",
                    observedAt: observedAt
                )
            )
        }))
    }

    static var codexNormal: AgentReplayFixture {
        let id = sessionID(.codex, "codex-normal")
        return AgentReplayFixture(name: "Codex normal", events: [
            event(
                "codex-start",
                sessionID: id,
                type: .sessionStarted,
                offset: 0,
                payload: .sessionMetadata(AgentSessionMetadata(project: project(model: "gpt-5.6")))
            ),
            event(
                "codex-capabilities",
                sessionID: id,
                type: .capabilitiesUpdated,
                offset: 1,
                payload: .capabilities(capabilities([
                    .sessionLifecycle, .explicitThinking, .commandLifecycle,
                    .planLifecycle, .approvalObservation, .taskLifecycle, .tokenUsage
                ]))
            ),
            event(
                "codex-thinking-start",
                sessionID: id,
                type: .thinkingStarted,
                offset: 2,
                payload: .activity(AgentActivityDescriptor(title: "Thinking", summary: nil))
            ),
            event("codex-thinking-end", sessionID: id, type: .thinkingEnded, offset: 3),
            event(
                "codex-command-start",
                sessionID: id,
                type: .commandStarted,
                offset: 4,
                correlationID: "command-1",
                payload: .command(AgentCommandEvent(executable: "/usr/bin/git status --secret value", success: nil, exitCode: nil))
            ),
            event(
                "codex-command-end",
                sessionID: id,
                type: .commandCompleted,
                offset: 5,
                correlationID: "command-1",
                payload: .command(AgentCommandEvent(executable: nil, success: true, exitCode: 0))
            ),
            event(
                "codex-planning",
                sessionID: id,
                type: .planningStarted,
                offset: 6,
                payload: .activity(AgentActivityDescriptor(title: "Planning", summary: "Preparing implementation"))
            ),
            event(
                "codex-plan-update",
                sessionID: id,
                type: .planUpdated,
                offset: 7,
                payload: .plan(AgentPlanEvent(summary: "Implement then test"))
            ),
            event(
                "codex-plan-ready",
                sessionID: id,
                type: .planReady,
                offset: 8,
                payload: .plan(AgentPlanEvent(summary: "Plan ready for review"))
            ),
            event(
                "codex-approval-request",
                sessionID: id,
                type: .approvalRequested,
                offset: 9,
                correlationID: "approval-1",
                payload: .approvalRequest(AgentApprovalRequest(
                    summary: "Allow test command",
                    operationCorrelationID: correlation("command-tests"),
                    expiresAt: nil
                ))
            ),
            event(
                "codex-approval-resolved",
                sessionID: id,
                type: .approvalResolved,
                offset: 10,
                correlationID: "approval-1",
                payload: .approvalResolution(AgentApprovalResolution(state: .approved))
            ),
            event(
                "codex-working",
                sessionID: id,
                type: .agentWorking,
                offset: 11,
                payload: .activity(AgentActivityDescriptor(title: "Implementing", summary: nil))
            ),
            event(
                "codex-tests-start",
                sessionID: id,
                type: .commandStarted,
                offset: 12,
                correlationID: "command-tests",
                payload: .command(AgentCommandEvent(executable: "swift", success: nil, exitCode: nil))
            ),
            event(
                "codex-tests-end",
                sessionID: id,
                type: .commandCompleted,
                offset: 13,
                correlationID: "command-tests",
                payload: .command(AgentCommandEvent(executable: nil, success: true, exitCode: 0))
            ),
            event(
                "codex-complete",
                sessionID: id,
                type: .taskCompleted,
                offset: 14,
                payload: .terminal(AgentTerminalEvent(summary: "Implementation complete"))
            )
        ])
    }

    static var claudeNormal: AgentReplayFixture {
        let id = sessionID(.claude, "claude-normal")
        return AgentReplayFixture(name: "Claude normal", events: [
            event(
                "claude-start",
                sessionID: id,
                source: .vscode,
                type: .sessionStarted,
                offset: 0,
                payload: .sessionMetadata(AgentSessionMetadata(project: project(model: "claude")))
            ),
            event(
                "claude-thinking",
                sessionID: id,
                source: .vscode,
                type: .thinkingStarted,
                offset: 1,
                payload: .activity(AgentActivityDescriptor(title: "Thinking", summary: nil))
            ),
            event(
                "claude-task",
                sessionID: id,
                source: .vscode,
                type: .planUpdated,
                offset: 2,
                payload: .plan(AgentPlanEvent(summary: "Todo: inspect, change, test"))
            ),
            event(
                "claude-tool-start",
                sessionID: id,
                source: .vscode,
                type: .toolStarted,
                offset: 3,
                correlationID: "tool-1",
                payload: .tool(AgentToolEvent(name: "Edit", category: "filesystem", summary: "Editing file", success: nil))
            ),
            event(
                "claude-permission",
                sessionID: id,
                source: .vscode,
                type: .approvalRequested,
                offset: 4,
                correlationID: "permission-1",
                payload: .approvalRequest(AgentApprovalRequest(
                    summary: "Allow file edit",
                    operationCorrelationID: correlation("tool-1"),
                    expiresAt: nil
                ))
            ),
            event(
                "claude-permission-resolved",
                sessionID: id,
                source: .vscode,
                type: .approvalResolved,
                offset: 5,
                correlationID: "permission-1",
                payload: .approvalResolution(AgentApprovalResolution(state: .approved))
            ),
            event(
                "claude-subagent-start",
                sessionID: id,
                source: .vscode,
                type: .subagentStarted,
                offset: 6,
                correlationID: "subagent-1",
                payload: .subagent(AgentSubagentEvent(nativeID: "child-1", displayName: "Reviewer"))
            ),
            event(
                "claude-subagent-end",
                sessionID: id,
                source: .vscode,
                type: .subagentEnded,
                offset: 7,
                correlationID: "subagent-1",
                payload: .subagent(AgentSubagentEvent(nativeID: "child-1", displayName: "Reviewer"))
            ),
            event(
                "claude-tool-end",
                sessionID: id,
                source: .vscode,
                type: .toolCompleted,
                offset: 8,
                correlationID: "tool-1",
                payload: .tool(AgentToolEvent(name: "Edit", category: nil, summary: "Edit complete", success: true))
            ),
            event(
                "claude-complete",
                sessionID: id,
                source: .vscode,
                type: .taskCompleted,
                offset: 9,
                payload: .terminal(AgentTerminalEvent(summary: "Claude task complete"))
            )
        ])
    }
}
