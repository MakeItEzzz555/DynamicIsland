import SwiftUI

/// A navigation projection of the existing approval controller. It owns no
/// request, decision, acknowledgement, or expiration state.
enum AgentWorkspaceApprovalAttentionProjection {
    static func requests(
        pending: [AgentApprovalControlRequest],
        delivering: [AgentApprovalControlRequest],
        selectedSessionID: AgentSessionInstanceID?,
        now: Date
    ) -> [AgentApprovalControlRequest] {
        var exact: [AgentApprovalControlKey: AgentApprovalControlRequest] = [:]
        for request in pending where request.expiresAt > now {
            exact[request.key] = request
        }
        // An unconfirmed delivery remains discoverable, including failures.
        for request in delivering { exact[request.key] = request }
        return exact.values.filter { $0.key.session != selectedSessionID }.sorted {
            if $0.expiresAt != $1.expiresAt { return $0.expiresAt < $1.expiresAt }
            if $0.key.session.sessionID.provider.deterministicSortKey != $1.key.session.sessionID.provider.deterministicSortKey {
                return $0.key.session.sessionID.provider.deterministicSortKey < $1.key.session.sessionID.provider.deterministicSortKey
            }
            if $0.key.session.sessionID.nativeID != $1.key.session.sessionID.nativeID {
                return $0.key.session.sessionID.nativeID < $1.key.session.sessionID.nativeID
            }
            if $0.key.session.generation != $1.key.session.generation {
                return $0.key.session.generation > $1.key.session.generation
            }
            return $0.key.requestID.rawValue < $1.key.requestID.rawValue
        }
    }
}

/// Background approvals never enter the selected session's normal Feed. This
/// global affordance navigates to their exact owner before any decision occurs.
struct AgentWorkspaceApprovalAttentionControl: View {
    @ObservedObject var approvals: AgentApprovalController
    let selectedSessionID: AgentSessionInstanceID?
    let onSelect: (AgentSessionInstanceID) -> Void

    var body: some View {
        let requests = AgentWorkspaceApprovalAttentionProjection.requests(
            pending: Array(approvals.pendingRequests.values),
            delivering: Array(approvals.deliveringRequests.values),
            selectedSessionID: selectedSessionID, now: Date()
        )
        if !requests.isEmpty {
            Menu {
                ForEach(requests) { request in
                    Button {
                        onSelect(request.key.session)
                    } label: {
                        let provider = request.key.session.sessionID.provider.stableName.capitalized
                        let identity = request.key.session.sessionID.nativeID.suffix(6)
                        let state = deliveryLabel(for: request)
                        Label("\(provider) …\(identity) · \(state)", systemImage: "exclamationmark.bubble")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.bubble.fill")
                    Text("\(requests.count)").monospacedDigit()
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .frame(height: 25)
                .background(Color.orange.opacity(0.10), in: Capsule())
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Open the exact agent with a pending or unconfirmed approval")
            .accessibilityLabel("\(requests.count) approval requests on other agents. Select an exact owner to open its Feed.")
        }
    }

    private func deliveryLabel(for request: AgentApprovalControlRequest) -> String {
        switch approvals.deliveryState(for: request.key) {
        case .submitting: "Awaiting acknowledgement"
        case .failed: "Decision not confirmed"
        case .awaitingDecision, nil: "Approval required"
        }
    }
}
