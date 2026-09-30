import Foundation

/// Persists only messaging preferences (booleans and provider names).
/// Message bodies, conversations, recipients and drafts are never stored.
struct MessagingPreferencesPersistence {
    static let enabledKey = "messaging.enabled"
    static let showPreviewKey = "messaging.showPreviewOnCompact"
    static let mutedProvidersKey = "messaging.mutedProviders"

    let defaults: UserDefaults

    func load() -> MessagingController.Preferences {
        var preferences = MessagingController.Preferences()
        if defaults.object(forKey: Self.enabledKey) != nil {
            preferences.enabled = defaults.bool(forKey: Self.enabledKey)
        }
        if defaults.object(forKey: Self.showPreviewKey) != nil {
            preferences.showPreviewOnCompact = defaults.bool(forKey: Self.showPreviewKey)
        }
        let muted = defaults.stringArray(forKey: Self.mutedProvidersKey) ?? []
        preferences.mutedProviders = Set(muted.compactMap(Self.provider(named:)))
        return preferences
    }

    func save(_ preferences: MessagingController.Preferences) {
        defaults.set(preferences.enabled, forKey: Self.enabledKey)
        defaults.set(preferences.showPreviewOnCompact, forKey: Self.showPreviewKey)
        defaults.set(preferences.mutedProviders.map(\.stableName).sorted(), forKey: Self.mutedProvidersKey)
    }

    static func provider(named name: String) -> MessagingProviderID? {
        switch name {
        case "messages": .messages
        case "whatsapp": .whatsapp
        case "telegram": .telegram
        default: name.hasPrefix("custom:") ? .custom(String(name.dropFirst("custom:".count))) : nil
        }
    }
}

/// Provider state for Settings and Copy Diagnostics. Contains no message
/// bodies, titles, senders, handles, conversation ids or drafts.
struct MessagingDiagnosticsReport: Equatable, Sendable {
    struct ProviderRow: Equatable, Sendable {
        let provider: MessagingProviderID
        let availability: MessagingProviderAvailability
        let hasAdapter: Bool
        let muted: Bool
        let observeIncoming: Bool
        let inlineReply: Bool
        let exactTarget: Bool
        let openAction: Bool
        let limitations: [MessagingCapability: String]
        let lastEventAt: Date?
        let queuedConversations: Int

        var observationSummary: String {
            observeIncoming ? "Observes incoming messages" : (limitations[.observeIncoming] ?? "No incoming source")
        }

        var replySummary: String {
            if inlineReply { return "Inline reply with exact conversation targeting" }
            return limitations[.sendReply] ?? "Inline reply not available"
        }

        var fallbackSummary: String {
            if inlineReply { return "Open app if a send fails" }
            if openAction { return "Open-App fallback" }
            return "None"
        }
    }

    /// Providers audited but not shipped as adapters (not installed here).
    static let auditedProviders: [MessagingProviderID] = [.messages, .whatsapp, .telegram]

    let messagingEnabled: Bool
    let showsPreviewOnCompact: Bool
    let providers: [ProviderRow]

    @MainActor
    static func make(controller: MessagingController) -> Self {
        let providerIDs = (auditedProviders + controller.orderedProviders).reduce(into: [MessagingProviderID]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        let rows = providerIDs.map { id -> ProviderRow in
            let adapter = controller.adapters[id]
            let capabilities = adapter?.capabilities ?? MessagingProviderCapabilities(
                supported: [],
                limitations: [
                    .observeIncoming: "No public incoming source; not installed on this Mac",
                    .sendReply: "No supported send mechanism; documented links only pre-fill a compose window"
                ]
            )
            return ProviderRow(
                provider: id,
                availability: adapter?.availability ?? .notInstalled,
                hasAdapter: adapter != nil,
                muted: controller.preferences.mutedProviders.contains(id),
                observeIncoming: capabilities.contains(.observeIncoming),
                inlineReply: capabilities.supportsInlineReply,
                exactTarget: capabilities.contains(.exactConversationTarget),
                openAction: capabilities.contains(.openApp) || capabilities.contains(.openConversation),
                limitations: capabilities.limitations,
                lastEventAt: controller.providerHealth[id],
                queuedConversations: controller.queue.entries.filter { $0.conversation.provider == id }.count
            )
        }
        return Self(
            messagingEnabled: controller.preferences.enabled,
            showsPreviewOnCompact: controller.preferences.showPreviewOnCompact,
            providers: rows
        )
    }

    func plainText(generatedAt: Date = Date()) -> String {
        var lines = ["DynamicIsland messaging diagnostics", "Generated: \(ISO8601DateFormatter().string(from: generatedAt))"]
        lines.append("messaging: \(messagingEnabled ? "enabled" : "disabled") · compact preview: \(showsPreviewOnCompact ? "shown" : "hidden")")
        for row in providers {
            lines.append("")
            lines.append("[\(row.provider.stableName)]")
            lines.append("  availability: \(Self.describe(row.availability))\(row.hasAdapter ? "" : " (no adapter)")")
            lines.append("  muted: \(row.muted ? "yes" : "no")")
            lines.append("  incoming: \(row.observationSummary)")
            lines.append("  reply: \(row.replySummary)")
            lines.append("  exact target: \(row.exactTarget ? "yes" : "no")")
            lines.append("  fallback: \(row.fallbackSummary)")
            lines.append("  last event: \(row.lastEventAt.map { ISO8601DateFormatter().string(from: $0) } ?? "never")")
            lines.append("  queued conversations: \(row.queuedConversations)")
        }
        return lines.joined(separator: "\n")
    }

    static func describe(_ availability: MessagingProviderAvailability) -> String {
        switch availability {
        case .available: "available"
        case .notInstalled: "not installed"
        case .unavailable(let reason): "unavailable (\(reason))"
        }
    }
}
