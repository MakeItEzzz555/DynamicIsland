import AppKit
import SwiftUI

/// Three circular actions attached below the expanded island while the
/// File Tray is shown. They drive existing production controllers and
/// report their frame so hover, hit-testing and passthrough include them.
struct FileTrayQuickActionBar: View {
    @ObservedObject var fileShelf: FileShelfStore
    @ObservedObject var backgroundRemoval: BackgroundRemovalController
    let layoutStore: IslandLayoutStore
    let reduceMotion: Bool

    @State private var hovered: FileTrayQuickAction?
    @State private var status: String?
    @State private var statusIsError = false
    @State private var statusGeneration = 0
    @State private var converting = false
    @State private var shareAnchor = SharingAnchorHolder()

    private var targets: FileTrayActionTargets { fileShelf.quickActionTargets }

    var body: some View {
        HStack(spacing: FileTrayQuickActionMetrics.spacing) {
            circle(.removeBackground) { removeBackground() }
            convertCircle
            circle(.share) { share() }
                .background(SharingAnchorView(holder: shareAnchor))
            if let status {
                Text(status)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusIsError ? Color.orange : Color.white.opacity(0.8))
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .transition(.opacity)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FileTrayQuickActionFrameKey.self,
                    value: proxy.frame(in: .named(IslandCanvasCoordinateSpace.name))
                )
            }
        }
        .onPreferenceChange(FileTrayQuickActionFrameKey.self) { frame in
            layoutStore.setExpandedAccessoryFrames([
                IslandCanvasCoordinateSpace.appKitLocalRect(fromSwiftUI: frame, canvasHeight: layoutStore.canvasSize.height)
            ])
        }
        .onDisappear {
            layoutStore.setExpandedAccessoryFrames([])
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: status)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File Tray quick actions")
    }

    // MARK: Circles

    private func circle(_ action: FileTrayQuickAction, perform: @escaping () -> Void) -> some View {
        let availability = targets.availability(of: action)
        return Button(action: perform) {
            circleLabel(action, enabled: availability.isAvailable, busy: action == .removeBackground && backgroundRemoval.isProcessing)
        }
        .buttonStyle(.plain)
        .disabled(!availability.isAvailable)
        .onHover { hovered = $0 ? action : (hovered == action ? nil : hovered) }
        .help(helpText(action, availability))
        .accessibilityLabel(action.title)
        .accessibilityHint(helpText(action, availability))
    }

    private var convertCircle: some View {
        let availability = targets.availability(of: .convert)
        let formats = targets.urls.first.map(FileConversionController.targetFormats(for:)) ?? []
        return Menu {
            ForEach(formats) { format in
                Button("Convert to \(format.displayName)") { convert(to: format) }
            }
        } label: {
            circleLabel(.convert, enabled: availability.isAvailable, busy: converting)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!availability.isAvailable || converting)
        .onHover { hovered = $0 ? .convert : (hovered == .convert ? nil : hovered) }
        .help(helpText(.convert, availability))
        .accessibilityLabel(FileTrayQuickAction.convert.title)
    }

    private func circleLabel(_ action: FileTrayQuickAction, enabled: Bool, busy: Bool) -> some View {
        let isHovered = hovered == action && enabled
        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.92))
            Circle()
                .stroke(Color.white.opacity(isHovered ? 0.28 : 0.12), lineWidth: 1)
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: action.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? (isHovered ? 1 : 0.82) : 0.28))
            }
        }
        .frame(width: FileTrayQuickActionMetrics.diameter, height: FileTrayQuickActionMetrics.diameter)
        .scaleEffect(isHovered && !reduceMotion ? 1.08 : 1)
        .contentShape(Circle())
    }

    private func helpText(_ action: FileTrayQuickAction, _ availability: FileTrayActionTargets.Availability) -> String {
        switch availability {
        case .available:
            let count = targets.urls.count
            return count > 1 ? "\(action.title) \(count) files" : "\(action.title) \(targets.urls.first?.lastPathComponent ?? "")"
        case .unavailable(let reason):
            return reason
        }
    }

    // MARK: Actions

    private func removeBackground() {
        guard let url = targets.urls.first, targets.availability(of: .removeBackground).isAvailable else { return }
        do {
            try backgroundRemoval.process(imageURL: url, addResultToShelfWhenFinished: true)
            show("Removing background…")
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    private func convert(to format: FileConversionFormat) {
        guard let url = targets.urls.first else { return }
        converting = true
        Task { @MainActor in
            defer { converting = false }
            do {
                let output = try await FileConversionController.convert(url, to: format)
                fileShelf.add([output])
                fileShelf.select(output)
                show("Converted to \(format.displayName)")
            } catch {
                show(error.localizedDescription, error: true)
            }
        }
    }

    private func share() {
        let urls = targets.urls
        guard !urls.isEmpty, let view = shareAnchor.view else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private func show(_ message: String, error: Bool = false) {
        statusGeneration += 1
        let token = statusGeneration
        status = message
        statusIsError = error
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if statusGeneration == token { status = nil }
        }
    }
}

struct FileTrayQuickActionFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

/// Holds the AppKit view the system share picker anchors to.
final class SharingAnchorHolder {
    weak var view: NSView?
}

struct SharingAnchorView: NSViewRepresentable {
    let holder: SharingAnchorHolder

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        holder.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        holder.view = nsView
    }
}
