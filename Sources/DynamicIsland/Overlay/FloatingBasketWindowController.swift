import AppKit
import Combine
import SwiftUI

// Source parity: Droppy/FloatingBasketWindowController.swift (borderless
// non-activating panel, all Spaces + full-screen auxiliary, opens centred on
// the pointer, never steals focus during a drag), BasketDragContainer.swift
// (AppKit drop container with NSFilePromiseReceiver), AppKitMotion.swift
// (0.88 → 1 spring-in, 0.95 fade-out). Intentional differences: the panel is
// sized to the visible basket (no 500×600 invisible drop shield), drops are
// accepted only over the surface, and present/dismiss motion runs in SwiftUI
// so it scales around the basket's centre and honours Reduce Motion.

final class BasketPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }
}

/// Drives the SwiftUI present/dismiss transition for one basket window.
@MainActor
final class BasketPresentation: ObservableObject {
    @Published var isShown = false
    @Published var metrics = BasketMetrics()
}

/// One floating panel per basket. Ownership: created and destroyed only by
/// BasketPresenter; it never outlives its BasketState.
@MainActor
final class FloatingBasketWindowController {
    let state: BasketState
    let panel: BasketPanel
    let presentation = BasketPresentation()
    private let dropView = FilePromiseDropNSView()
    private var cancellables: Set<AnyCancellable> = []
    private var resizeWork: DispatchWorkItem?
    private var dismissWork: DispatchWorkItem?

    init(state: BasketState, rootView: (BasketPresentation) -> AnyView) {
        self.state = state
        panel = BasketPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 300, height: 300)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.title = "Basket"

        let hosting = NSHostingView(rootView: rootView(presentation))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: dropView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: dropView.bottomAnchor)
        ])
        panel.contentView = dropView
        dropView.acceptsDropAt = { [weak self] point in
            guard let self else { return false }
            return self.surfaceRect.contains(point)
        }

        Publishers.CombineLatest3(state.$items.map(\.count).removeDuplicates(), state.$isExpanded, state.$layout)
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applySize() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in
                guard let self, self.panel.isVisible else { return }
                self.state.lastOrigin = self.panel.frame.origin
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification, object: panel)
            .sink { [weak self] _ in self?.refreshMetrics() }
            .store(in: &cancellables)
    }

    var dropTarget: FilePromiseDropNSView { dropView }

    private var surfaceSize: CGSize {
        presentation.metrics.surfaceSize(itemCount: state.items.count, isExpanded: state.isExpanded, layout: state.layout)
    }

    private var windowSize: CGSize { presentation.metrics.windowSize(surface: surfaceSize) }

    var surfaceRect: CGRect {
        presentation.metrics.surfaceRect(surface: surfaceSize, windowSize: panel.frame.size)
    }

    private static var screenFrames: [CGRect] { NSScreen.screens.map(\.visibleFrame) }

    // MARK: Presentation

    /// Centres the visible surface on the pointer, clamped to that screen.
    func present(near pointer: CGPoint) {
        refreshMetrics(for: NSScreen.screens.first { $0.frame.contains(pointer) })
        let size = windowSize
        let surface = presentation.metrics.surfaceRect(surface: surfaceSize, windowSize: size)
        let windowCenter = CGPoint(x: pointer.x + size.width / 2 - surface.midX,
                                   y: pointer.y + size.height / 2 - surface.midY)
        show(frame: BasketPlacement.frame(centeredAt: windowCenter, size: size, screens: Self.screenFrames))
    }

    /// Re-shows at the remembered position when its display still exists.
    func presentAtLastPosition(fallback pointer: CGPoint) {
        let size = windowSize
        if let frame = BasketPlacement.restoredFrame(origin: state.lastOrigin, size: size, screens: Self.screenFrames) {
            refreshMetrics(for: NSScreen.screens.first { $0.visibleFrame.intersects(frame) })
            show(frame: frame)
        } else {
            present(near: pointer)
        }
    }

    private func show(frame: CGRect) {
        dismissWork?.cancel()
        dismissWork = nil
        panel.setFrame(frame, display: false)
        state.lastOrigin = frame.origin
        // orderFrontRegardless, never makeKey: no focus stealing mid-drag.
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [presentation] in presentation.isShown = true }
    }

    /// Fades out and orders out; `completion` runs after the motion.
    func dismiss(completion: @escaping () -> Void) {
        guard panel.isVisible else { completion(); return }
        presentation.isShown = false
        let work = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
            completion()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    func bringToFront() {
        guard panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    // MARK: Sizing

    /// Grows immediately (content animates inside), shrinks after the
    /// content animation so nothing clips. Top-centre stays fixed.
    private func applySize() {
        guard panel.isVisible else { return }
        let target = windowSize
        let current = panel.frame
        resizeWork?.cancel()
        let union = CGSize(width: max(target.width, current.width), height: max(target.height, current.height))
        if union != current.size {
            panel.setFrame(BasketPlacement.resized(current, to: union, screens: Self.screenFrames), display: true)
        }
        guard union != target else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.panel.setFrame(BasketPlacement.resized(self.panel.frame, to: self.windowSize, screens: Self.screenFrames), display: true)
        }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func refreshMetrics(for screen: NSScreen? = nil) {
        let metrics = BasketMetrics(display: IslandDisplayMetricsResolver.resolve(screen: screen ?? panel.screen ?? NSScreen.main))
        guard metrics != presentation.metrics else { return }
        presentation.metrics = metrics
        if panel.isVisible { applySize() }
    }
}

/// Root of a basket window: observes the manager only for cross-basket
/// facts (accent identity), so selection in one basket never rebuilds others.
struct FloatingBasketRootView: View {
    @ObservedObject var manager: BasketManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var presentation: BasketPresentation
    let state: BasketState
    let actions: BasketViewActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FloatingBasketView(
            state: state,
            showsAccent: manager.showsAccentIdentity,
            metrics: presentation.metrics,
            actions: actions,
            multiBasketMode: settings.basketMultipleEnabled
        )
        .opacity(presentation.isShown ? 1 : 0)
        .scaleEffect(presentation.isShown || reduceMotion ? 1 : 0.88, anchor: .center)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.16)
                : (presentation.isShown ? .spring(response: 0.3, dampingFraction: 0.78) : .easeIn(duration: 0.2)),
            value: presentation.isShown
        )
        .onHover { state.setHold(.pointer, $0) }
    }
}
