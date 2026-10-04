import AgentBridgeShared
import SwiftUI

/// Presentation of controller-owned exact requests only. Observations cannot
/// acquire control by appearing in attention, nor can selection retarget a click.
struct AgentCompactPermission: Equatable {
    let request: AgentApprovalControlRequest
    let session: AgentSession

    @MainActor
    static func current(sessions: [AgentSession], approvals: AgentApprovalController,
                        managed: AgentManagedSessionController) -> Self? {
        let requests = Array(approvals.pendingRequests.values) + Array(approvals.deliveringRequests.values)
        return requests.sorted {
            if $0.expiresAt != $1.expiresAt { return $0.expiresAt < $1.expiresAt }
            return $0.key.requestID.rawValue < $1.key.requestID.rawValue
        }.compactMap { request -> Self? in
            guard let session = sessions.first(where: { $0.id == request.key.session }),
                  managed.isManaged(session), session.capabilities.contains(.approvalControl),
                  approvals.deliveryState(for: request.key) != nil else { return nil }
            return Self(request: request, session: session)
        }.first
    }

    @MainActor
    @discardableResult
    func decide(_ decision: AgentBridgePermissionDecision, approvals: AgentApprovalController) -> AgentApprovalControlResult {
        approvals.resolve(session: request.key.session, requestID: request.key.requestID, decision: decision)
    }
}

/// transitions.dev smooth-out, restrained 150 ms reversible surface resize.
/// All geometry and depth values live here; no timers or extra shell state.
enum AgentCompactPermissionMotion {
    static let duration = 0.15
    static let hoverWidth: CGFloat = 20
    static let hoverHeight: CGFloat = 8
    static let shadowOpacity = 0.22
    static let shadowRadius: CGFloat = 7
    static let shadowY: CGFloat = 3
    static let contentWidth: CGFloat = 330
    static let buttonWidth: CGFloat = 78
    static let buttonHeight: CGFloat = 28

    static func animation(reduceMotion: Bool) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: reduceMotion ? 0.01 : duration)
    }
}

struct AgentCompactPermissionView: View {
    let permission: AgentCompactPermission
    @ObservedObject var approvals: AgentApprovalController
    let topBandHeight: CGFloat

    var body: some View {
        let state = approvals.deliveryState(for: permission.request.key)
        VStack(spacing: 5) {
            // Keep controls below the physical notch, centered at fixed offsets.
            Color.clear.frame(height: topBandHeight)
            HStack(spacing: 5) {
                Image(systemName: AgentVisualStyle.providerSymbol(permission.session.id.sessionID.provider))
                Text(permission.session.id.sessionID.provider.stableName.capitalized)
                    .fontWeight(.semibold)
                Text("· …" + permission.session.id.sessionID.nativeID.suffix(4)).foregroundStyle(.secondary)
                Text(permission.request.summary.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 10))
            .frame(height: 16)
            .help(permission.request.summary)
            .accessibilityLabel("Permission owner: \(permission.session.id.sessionID.provider.stableName), session \(permission.session.id.sessionID.nativeID), generation \(permission.session.id.generation.rawValue). \(permission.request.summary)")
            HStack(spacing: 8) {
                decisionButton("Deny", decision: .deny, enabled: state == .awaitingDecision)
                decisionButton("Approve", decision: .allow, enabled: state == .awaitingDecision)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if case .submitting = state {
                    Text("Confirming…").font(.system(size: 9)).foregroundStyle(.secondary)
                } else if case .failed = state {
                    Text("Not confirmed").font(.system(size: 9)).foregroundStyle(.red)
                        .help("Delivery failed. Resolve in the provider or inspect the full Feed.")
                }
            }
            .frame(height: AgentCompactPermissionMotion.buttonHeight)
        }
        .frame(maxWidth: AgentCompactPermissionMotion.contentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agents.compactPermission")
    }

    private func decisionButton(_ title: String, decision: AgentBridgePermissionDecision, enabled: Bool) -> some View {
        Button { permission.decide(decision, approvals: approvals) } label: {
            Text(title).font(.system(size: 10, weight: .semibold))
                .frame(width: AgentCompactPermissionMotion.buttonWidth, height: AgentCompactPermissionMotion.buttonHeight)
                .foregroundStyle(decision == .allow ? Color.black : Color.white)
                .background(decision == .allow ? Color.white.opacity(0.95) : Color.white.opacity(0.10), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .agentComposerRegion(title.lowercased())
        .disabled(!enabled)
        .accessibilityLabel("\(title) exact \(permission.session.id.sessionID.provider.stableName.capitalized) permission")
        .accessibilityHint("One decision; final state requires provider acknowledgement")
        .accessibilityIdentifier("agents.compactPermission.\(title.lowercased())")
    }
}
