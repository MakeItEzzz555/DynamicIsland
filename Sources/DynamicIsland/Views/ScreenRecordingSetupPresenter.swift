import AppKit
import SwiftUI

/// Where the recorder setup should appear: the island's current screen and
/// the island's visible shell frame, both in AppKit screen coordinates.
struct ScreenRecordingSetupAnchor: Equatable {
    let screenVisibleFrame: CGRect
    let islandFrame: CGRect
}

/// Places the setup surface centered under the island on the island's
/// screen, never over the island and never off the screen.
enum ScreenRecordingSetupPlacement {
    static let gapBelowIsland: CGFloat = 10
    static let screenMargin: CGFloat = 8

    static func frame(contentSize: CGSize, anchor: ScreenRecordingSetupAnchor) -> CGRect {
        let bounds = anchor.screenVisibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let width = min(max(contentSize.width, 1), bounds.width)
        let height = min(max(contentSize.height, 1), bounds.height)
        let x = min(max(anchor.islandFrame.midX - width / 2, bounds.minX), bounds.maxX - width)
        let top = min(anchor.islandFrame.minY - gapBelowIsland, bounds.maxY)
        let y = max(top - height, bounds.minY)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
    }
}

/// A window that shows the recorder setup. Production uses an owned NSPanel;
/// tests use a fake to verify presentation lifecycle deterministically.
@MainActor
protocol ScreenRecordingSetupSurface: AnyObject {
    var isVisible: Bool { get }
    var fittingSize: CGSize { get }
    /// Called when the surface closes itself (close button, Esc).
    var onUserClose: (() -> Void)? { get set }
    func show(frame: CGRect)
    func close()
}

/// Owns the recorder setup presentation outside the island's SwiftUI tree,
/// so island collapse, page switches and re-renders cannot dismiss it, and
/// repeated tile clicks reuse the single surface.
///
/// A SwiftUI `.sheet` from the tile was the previous presenter: AppKit
/// attached it over the island inside the top-pinned overlay panel (pushing
/// that panel off the screen top) and the tile's @State died with every
/// island collapse, taking the sheet with it.
@MainActor
final class ScreenRecordingSetupPresenter: ObservableObject {
    @Published private(set) var isPresented = false

    var anchorProvider: () -> ScreenRecordingSetupAnchor?
    private let makeSurface: () -> ScreenRecordingSetupSurface
    private var surface: ScreenRecordingSetupSurface?

    init(
        makeSurface: @escaping () -> ScreenRecordingSetupSurface,
        anchorProvider: @escaping () -> ScreenRecordingSetupAnchor? = { nil }
    ) {
        self.makeSurface = makeSurface
        self.anchorProvider = anchorProvider
    }

    static func production(
        controller: ScreenRecordingController,
        anchorProvider: @escaping () -> ScreenRecordingSetupAnchor? = { nil }
    ) -> ScreenRecordingSetupPresenter {
        ScreenRecordingSetupPresenter(
            makeSurface: { ScreenRecordingSetupPanelSurface(controller: controller) },
            anchorProvider: anchorProvider
        )
    }

    /// Shows the setup (or brings the existing one forward). Never starts a
    /// recording and never requests permission by itself.
    func present() {
        let surface = self.surface ?? makeSurface()
        if self.surface == nil {
            surface.onUserClose = { [weak self] in self?.isPresented = false }
            self.surface = surface
        }
        let anchor = anchorProvider() ?? Self.fallbackAnchor()
        surface.show(frame: ScreenRecordingSetupPlacement.frame(contentSize: surface.fittingSize, anchor: anchor))
        isPresented = true
    }

    func dismiss() {
        surface?.close()
        isPresented = false
    }

    private static func fallbackAnchor() -> ScreenRecordingSetupAnchor {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = screen?.visibleFrame ?? frame
        return ScreenRecordingSetupAnchor(
            screenVisibleFrame: visible,
            islandFrame: CGRect(x: frame.midX - 100, y: visible.maxY, width: 200, height: frame.maxY - visible.maxY)
        )
    }
}

/// Production surface: a dedicated non-activating panel above the island
/// hosting the production ScreenRecordingSetupView. The frontmost app keeps
/// focus; closing orders the panel out (it is reused, never released).
@MainActor
final class ScreenRecordingSetupPanelSurface: ScreenRecordingSetupSurface {
    var onUserClose: (() -> Void)?

    private let controller: ScreenRecordingController
    private let panel: ScreenRecordingSetupPanel
    private let hostingView: NSHostingView<AnyView>

    init(controller: ScreenRecordingController) {
        self.controller = controller
        panel = ScreenRecordingSetupPanel(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        // Above the island (status bar level) but below the area selector.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.contentView = hostingView
        panel.onCancel = { [weak self] in self?.closeFromUser() }
        updateRootView(metrics: .fallback)
    }

    var isVisible: Bool { panel.isVisible }

    var fittingSize: CGSize { hostingView.fittingSize }

    func show(frame: CGRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        updateRootView(metrics: IslandDisplayMetricsResolver.resolve(screen: screen))
        let size = hostingView.fittingSize
        let sized = CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
        panel.pinnedTopY = frame.maxY
        panel.setFrame(sized, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        panel.orderOut(nil)
    }

    private func closeFromUser() {
        close()
        onUserClose?()
    }

    private func updateRootView(metrics: ResolvedIslandMetrics) {
        hostingView.rootView = AnyView(
            ScreenRecordingSetupView(controller: controller, onClose: { [weak self] in self?.closeFromUser() })
                .environment(\.islandDisplayMetrics, metrics)
        )
    }
}

/// Keeps its top edge fixed while SwiftUI resizes it (setup → active
/// controls), so the surface grows downward away from the island.
final class ScreenRecordingSetupPanel: NSPanel {
    var pinnedTopY: CGFloat?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if let pinnedTopY {
            rect.origin.y = pinnedTopY - rect.height
        }
        super.setFrame(rect, display: flag)
    }
}
