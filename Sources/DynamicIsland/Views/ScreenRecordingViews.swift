import AppKit
import SwiftUI

struct ScreenRecordingTile: View {
    @ObservedObject var controller: ScreenRecordingController
    let status: String?
    @State private var showsSetup = false

    var body: some View {
        Button {
            showsSetup = true
        } label: {
            WorkspaceTileLabel(
                symbol: controller.isActuallyCapturing ? "record.circle.fill" : RightWorkspaceTool.screenRecording.symbolName,
                title: "Screen Record",
                status: controller.isActuallyCapturing ? controller.statusText + " · " + controller.formattedDuration : (status ?? controller.statusText),
                isOn: controller.isActuallyCapturing,
                accent: .red,
                isBusy: controller.phase == .preparing || controller.phase == .finalizing
            )
        }
        .buttonStyle(WorkspaceTileButtonStyle(isOn: controller.isActuallyCapturing, accent: .red))
        .accessibilityLabel(controller.isActuallyCapturing ? "Screen recording controls" : "Start screen recording")
        .accessibilityValue(controller.statusText)
        .sheet(isPresented: $showsSetup) {
            ScreenRecordingSetupView(controller: controller)
        }
    }
}

struct CollapsedScreenRecordingActivityView: View {
    @ObservedObject var controller: ScreenRecordingController
    let layout: CompactCollapsedSideSlotGeometry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        CompactCollapsedSideSlotLayout(geometry: layout) {
            preview
                .frame(
                    width: CollapsedActivityLayoutProfile.screenRecordingLeftContentWidth,
                    height: 38
                )
        } right: {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(controller.phase == .paused ? Color.red.opacity(0.38) : .red)
                        .frame(width: 7, height: 7)
                        .opacity(controller.phase == .recording && !reduceMotion ? (pulse ? 0.38 : 1) : 0.82)
                        .animation(
                            controller.phase == .recording && !reduceMotion
                                ? .easeInOut(duration: 0.78).repeatForever(autoreverses: true)
                                : .default,
                            value: pulse
                        )
                    Text(controller.formattedDuration)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Button {
                        controller.togglePause()
                    } label: {
                        Image(systemName: controller.phase == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 22, height: 16)
                    }
                    .buttonStyle(.plain)
                    .background(.white.opacity(0.10), in: Capsule())
                    .accessibilityLabel(controller.phase == .paused ? "Resume screen recording" : "Pause screen recording")
                    .disabled(controller.phase == .finalizing)

                    Button {
                        Task { await controller.stopAndSave() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 7.5, weight: .bold))
                            .frame(width: 22, height: 16)
                    }
                    .buttonStyle(.plain)
                    .background(.red.opacity(0.82), in: Capsule())
                    .accessibilityLabel("Stop and save screen recording")
                    .disabled(controller.phase == .finalizing)
                }
                .foregroundStyle(.white)
            }
            .frame(
                width: CollapsedActivityLayoutProfile.screenRecordingRightContentWidth,
                alignment: .trailing
            )
        }
        .onAppear {
            pulse = controller.phase == .recording
        }
        .onChange(of: controller.phase) { _, phase in
            pulse = phase == .recording
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            controller.phase == .paused
                ? "Screen recording paused, \(controller.formattedDuration)"
                : "Screen recording, \(controller.formattedDuration)"
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let image = controller.previewImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 54, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 54, height: 34)
                .overlay {
                    Image(systemName: "rectangle.dashed.badge.record")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.64))
                }
        }
    }
}

