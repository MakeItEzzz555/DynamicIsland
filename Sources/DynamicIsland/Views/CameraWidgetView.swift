import AppKit
import SwiftUI

/// What the Camera widget shows. Pure, so every capture/permission state is
/// testable without a camera. Only `.live` ever renders frames.
enum CameraWidgetContent: Equatable {
    case live
    case starting
    /// Explicit Allow required (never prompts on appear).
    case needsPermission
    case denied
    /// Authorized and idle: explicit Start required (appear is not intent).
    case ready
    case failed(String)
    case disabled
    case noCamera
    /// Settings/editor sample: never touches the capture session.
    case sample

    static func resolve(
        isSample: Bool,
        isEnabled: Bool,
        permission: CameraPermissionState,
        phase: CameraPreviewPhase,
        hasSession: Bool,
        hasDevices: Bool
    ) -> Self {
        if isSample { return .sample }
        guard isEnabled else { return .disabled }
        // A running session (mirror or hand navigation) is shown as-is; it
        // already owns the camera light, so showing it starts nothing.
        if case .running = phase, hasSession { return .live }
        switch permission {
        case .notDetermined: return .needsPermission
        case .denied, .restricted: return .denied
        case .authorized: break
        }
        switch phase {
        case .starting, .running: return .starting
        case .failed(let message): return .failed(message)
        case .idle, .stopping: return hasDevices ? .ready : .noCamera
        }
    }

    var message: String {
        switch self {
        case .live: "Camera on"
        case .starting: "Starting camera"
        case .needsPermission: "Camera access needed"
        case .denied: "Camera access is off"
        case .ready: "Camera off"
        case .failed(let message): message
        case .disabled: "Camera disabled"
        case .noCamera: "No camera connected"
        case .sample: "Camera preview"
        }
    }

    /// The single explicit action this state offers, if any.
    var actionTitle: String? {
        switch self {
        case .needsPermission: "Allow"
        case .denied: "Open Settings"
        case .ready: "Start"
        case .failed: "Retry"
        case .live, .starting, .disabled, .noCamera, .sample: nil
        }
    }
}

/// Standalone Camera widget: one rounded live preview whose composition
/// follows the semantic size class (Compact 1x1, Standard 2x1, Large 2x2).
/// It reuses the island's single capture session through a
/// `CameraMirrorConsumerLease`; it never opens its own session and never
/// starts capture by appearing (see `CameraUserIntent`).
struct CameraWidgetView: View {
    @ObservedObject var controller: CameraPreviewController
    let reduceMotion: Bool

    @Environment(\.workspaceWidgetPlacement) private var placement
    @Environment(\.isSettingsPreview) private var isSettingsPreview
    @Environment(\.islandDisplayMetrics) private var displayMetrics
    @State private var lease: CameraMirrorConsumerLease
    @State private var isHovering = false
    @State private var actionError: String?

    init(controller: CameraPreviewController, reduceMotion: Bool) {
        self.controller = controller
        self.reduceMotion = reduceMotion
        _lease = State(initialValue: CameraMirrorConsumerLease(controller: controller))
    }

    private var content: CameraWidgetContent {
        .resolve(
            isSample: isSettingsPreview,
            isEnabled: controller.isEnabled,
            permission: controller.permissionState,
            phase: controller.phase,
            hasSession: controller.previewSession != nil,
            hasDevices: !controller.devices.isEmpty
        )
    }

