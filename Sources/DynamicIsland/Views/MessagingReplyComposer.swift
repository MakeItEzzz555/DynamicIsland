import AppKit
import SwiftUI

/// Shares the exact-target draft/send path with the expanded Messages page.
struct MessagingReplyComposer: View {
    @ObservedObject var controller: MessagingController
    let entry: MessagingQueueEntry
    var onFocus: (Bool) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    @FocusState private var composerFocused: Bool
    @State private var inputWindow: NSWindow?
    @State private var inputOwner = UUID()
    @State private var measuredFrame = TimerRulerMeasuredFrame()
    @Environment(\.timerRulerInteractionRegistration) private var inputRegistration

    var body: some View {
        let draft = controller.draft(for: entry)
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
                .id(entry.key)
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
                    .frame(width: 34, height: 34)
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
            .frame(height: 34)
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
        .background(ReplyComposerWindowOwner { inputWindow = $0 })
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(IslandCanvasCoordinateSpace.name))
        } action: { frame in
            measuredFrame.frame = frame
            DispatchQueue.main.async {
                inputRegistration.report(inputOwner, inputRegistration.enabled && !frame.isEmpty ? frame : nil)
            }
        }
        .onChange(of: inputRegistration.enabled) { _, enabled in
            inputRegistration.report(inputOwner, enabled ? measuredFrame.frame : nil)
        }
        .onChange(of: composerFocused) { _, focused in
            onFocus(focused)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window === inputWindow {
                composerFocused = false
                onDismiss()
            }
        }
        .onExitCommand {
            composerFocused = false
            onDismiss()
        }
        .onDisappear {
            inputWindow = nil
            inputRegistration.report(inputOwner, nil)
            onFocus(false)
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

}

private struct ReplyComposerWindowOwner: NSViewRepresentable {
    let changed: (NSWindow?) -> Void
    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.changed = { _ in } }

    final class Probe: NSView {
        var changed: (NSWindow?) -> Void
        init(changed: @escaping (NSWindow?) -> Void) { self.changed = changed; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.changed(self.window)
            }
        }
    }
}
