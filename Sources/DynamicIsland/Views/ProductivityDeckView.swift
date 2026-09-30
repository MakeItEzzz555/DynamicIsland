import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Right-workspace Productivity page. Every control calls the existing
/// production controller; status text comes from the controllers' own
/// capability snapshots. No duplicate feature state lives here.
struct ProductivityDeckView: View {
    let productivity: ProductivityModules
    let fileShelf: FileShelfStore
    let tools: [RightWorkspaceTool]
    @ObservedObject var capabilities: IslandCapabilityRegistry
    let reduceMotion: Bool

    init(
        productivity: ProductivityModules,
        fileShelf: FileShelfStore,
        tools: [RightWorkspaceTool],
        reduceMotion: Bool
    ) {
        self.productivity = productivity
        self.fileShelf = fileShelf
        self.tools = tools
        self.capabilities = productivity.capabilities
        self.reduceMotion = reduceMotion
    }

    var body: some View {
        GeometryReader { proxy in
            let showsCamera = tools.contains(.camera)
            let gridTools = tools.filter { $0 != .camera }
            let availableWidth = max(proxy.size.width, 1)
            let availableHeight = max(proxy.size.height, 60)
            let mirror = min(max(availableWidth * 0.34, 104), 154)
            let gridWidth = max(availableWidth - (showsCamera ? mirror + 10 : 0), 0)
            let columns = gridWidth >= 200 ? 2 : 1
            let rows = Int(ceil(Double(gridTools.count) / Double(max(columns, 1))))
            let gridContentHeight = CGFloat(max(rows, 1)) * 48 + CGFloat(max(rows - 1, 0)) * 6
            let contentHeight = max(availableHeight, gridContentHeight)

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    if showsCamera {
                        CameraMirrorView(controller: productivity.camera, diameter: mirror)
                            .frame(width: mirror, height: min(contentHeight, max(mirror, availableHeight)), alignment: .top)
                    }
                    if !gridTools.isEmpty {
                        toolGrid(
                            gridTools,
                            width: gridWidth,
                            height: contentHeight
                        )
                    }
                }
                .frame(width: availableWidth, alignment: .topLeading)
                .frame(minHeight: availableHeight, alignment: .topLeading)
            }
            .frame(width: availableWidth, height: availableHeight, alignment: .topLeading)
        }
        .environment(\.colorScheme, .dark)
    }

    private func toolGrid(_ gridTools: [RightWorkspaceTool], width: CGFloat, height: CGFloat) -> some View {
        let columns = width >= 200 ? 2 : 1
        let rows = Int(ceil(Double(gridTools.count) / Double(columns)))
        let spacing: CGFloat = 6
        let rowHeight = max((height - spacing * CGFloat(max(rows - 1, 0))) / CGFloat(max(rows, 1)), 30)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
            alignment: .leading,
            spacing: spacing
        ) {
            ForEach(gridTools) { tool in
                ProductivityToolTile(
                    tool: tool,
                    productivity: productivity,
                    fileShelf: fileShelf,
                    snapshot: capabilities.snapshot(for: capabilityID(tool))
                )
                .frame(height: min(rowHeight, 48))
            }
        }
        .frame(width: max(width, 0), alignment: .topLeading)
    }

    private func capabilityID(_ tool: RightWorkspaceTool) -> IslandCapabilityID {
        switch tool {
        case .camera: .camera
        case .keepAwake: .keepAwake
        case .windowSnap: .windowSnap
        case .terminal: .terminal
        case .voice: .voiceTranscribe
        case .backgroundRemoval, .convert: .backgroundRemoval
        case .reminders: .reminders
        }
    }
}

// MARK: - Camera mirror