    private var navigationOwnsCapture: Bool { controller.activeNavigationOwners > 0 }
    private var size: WidgetPresentationSize { placement.presentationSize }
    private var cornerRadius: CGFloat { WorkspaceEditorChrome.cornerRadius * displayMetrics.cornerRadiusScale }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    var body: some View {
        ZStack {
            shape.fill(Color.white.opacity(0.06))
            if content == .live, let session = controller.previewSession {
                CameraPreviewView(session: session, mirrored: true)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            } else {
                placeholder
                    .transition(.opacity)
            }
            if content == .live {
                liveControls
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
            }
        }
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(shape)
        .onHover { hovering in
            withAnimation(WorkspaceMotion.smoothContent(reduceMotion: reduceMotion)) { isHovering = hovering }
        }
        .animation(WorkspaceMotion.smoothContent(reduceMotion: reduceMotion), value: content)
        .contextMenu { contextMenuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera")
        .accessibilityValue(actionError ?? content.message)
        .accessibilityAction(named: content == .live ? "Stop camera" : "Start camera") {
            if content == .live { if !navigationOwnsCapture { stop() } } else { perform() }
        }
        .task {
            guard !isSettingsPreview else { return }
            await lease.acquire()
        }
        .onDisappear {
            guard !isSettingsPreview else { return }
            let lease = lease
            Task { await lease.release() }
        }
    }

    // MARK: Placeholder states

    private var placeholder: some View {
        VStack(spacing: size == .compact ? 6 : 8) {
            if content == .starting {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size == .large ? 26 : 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Text(actionError ?? content.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let title = content.actionTitle {
                Button(action: perform) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                }
                    .buttonStyle(WorkspaceTileButtonStyle(isOn: content != .denied, accent: .cyan, cornerRadius: 8))
                    .accessibilityLabel(title == "Open Settings" ? "Open camera privacy settings" : "\(title) camera")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        switch content {
        case .denied: "video.slash.fill"
        case .disabled, .noCamera: "video.slash"
        case .failed: "exclamationmark.triangle.fill"
        default: "video.fill"
        }
    }

    // MARK: Live controls (revealed on hover only)

    private var liveControls: some View {
        VStack {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if size == .large, controller.devices.count > 1 {
                    Menu {
                        ForEach(controller.devices) { device in
                            Button {
                                Task { try? await controller.selectDevice(id: device.id) }
                            } label: {
                                if device.id == controller.selectedDeviceID { Label(device.name, systemImage: "checkmark") }
                                else { Text(device.name) }
                            }
                        }
                    } label: {
                        controlGlyph("arrow.triangle.2.circlepath.camera")
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Choose camera")
                    .accessibilityLabel("Choose camera")
                }
                if navigationOwnsCapture {
                    // Hand navigation owns this session; Stop here could not
                    // turn the camera off, so it is not offered.
                    controlGlyph("hand.raised.fill")
                        .help("Camera is in use by hand navigation")
                        .accessibilityLabel("Camera in use by hand navigation")
                } else {
                    Button(action: stop) { controlGlyph("xmark") }
                        .buttonStyle(.plain)
                        .help("Stop camera")
                        .accessibilityLabel("Stop camera")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    private func controlGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 24, height: 24)
            .background(.ultraThinMaterial, in: Circle())
            .environment(\.colorScheme, .dark)
            .contentShape(Circle())
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if content == .live {
            if !navigationOwnsCapture { Button("Stop Camera", action: stop) }
        } else if let title = content.actionTitle {
            Button(title == "Open Settings" ? "Open Camera Privacy Settings…" : "\(title) Camera", action: perform)
        }
    }

    // MARK: Actions

    private func perform() {
        guard !isSettingsPreview else { return }
        actionError = nil
        switch content {
        case .denied:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        case .needsPermission, .ready, .failed:
            let lease = lease
            Task { @MainActor in
                do { try await lease.startExplicitly() }
                catch { actionError = error.localizedDescription }
            }
        case .live, .starting, .disabled, .noCamera, .sample:
            break
        }
    }

    private func stop() {
        guard !isSettingsPreview else { return }
        let lease = lease
        // The close is recorded synchronously so no remount restarts capture;
        // a fresh consumer is attached so the tile keeps offering Start.
        Task { @MainActor in
            await lease.closeByUser()
            await lease.acquire()
        }
    }
}
