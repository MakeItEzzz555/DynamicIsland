import AgentBridgeShared
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

/// Auto-follow policy for the live transcript.
///
/// Following is a user intent: it turns off only when the viewport moves
/// away from the bottom without new content (the user scrolled up), and it
/// turns back on when the user returns near the bottom. Content growth alone
/// never cancels following, so live output keeps the view pinned while the
/// user is at the bottom and never yanks it back while they read history.
struct AgentTranscriptFollowState: Equatable, Sendable {
    static let nearBottomThreshold: CGFloat = 28
    /// Layout passes tolerated while an auto-scroll is still landing.
    static let autoScrollGracePasses = 4

    private(set) var isFollowing = true
    private(set) var hasUnseenContent = false
    private var lastContentToken: String?
    private var pendingAutoScrollPasses = 0

    /// `distanceFromBottom` is content bottom minus viewport height (>= 0
    /// when content extends below the viewport).
    mutating func observeViewport(distanceFromBottom: CGFloat, contentToken: String) {
        let contentChanged = lastContentToken != nil && lastContentToken != contentToken
        lastContentToken = contentToken
        let nearBottom = distanceFromBottom <= Self.nearBottomThreshold
        if nearBottom {
            isFollowing = true
            hasUnseenContent = false
            pendingAutoScrollPasses = 0
        } else if contentChanged {
            return
        } else if pendingAutoScrollPasses > 0 {
            pendingAutoScrollPasses -= 1
        } else {
            isFollowing = false
        }
    }

    /// New content arrived. Returns whether the view should scroll to it.
    mutating func contentDidChange(to contentToken: String) -> Bool {
        lastContentToken = contentToken
        if isFollowing {
            pendingAutoScrollPasses = Self.autoScrollGracePasses
            return true
        }
        hasUnseenContent = true
        return false
    }

    mutating func jumpToLatest() {
        isFollowing = true
        hasUnseenContent = false
        pendingAutoScrollPasses = Self.autoScrollGracePasses
    }

    mutating func reset() {
        self = AgentTranscriptFollowState()
    }
}

enum AgentTranscriptScrollTarget {
    static func latestConversationEntryID(_ entries: [AgentManagedTranscriptEntry]) -> String? {
        entries.last(where: { $0.role == .user || $0.role == .agent })
            .map { "message:\($0.id)" }
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
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        // Plain Return is the primary send action. Command-Return remains a
        // supported accelerator; Shift-Return intentionally inserts a newline.
        guard !flags.contains(.shift) else { return false }
        return flags.subtracting([.command, .capsLock, .numericPad, .function]).isEmpty
    }
}


@MainActor
enum AgentConsoleTimelineProjectionCache {
    private static var cache: [String: [AgentConsoleEntry]] = [:]
    private static var order: [String] = []
    private static let maximumRevisions = 64

    static func entries(
        session: AgentSession,
        transcript: [AgentManagedTranscriptEntry],
        limit: Int,
        includePendingApprovals: Bool
    ) -> [AgentConsoleEntry] {
        let tail = transcript.last.map { "\($0.id):\($0.text.count)" } ?? "none"
        let key = [
            String(describing: session.id),
            String(session.lastUpdatedAt.timeIntervalSince1970),
            tail,
            String(transcript.count),
            String(limit),
            includePendingApprovals ? "pending" : "no-pending"
        ].joined(separator: "|")
        if let cached = cache[key] { return cached }

        let operations = AgentOperationAggregation.make(
            for: session,
            limit: limit,
            includePendingApprovals: includePendingApprovals
        )
        let value = AgentConsoleEntry.make(
            transcript: transcript,
            operations: operations,
            provider: session.id.sessionID.provider
        )
        cache[key] = value
        order.append(key)
        if order.count > maximumRevisions {
            for stale in order.prefix(order.count - maximumRevisions) {
                cache.removeValue(forKey: stale)
            }
            order.removeFirst(order.count - maximumRevisions)
        }
        return value
    }
}

struct AgentEmbeddedConsoleView: View {
    @Environment(\.agentVisualPreferences) private var visualPreferences
    @Environment(\.islandDisplayMetrics) private var displayMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: AgentSession
    var mode: AgentConsoleMode = .observed
    var interactionState: AgentManagedInteractionState = .observed
    var maximumActivityEntries = 3
    var showsOperationalTraffic = true
    var showsActivityOrb = true
    var transcriptEntries: [AgentManagedTranscriptEntry] = []
    var workspaceSessions: [AgentSession] = []
    var layoutStore: IslandLayoutStore? = nil
    @ObservedObject var approvalControl: AgentApprovalController
    let onSelectSession: (AgentSessionInstanceID) -> Void
    let onSubmit: (String) async -> Bool
    let onInterrupt: () -> Void
    /// Drafts belong to one exact session instance: switching session,
    /// provider or project stores the draft and restores that session's own.
    var loadDraft: ((AgentSessionInstanceID) -> String)? = nil
    var saveDraft: ((String, AgentSessionInstanceID) -> Void)? = nil

