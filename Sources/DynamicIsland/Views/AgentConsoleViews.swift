import AppKit
import SwiftUI

struct AgentEmbeddedConsoleView: View {
    let session: AgentSession
    var canSubmit = false
    var canInterrupt = false
    let onSubmit: (String) -> Void
    let onInterrupt: () -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            activity
            composer
        }
        .padding(8)
        .background(Color.black.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent console for \(AgentSessionPresentation.primaryTitle(for: session))")
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
            Text(AgentSessionPresentation.primaryTitle(for: session))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
            Text(session.id.sessionID.provider.stableName.capitalized)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.40))
            Spacer(minLength: 8)
            if canSubmit {
                Label("Interactive", systemImage: "bolt.fill")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(.green.opacity(0.82))
            } else {
                Text("Observed")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.36))
            }
            if canInterrupt {
                Button(action: onInterrupt) {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Interrupt the current managed turn")
            }
        }
    }

    @ViewBuilder
    private var activity: some View {
        let operations = Array(
            AgentOperationAggregation.make(
                for: session,
                limit: 4,
                includePendingApprovals: false
            ).suffix(4)
        )
        VStack(alignment: .leading, spacing: 3) {
            if operations.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: AgentSessionPresentation.stateSymbol(session.state))
                        .frame(width: 11)
                    Text(AgentSessionPresentation.stateLabel(session.state))
                }
                .foregroundStyle(.white.opacity(0.48))
            } else {
                ForEach(operations) { operation in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: operation.symbol)
                            .frame(width: 11)
                            .foregroundStyle(operationColor(operation.status))
                        Text(operation.displayTitle)
                            .fontDesign(operation.isCommand ? .monospaced : .default)
                            .foregroundStyle(.white.opacity(operation.status == .active ? 0.88 : 0.52))
                            .lineLimit(1)
                        if let detail = operation.detail, !detail.isEmpty {
                            Text(detail)
                                .fontDesign(operation.isCommand ? .monospaced : .default)
                                .foregroundStyle(.white.opacity(0.34))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .font(.system(size: 8.5, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 7) {
            AgentPromptEditor(
                text: $draft,
                enabled: canSubmit,
                placeholder: canSubmit ? "Message Codex…" : "Observed session — interactive control unavailable",
                onSubmit: submitDraft
            )
            .frame(minHeight: 30, maxHeight: 48)

            Button(action: submitDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(canSubmit && !trimmedDraft.isEmpty ? .white : .white.opacity(0.24))
            .disabled(!canSubmit || trimmedDraft.isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Send prompt (Command-Return)")
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitDraft() {
        let value = String(trimmedDraft.prefix(8_000))
        guard !value.isEmpty else { return }
        onSubmit(value)
        draft = ""
    }

    private func operationColor(_ status: AgentOperationStatus) -> Color {
        switch status {
        case .active: .white.opacity(0.86)
        case .pending: .orange.opacity(0.88)
        case .failed: .red.opacity(0.88)
        case .completed, .resolved: .green.opacity(0.58)
        case .cancelled, .unknown: .white.opacity(0.34)
        }
    }
}

private struct AgentPromptEditor: NSViewRepresentable {
    @Binding var text: String
    let enabled: Bool
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let editor = AgentPromptTextView()
        editor.delegate = context.coordinator
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 7, height: 6)
        editor.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        editor.textColor = NSColor.white.withAlphaComponent(0.88)
        editor.insertionPointColor = .white
        editor.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.45),
            .foregroundColor: NSColor.white
        ]
        editor.submitHandler = onSubmit
        editor.placeholder = placeholder
        editor.isEditable = enabled
        editor.isSelectable = true

        scroll.documentView = editor
        context.coordinator.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? AgentPromptTextView else { return }
        editor.submitHandler = onSubmit
        editor.placeholder = placeholder
        editor.isEditable = enabled
        if editor.string != text {
            editor.string = text
        }
        editor.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var editor: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            text = editor.string
        }
    }
}

private final class AgentPromptTextView: NSTextView {
    var submitHandler: (() -> Void)?
    var placeholder = ""

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            submitHandler?()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if isEditable {
            window?.makeKey()
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.30)
        ]
        NSString(string: placeholder).draw(
            at: NSPoint(x: textContainerInset.width + 1, y: textContainerInset.height),
            withAttributes: attributes
        )
    }
}
