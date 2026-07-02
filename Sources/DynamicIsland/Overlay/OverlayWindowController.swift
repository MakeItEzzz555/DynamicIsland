import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let settings: AppSettings
    private let islandState: IslandStateStore
    private let geometryService: NotchGeometryService
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []
    private var mouseContainmentTimer: Timer?
    private var frameAnimationTimer: Timer?
    private var targetExpandedFrame: NSRect?

    init(
        settings: AppSettings,
        islandState: IslandStateStore,
        modules: IslandModules,
        geometryService: NotchGeometryService
    ) {
        self.settings = settings
        self.islandState = islandState
        self.geometryService = geometryService

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.sharingType = .readOnly
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let rootView = IslandRootView(
            settings: settings,
            islandState: islandState,
            modules: modules
        )
        let hostingView = IslandHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.onMouseDown = { [weak islandState] in
            guard islandState?.state == .collapsed else { return true }
            islandState?.toggleExpanded()
            return false
        }
        panel.contentView = hostingView

        islandState.$state
            .sink { [weak self] state in
                self?.panel.orderFrontRegardless()
                self?.reposition(animated: true)
                if state == .collapsed {
                    self?.updateMouseContainmentTimer(for: state)
                }
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setVisible(self.settings.overlayEnabled)
                    self.reposition(animated: false)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.reposition(animated: false)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.reposition(animated: false)
            }
            .store(in: &cancellables)
    }

    func show() {
        islandState.collapse()
        reposition(animated: false)
        panel.orderFrontRegardless()
    }

    func setVisible(_ visible: Bool) {
        visible ? show() : panel.orderOut(nil)
        if !visible {
            updateMouseContainmentTimer(for: .collapsed)
        }
    }

    func reposition(animated: Bool = false) {
        let geometry = geometryService.geometry(
            collapsedSize: settings.collapsedSize,
            expandedSize: settings.expandedSize
        )
        let targetFrame = islandState.state == .collapsed ? geometry.collapsedFrame : geometry.expandedFrame
        targetExpandedFrame = geometry.expandedFrame

        if animated {
            animateFrame(to: targetFrame, duration: islandState.state == .expanded ? 0.28 : 0.22)
        } else {
            applyFrame(targetFrame)
            updateMouseContainmentTimer(for: islandState.state)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let correctedGeometry = self.geometryService.geometry(
                collapsedSize: self.settings.collapsedSize,
                expandedSize: self.settings.expandedSize
            )
            let correctedFrame = self.islandState.state == .collapsed ? correctedGeometry.collapsedFrame : correctedGeometry.expandedFrame
            if !animated {
                self.applyFrame(correctedFrame)
            }
        }
    }

    private func animateFrame(to targetFrame: NSRect, duration: TimeInterval) {
        frameAnimationTimer?.invalidate()
        let startFrame = panel.frame
        let startDate = Date()
        let startTop = startFrame.maxY
        let targetTop = targetFrame.maxY
        let startCenterX = startFrame.midX
        let targetCenterX = targetFrame.midX

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                let progress = min(1, Date().timeIntervalSince(startDate) / duration)
                let eased = self.easeInOut(progress)
                let width = startFrame.width + (targetFrame.width - startFrame.width) * eased
                let height = startFrame.height + (targetFrame.height - startFrame.height) * eased
                let centerX = startCenterX + (targetCenterX - startCenterX) * eased
                let top = startTop + (targetTop - startTop) * eased
                let frame = NSRect(
                    x: centerX - width / 2,
                    y: top - height,
                    width: width,
                    height: height
                ).integral
                self.applyFrame(frame)

                if progress >= 1 {
                    self.frameAnimationTimer?.invalidate()
                    self.frameAnimationTimer = nil
                    self.applyFrame(targetFrame)
                    self.updateMouseContainmentTimer(for: self.islandState.state)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameAnimationTimer = timer
    }

    private func easeInOut(_ progress: Double) -> Double {
        progress * progress * (3 - 2 * progress)
    }

    private func applyFrame(_ frame: NSRect) {
        panel.animations.removeAll()
        panel.disableScreenUpdatesUntilFlush()
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        panel.orderFrontRegardless()
    }

    private func updateMouseContainmentTimer(for state: IslandPresentationState) {
        mouseContainmentTimer?.invalidate()
        mouseContainmentTimer = nil

        guard state == .expanded else { return }
        let hitFrame = targetExpandedFrame ?? panel.frame
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.islandState.state == .expanded else { return }
                let expandedHitFrame = hitFrame.insetBy(dx: -8, dy: -8)
                if !expandedHitFrame.contains(NSEvent.mouseLocation) {
                    self.islandState.collapse()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseContainmentTimer = timer
    }
}

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: (() -> Bool)?
    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        if onMouseDown?() ?? true {
            super.mouseDown(with: event)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
