import AppKit
import SwiftUI

@MainActor
final class CameraPointerStore: ObservableObject {
    @Published var presentation: CameraPointerPresentation?
    @Published var isMounted = false
}

struct CameraPointerOverlay: View {
    @ObservedObject var store: CameraPointerStore
    let canvasSize: CGSize
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let pointer = store.presentation {
                CameraVirtualPointer(presentation: pointer)
                    .position(x: pointer.point.x, y: canvasSize.height - pointer.point.y)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
        .onAppear { store.isMounted = true }
        .onDisappear { store.isMounted = false }
    }
}

struct CameraVirtualPointer: View {
    let presentation: CameraPointerPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Circle()
            .fill(presentation.phase == .pressed || presentation.phase == .dragging || reduceTransparency ? Color.white : Color.white.opacity(0.15))
            .overlay { Circle().strokeBorder(.white.opacity(presentation.overControl || contrast == .increased ? 0.95 : 0.65), lineWidth: contrast == .increased ? 2 : 1.5) }
            .frame(width: presentation.phase == .pressed ? 8 : 11, height: presentation.phase == .pressed ? 8 : 11)
            .shadow(color: .black.opacity(0.35), radius: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(reduceMotion ? .identity : .opacity)
    }
}

struct CameraNavigationSettingsView: View {
    @ObservedObject var navigation: CameraNavigationController
    @ObservedObject var camera: CameraPreviewController
    @State private var changing = false

    var body: some View {
        GroupBox("Camera Navigation") {
            VStack(alignment: .leading, spacing: 12) {
                if let warning = navigation.duplicateInstanceWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                    Text("Quit other DynamicIsland copies if camera tracking does not start.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Status", value: navigation.status)
                LabeledContent("Camera permission", value: camera.permissionState == .authorized ? "Granted" : "Required")
                Picker("Camera", selection: Binding(get: { camera.selectedDeviceID ?? "" }, set: { id in
                    changing = true
                    Task { @MainActor in
                        do { try await camera.selectDevice(id: id) }
                        catch { /* Controller publishes the start failure. */ }
                        changing = false
                    }
                })) {
                    if camera.devices.isEmpty { Text("No available camera").tag("") }
                    ForEach(camera.devices) { device in Text(device.name).tag(device.id) }
                }.disabled(changing || camera.devices.isEmpty)
                if camera.permissionState == .notDetermined {
                    Button("Allow Camera") { Task { await navigation.allowCamera() } }
                        .disabled(!navigation.desiredCameraNavigation || navigation.runtimeState == .starting)
                } else if camera.permissionState != .authorized {
                    Button("Open Camera Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
                    }
                }
                Button("Check Again") { Task { await navigation.checkAgain() } }
                if navigation.runtimeState == .noFrames {
                    Text("Check Again or select another camera.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Show virtual pointer", isOn: $navigation.preferences.showPointer)
                Toggle("Magnetic controls", isOn: $navigation.preferences.magneticControls)
                Toggle("Horizontal page swipe", isOn: $navigation.preferences.horizontalPageSwipe)
                Toggle("Two-finger scroll", isOn: $navigation.preferences.twoFingerScroll)
                LabeledContent("Pointer sensitivity") { Slider(value: $navigation.preferences.sensitivity, in: 0...1).accessibilityLabel("Pointer sensitivity") }
                LabeledContent("Pointer smoothing") { Slider(value: $navigation.preferences.smoothing, in: 0...1).accessibilityLabel("Pointer smoothing") }
                LabeledContent("Pinch sensitivity") { Slider(value: $navigation.preferences.pinchSensitivity, in: 0...1).accessibilityLabel("Pinch sensitivity") }
                HStack {
                    Button("Calibrate…") { navigation.beginCalibration() }.disabled(!navigation.isEnabled)
                    Button("Reset Calibration") { navigation.resetCalibration() }
                }
                if let error = navigation.calibrationError { Text(error).font(.caption) }
                if let step = navigation.calibrationStep {
                    Text("Point \(["left", "right", "top", "bottom"][step]), then pinch to confirm.")
                    Button("Cancel Calibration") { navigation.cancelCalibration() }
                }
                Text("Use one hand: point with your index finger, pinch to click or drag, and open your palm to cancel. Text entry uses the keyboard. Processing stays on this Mac; camera images are never saved.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Diagnostics") {
                    LabeledContent("Capture session running", value: camera.isRunning ? "Yes" : "No")
                    LabeledContent("Video output attached", value: navigation.videoOutputAttached ? "Yes" : "No")
                    LabeledContent("Video frames received", value: navigation.firstFrameReceived ? "Yes" : "No")
                    LabeledContent("Hand", value: navigation.isTracking ? "Tracking" : "No hand")
                    if navigation.firstFrameReceived {
                        LabeledContent("Recognition", value: String(format: "%.1f FPS", navigation.recognitionFPS))
                    }
                    LabeledContent("Vision latency", value: String(format: "%.1f ms mean · %.1f ms p95", navigation.meanLatencyMS, navigation.p95LatencyMS))
                    LabeledContent("Session owners", value: "Navigation \(camera.activeNavigationOwners) · Mirror \(camera.activePreviewConsumers)")
                }
                // This preview uses numeric synthetic state and owns no camera.
                HStack {
                    CameraVirtualPointer(presentation: .init(point: .zero, phase: .tracking, overControl: true))
                        .frame(width: 24, height: 24).background(.black, in: RoundedRectangle(cornerRadius: 5))
                    Text("Virtual pointer preview").font(.caption).foregroundStyle(.secondary)
                }.frame(height: 24)
            }
            .toggleStyle(.switch)
            .padding(8)
        }
    }
}
