import AppKit
import SwiftUI

/// Messaging settings: privacy preferences plus the truthful capability
/// state of every provider. Never shows message content.
struct MessagingSettingsView: View {
    @ObservedObject var controller: MessagingController
    @State private var copied = false

    var body: some View {
        let report = MessagingDiagnosticsReport.make(controller: controller)
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup("Messaging") {
                Toggle("Show incoming messages in the island", isOn: $controller.preferences.enabled)
                Toggle("Show message preview on the compact island", isOn: $controller.preferences.showPreviewOnCompact)
                    .disabled(!controller.preferences.enabled)
                HelpText("Messages are kept in memory only while they are shown. Message text, conversations and reply drafts are never saved to disk or included in diagnostics.")
            }

            SettingsGroup("Providers") {
                ForEach(report.providers, id: \.provider) { row in
                    providerRow(row)
                    if row.provider != report.providers.last?.provider {
                        Divider()
                    }
                }
            }

            SettingsGroup("Diagnostics") {
                HStack {
                    Button("Refresh") { controller.refreshProviders() }
                    Button(copied ? "Copied" : "Copy Diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.plainText(), forType: .string)
                        copied = true
                    }
                }
                .controlSize(.small)
                HelpText("Includes provider availability and capabilities only. Never includes message text, names, handles or conversation identifiers.")
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ row: MessagingDiagnosticsReport.ProviderRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: row.provider.symbolName)
                Text(row.provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                chip(MessagingDiagnosticsReport.describe(row.availability).capitalized, ok: row.availability == .available)
                chip(classification(row), ok: row.inlineReply)
                Spacer()
                if row.hasAdapter {
                    Toggle("Enabled", isOn: Binding(
                        get: { !controller.preferences.mutedProviders.contains(row.provider) },
                        set: { enabled in
                            if enabled {
                                controller.preferences.mutedProviders.remove(row.provider)
                            } else {
                                controller.preferences.mutedProviders.insert(row.provider)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
            detail("Incoming", row.observationSummary)
            detail("Reply", row.replySummary)
            detail("Exact conversation", row.exactTarget ? "Available" : (row.limitations[.exactConversationTarget] ?? "Not available"))
            detail("Permission", row.hasAdapter ? "None required" : "—")
            detail("Fallback", row.fallbackSummary)
            detail("Last event", row.lastEventAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
            if row.hasAdapter, row.openAction {
                Button("Open \(row.provider.displayName)") {
                    _ = controller.adapters[row.provider]?.open(nil)
                }
                .controlSize(.small)
            }
        }
    }

    private func classification(_ row: MessagingDiagnosticsReport.ProviderRow) -> String {
        if row.inlineReply { return "Inline reply" }
        if !row.hasAdapter { return "Not supported" }
        if row.openAction { return "Open app only" }
        return "Read-only"
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chip(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((ok ? Color.green : Color.secondary).opacity(0.15), in: Capsule())
            .foregroundStyle(ok ? Color.green : Color.secondary)
    }
}