struct ScreenRecordingSetupView: View {
    @ObservedObject var controller: ScreenRecordingController
    @Environment(\.dismiss) private var dismiss
    @State private var targetKind: ScreenRecordingTargetKind = .display
    @State private var displayID: CGDirectDisplayID?
    @State private var windowID: CGWindowID?
    @State private var isChoosingArea = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Screen Record", systemImage: "record.circle")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close screen recording controls")
            }

            if controller.phase == .recording || controller.phase == .paused || controller.phase == .finalizing {
                activeControls
            } else {
                setupControls
            }

            if controller.phase == .saved, let url = controller.lastSavedURL {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Saved \(url.lastPathComponent)")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Button("Reveal") { controller.revealLastRecording() }
                }
            } else if controller.phase == .failed {
                Text(controller.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(.black.opacity(0.96))
        .preferredColorScheme(.dark)
        .task {
            await controller.prepareTargets(requestPermission: false)
            if displayID == nil { displayID = controller.displays.first?.id }
            if windowID == nil { windowID = controller.windows.first?.id }
        }
        .onChange(of: controller.displays) { _, displays in
            if displayID == nil || !displays.contains(where: { $0.id == displayID }) {
                displayID = displays.first?.id
            }
        }
        .onChange(of: controller.windows) { _, windows in
            if windowID == nil || !windows.contains(where: { $0.id == windowID }) {
                windowID = windows.first?.id
            }
        }
    }

    @ViewBuilder
    private var setupControls: some View {
        Picker("Target", selection: $targetKind) {
            ForEach(ScreenRecordingTargetKind.allCases) { target in
                Text(target.title).tag(target)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Screen recording target")

        if CGPreflightScreenCaptureAccess() {
            switch targetKind {
            case .display:
                Picker("Display", selection: Binding(
                    get: { displayID ?? controller.displays.first?.id ?? 0 },
                    set: { displayID = $0 }
                )) {
                    ForEach(controller.displays) { display in
                        Text(display.name).tag(display.id)
                    }
                }

            case .window:
                Picker("Window", selection: Binding(
                    get: { windowID ?? controller.windows.first?.id ?? 0 },
                    set: { windowID = $0 }
                )) {
                    ForEach(controller.windows) { window in
                        Text(window.displayTitle).tag(window.id)
                    }
                }

            case .area:
                if let display = selectedDisplay {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(display.name)
                                .font(.system(size: 11, weight: .semibold))
                            Text("Drag over the area to record after pressing Start")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            Toggle("System audio", isOn: $controller.options.capturesSystemAudio)
            Toggle("Microphone", isOn: $controller.options.capturesMicrophone)
                .disabled(!controller.microphoneCaptureAvailable)
            Toggle("Show pointer", isOn: $controller.options.showsCursor)
            Toggle("Exclude DynamicIsland", isOn: $controller.options.excludesDynamicIsland)

            if !controller.microphoneCaptureAvailable {
                Text("Direct microphone capture requires macOS 15 or later.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(controller.statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Start Recording") {
                    Task { await startSelectedTarget() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canStart || isChoosingArea)
            }
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Text("Screen Recording permission is required to choose and capture a display, window, or area.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Allow Screen Recording") {
                        Task {
                            await controller.prepareTargets(requestPermission: true)
                            displayID = controller.displays.first?.id
                            windowID = controller.windows.first?.id
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Open Settings") { controller.openScreenRecordingSettings() }
                }
            }
        }
    }

    private var activeControls: some View {
        VStack(spacing: 12) {
            if let image = controller.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(controller.phase == .paused ? Color.red.opacity(0.38) : Color.red)
                    .frame(width: 9, height: 9)
                    .opacity(controller.phase == .recording ? 1 : 0.75)
                    .animation(
                        controller.phase == .recording
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: controller.phase
                    )
                    .accessibilityHidden(true)

                Text(controller.phase == .paused ? "Paused" : controller.phase == .finalizing ? "Saving" : "Recording")
                    .font(.system(size: 11, weight: .bold))
                Text(controller.formattedDuration)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .monospacedDigit()

                Spacer()

                if controller.phase == .recording || controller.phase == .paused {
                    Button {
                        controller.togglePause()
                    } label: {
                        Label(controller.phase == .paused ? "Resume" : "Pause",
                              systemImage: controller.phase == .paused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        Task { await controller.stopAndSave() }
                    } label: {
                        Label("Stop & Save", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var selectedDisplay: ScreenRecordingDisplayChoice? {
        guard let displayID else { return controller.displays.first }
        return controller.displays.first { $0.id == displayID }
    }

    private var canStart: Bool {
        switch targetKind {
        case .display, .area:
            return selectedDisplay != nil
        case .window:
            guard let windowID else { return false }
            return controller.windows.contains { $0.id == windowID }
        }
    }

    private func startSelectedTarget() async {
        switch targetKind {
        case .display:
            guard let id = selectedDisplay?.id else { return }
            await controller.startDisplay(id)

        case .window:
            guard let id = windowID else { return }
            await controller.startWindow(id)

        case .area:
            guard let display = selectedDisplay,
                  let screen = NSScreen.screens.first(where: {
                      ScreenRecordingController.displayID(for: $0) == display.id
                  }) else { return }
            isChoosingArea = true
            defer { isChoosingArea = false }
            if let sourceRect = await ScreenRecordingAreaSelector.select(on: screen) {
                await controller.startArea(displayID: display.id, sourceRect: sourceRect)
            }
        }
    }
}

@MainActor
enum ScreenRecordingAreaSelector {
    private static var retainedWindow: ScreenRecordingAreaWindow?

    static func select(on screen: NSScreen) async -> CGRect? {
        await withCheckedContinuation { continuation in
            let window = ScreenRecordingAreaWindow(screen: screen)
            retainedWindow = window
            window.onComplete = { rect in
                let sourceRect = ScreenRecordingAreaGeometry.sourceRect(
                    fromAppKitLocalRect: rect,
                    displayHeight: screen.frame.height
                )
                retainedWindow?.orderOut(nil)
                retainedWindow?.close()
                retainedWindow = nil
                continuation.resume(returning: sourceRect)
            }
            window.onCancel = {
                retainedWindow?.orderOut(nil)
                retainedWindow?.close()
                retainedWindow = nil
                continuation.resume(returning: nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
private final class ScreenRecordingAreaWindow: NSWindow {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = ScreenRecordingAreaSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.onComplete = { [weak self] rect in self?.onComplete?(rect) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
private final class ScreenRecordingAreaSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint = CGPoint.zero
    private var currentPoint = CGPoint.zero
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        currentPoint = convert(event.locationInWindow, from: nil)
        let rect = selectionRect.intersection(bounds)
        if rect.width >= 20, rect.height >= 20 {
            onComplete?(rect)
        } else {
            onCancel?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isDragging else { return }
        let rect = selectionRect.intersection(bounds)
        NSColor.systemRed.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        NSColor.systemRed.setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        border.lineWidth = 2
        border.stroke()

        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.72)
        ]
        label.draw(
            at: CGPoint(x: max(rect.minX, 8), y: min(rect.maxY + 7, bounds.maxY - 22)),
            withAttributes: attributes
        )
    }

    private var selectionRect: CGRect {
        CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }
}
