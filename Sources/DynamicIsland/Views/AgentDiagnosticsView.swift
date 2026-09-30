import AppKit
import SwiftUI

/// Compact provider and project diagnostics for the AI Agents settings.
struct AgentDiagnosticsView: View {
    @ObservedObject var agentEvents: AgentEventStore
    @ObservedObject var managedControl: AgentManagedSessionController
    @ObservedObject var projects: AgentProjectProjectionStore
    @State private var copied = false

    private var report: AgentDiagnosticsReport {
        AgentDiagnosticsReport.make(
            sessions: agentEvents.sessions,
            managedProviders: managedControl.managedProviders,
            accountUsageByProvider: managedControl.accountUsageByProvider,
            selectedSessionIDs: managedControl.selectedSessionIDs,
            transportErrors: managedControl.transportErrorsByProvider,
            locations: projects.index,
            projectionResolving: projects.status == .resolving,
            lastProjectionRefreshAt: projects.lastRefreshAt
        )
    }

    var body: some View {
        let report = report
        VStack(alignment: .leading, spacing: 12) {
            ForEach(report.providers, id: \.provider) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: AgentVisualStyle.providerSymbol(row.provider))
                        Text(row.provider.stableName.capitalized)
                            .font(.system(size: 12, weight: .semibold))
                        statusChip(row.detected ? "Detected" : "Not detected", ok: row.detected)
                        statusChip(
                            row.managedControlAvailable ? "Managed control" : "Observation only",
                            ok: row.managedControlAvailable
                        )
                        Spacer()
                        Text("\(row.observedSessionCount) sessions · \(row.resumableSessionCount) resumable")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(row.usage.map(usageSummary).joined(separator: "   "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = row.transportError {
                        Text("Last transport error: \(error)")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
            }

            Divider()

            HStack {
                Text("Project resolution")
                    .font(.system(size: 12, weight: .semibold))
                Text(report.projectionResolving ? "Resolving…" : "Idle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let refreshed = report.lastProjectionRefreshAt {
                    Text("· refreshed \(refreshed.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { projects.refresh() }
                    .controlSize(.small)
            }

            if report.projects.isEmpty {
                Text("No session working directories reported yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.projects, id: \.displayedDirectory) { project in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.displayedDirectory)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .textSelection(.enabled)
                        Text(projectDetail(project))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack {
                Button(copied ? "Copied" : "Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.plainText(), forType: .string)
                    copied = true
                }
                .controlSize(.small)
                Text("Includes counts, capability state and project paths. Never includes prompts, transcripts or session IDs.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func usageSummary(_ indicator: AgentUsageIndicator) -> String {
        guard indicator.isAvailable else { return "\(indicator.label): unavailable" }
        return "\(indicator.label): \(indicator.valueText) \(indicator.directionLabel) (\(indicator.authority.rawValue), \(indicator.freshness.rawValue))"
    }

    private func projectDetail(_ project: AgentDiagnosticsReport.ProjectRow) -> String {
        var parts: [String] = []
        if project.canonicalPath != project.displayedDirectory {
            parts.append("canonical \(project.canonicalPath)")
        }
        parts.append("repository \(project.repositoryRoot ?? "none")")
        parts.append(project.status?.rawValue ?? "unresolved")
        parts.append("\(project.sessionCount) session\(project.sessionCount == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private func statusChip(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((ok ? Color.green : Color.secondary).opacity(0.15), in: Capsule())
            .foregroundStyle(ok ? Color.green : Color.secondary)
    }
}
