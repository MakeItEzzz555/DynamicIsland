import SwiftUI

/// Productivity settings. Every control drives a production controller;
/// status comes from `IslandCapabilityRegistry`.
struct ProductivitySettingsView: View {
    let productivity: ProductivityModules
    @ObservedObject var capabilities: IslandCapabilityRegistry

    init(productivity: ProductivityModules) {
        self.productivity = productivity
        self.capabilities = productivity.capabilities
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HelpText("Productivity tools also appear on the island's Tools page. Enable switches apply until the app quits. Permissions are requested only when you use a tool.")

            SettingsGroup("Keep Awake") {
                enabledToggle(.keepAwake) { productivity.keepAwake.setEnabled($0) }
                CapabilityStatusLine(capabilities: capabilities, id: .keepAwake)
                KeepAwakePanel(controller: productivity.keepAwake)
            }

            SettingsGroup("Window Snap") {
                enabledToggle(.windowSnap) { productivity.windowSnap.setEnabled($0) }
                CapabilityStatusLine(capabilities: capabilities, id: .windowSnap)
                HStack(spacing: 6) {
                    Button("Request Accessibility Access") {
                        SystemHUDAccessibilityPermission.request()
                        refresh(productivity.windowSnap)
                    }
                    Button("Open Accessibility Settings") {
                        SystemHUDAccessibilityPermission.openSettings()
                    }
                    Button("Test") {
                        Task { try? await productivity.windowSnap.perform(.test) }
                    }
                }
                .controlSize(.small)
                HelpText("Supported layouts. Snapping applies to the focused window of the frontmost app, so use these from the island's Tools page. Keyboard shortcuts are not available: DynamicIsland has no global shortcut system yet.")
                WindowSnapPanel(controller: productivity.windowSnap)
            }

            SettingsGroup("Terminal") {
                enabledToggle(.terminal) { productivity.terminal.setEnabled($0) }
                CapabilityStatusLine(capabilities: capabilities, id: .terminal)
                TerminalSettingsPanel(controller: productivity.terminal)
                TerminalSessionView(controller: productivity.terminal)
            }

            SettingsGroup("Reminders") {
                enabledToggle(.reminders) { productivity.reminders.setEnabled($0) }
                CapabilityStatusLine(capabilities: capabilities, id: .reminders)
                RemindersPanel(controller: productivity.reminders)
            }

            SettingsGroup("Voice Transcribe") {
                enabledToggle(.voiceTranscribe) { productivity.voice.setEnabled($0) }
                CapabilityStatusLine(capabilities: capabilities, id: .voiceTranscribe)
                VoicePermissionRows(controller: productivity.voice)
                VoiceTranscribePanel(controller: productivity.voice)
                HelpText("Speech models are managed by macOS. DynamicIsland cannot install or remove recognition models from here.")
            }

            SettingsGroup("Camera") {
                enabledToggle(.camera) { enabled in
                    Task { await productivity.camera.setEnabled(enabled) }
                }
                CapabilityStatusLine(capabilities: capabilities, id: .camera)
                Button("Open Camera Privacy Settings") {
                    Task { try? await productivity.camera.perform(.openSettings) }
                }
                .controlSize(.small)
                CameraPanel(controller: productivity.camera, previewHeight: 180)
                HelpText("Preview only. Frames are never recorded or saved, and the camera turns off when you close the preview or leave this page.")
            }

            SettingsGroup("Background Removal") {
                enabledToggle(.backgroundRemoval) { productivity.backgroundRemoval.setEnabled($0) }
                CapabilityStatusLine(capabilities: capabilities, id: .backgroundRemoval)
                BackgroundRemovalPanel(controller: productivity.backgroundRemoval, imageHeight: 140)
                HelpText("Runs on this Mac with Vision. The original image is never modified.")
            }
        }
        .task {
            await productivity.keepAwake.refresh()
            await productivity.windowSnap.refresh()
            await productivity.reminders.refresh()
            await productivity.voice.refresh()
            await productivity.camera.refresh()
        }
    }

    private func enabledToggle(
        _ id: IslandCapabilityID,
        set: @escaping (Bool) -> Void
    ) -> some View {
        Toggle("Enabled", isOn: Binding(
            get: { capabilities.snapshot(for: id)?.isEnabled ?? true },
            set: set
        ))
    }

    private func refresh(_ adapter: some IslandCapabilityAdapter) {
        Task { await adapter.refresh() }
    }
}

private struct VoicePermissionRows: View {
    @ObservedObject var controller: VoiceTranscriptionController

    var body: some View {
        HStack(spacing: 12) {
            permissionLabel("Microphone", controller.microphoneState)
            permissionLabel("Speech", controller.speechState)
            Spacer()
            if controller.microphoneState == .notDetermined || controller.speechState == .notDetermined {
                Button("Request Access") {
                    Task { await controller.requestPermissions() }
                }
            } else if controller.microphoneState != .authorized || controller.speechState != .authorized {
                Button("Open Privacy Settings") {
                    Task { try? await controller.perform(.openSettings) }
                }
            }
        }
        .controlSize(.small)
        Toggle("Allow Apple server recognition when on-device is unavailable", isOn: $controller.allowsServerRecognition)
        Text(controller.recognizerAvailability.supportsOnDeviceRecognition
             ? "On-device recognition is available for \(controller.recognizerAvailability.localeIdentifier)."
             : "On-device recognition is not available for \(controller.recognizerAvailability.localeIdentifier).")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private func permissionLabel(_ title: String, _ state: VoicePermissionState) -> some View {
        let text: String
        switch state {
        case .authorized: text = "Allowed"
        case .denied: text = "Denied"
        case .restricted: text = "Restricted"
        case .notDetermined: text = "Not requested"
        }
        return Text("\(title): \(text)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(state == .authorized ? Color.secondary : Color.orange)
    }
}
