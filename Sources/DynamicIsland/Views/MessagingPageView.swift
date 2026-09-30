import SwiftUI

/// What the expanded message surface may offer for one conversation.
/// Derived purely from provider capability and draft state, so the view
/// cannot show a control the provider does not support.
enum MessagingInteractionMode: Equatable {
    /// Exact target + send authority: composer and Send.
    case reply
    /// Message visible; Open App available; no composer.
    case openAppOnly
    /// Message visible; nothing actionable.
    case readOnly

    static func resolve(
        canReply: Bool,
        capabilities: MessagingProviderCapabilities
    ) -> Self {
        if canReply { return .reply }
        if capabilities.contains(.openApp) || capabilities.contains(.openConversation) {
            return .openAppOnly
        }
        return .readOnly
    }
}

enum MessagingDraftStatusPresentation: Equatable {
    case none
    case sending
    case sent
    case failed(String, retryable: Bool)
    case uncertain(String)

    init(_ state: MessagingDraftState) {
        switch state {
        case .idle, .drafting: self = .none
        case .sending: self = .sending
        case .sent: self = .sent
        case .failed(let reason, let retryable): self = .failed(reason, retryable: retryable)
        case .uncertain(let reason): self = .uncertain(reason)
        }
    }
}

/// Expanded Messages page inside the existing island shell. No separate
/// window, no scroll views (island scroll gestures stay unambiguous).
struct MessagingPageView: View {
    @ObservedObject var controller: MessagingController
    let layoutStore: IslandLayoutStore?
    let pageHeight: CGFloat
    @State private var selectedKey: String?
    @FocusState private var composerFocused: Bool

    private var entries: [MessagingQueueEntry] { controller.visibleEntries }

    private var entry: MessagingQueueEntry? {
        entries.first { $0.key == selectedKey } ?? entries.first
    }

    var body: some View {
        Group {
            if let entry {
                content(for: entry)
            } else {
                Text("No messages")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: pageHeight, alignment: .topLeading)
        .onChange(of: composerFocused) { _, focused in
            layoutStore?.setTextInputFocused(focused)
        }
        .onDisappear {
            layoutStore?.setTextInputFocused(false)
        }
    }

    @ViewBuilder
    private func content(for entry: MessagingQueueEntry) -> some View {
        let capabilities = controller.capabilities(for: entry.conversation.provider)
        let mode = MessagingInteractionMode.resolve(
            canReply: controller.canReply(to: entry),
            capabilities: capabilities
        )
        let draft = controller.draft(for: entry)

        VStack(alignment: .leading, spacing: 10) {
            header(for: entry)

            Text(entry.latest.body ?? "Message content is not available from \(entry.conversation.provider.displayName).")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(entry.latest.body == nil ? 0.45 : 0.9))
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            switch mode {
            case .reply:
                composer(for: entry, draft: draft)
            case .openAppOnly, .readOnly:
                readOnlyFooter(for: entry, mode: mode, capabilities: capabilities)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { controller.acknowledge(entry) }
        .onChange(of: entry.key) { _, _ in controller.acknowledge(entry) }
    }

    private func header(for entry: MessagingQueueEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.conversation.provider.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.conversation.displayTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(entry.conversation.provider.displayName) · \(entry.latest.receivedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 8)
            if entries.count > 1 {
                conversationSwitcher(current: entry)
            }
            Button {
                controller.dismiss(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss message from \(entry.conversation.displayTitle)")
        }
    }

    private func conversationSwitcher(current: MessagingQueueEntry) -> some View {
        HStack(spacing: 4) {
            ForEach(entries.prefix(4)) { candidate in
                Button {
                    selectedKey = candidate.key
                } label: {
                    Text(initials(candidate.conversation.displayTitle))
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white.opacity(candidate.key == current.key ? 0.95 : 0.55))
                        .frame(width: 20, height: 20)
                        .background(
                            .white.opacity(candidate.key == current.key ? 0.18 : 0.07),
                            in: Circle()
                        )
                        .overlay(alignment: .topTrailing) {
                            if candidate.unseenCount > 0, candidate.key != current.key {
                                Circle().fill(.blue).frame(width: 6, height: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show conversation \(candidate.conversation.displayTitle)")
            }
        }
    }

    private func composer(for entry: MessagingQueueEntry, draft: MessagingDraft) -> some View {
        let status = MessagingDraftStatusPresentation(draft.state)
        let sending = status == .sending
        return VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Reply to \(entry.conversation.displayTitle)…", text: Binding(
                    get: { controller.draft(for: entry).text },
                    set: { controller.updateDraft($0, for: entry) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($composerFocused)
                .disabled(sending)
                .onSubmit { send(entry) }

                Button {
                    send(entry)
                } label: {
                    Group {
                        if sending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSubmit(draft) ? .white : .white.opacity(0.25))
                .disabled(!canSubmit(draft))
                .fixedSize()
                .help("Send reply")
                .accessibilityLabel("Send reply")
            }
            .padding(.leading, 10)
            .padding(.trailing, 5)
            .frame(height: 32)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            }

            HStack(spacing: 8) {
                statusText(status)
                Spacer(minLength: 0)
                openAppButton(for: entry)
            }
        }
    }

    @ViewBuilder
    private func statusText(_ status: MessagingDraftStatusPresentation) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .sending:
            Text("Sending…").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
        case .sent:
            Label("Sent", systemImage: "checkmark").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.green)
        case .failed(let reason, let retryable):
            Text(retryable ? "\(reason) · draft kept, retry or open the app" : "\(reason) · draft kept")
                .font(.system(size: 9.5)).foregroundStyle(.orange).lineLimit(1)
        case .uncertain(let reason):
            Text("\(reason) · draft kept").font(.system(size: 9.5)).foregroundStyle(.orange).lineLimit(1)
        }
    }

    private func readOnlyFooter(
        for entry: MessagingQueueEntry,
        mode: MessagingInteractionMode,
        capabilities: MessagingProviderCapabilities
    ) -> some View {
        HStack(spacing: 8) {
            Label(
                capabilities.limitations[.sendReply]
                    ?? capabilities.limitations[.exactConversationTarget]
                    ?? "Replying from the island is not available for \(entry.conversation.provider.displayName)",
                systemImage: "info.circle"
            )
            .font(.system(size: 9.5))
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(2)
            Spacer(minLength: 0)
            if mode == .openAppOnly {
                openAppButton(for: entry)
            }
        }
    }

    private func openAppButton(for entry: MessagingQueueEntry) -> some View {
        Button("Open \(entry.conversation.provider.displayName)") {
            controller.open(entry)
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(.white.opacity(0.07), in: Capsule())
    }

    private func canSubmit(_ draft: MessagingDraft) -> Bool {
        !draft.state.isSending && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ entry: MessagingQueueEntry) {
        guard canSubmit(controller.draft(for: entry)) else { return }
        Task { await controller.send(for: entry) }
    }

    private func initials(_ title: String) -> String {
        let parts = title.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