/// Large circular mirror of the real camera. Capture runs only while this
/// view is visible and access was already granted (Droppy
/// previewDidAppear/previewDidDisappear); access is requested only from
/// the explicit Allow button.
struct CameraMirrorView: View {
    @ObservedObject var controller: CameraPreviewController
    let diameter: CGFloat
    @Environment(\.isSettingsPreview) private var isSettingsPreview

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.24))
            if !isSettingsPreview, let session = controller.previewSession {
                CameraPreviewView(session: session, mirrored: true)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            } else {
                placeholder
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera mirror, \(controller.statusText)")
        .task {
            // Settings previews show the mirror's shell only; they never
            // start capture.
            guard !isSettingsPreview else { return }
            await controller.attachPreviewConsumer()
        }
        .onDisappear {
            guard !isSettingsPreview else { return }
            Task { await controller.detachPreviewConsumer() }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.fill")
                .font(.system(size: max(diameter * 0.12, 12), weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(controller.statusText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: diameter * 0.7)
            switch controller.permissionState {
            case .notDetermined:
                Button { Task { try? await controller.open() } } label: { mirrorButtonLabel("Allow") }
                    .buttonStyle(WorkspaceTileButtonStyle(isOn: true, accent: .cyan, cornerRadius: 8))
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityLabel("Allow camera access")
            case .denied, .restricted:
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                } label: { mirrorButtonLabel("Settings") }
                .buttonStyle(WorkspaceTileButtonStyle(isOn: true, accent: .cyan, cornerRadius: 8))
                .font(.system(size: 9, weight: .semibold))
            case .authorized:
                if controller.phase != .starting {
                    // Capture normally starts on appear; this covers a
                    // failed or externally stopped session.
                    Button { Task { try? await controller.open() } } label: { mirrorButtonLabel(controller.phase == .idle ? "Start" : "Retry") }
                        .buttonStyle(WorkspaceTileButtonStyle(cornerRadius: 8))
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityLabel("Start camera mirror")
                }
            }
        }
        .padding(8)
    }

    private func mirrorButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .frame(height: 22)
    }
}

// MARK: - Tool tiles

private struct ProductivityToolTile: View {
    let tool: RightWorkspaceTool
    let productivity: ProductivityModules
    let fileShelf: FileShelfStore
    let snapshot: IslandCapabilitySnapshot?

    @State private var message: String?
    @State private var converting = false

    var body: some View {
        switch tool {
        case .keepAwake:
            KeepAwakeTile(controller: productivity.keepAwake, status: snapshot?.statusText)
        case .windowSnap:
            Menu {
                ForEach(WindowSnapTarget.allCases) { target in
                    Button {
                        do { try productivity.windowSnap.snap(to: target) } catch { message = error.localizedDescription }
                    } label: {
                        Label(target.displayName, systemImage: target.symbolName)
                    }
                }
            } label: {
                WorkspaceTileLabel(symbol: tool.symbolName, title: tool.title, status: message ?? snapshot?.statusText ?? "Snap the front window")
            }
            .menuStyle(.button)
            .buttonStyle(WorkspaceTileButtonStyle())
            .menuIndicator(.hidden)
            .help("Snap the frontmost window")
            .accessibilityLabel("Window Snap")
        case .terminal:
            Button {
                if !productivity.terminal.openExternalTerminal() {
                    message = "Terminal could not be opened"
                }
            } label: {
                WorkspaceTileLabel(
                    symbol: tool.symbolName,
                    title: tool.title,
                    status: message ?? (productivity.terminal.isRunning ? productivity.terminal.statusText : "Open Terminal")
                )
            }
            .buttonStyle(WorkspaceTileButtonStyle(isOn: productivity.terminal.isRunning, accent: .green))
            .accessibilityLabel("Open Terminal")
        case .voice:
            VoiceTile(controller: productivity.voice, status: snapshot?.statusText)
        case .backgroundRemoval:
            BackgroundRemovalTile(controller: productivity.backgroundRemoval, status: snapshot?.statusText)
        case .convert:
            Menu {
                ForEach(FileConversionController.availableFormats) { format in
                    Button("Choose Image → \(format.displayName)…") { convert(to: format) }
                }
            } label: {
                WorkspaceTileLabel(
                    symbol: tool.symbolName,
                    title: tool.title,
                    status: message ?? "Image to PNG, JPEG, HEIC…",
                    isBusy: converting
                )
            }
            .menuStyle(.button)
            .buttonStyle(WorkspaceTileButtonStyle())
            .menuIndicator(.hidden)
            .disabled(converting)
            .accessibilityLabel("Convert an image")
        case .reminders:
            RemindersTile(controller: productivity.reminders, status: snapshot?.statusText)
        case .camera:
            EmptyView()
        }
    }