    @State private var follow = AgentTranscriptFollowState()
    @State private var scrollToLatestRequest = 0
    /// At most one bottom-settle in flight: a burst of streamed output
    /// produces one scroll, not one per delta.
    @State private var settlePending = false
    @State private var settleRequestedAgain = false

    var body: some View {
        let _ = AgentPerformanceProbe.count("agents.console.body")
        VStack(alignment: .leading, spacing: 7) {
            transcript
            if mode.showsComposer {
                managedInteractionFooter
                // Its own view owning the draft: typing re-renders only the
                // composer, never the transcript above it.
                AgentConsoleComposer(
                    session: session,
                    interactionState: interactionState,
                    layoutStore: layoutStore,
                    onSubmit: onSubmit,
                    onInterrupt: onInterrupt,
                    loadDraft: loadDraft,
                    saveDraft: saveDraft
                )
            } else {
                observedFooter
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .coordinateSpace(name: AgentComposerActionFrameKey.coordinateSpace)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected session details for \(AgentSessionPresentation.primaryTitle(for: session))")
        .onChange(of: session.id) { _, _ in
            follow.reset()
            scrollToLatestRequest &+= 1
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
                                    // Whole points: sub-pixel jitter from lazy row
                                    // height estimates must not feed back into state.
                                    Color.clear.preference(
                                        key: AgentConsoleBottomPositionPreferenceKey.self,
                                        value: bottomProxy.frame(
                                            in: .named(AgentConsoleCoordinateSpace.transcript)
                                        ).maxY.rounded()
                                    )
                                }
                            }
                    }
                    .coordinateSpace(name: AgentConsoleCoordinateSpace.transcript)
                    .defaultScrollAnchor(.bottom)
                    .scrollBounceBehavior(.basedOnSize)
                    .onPreferenceChange(AgentConsoleBottomPositionPreferenceKey.self) { bottomY in
                        // Write state only on a real change: an unconditional write
                        // re-renders the transcript, which re-measures the lazy
                        // stack and can report another bottom position — a layout
                        // feedback loop that could livelock while output streams.
                        var next = follow
                        next.observeViewport(
                            distanceFromBottom: bottomY - viewport.size.height.rounded(),
                            contentToken: transcriptFollowToken
                        )
                        if next != follow { follow = next }
                    }
                    .onChange(of: transcriptFollowToken) { _, token in
                        guard follow.contentDidChange(to: token) else { return }
                        settleAtLatest(proxy, target: latestScrollTarget, animated: false)
                    }
                    .onChange(of: scrollToLatestRequest) { _, _ in
                        follow.jumpToLatest()
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(latestScrollTarget, anchor: .bottom)
                        }
                    }
                    .onAppear {
                        follow.jumpToLatest()
                        settleAtLatest(proxy, target: latestScrollTarget, animated: false)
                    }
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            if !follow.isFollowing && follow.hasUnseenContent {
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

    private func settleAtLatest(_ proxy: ScrollViewProxy, target: AnyHashable, animated: Bool) {
        guard !settlePending else {
            settleRequestedAgain = true
            return
        }
        settlePending = true
        AgentPerformanceProbe.count("agents.console.autoscroll")
        Task { @MainActor in
            defer {
                settlePending = false
                if settleRequestedAgain, follow.isFollowing {
                    // Coalesce a burst of streamed deltas into at most one
                    // additional settle against the newest stable row.
                    settleRequestedAgain = false
                    settleAtLatest(proxy, target: latestScrollTarget, animated: false)
                } else {
                    settleRequestedAgain = false
                }
            }
            // One layout yield is enough for the growing LazyVStack row. A
            // second unconditional bottom scroll could run against newer
            // geometry and overshoot below the response the user is reading.
            await Task.yield()
            guard follow.isFollowing else { return }
            if animated {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    private var latestScrollTarget: AnyHashable {
        if let entryID = AgentTranscriptScrollTarget.latestConversationEntryID(transcriptEntries) {
            return AnyHashable(entryID)
        }
        return AnyHashable(AgentConsoleScrollAnchor.bottom)
    }

    private var transcriptFollowToken: String {
        let transcriptToken = transcriptEntries.last.map {
            "\($0.id):\($0.text.count)"
        } ?? "none"

        // The dedicated Feed owns operational/provider state. In conversation-
        // only mode, scrolling follows only transcript growth; state/approval
        // publications must not move the user's chat viewport.
        guard showsOperationalTraffic else { return transcriptToken }

        let managedApprovalToken: String = {
            guard let request = actionableApproval else { return "managed:none" }
            let delivery = approvalControl.deliveryState(for: request.key)
                .map { String(describing: $0) } ?? "none"
            return "managed:\(request.key.requestID.rawValue):\(delivery)"
        }()
        let externalApprovalToken = externalPendingApproval.map {
            "external:\($0.requestID.rawValue):\($0.state)"
        } ?? "external:none"
        return [
            transcriptToken,
            String(session.lastUpdatedAt.timeIntervalSince1970),
            managedApprovalToken,
            externalApprovalToken
        ].joined(separator: "|")
    }

    private var transcriptContent: some View {
        let timeline = AgentPerformanceProbe.measure("agents.timeline.projection") {
            AgentConsoleTimelineProjectionCache.entries(
                session: session,
                transcript: transcriptEntries,
                limit: maximumActivityEntries,
                includePendingApprovals: showsOperationalTraffic && actionableApproval == nil && externalPendingApproval == nil
            )
        }
        let displayedEntries = showsOperationalTraffic ? timeline : conversationEntries
        let latestAgentEntryID = displayedEntries.last(where: { $0.kind == .agent })?.id
        let _ = AgentPerformanceProbe.gauge("agents.timeline.rows", displayedEntries.count)

        return LazyVStack(alignment: .leading, spacing: 7) {
            if showsOperationalTraffic { AgentCurrentWorkSummary(session: session, mode: mode) }

            if showsOperationalTraffic && workspaceSessions.count > 1 {
                AgentWorkspaceActivityGroups(
                    sessions: workspaceSessions,
                    selectedSessionID: session.id,
                    onSelect: onSelectSession
                )
            }

            if timeline.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: AgentSessionPresentation.stateSymbol(session.state))
                        .frame(width: 11)
                    Text(AgentSessionPresentation.stateLabel(session.state))
                }
                .foregroundStyle(.white.opacity(0.48))
            } else {
                // Lazy: only on-screen rows are realized and measured, so the
                // controller's full bounded history costs nothing extra to
                // keep. (A smaller eager or windowed stack measured slower and
                // was less stable against the bottom anchor.)
                ForEach(displayedEntries) { entry in
                    let isLatestAgentResponse = entry.kind == .agent && entry.id == latestAgentEntryID
                    AgentConsoleEntryRow(
                        entry: entry,
                        sessionID: session.id,
                        sessionState: isLatestAgentResponse ? session.state : .idle,
                        processingKind: isLatestAgentResponse ? session.currentProcessingKind : nil,
                        isLatestAgentResponse: isLatestAgentResponse
                    )
                    .equatable()
                    .id(entry.id)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.995, anchor: .topLeading)
                        )
                    )
                }
            }

