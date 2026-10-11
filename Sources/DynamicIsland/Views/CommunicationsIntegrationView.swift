import SwiftUI

struct CommunicationsIntegrationView: View {
    @ObservedObject var faceTime: FaceTimeAccessibilityProvider
    @ObservedObject var messaging: MessagingController
    @ObservedObject private var notifications: SystemNotificationMonitor

    init(faceTime: FaceTimeAccessibilityProvider, messaging: MessagingController) {
        self.faceTime = faceTime
        self.messaging = messaging
        self.notifications = faceTime.notifications
    }

    var body: some View {
        SettingsGroup("Communications Integration") {
            Toggle("Observe FaceTime", isOn: Binding(get: { faceTime.enabled }, set: { faceTime.setEnabled($0) }))
            Text(faceTime.state.rawValue).font(.callout).foregroundStyle(.secondary)
            HelpText("Reads only FaceTime’s interface when enabled. No calls are placed or answered. Call detection and controls are not yet verified for this FaceTime version.")
            HStack {
                Button("Request Accessibility") { _ = SystemHUDAccessibilityPermission.request(); faceTime.checkAgain() }
                Button("Open Accessibility Settings") { SystemHUDAccessibilityPermission.openSettings() }
                Button("Check Again") { faceTime.refreshNotificationAccess(); messaging.refreshProviders() }
            }.controlSize(.small)
            Button("Open FaceTime") { FaceTimeAccessibilityProvider.openFaceTime() }.controlSize(.small)
            row("FaceTime notifications", notificationStatus)
            row("FaceTime interface", faceTime.state == .permissionRequired ? "Permission Required"
                : (faceTime.state == .available ? "Available" : "Not Verified"))
            ForEach(["Answer", "Decline", "End", "Mute"], id: \.self) { row($0, "Not Verified") }
            Group {
                let capabilities = messaging.capabilities(for: .messages)
                row("Messages notifications", capabilities.contains(.observeIncoming) ? "Available" : "Permission Required")
                row("Exact conversation matching", capabilities.contains(.exactConversationTarget) ? "Available" : "Not Verified")
                row("Send reply", sendStatus)
                row("Send confirmation", capabilities.contains(.confirmSend) ? "Available" : "Not Verified")
            }
            DisclosureGroup("Diagnostics") {
                Text("Call state and controls have not been verified in an active FaceTime call. Generic buttons and notifications cannot establish a connected call. Notifications require Full Disk Access; Accessibility permission is separate.")
                Text("Interface elements: \(faceTime.snapshot?.nodes.count ?? 0) · observer events: \(faceTime.supportedEvents.count) · scan bounded: \(faceTime.snapshot?.truncated == true ? "yes" : "no")")
                Text("Messages replies use the exact conversation and clear only after the outgoing message is confirmed. Accessibility previews cannot authorize a reply.")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private var sendStatus: String {
        guard let adapter = messaging.adapters[.messages] as? MessagesAppAdapter else { return "Unsupported" }
        if adapter.automationPermission == .denied || adapter.automationPermission == .notDetermined { return "Permission Required" }
        return adapter.automationPermission == .granted && adapter.capabilities.contains(.sendReply) ? "Available" : "Not Verified"
    }

    private var notificationStatus: String {
        switch notifications.state {
        case .running: "Available"
        case .permissionRequired: "Permission Required"
        case .unavailable: "Unsupported"
        default: "Not Verified"
        }
    }

    private func row(_ label: String, _ status: String) -> some View {
        HStack { Text(label); Spacer(); Text(status).foregroundStyle(.secondary) }
            .font(.system(size: 11))
            .accessibilityElement(children: .combine)
    }
}
