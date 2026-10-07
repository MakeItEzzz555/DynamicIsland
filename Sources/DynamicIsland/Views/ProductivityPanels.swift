import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Shared productivity controls bound to the production controllers. Used by
// the Productivity settings section and the expanded island Tools page, so
// neither surface keeps its own feature state.

struct CapabilityStatusLine: View {
    @ObservedObject var capabilities: IslandCapabilityRegistry
    let id: IslandCapabilityID

    var body: some View {
        if let snapshot = capabilities.snapshot(for: id) {
            HStack(spacing: 6) {
                Image(systemName: symbol(for: snapshot))
                    .foregroundStyle(color(for: snapshot))
                Text(snapshot.statusText ?? "")
                    .lineLimit(2)
                if let reason = availabilityReason(snapshot.availability) {
                    Text("· \(reason)")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .accessibilityElement(children: .combine)
        }
    }

    private func symbol(for snapshot: IslandCapabilitySnapshot) -> String {
        if case .failed = snapshot.health { return "xmark.octagon.fill" }
        if snapshot.permission == .denied { return "hand.raised.fill" }
        if snapshot.isActive { return "circle.fill" }
        return snapshot.isOperational ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private func color(for snapshot: IslandCapabilitySnapshot) -> Color {
        if case .failed = snapshot.health { return .red }
        if snapshot.permission == .denied { return .red }
        if snapshot.isActive { return .green }
        return snapshot.isOperational ? .green : .orange
    }

    private func availabilityReason(_ availability: IslandCapabilityAvailability) -> String? {
        switch availability {
        case .available: nil
        case .unsupported(let reason), .temporarilyUnavailable(let reason): reason
        }
    }
}

// MARK: - Keep Awake

struct KeepAwakePanel: View {
    @ObservedObject var controller: KeepAwakeController
    @State private var customMinutes = 45

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(KeepAwakePreset.allCases) { preset in
                    Button(preset.displayName) {
                        try? controller.start(preset: preset)
                    }
                }
                Button("Indefinite") {
                    try? controller.startIndefinite()
                }
            }
            .controlSize(.small)

            HStack(spacing: 8) {
                Stepper(value: $customMinutes, in: 1...720, step: 5) {
                    Text("Custom: \(customMinutes) min")
                        .monospacedDigit()
                }
                Button("Start") {
                    try? controller.start(customDuration: TimeInterval(customMinutes * 60))
                }
                Spacer()
                if controller.isActive {
                    Button("Stop", role: .destructive) { controller.stop() }
                }
            }
            .controlSize(.small)

            if controller.isActive {
                if let expiresAt = controller.expiresAt {
                    HStack(spacing: 4) {
                        Text("Remaining")
                        Text(expiresAt, style: .timer)
                            .monospacedDigit()
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                } else {
                    Text("Active until stopped")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Window Snap

struct WindowSnapPanel: View {
    @ObservedObject var controller: WindowSnapController
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(WindowSnapTarget.allCases) { target in
                Button {
                    try? controller.snap(to: target)
                } label: {
                    Label(target.displayName, systemImage: target.symbolName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Terminal

struct TerminalSettingsPanel: View {
    @ObservedObject var controller: TerminalSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Shell", text: $controller.shellPath)
                .textFieldStyle(.roundedBorder)
            TextField("Working directory", text: $controller.workingDirectoryPath)
                .textFieldStyle(.roundedBorder)
            Toggle("Keep command history for this session", isOn: $controller.persistCommandHistory)
            HStack {
                Text(controller.commandHistory.isEmpty
                     ? "No command history"
                     : "\(controller.commandHistory.count) command(s) in history")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear History") { controller.clearCommandHistory() }
                    .disabled(controller.commandHistory.isEmpty)
                Button("Open in Terminal") { _ = controller.openExternalTerminal() }
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Reminders

struct RemindersPanel: View {
    @ObservedObject var controller: RemindersController
    var maxUpcoming = 5
    @State private var title = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(3_600)
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch controller.accessState {
            case .fullAccess:
                authorizedContent
            case .notDetermined:
                Button("Allow Reminders Access") {
                    Task { await controller.requestAccess() }
                }
            case .denied, .restricted, .writeOnly, .unavailable:
                Button("Open Privacy Settings") {
                    Task { try? await controller.perform(.openSettings) }
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var authorizedContent: some View {
        if !controller.lists.isEmpty {
            Picker("List", selection: Binding(
                get: { controller.selectedListID ?? "" },
                set: { controller.selectedListID = $0 }
            )) {
                ForEach(controller.lists) { list in
                    Text(list.title).tag(list.id)
                }
            }
        }

        HStack(spacing: 6) {
            TextField("New reminder", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            Button("Add", action: create)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        HStack(spacing: 6) {
            Toggle("Due", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("", selection: $dueDate)
                    .labelsHidden()
            }
        }
        .controlSize(.small)

        if controller.upcomingReminders.isEmpty {
            Text("No upcoming reminders")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            ForEach(controller.upcomingReminders.prefix(maxUpcoming)) { reminder in
                HStack(spacing: 6) {
                    Button {
                        complete(reminder)
                    } label: {
                        Image(systemName: "circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Complete \(reminder.title)")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reminder.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(reminder.dueDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? reminder.listTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func create() {
        let value = title
        let due = hasDueDate ? dueDate : nil
        Task {
            do {
                try await controller.createReminder(title: value, dueDate: due)
                title = ""
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func complete(_ reminder: ReminderDescriptor) {
        Task {
            do {
                try await controller.completeReminder(id: reminder.id)
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - Voice Transcribe

struct VoiceTranscribePanel: View {
    @ObservedObject var controller: VoiceTranscriptionController
    /// Compact mode avoids nested scroll views inside the island.
    var compact = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                switch controller.phase {
                case .recording:
                    Button {
                        run { try await controller.stopAndTranscribe() }
                    } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                    }
                    Button("Cancel", role: .cancel) { controller.cancel() }
                case .requestingPermission, .preparing, .stopping, .transcribing:
                    ProgressView()
                        .controlSize(.small)
                    Button("Cancel", role: .cancel) { controller.cancel() }
                case .idle, .completed, .failed:
                    Button {
                        run { try await controller.startRecording() }
                    } label: {
                        Label("Record", systemImage: "mic.circle.fill")
                    }
                    .disabled(!controller.isEnabled)
                }
                Spacer()
                Text(controller.willTranscribeOnDevice ? "On-device" : "On-device unavailable")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(controller.willTranscribeOnDevice ? .green : .orange)
            }
            .controlSize(.small)

            if let transcript = controller.transcript {
                Group {
                    if compact {
                        Text(transcript.text)
                            .font(.system(size: 12))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        ScrollView {
                            Text(transcript.text)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(maxHeight: 90)
                    }
                }
                .padding(6)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 6) {
                    Button("Copy") { run { try controller.copyTranscript() } }
                    Button("Save…", action: save)
                    ShareLink(item: transcript.text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button("Add to Shelf") { run { try controller.addTranscriptToShelf() } }
                }
                .controlSize(.small)
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private func save() {
        guard let transcript = controller.transcript else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = VoiceTranscriptionController.transcriptFilename(for: transcript.createdAt)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { try controller.saveTranscript(to: url) }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - Camera

struct CameraPanel: View {
    @ObservedObject var controller: CameraPreviewController
    var previewHeight: CGFloat = 120
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if !controller.devices.isEmpty {
                    Picker("Camera", selection: Binding(
                        get: { controller.selectedDeviceID ?? "" },
                        set: { id in run { try await controller.selectDevice(id: id) } }
                    )) {
                        ForEach(controller.devices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
                Spacer()
                if controller.isRunning || controller.phase == .starting {
                    Button("Close") { Task { await controller.close() } }
                } else {
                    Button("Open Preview") { run { try await controller.open() } }
                        .disabled(!controller.isEnabled)
                }
            }
            .controlSize(.small)

            if controller.isRunning {
                CameraPreviewView(session: controller.previewSession)
                    .frame(height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Live camera preview")
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .onDisappear {
            // Preview-only: leaving the surface releases the capture this
            // panel opened. Passive, so it never records a user close.
            Task { await controller.releaseExplicitPreview() }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - Background Removal

struct BackgroundRemovalPanel: View {
    @ObservedObject var controller: BackgroundRemovalController
    var imageHeight: CGFloat = 96
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button("Choose Image…", action: chooseImage)
                    .disabled(controller.isProcessing || !controller.isEnabled)
                if controller.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                    Button("Cancel", role: .cancel) { controller.cancel() }
                }
                Spacer()
            }
            .controlSize(.small)

            if let result = controller.result {
                HStack(spacing: 8) {
                    imageTile(result.sourceURL, label: "Before")
                    imageTile(result.previewURL, label: "After", checkerboard: true)
                }
                HStack(spacing: 6) {
                    Button("Export") { run { try controller.export() } }
                    Button("Export To…", action: exportToFolder)
                    Button("Add to Shelf") { run { try controller.addResultToShelf() } }
                }
                .controlSize(.small)
                if let exported = controller.lastExportURL {
                    Text("Saved \(exported.lastPathComponent)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private func imageTile(_ url: URL, label: String, checkerboard: Bool = false) -> some View {
        VStack(spacing: 3) {
            ZStack {
                if checkerboard {
                    Rectangle().fill(.white.opacity(0.08))
                }
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(height: imageHeight)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { try controller.process(imageURL: url) }
    }

    private func exportToFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { try controller.export(toDirectory: url) }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