            // A pending permission is the newest authoritative event, so it
            // lives at the chronological bottom of the console. Resolved
            // approvals remain in `timeline` through normalized provider data.
            if showsOperationalTraffic, let approval = actionableApproval {
                AgentConsoleApprovalRow(
                    request: approval,
                    session: session,
                    approvalControl: approvalControl
                )
            } else if showsOperationalTraffic, let approval = externalPendingApproval {
                AgentConsoleExternalApprovalRow(
                    approval: approval,
                    sourceTarget: AgentSourceAssociationResolver.openTarget(for: session)
                )
            }

        }
        .font(.system(size: displayMetrics.transcriptFontSize, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: displayedEntries.map(\.id)
        )
    }

    private var conversationEntries: [AgentConsoleEntry] {
        AgentConsoleEntry.make(
            transcript: transcriptEntries.filter { $0.role == .user || $0.role == .agent },
            operations: [], provider: session.id.sessionID.provider
        )
    }

    private var actionableApproval: AgentApprovalControlRequest? {
        let pending = approvalControl.presentedRequest(for: session.id)
        return AgentApprovalPresentation.isPresented(
            session: session,
            pending: pending,
            delivery: pending.flatMap { approvalControl.deliveryState(for: $0.key) }
        ) ? pending : nil
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
    private func registeredTranscript<Content: View>(_ content: Content) -> some View {
        if let layoutStore {
            // The transcript viewport is intentionally the only Agents region handed to the
            // panel-level scroll router. Toolbar, usage, session rail, approvals outside the
            // transcript, and the composer must continue to use the island's global gestures.
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

    private var managedInteractionFooter: some View {
        HStack(spacing: 6) {
            if showsActivityOrb && (interactionState == .connecting || interactionState == .checkingAttachment || interactionState == .submitting || interactionState == .stopping || AgentVisualMotion.animates(session.state)) {
                AgentOrbView(state: AgentOrbStateMapper.state(for: interactionState, session: session), size: 20, speed: visualPreferences.orbSpeed)
            } else {
                Image(systemName: interactionSymbol)
                    .font(.system(size: 7.5, weight: .semibold))
            }
            Text(interactionLabel)
                .font(.system(size: 7.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if interactionState.canInterrupt {
                Text("Stop available")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .foregroundStyle(interactionColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(interactionLabel)
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

    private var interactionLabel: String {
        switch interactionState {
        case .observed: "Observed · read only"
        case .connecting: "Connecting to exact thread…"
        case .checkingAttachment: "Checking official thread…"
        case .ready: "Connected · ready for prompt"
        case .submitting: "Sending prompt…"
        case .working: AgentSessionPresentation.displayedStateLabel(for: session, at: Date())
        case .stopping: "Stopping current turn…"
        case .failed(let message): message
        }
    }

    private var interactionSymbol: String {
        switch interactionState {
        case .observed: "eye"
        case .connecting, .checkingAttachment: "link.badge.plus"
        case .ready: "checkmark.circle.fill"
        case .submitting: "paperplane.fill"
        case .working: "sparkles"
        case .stopping: "stop.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var interactionColor: Color {
        switch interactionState {
        case .ready: .green.opacity(0.62)
        case .submitting, .working: .cyan.opacity(0.70)
        case .stopping: .orange.opacity(0.80)
        case .failed: .red.opacity(0.76)
        case .observed, .connecting, .checkingAttachment: .white.opacity(0.34)
        }
    }


}

/// Prompt editor and Send/Stop. Owns the draft so keystrokes invalidate only
/// this view. Drafts belong to one exact session instance: switching
/// session, provider or project stores the draft and restores that
/// session's own; leaving interactive mode stores it.
private struct AgentConsoleComposer: View {
    let session: AgentSession
    let interactionState: AgentManagedInteractionState
    let layoutStore: IslandLayoutStore?
    let onSubmit: (String) async -> Bool
    let onInterrupt: () -> Void
    var loadDraft: ((AgentSessionInstanceID) -> String)?
    var saveDraft: ((String, AgentSessionInstanceID) -> Void)?

    @State private var draft = ""
    @State private var submissionInFlight = false
    @Environment(\.agentVisualPreferences) private var visualPreferences

    var body: some View {
        composer
            .onChange(of: session.id) { previous, current in
                saveDraft?(draft, previous)
                draft = loadDraft?(current) ?? ""
            }
            .onAppear {
                if draft.isEmpty, let stored = loadDraft?(session.id) { draft = stored }
            }
            .onDisappear {
                saveDraft?(draft, session.id)
            }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 4) {
            AgentPromptEditor(
                text: $draft,
                placeholder: composerPlaceholder,
                isEnabled: interactionState.allowsPromptSubmission && !submissionInFlight,
                onSubmit: submitDraft,
                onFocusChange: { focused in layoutStore?.setTextInputFocused(focused) }
            )
            .id(session.id)
            .frame(minWidth: 40, maxWidth: .infinity, minHeight: 30, maxHeight: 48)

            if interactionState.canInterrupt {
                Button(action: onInterrupt) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange.opacity(0.92))
                .fixedSize()
                .layoutPriority(3)
                .reportsComposerActionFrame()
                .help("Stop current agent turn")
                .accessibilityLabel("Stop current agent turn")
            } else {
                MetalSendButton(
                    configuration: visualPreferences.metal,
                    isEnabled: submissionValue != nil &&
                        interactionState.allowsPromptSubmission &&
                        !submissionInFlight,
                    action: { _ = submitDraft() }
                )
                .keyboardShortcut(.return, modifiers: [.command])
                .layoutPriority(3)
                .reportsComposerActionFrame()
                .help("Send prompt (Return or Command-Return; Shift-Return for newline)")
            }
        }
        .padding(.trailing, 5)
        .padding(.bottom, 3)
        .background(
            Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var composerPlaceholder: String {
        switch interactionState {
        case .ready:
            "Message \(session.id.sessionID.provider.stableName.capitalized)…"
        case .submitting:
            "Sending…"
        case .working:
            "\(session.id.sessionID.provider.stableName.capitalized) is working…"
        case .stopping:
            "Stopping…"
        case .failed:
            "Retry when ready…"
        case .connecting, .checkingAttachment:
            "Connecting…"
        case .observed:
            "Managed control unavailable"
        }
    }

    private var submissionValue: String? {
        AgentPromptDraftPolicy.submission(from: draft)
    }

    @discardableResult
    private func submitDraft() -> Bool {
        guard !submissionInFlight,
              interactionState.allowsPromptSubmission,
              let value = submissionValue else { return false }
        submissionInFlight = true
        let submittedDraft = value
        let originalDraft = draft
        let submittedSession = session.id
        Task { @MainActor in
            let accepted = await onSubmit(submittedDraft)
            if accepted {
                // Clear only the draft of the session that was submitted.
                if session.id == submittedSession, draft == originalDraft {
                    draft = ""
                }
                saveDraft?("", submittedSession)
            }
            submissionInFlight = false
        }
        return true
    }
}

/// One transcript row. Equatable so SwiftUI re-lays-out only rows whose
/// content changed: while output streams, just the growing row is measured
/// again instead of every visible row (and its text-selection overlay).
private struct AgentConsoleEntryRow: View, Equatable {
    let entry: AgentConsoleEntry
    let sessionID: AgentSessionInstanceID
    let sessionState: AgentState
    let processingKind: AgentProcessingKind?
    let isLatestAgentResponse: Bool

    var body: some View {
        if entry.kind == .approval {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: entry.status == .failed ? "exclamationmark.triangle.fill" :
                    entry.status == .resolved ? "checkmark.circle.fill" : "hand.raised.fill")
                    .frame(width: 12)
                    .foregroundStyle(operationColor(entry.status ?? .pending))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.90))
                    if let text = entry.text, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
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
        } else if entry.kind == .user {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
                if let text = entry.text {
                    Text(text)
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 2)
        } else if entry.kind == .agent {
            HStack(alignment: .top, spacing: 7) {
                AgentInlineResponseAvatar(
                    sessionID: sessionID,
                    state: sessionState,
                    processingKind: processingKind,
                    isLatest: isLatestAgentResponse
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.cyan.opacity(0.72))
                    if let text = entry.text {
                        Text(text)
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.88))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func operationColor(_ status: AgentOperationStatus) -> Color {
        AgentConsoleStatusColor.color(status)
    }
}

struct AgentInlineResponseAvatarTuning: Equatable, Sendable {
    let speedMultiplier: Double
    let turnMultiplier: Double
    let minimumWhirl: Double
    let motionMultiplier: Double
    let animates: Bool
}

enum AgentInlineResponseAvatarPresentation {
    static func tuning(
        state: AgentState,
        processingKind: AgentProcessingKind?,
        isLatest: Bool
    ) -> AgentInlineResponseAvatarTuning {
        guard isLatest, AgentVisualMotion.animates(state) else {
            return .init(
                speedMultiplier: 1,
                turnMultiplier: 1,
                minimumWhirl: 0,
                motionMultiplier: 1,
                animates: false
            )
        }

        switch processingKind {
        case .reasoning:
            return .init(speedMultiplier: 0.72, turnMultiplier: 0.50, minimumWhirl: 0, motionMultiplier: 0.62, animates: true)
        case .planning:
            return .init(speedMultiplier: 0.78, turnMultiplier: 0.62, minimumWhirl: 0, motionMultiplier: 0.68, animates: true)
        case .searching:
            return .init(speedMultiplier: 0.96, turnMultiplier: 1.45, minimumWhirl: 0.10, motionMultiplier: 0.82, animates: true)
        case .executing:
            return .init(speedMultiplier: 1.22, turnMultiplier: 1.00, minimumWhirl: 0.46, motionMultiplier: 1.00, animates: true)
        case .connecting:
            return .init(speedMultiplier: 0.90, turnMultiplier: 0.78, minimumWhirl: 0.72, motionMultiplier: 0.72, animates: true)
        case .listening:
            return .init(speedMultiplier: 0.62, turnMultiplier: 0.48, minimumWhirl: 0, motionMultiplier: 0.46, animates: true)
        case .composing:
            return .init(speedMultiplier: 0.84, turnMultiplier: 0.56, minimumWhirl: 0, motionMultiplier: 0.62, animates: true)
        case .synthesizing:
            return .init(speedMultiplier: 0.94, turnMultiplier: 0.90, minimumWhirl: 0.24, motionMultiplier: 0.76, animates: true)
        case .background:
            return .init(speedMultiplier: 0.55, turnMultiplier: 0.36, minimumWhirl: 0, motionMultiplier: 0.40, animates: true)
        case nil:
            switch state {
            case .runningCommand, .runningTool:
                return .init(speedMultiplier: 1.18, turnMultiplier: 0.95, minimumWhirl: 0.36, motionMultiplier: 0.95, animates: true)
            case .thinking, .planning:
                return .init(speedMultiplier: 0.76, turnMultiplier: 0.55, minimumWhirl: 0, motionMultiplier: 0.65, animates: true)
            case .working:
                return .init(speedMultiplier: 1.00, turnMultiplier: 0.82, minimumWhirl: 0.12, motionMultiplier: 0.82, animates: true)
            default:
                return .init(speedMultiplier: 1, turnMultiplier: 1, minimumWhirl: 0, motionMultiplier: 1, animates: false)
            }
        }
    }

    static func displayedState(state: AgentState, isLatest: Bool) -> AgentState {
        guard isLatest else { return .idle }
        switch state {
        case .waitingForApproval, .waitingForUser, .planReady,
             .completed, .failed, .interrupted, .idle:
            return .idle
        default:
            return state
        }
    }
}

private struct AgentInlineResponseAvatar: View {
    let sessionID: AgentSessionInstanceID
    let state: AgentState
    let processingKind: AgentProcessingKind?
    let isLatest: Bool

    @Environment(\.agentVisualPreferences) private var visualPreferences

    var body: some View {
        let tuning = AgentInlineResponseAvatarPresentation.tuning(
            state: state,
            processingKind: processingKind,
            isLatest: isLatest
        )
        BotAvatarView(
            sessionID: sessionID,
            configuration: configuration(tuning),
            state: AgentInlineResponseAvatarPresentation.displayedState(
                state: state,
                isLatest: isLatest
            ),
            compact: true,
            paused: !tuning.animates,
            frozenTime: tuning.animates ? nil : 0.6,
            interactionEnabled: false
        )
        .frame(width: 28, height: 30, alignment: .top)
        .accessibilityLabel(
            isLatest
                ? "\(sessionID.sessionID.provider.stableName.capitalized) response, \(processingKind?.rawValue ?? state.rawValue)"
                : "\(sessionID.sessionID.provider.stableName.capitalized) response"
        )
    }

    private func configuration(_ tuning: AgentInlineResponseAvatarTuning) -> BotAvatarConfiguration {
        var value = visualPreferences.avatar
        value.size = min(30, max(24, value.size))
        value.interactive = false
        value.speed = min(2, max(0.25, value.speed * tuning.speedMultiplier))
        value.turn = min(2, max(0, value.turn * tuning.turnMultiplier))
        value.whirl = min(2, max(value.whirl, tuning.minimumWhirl))
        value.motionStrength = min(2, max(0, value.motionStrength * tuning.motionMultiplier))
        return value
    }
}

enum AgentConsoleStatusColor {
    static func color(_ status: AgentOperationStatus) -> Color {
        switch status {
        case .active: .white.opacity(0.86)
        case .pending: .orange.opacity(0.88)
        case .failed: .red.opacity(0.88)
        case .completed, .resolved: .green.opacity(0.58)
        case .cancelled, .unknown: .white.opacity(0.34)
        }
    }
}

private struct AgentCurrentWorkSummary: View {
    let session: AgentSession
    let mode: AgentConsoleMode

    private var projectedProject: AgentProjectDisplayContext {
        AgentPrivacyProjection.displayProject(session.project)
    }

    private var projectName: String {
        projectedProject.displayName ?? session.id.sessionID.provider.stableName.capitalized
    }

    private var title: String {
        AgentSessionPresentation.displayedPrimaryTitle(for: session, at: Date())
    }

    private var isAttention: Bool {
        AgentSessionPresentation.requiresAttention(session)
    }

    private var accent: Color {
        AgentVisualStyle.accent(for: session.state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(projectName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                if let branch = projectedProject.gitBranch, !branch.isEmpty {
                    Text(branch)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.32))
                        .lineLimit(1)
                }
                if let source = projectedProject.sourceApplicationName, !source.isEmpty {
                    Text("· \(source)")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.32))
                        .lineLimit(1)
                }
                if let model = projectedProject.model, !model.isEmpty {
                    Text("· \(model)")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.32))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: mode.showsComposer ? "link" : "eye")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.30))
                    .help(mode.showsComposer ? "Managed session" : "Observed session")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: accent.opacity(isAttention ? 0.65 : 0.25), radius: 4)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Label(
                    AgentSessionPresentation.displayedStateLabel(for: session, at: Date()),
                    systemImage: AgentSessionPresentation.displayedStateSymbol(for: session, at: Date())
                )
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent.opacity(0.92))
                .lineLimit(1)
            }
        }
        .padding(.horizontal, isAttention ? 10 : 2)
        .padding(.vertical, isAttention ? 9 : 5)
        .background {
            if isAttention {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.88))
                            .frame(width: 2.5)
                            .padding(.vertical, 5)
                    }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(projectName), \(title), \(AgentSessionPresentation.displayedStateLabel(for: session, at: Date()))")
    }
}

