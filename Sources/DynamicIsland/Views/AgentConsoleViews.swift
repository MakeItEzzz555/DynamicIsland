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
    var transcriptEntries: [AgentManagedTranscriptEntry] = []
    var layoutStore: IslandLayoutStore? = nil
    @ObservedObject var approvalControl: AgentApprovalController
    let onSubmit: (String) async -> Bool
    let onInterrupt: () -> Void

    @State private var draft = ""
    @State private var submissionInFlight = false
    @State private var transcriptIsNearBottom = true
    @State private var hasNewActivityOffscreen = false
    @State private var scrollToLatestRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            transcript
            if mode.showsComposer {
                composer
            } else {
                observedFooter
            }
        }
        .padding(8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected session details for \(AgentSessionPresentation.primaryTitle(for: session))")
        .onChange(of: session.id) { _, _ in
            draft = ""
            hasNewActivityOffscreen = false
            transcriptIsNearBottom = true
        }
        .onChange(of: mode.showsComposer) { _, isInteractive in
            if !isInteractive { draft = "" }
        }
    }

    @ViewBuilder
    private var transcript: some View {
        registeredTranscript(
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        transcriptContent
                            .padding(.vertical, 2)

                        Color.clear
                            .frame(height: 1)
                            .id(AgentConsoleScrollAnchor.bottom)
                            .background {
                                GeometryReader { bottomProxy in
                                    Color.clear.preference(
                                        key: AgentConsoleBottomPositionPreferenceKey.self,
                                        value: bottomProxy.frame(
                                            in: .named(AgentConsoleCoordinateSpace.transcript)
                                        ).maxY
                                    )
                                }
                            }
                    }
                    .coordinateSpace(name: AgentConsoleCoordinateSpace.transcript)
                    .scrollBounceBehavior(.basedOnSize)
                    .onPreferenceChange(AgentConsoleBottomPositionPreferenceKey.self) { bottomY in
                        transcriptIsNearBottom = bottomY <= viewport.size.height + 28
                        if transcriptIsNearBottom {
                            hasNewActivityOffscreen = false
                        }
                    }
                    .onChange(of: transcriptFollowToken) { _, _ in
                        guard transcriptIsNearBottom else {
                            hasNewActivityOffscreen = true
                            return
                        }
                        DispatchQueue.main.async {
                            proxy.scrollTo(AgentConsoleScrollAnchor.bottom, anchor: .bottom)
                        }
                    }
                    .onChange(of: scrollToLatestRequest) { _, _ in
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(AgentConsoleScrollAnchor.bottom, anchor: .bottom)
                        }
                        transcriptIsNearBottom = true
                        hasNewActivityOffscreen = false
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo(AgentConsoleScrollAnchor.bottom, anchor: .bottom)
                        }
                    }
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            if !transcriptIsNearBottom && hasNewActivityOffscreen {
                Button {
                    scrollToLatestRequest &+= 1
                } label: {
                    Label("New activity", systemImage: "arrow.down")
                        .font(.system(size: 8, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(.black.opacity(0.82), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
                .foregroundStyle(.white.opacity(0.88))
                .padding(5)
                .help("Jump to latest agent output")
            }
        }
    }

    private var transcriptFollowToken: String {
        let transcriptToken = transcriptEntries.last.map {
            "\($0.id):\($0.text.count)"
        } ?? "none"
        return "\(transcriptToken):\(session.lastUpdatedAt.timeIntervalSince1970)"
    }

    private var transcriptContent: some View {
        let operations = AgentOperationAggregation.make(
            for: session,
            limit: maximumActivityEntries,
            includePendingApprovals: actionableApproval == nil && externalPendingApproval == nil
        )
        let timeline = AgentConsoleEntry.make(
            transcript: transcriptEntries,
            operations: operations,
            provider: session.id.sessionID.provider
        )

        return LazyVStack(alignment: .leading, spacing: 7) {
            if timeline.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: AgentSessionPresentation.stateSymbol(session.state))
                        .frame(width: 11)
                    Text(AgentSessionPresentation.stateLabel(session.state))
                }
                .foregroundStyle(.white.opacity(0.48))
            } else {
                ForEach(timeline) { entry in
                    consoleEntryRow(entry)
                }
            }

            if let approval = actionableApproval {
                AgentConsoleApprovalRow(
                    request: approval,
                    session: session,
                    approvalControl: approvalControl
                )
            } else if let approval = externalPendingApproval {
                AgentConsoleExternalApprovalRow(
                    approval: approval,
                    sourceTarget: AgentSourceAssociationResolver.openTarget(for: session)
                )
            }
        }
        .font(.system(size: 8.5, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionableApproval: AgentApprovalControlRequest? {
        let pending = approvalControl.pendingRequest(for: session.id)
        return AgentApprovalPresentation.isActionable(session: session, pending: pending) ? pending : nil
    }

    private var externalPendingApproval: AgentApproval? {
        guard case .observed = mode else { return nil }
        return session.approvals.values
            .filter { $0.state == .pending }
            .sorted { lhs, rhs in
                if lhs.requestedAt != rhs.requestedAt { return lhs.requestedAt < rhs.requestedAt }
                return lhs.requestID.rawValue < rhs.requestID.rawValue
            }
            .first
    }

    @ViewBuilder
    private func consoleEntryRow(_ entry: AgentConsoleEntry) -> some View {
        if entry.kind == .approval {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: entry.status == .failed ? "exclamationmark.triangle.fill" :
                    entry.status == .resolved ? "checkmark.circle.fill" : "hand.raised.fill")
                    .frame(width: 12)
                    .foregroundStyle(operationColor(entry.status ?? .pending))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.90))
                    if let text = entry.text, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(7)
            .background(
                (entry.status == .resolved ? Color.green :
                    entry.status == .failed ? Color.red : Color.orange).opacity(0.07)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        (entry.status == .resolved ? Color.green :
                            entry.status == .failed ? Color.red : Color.orange).opacity(0.16),
                        lineWidth: 1
                    )
            }
        } else if entry.kind == .user || entry.kind == .agent {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(
                        entry.kind == .user
                            ? Color.white.opacity(0.48)
                            : Color.cyan.opacity(0.72)
                    )
                if let text = entry.text {
                    Text(text)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(entry.kind == .user ? 0.72 : 0.88))
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 2)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol(for: entry.kind))
                    .frame(width: 11)
                    .foregroundStyle(operationColor(entry.status ?? .unknown))
                Text(entry.title)
                    .fontDesign(entry.kind == .command ? .monospaced : .default)
                    .foregroundStyle(.white.opacity(entry.status == .active ? 0.88 : 0.52))
                    .lineLimit(2)
                if let text = entry.text, !text.isEmpty {
                    Text(text)
                        .fontDesign(entry.kind == .command ? .monospaced : .default)
                        .foregroundStyle(.white.opacity(0.34))
                        .lineLimit(2)
                }
            }
        }
    }

    private func symbol(for kind: AgentConsoleEntryKind) -> String {
        switch kind {
        case .user: "person.fill"
        case .agent: "sparkles"
        case .tool: "wrench.and.screwdriver"
        case .command: "terminal"
        case .plan: "list.bullet.clipboard"
        case .approval: "checkmark.shield"
        case .status: "circle.dotted"
        case .error: "exclamationmark.triangle.fill"
        }
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
                placeholder: "Message \(session.id.sessionID.provider.stableName.capitalized)…",
                onSubmit: submitDraft
            )
            .id(session.id)
            .frame(minHeight: 30, maxHeight: 48)

            Button(action: { _ = submitDraft() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(
                submissionValue != nil && !submissionInFlight
                    ? .white
                    : .white.opacity(0.24)
            )
            .disabled(submissionValue == nil || submissionInFlight)
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
        guard !submissionInFlight, let value = submissionValue else { return false }
        submissionInFlight = true
        let submittedDraft = value
        let originalDraft = draft
        Task { @MainActor in
            let accepted = await onSubmit(submittedDraft)
            if accepted, draft == originalDraft {
                draft = ""
            }
            submissionInFlight = false
        }
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

private enum AgentConsoleCoordinateSpace {
    static let transcript = "dynamicIsland.agentConsole.transcript"
}

private enum AgentConsoleScrollAnchor: Hashable {
    case bottom
}

private struct AgentConsoleBottomPositionPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AgentConsoleApprovalRow: View {
    let request: AgentApprovalControlRequest
    let session: AgentSession
    @ObservedObject var approvalControl: AgentApprovalController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Approval required", systemImage: "hand.raised.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.orange.opacity(0.92))
            Text(request.summary)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3)

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    approvalControl.resolve(
                        session: session.id,
                        requestID: request.key.requestID,
                        decision: .deny
                    )
                } label: {
                    Label("Deny", systemImage: "xmark.circle.fill")
                }

                Menu {
                    Button("Approve once") {
                        approvalControl.resolve(
                            session: session.id,
                            requestID: request.key.requestID,
                            decision: .allow
                        )
                    }
                } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                }
                .menuStyle(.borderlessButton)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.orange.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.id.sessionID.provider.stableName.capitalized) approval required")
    }
}

private struct AgentConsoleExternalApprovalRow: View {
    let approval: AgentApproval
    let sourceTarget: AgentSourceOpenTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                "Approval required in \(sourceTarget?.displayName ?? "source app")",
                systemImage: "exclamationmark.shield.fill"
            )
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.orange.opacity(0.92))
            Text(approval.summary)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3)
            HStack(spacing: 6) {
                Text("External session · approve in \(sourceTarget?.displayName ?? "source app")")
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                if let sourceTarget {
                    Button("Open \(sourceTarget.displayName)") {
                        _ = AppLaunchService.openApp(bundleIdentifier: sourceTarget.bundleIdentifier)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(8)
        .background(.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.orange.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Approval required in external source application")
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
