import AppKit
import SwiftUI

enum AgentConsoleMode: Equatable, Sendable {
    case observed
    case interactive(canInterrupt: Bool)

    var showsComposer: Bool {
        if case .interactive = self { return true }
        return false
    }

    var canInterrupt: Bool {
        if case let .interactive(canInterrupt) = self { return canInterrupt }
        return false
    }
}

enum AgentPromptDraftPolicy {
    static let maximumLength = 8_000

    static func bounded(_ value: String) -> String {
        String(value.prefix(maximumLength))
    }

    static func submission(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return bounded(trimmed)
    }

    static func submitsReturn(with modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.intersection(.deviceIndependentFlagsMask).contains(.command)
    }
}

struct AgentEmbeddedConsoleView: View {
    let session: AgentSession
    var mode: AgentConsoleMode = .observed
    var maximumActivityEntries = 3
    var layoutStore: IslandLayoutStore? = nil
    let onSubmit: (String) -> Bool
    let onInterrupt: () -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            transcript
            if mode.showsComposer {
                composer
            } else {
                observedFooter
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected session details for \(AgentSessionPresentation.primaryTitle(for: session))")
        .onChange(of: session.id) { _, _ in draft = "" }
        .onChange(of: mode.showsComposer) { _, isInteractive in
            if !isInteractive { draft = "" }
        }
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
            Label(
                AgentSessionPresentation.shortStateLabel(session.state),
                systemImage: AgentSessionPresentation.stateSymbol(session.state)
            )
            .font(.system(size: 7.5, weight: .semibold))
            .foregroundStyle(AgentVisualStyle.accent(for: session.state).opacity(0.86))
            if mode.canInterrupt {
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
    private var transcript: some View {
        registeredTranscript(
            ScrollView(.vertical, showsIndicators: true) {
                transcriptContent
                    .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var transcriptContent: some View {
        let operations = Array(
            AgentOperationAggregation.make(
                for: session,
                limit: maximumActivityEntries,
                includePendingApprovals: true
            ).suffix(maximumActivityEntries)
        )
        return LazyVStack(alignment: .leading, spacing: 5) {
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
                            .lineLimit(2)
                        if let detail = operation.detail, !detail.isEmpty {
                            Text(detail)
                                .fontDesign(operation.isCommand ? .monospaced : .default)
                                .foregroundStyle(.white.opacity(0.34))
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .font(.system(size: 8.5, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func registeredTranscript<Content: View>(_ content: Content) -> some View {
        if let layoutStore {
            content
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AgentConsoleScrollRegionPreferenceKey.self,
                            value: proxy.frame(in: .named(IslandCanvasCoordinateSpace.name))
                        )
                    }
                }
                .onPreferenceChange(AgentConsoleScrollRegionPreferenceKey.self) { frame in
                    let localFrame = IslandCanvasCoordinateSpace.appKitLocalRect(
                        fromSwiftUI: frame,
                        canvasHeight: layoutStore.canvasSize.height
                    )
                    layoutStore.setExpandedContentScrollRegion(localFrame)
                }
                .onDisappear {
                    layoutStore.setExpandedContentScrollRegion(.zero)
                }
        } else {
            content
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 7) {
            AgentPromptEditor(
                text: $draft,
                placeholder: "Message Codex…",
                onSubmit: submitDraft
            )
            .id(session.id)
            .frame(minHeight: 30, maxHeight: 48)

            Button(action: { _ = submitDraft() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(submissionValue != nil ? .white : .white.opacity(0.24))
            .disabled(submissionValue == nil)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Send prompt (Command-Return)")
            .accessibilityLabel("Send prompt")
        }
    }

    private var observedFooter: some View {
        HStack(spacing: 5) {
            Image(systemName: "eye")
            Text("Observed session")
            Text("·")
            Text("Interactive control unavailable")
        }
        .font(.system(size: 7.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.34))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Observed session. Interactive control unavailable.")
    }

    private var submissionValue: String? {
        AgentPromptDraftPolicy.submission(from: draft)
    }

    @discardableResult
    private func submitDraft() -> Bool {
        guard let value = submissionValue, onSubmit(value) else { return false }
        draft = ""
        return true
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

private struct AgentConsoleScrollRegionPreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct AgentPromptEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Bool

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
        editor.isEditable = true
        editor.isSelectable = true
        editor.setAccessibilityLabel("Agent prompt")
        editor.setAccessibilityHelp("Command-Return sends. Shift-Return inserts a new line. Escape releases focus.")

        scroll.documentView = editor
        context.coordinator.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? AgentPromptTextView else { return }
        editor.submitHandler = onSubmit
        editor.placeholder = placeholder
        let boundedText = AgentPromptDraftPolicy.bounded(text)
        if editor.string != boundedText {
            editor.string = boundedText
        }
        editor.needsDisplay = true
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? AgentPromptTextView,
              editor.window?.firstResponder === editor else { return }
        editor.window?.makeFirstResponder(nil)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var editor: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            let boundedText = AgentPromptDraftPolicy.bounded(editor.string)
            if boundedText != editor.string {
                editor.string = boundedText
                editor.setSelectedRange(NSRange(location: (boundedText as NSString).length, length: 0))
            }
            text = boundedText
        }
    }
}

private final class AgentPromptTextView: NSTextView {
    var submitHandler: (() -> Bool)?
    var placeholder = ""

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }
        if event.keyCode == 36, AgentPromptDraftPolicy.submitsReturn(with: event.modifierFlags) {
            _ = submitHandler?()
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