private struct AgentWorkspaceActivityGroups: View {
    let sessions: [AgentSession]
    let selectedSessionID: AgentSessionInstanceID
    let onSelect: (AgentSessionInstanceID) -> Void
    @Environment(\.agentProjectLocations) private var projectLocations

    private var groups: [AgentProjectGroupPresentation] {
        AgentDashboardPresentation.make(
            orderedSessions: AgentWorkspaceSelection.ordered(sessions: sessions),
            locations: projectLocations
        ).groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groups) { group in
                let visible = group.sessions.filter { $0.id != selectedSessionID }
                if !visible.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(group.title)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.46))
                                .lineLimit(1)
                            Text("\(group.sessions.count)")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.25))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 2)

                        ForEach(visible, id: \.id) { candidate in
                            AgentWorkspaceActivityRow(session: candidate) {
                                onSelect(candidate.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Other agent work")
    }
}

private struct AgentWorkspaceActivityRow: View {
    let session: AgentSession
    let select: () -> Void
    @State private var hovering = false

    private var accent: Color {
        AgentVisualStyle.accent(for: session.state)
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Circle()
                    .stroke(accent.opacity(0.85), lineWidth: 1.5)
                    .frame(width: 9, height: 9)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AgentSessionPresentation.displayedPrimaryTitle(for: session, at: Date()))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if let branch = session.project.gitBranch, !branch.isEmpty {
                            Label(branch, systemImage: "arrow.triangle.branch")
                        } else {
                            Text(session.id.sessionID.provider.stableName.capitalized)
                        }
                        Text("…\(session.id.sessionID.nativeID.suffix(4))")
                    }
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(AgentSessionPresentation.displayedStateLabel(for: session, at: Date()))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.88))
                    Text(session.lastUpdatedAt, style: .relative)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
            .background(
                hovering ? Color.white.opacity(0.055) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.13), value: hovering)
        .accessibilityLabel(
            "\(AgentSessionPresentation.displayedPrimaryTitle(for: session, at: Date())), " +
            AgentSessionPresentation.displayedStateLabel(for: session, at: Date())
        )
        .accessibilityHint("Select this agent session")
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
    private let accent = Color.orange

    private var deliveryState: AgentApprovalDeliveryState {
        approvalControl.deliveryState(for: request.key) ?? .awaitingDecision
    }

    /// Buttons are live only while the provider still awaits a decision.
    private var isSubmitting: Bool {
        deliveryState != .awaitingDecision
    }

    private var failure: (decision: AgentBridgePermissionDecision, reason: String)? {
        if case .failed(let decision, let reason) = deliveryState { return (decision, reason) }
        return nil
    }

    /// Always the exact request this row was built for, never whichever
    /// session is currently displayed.
    private func decide(_ decision: AgentBridgePermissionDecision) {
        _ = approvalControl.resolve(
            session: request.key.session,
            requestID: request.key.requestID,
            decision: decision
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 11, height: 11)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 6.5, weight: .black))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isSubmitting ? deliveryLabel : "Permission required")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(session.id.sessionID.provider.stableName.capitalized)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(AgentVisualStyle.providerAccent(session.id.sessionID.provider).opacity(0.82))
                }

                Spacer(minLength: 8)

                if let project = AgentPrivacyProjection.displayProject(session.project).displayName {
                    Text(project)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.34))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text(request.summary)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3)
                .textSelection(.enabled)

            if let failure {
                HStack(spacing: 8) {
                    Label(failure.reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Dismiss") { approvalControl.dismissFailedDelivery(request.key) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(.white.opacity(0.07), in: Capsule())
                        .accessibilityHint("The \(failure.decision == .allow ? "approval" : "denial") was not confirmed by the provider")
                }
            } else {
            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button {
                    decide(.deny)
                } label: {
                    Text("Deny")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .disabled(isSubmitting)
                .accessibilityHint("Deny this exact permission request")

                Button {
                    decide(.allow)
                } label: {
                    HStack(spacing: 5) {
                        Text("Approve")
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black.opacity(0.88))
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(.white.opacity(0.95), in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting)
                .accessibilityHint("Approve this exact permission request once")
            }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.36, green: 0.13, blue: 0.16).opacity(0.72),
                    Color(red: 0.25, green: 0.10, blue: 0.13).opacity(0.48)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(red: 1.0, green: 0.34, blue: 0.42))
                .frame(width: 3)
                .padding(.vertical, 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.id.sessionID.provider.stableName.capitalized) permission required")
    }

    private var deliveryLabel: String {
        switch deliveryState {
        case .awaitingDecision: "Permission required"
        case .submitting(let decision): decision == .allow ? "Approving…" : "Denying…"
        case .failed(let decision, _): decision == .allow ? "Approval not confirmed" : "Denial not confirmed"
        }
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
    let isEnabled: Bool
    let onSubmit: () -> Bool
    var onFocusChange: (Bool) -> Void = { _ in }

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
        editor.focusHandler = onFocusChange
        editor.placeholder = placeholder
        editor.isEditable = isEnabled
        editor.isSelectable = true
        editor.setAccessibilityLabel("Agent prompt")
        editor.setAccessibilityHelp("Return sends. Shift-Return inserts a new line. Command-Return also sends. Escape releases focus.")

        scroll.documentView = editor
        context.coordinator.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? AgentPromptTextView else { return }
        editor.submitHandler = isEnabled ? onSubmit : nil
        editor.focusHandler = onFocusChange
        editor.placeholder = placeholder
        editor.isEditable = isEnabled
        if !isEnabled, editor.window?.firstResponder === editor {
            editor.window?.makeFirstResponder(nil)
        }
        let boundedText = AgentPromptDraftPolicy.bounded(text)
        if editor.string != boundedText {
            editor.string = boundedText
        }
        editor.needsDisplay = true
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? AgentPromptTextView else { return }
        let handler = editor.focusHandler
        editor.focusHandler = nil
        if let handler {
            DispatchQueue.main.async { handler(false) }
        }
        guard editor.window?.firstResponder === editor else { return }
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
    var focusHandler: ((Bool) -> Void)?
    var placeholder = ""

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { publishFocus(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { publishFocus(false) }
        return resigned
    }

    /// NSViewRepresentable can be dismantled while SwiftUI/AppKit is already
    /// mutating the host hierarchy. Publishing layout-observed focus state
    /// synchronously from responder callbacks can re-enter that display-cycle
    /// constraint update. Defer one main-run-loop turn instead.
    private func publishFocus(_ focused: Bool) {
        guard let handler = focusHandler else { return }
        DispatchQueue.main.async { handler(focused) }
    }

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

    /// The app is an accessory with no visible menu bar, so standard editing
    /// shortcuts are handled here when the composer owns focus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              let action = AgentPromptEditingShortcut.action(
                  characters: event.charactersIgnoringModifiers,
                  modifiers: event.modifierFlags
              ) else {
            return super.performKeyEquivalent(with: event)
        }
        return NSApp.sendAction(action, to: self, from: self)
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

/// Frame of the composer's Send/Stop control in the console's coordinate
/// space. Used by layout regression tests to prove the control stays inside
/// the console (and therefore inside the island's hover region).
struct AgentComposerActionFrameKey: PreferenceKey {
    static let coordinateSpace = "AgentConsoleRoot"
    static let defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull { value = next }
    }
}

private extension View {
    func reportsComposerActionFrame() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: AgentComposerActionFrameKey.self,
                    value: proxy.frame(in: .named(AgentComposerActionFrameKey.coordinateSpace))
                )
            }
        }
    }
}

/// Standard text-editing shortcuts for the Agents composer.
enum AgentPromptEditingShortcut {
    static func action(characters: String?, modifiers: NSEvent.ModifierFlags) -> Selector? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else {
            return nil
        }
        switch (characters?.lowercased(), flags.contains(.shift)) {
        case ("a", false): return #selector(NSResponder.selectAll(_:))
        case ("c", false): return #selector(NSText.copy(_:))
        case ("v", false): return #selector(NSText.paste(_:))
        case ("x", false): return #selector(NSText.cut(_:))
        case ("z", false): return Selector(("undo:"))
        case ("z", true): return Selector(("redo:"))
        default: return nil
        }
    }
}