    private func convert(to format: FileConversionFormat) {
        guard let url = ProductivityFilePicker.chooseImage(prompt: "Convert") else { return }
        converting = true
        Task { @MainActor in
            defer { converting = false }
            do {
                let output = try await FileConversionController.convert(url, to: format)
                fileShelf.add([output])
                message = "Saved \(output.lastPathComponent)"
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

private struct KeepAwakeTile: View {
    @ObservedObject var controller: KeepAwakeController
    let status: String?

    var body: some View {
        Button {
            if controller.isActive {
                controller.stop()
            } else {
                try? controller.startIndefinite()
            }
        } label: {
            WorkspaceTileLabel(
                symbol: RightWorkspaceTool.keepAwake.symbolName,
                title: "Keep Awake",
                status: controller.lastError ?? (controller.isActive ? "On · tap to stop" : "Off · tap to start"),
                isOn: controller.isActive,
                accent: .orange
            )
        }
        .buttonStyle(WorkspaceTileButtonStyle(isOn: controller.isActive, accent: .orange))
        .contextMenu {
            ForEach(KeepAwakePreset.allCases) { preset in
                Button("Keep awake \(preset.displayName)") { try? controller.start(preset: preset) }
            }
        }
        .accessibilityLabel("Keep Awake")
        .accessibilityValue(controller.isActive ? "On" : "Off")
    }
}

private struct VoiceTile: View {
    @ObservedObject var controller: VoiceTranscriptionController
    let status: String?
    @State private var error: String?

    private var isRecording: Bool {
        if case .recording = controller.phase { return true }
        return false
    }

    private var isBusy: Bool {
        switch controller.phase {
        case .preparing, .stopping, .transcribing: true
        default: false
        }
    }

    var body: some View {
        Button {
            Task { @MainActor in
                do {
                    if isRecording {
                        try await controller.stopAndTranscribe()
                    } else {
                        try await controller.startRecording()
                    }
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } label: {
            WorkspaceTileLabel(
                symbol: isRecording ? "stop.fill" : RightWorkspaceTool.voice.symbolName,
                title: isRecording ? "Stop & Transcribe" : "Voice",
                status: error ?? status,
                isOn: isRecording,
                accent: .red,
                isBusy: isBusy
            )
        }
        .buttonStyle(WorkspaceTileButtonStyle(isOn: isRecording, accent: .red))
        .disabled(isBusy)
        .accessibilityLabel(isRecording ? "Stop recording and transcribe" : "Start voice recording")
    }
}

private struct BackgroundRemovalTile: View {
    @ObservedObject var controller: BackgroundRemovalController
    let status: String?
    @State private var error: String?

    var body: some View {
        Button {
            guard let url = ProductivityFilePicker.chooseImage(prompt: "Remove Background") else { return }
            do {
                try controller.process(imageURL: url, addResultToShelfWhenFinished: true)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        } label: {
            WorkspaceTileLabel(
                symbol: RightWorkspaceTool.backgroundRemoval.symbolName,
                title: "Remove BG",
                status: error ?? status,
                isBusy: controller.isProcessing
            )
        }
        .buttonStyle(WorkspaceTileButtonStyle(isOn: controller.isProcessing, accent: .purple))
        .disabled(controller.isProcessing)
        .accessibilityLabel("Remove background from an image")
    }
}

private struct RemindersTile: View {
    @ObservedObject var controller: RemindersController
    let status: String?

    var body: some View {
        Button {
            Task { @MainActor in
                if controller.accessState == .notDetermined {
                    await controller.requestAccess()
                } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                    _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        } label: {
            WorkspaceTileLabel(
                symbol: RightWorkspaceTool.reminders.symbolName,
                title: "Reminders",
                status: summary
            )
        }
        .buttonStyle(WorkspaceTileButtonStyle())
        .task { await controller.refresh() }
        .accessibilityLabel("Reminders")
        .accessibilityValue(summary ?? "")
    }

    private var summary: String? {
        switch controller.accessState {
        case .notDetermined: return "Tap to allow access"
        case .fullAccess:
            if let next = controller.upcomingReminders.first { return next.title }
            return "Nothing upcoming"
        default: return status
        }
    }
}

enum ProductivityFilePicker {
    @MainActor
    static func chooseImage(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = prompt
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
