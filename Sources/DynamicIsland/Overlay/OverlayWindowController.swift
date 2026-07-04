import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let expandedHoverTolerance: CGFloat = 2
    private let collapsedHoverTolerance: CGFloat = 4
    private let collapseContentExitDelay: DispatchTimeInterval = .milliseconds(205)
    private let settings: AppSettings
    private let islandState: IslandStateStore
    private let modules: IslandModules
    private let geometryService: NotchGeometryService
    private let layoutStore = IslandLayoutStore()
    private let islandPanel: IslandOverlayPanel
    private var cancellables: Set<AnyCancellable> = []
    private var mouseContainmentTimer: Timer?
    private var localMouseMovedMonitor: Any?
    private var globalMouseMovedMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var targetCollapsedFrame: NSRect?
    private var targetExpandedFrame: NSRect?
    private var visibilityGeneration: Int = 0
    private var morphGeneration: Int = 0
    private var collapseSequenceGeneration: Int = 0
    private var expandedAt: CFTimeInterval = 0
    #if DEBUG
    private var lastCollapseDebugLogAt: CFTimeInterval = 0
    #endif
    private weak var hostingView: IslandHostingView<IslandRootView>?

    init(
        settings: AppSettings,
        islandState: IslandStateStore,
        modules: IslandModules,
        geometryService: NotchGeometryService
    ) {
        self.settings = settings
        self.islandState = islandState
        self.modules = modules
        self.geometryService = geometryService
        #if DEBUG
        debugPrint(
            "DynamicIsland OverlayWindowController init",
            "mediaInstance=\(ObjectIdentifier(modules.media))"
        )
        #endif

        islandPanel = IslandOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        Self.configure(islandPanel)

        let rootView = IslandRootView(
            settings: settings,
            islandState: islandState,
            layoutStore: layoutStore,
            modules: modules,
            rendersExpandedVisualContent: true,
            onRequestExpand: { [weak self] in
                self?.expandFromCollapsedPreparingGeometry()
            },
            onRequestCollapse: { [weak self] in
                self?.requestCollapseWithSequencing()
            }
        )
        let hostingView = IslandHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.onMouseExited = { [weak self] in
            self?.collapseIfExpandedMouseOutsideAfterGrace()
        }
        hostingView.interactiveRegionProvider = { [weak self] in
            self?.currentInteractiveRegion() ?? .zero
        }
        islandPanel.contentView = hostingView
        self.hostingView = hostingView

        islandState.$state
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let state = self.islandState.state
                    self.debugLog("state committed as \(state)")
                    self.debugLog("state changed to \(state)")
                    if state == .expanded {
                        self.layoutStore.isExpandedContentExiting = false
                    }
                    self.beginVisualMorph(for: state)
                    if state == .expanded {
                        self.expandedAt = CACurrentMediaTime()
                        self.debugLog("expandedAt set to \(self.expandedAt)")
                        self.startMouseContainmentTimer()
                    } else {
                        self.stopMouseContainmentTimer()
                    }
                    self.updateWindowVisibility()
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

        modules.media.$hasActiveMediaSource
            .removeDuplicates()
            .sink { [weak self] hasActiveMediaSource in
                DispatchQueue.main.async {
                    #if DEBUG
                    debugPrint(
                        "DynamicIsland Overlay media active changed",
                        "hasActiveMediaSource=\(hasActiveMediaSource)",
                        "mediaInstance=\(ObjectIdentifier(modules.media))"
                    )
                    #endif
                    self?.reposition(animated: true)
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

        installMouseDownMonitors()
    }

    func show() {
        islandState.collapse()
        reposition(animated: false)
        updateWindowVisibility()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else {
            islandPanel.ignoresMouseEvents = true
            islandPanel.orderOut(nil)
        }
        if !visible {
            stopMouseContainmentTimer()
        }
    }

    func reposition(animated: Bool = false) {
        let geometry = geometryService.geometry(
            collapsedSize: settings.collapsedSize,
            expandedSize: settings.expandedSize,
            collapsedMediaActive: modules.media.hasActiveMediaSource
        )
        targetCollapsedFrame = geometry.collapsedFrame
        targetExpandedFrame = geometry.expandedFrame
        updateLayoutWithoutAnimation(
            panelFrame: geometry.expandedFrame,
            collapsedFrame: geometry.collapsedFrame,
            expandedFrame: geometry.expandedFrame,
            hasHardwareNotch: geometry.hasHardwareNotch
        )
        applyFrame(geometry.expandedFrame, to: islandPanel)
        hostingView?.needsLayout = true
        updateWindowVisibility()
        updateMousePassthrough()

        updateMouseContainmentTimer()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let correctedGeometry = self.geometryService.geometry(
                collapsedSize: self.settings.collapsedSize,
                expandedSize: self.settings.expandedSize,
                collapsedMediaActive: self.modules.media.hasActiveMediaSource
            )
            if !animated {
                self.targetCollapsedFrame = correctedGeometry.collapsedFrame
                self.targetExpandedFrame = correctedGeometry.expandedFrame
                self.updateLayoutWithoutAnimation(
                    panelFrame: correctedGeometry.expandedFrame,
                    collapsedFrame: correctedGeometry.collapsedFrame,
                    expandedFrame: correctedGeometry.expandedFrame,
                    hasHardwareNotch: correctedGeometry.hasHardwareNotch
                )
                self.applyFrame(correctedGeometry.expandedFrame, to: self.islandPanel)
                self.hostingView?.needsLayout = true
                self.updateWindowVisibility()
                self.updateMousePassthrough()
            }
        }
    }

    private static func configure(_ panel: IslandOverlayPanel) {
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
        panel.acceptsMouseMovedEvents = true
    }

    private func applyFrame(_ frame: NSRect, to panel: IslandOverlayPanel) {
        guard frame != .zero else { return }
        panel.animations.removeAll()
        panel.disableScreenUpdatesUntilFlush()
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func updateLayoutWithoutAnimation(
        panelFrame: NSRect,
        collapsedFrame: NSRect,
        expandedFrame: NSRect,
        hasHardwareNotch: Bool
    ) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            layoutStore.updateLocal(
                panelFrame: panelFrame,
                collapsedScreenFrame: collapsedFrame,
                expandedScreenFrame: expandedFrame,
                hasHardwareNotch: hasHardwareNotch
            )
        }
    }

    private func updateWindowVisibility() {
        visibilityGeneration += 1

        if islandState.state == .expanded {
            islandPanel.makeKeyAndOrderFront(nil)
            startMouseContainmentTimer()
        } else {
            debugLog("updateWindowVisibility received collapsed")
            islandPanel.orderFrontRegardless()
            stopMouseContainmentTimer()
        }
        updateMousePassthrough()
    }

    private func updateMouseContainmentTimer() {
        switch islandState.state {
        case .collapsed:
            stopMouseContainmentTimer()
        case .expanded:
            startMouseContainmentTimer()
        }
    }

    private func startMouseContainmentTimer() {
        guard mouseContainmentTimer == nil else {
            debugLog("timer start skipped; already running")
            return
        }
        debugLog("timer started")
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.debugLog("timer fired state=\(self?.islandState.state.rawValue ?? "nil") mouse=\(String(describing: self?.currentMouseScreenLocation()))")
                self?.updateMousePassthrough()
                self?.collapseIfExpandedMouseOutsideAfterGrace(source: "timer")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseContainmentTimer = timer
    }

    private func stopMouseContainmentTimer() {
        if mouseContainmentTimer != nil {
            debugLog("timer stopped")
        }
        mouseContainmentTimer?.invalidate()
        mouseContainmentTimer = nil
    }

    private func installMouseDownMonitors() {
        localMouseMovedMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.updateMousePassthrough()
            self?.collapseIfExpandedMouseOutsideAfterGrace(source: "localMouseMonitor")
            return event
        }

        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateMousePassthrough()
                self?.collapseIfExpandedMouseOutsideAfterGrace(source: "globalMouseMonitor")
            }
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == 53, self.islandState.state == .expanded else {
                return event
            }
            self.debugLog("Escape pressed while expanded; requesting sequenced collapse")
            self.requestCollapseWithSequencing()
            return nil
        }
    }

    private func currentMouseScreenLocation() -> NSPoint {
        NSEvent.mouseLocation
    }

    private func collapseIfExpandedMouseOutsideAfterGrace(source: String = "event") {
        debugLog("collapse check entered source=\(source) state=\(islandState.state)")
        guard islandState.state == .expanded else {
            debugLog("collapse check ignored; state is not expanded")
            return
        }
        let elapsedSinceExpansion = CACurrentMediaTime() - expandedAt
        guard elapsedSinceExpansion >= 0.18 else {
            debugLog("collapse check grace failed elapsed=\(elapsedSinceExpansion)")
            return
        }
        debugLog("collapse check grace passed elapsed=\(elapsedSinceExpansion)")

        let mouseLocation = currentMouseScreenLocation()
        let canonicalFrame = visibleExpandedShellScreenFrame()
        let paddedExpandedFrame = canonicalFrame.insetBy(
            dx: -expandedHoverTolerance,
            dy: -expandedHoverTolerance
        )
        let containsMouse = paddedExpandedFrame.contains(mouseLocation)
        logCollapseBoundaryCheck(
            source: source,
            mouseLocation: mouseLocation,
            canonicalFrame: canonicalFrame,
            paddedFrame: paddedExpandedFrame,
            containsMouse: containsMouse
        )
        debugLog("collapse hover contains=\(containsMouse)")

        if source == "timer", isMouseFarBelowTop(mouseLocation) {
            debugLog("timer hard test triggered; mouse is more than 350px below screen top; requesting sequenced collapse")
            updateMousePassthrough(at: mouseLocation)
            requestCollapseWithSequencing()
            return
        }

        if !containsMouse {
            debugLog("mouse outside padded hover rect; requesting sequenced collapse")
            updateMousePassthrough(at: mouseLocation)
            requestCollapseWithSequencing()
        }
    }

    private func isMouseFarBelowTop(_ mouseLocation: NSPoint) -> Bool {
        let screenTop = visibleExpandedShellScreenFrame().maxY
        return screenTop - mouseLocation.y > 350
    }

    private func visibleExpandedShellScreenFrame() -> NSRect {
        let visibleFrame = screenRect(for: layoutStore.expandedSurfaceFrame)
        return visibleFrame.isEmpty ? (targetExpandedFrame ?? islandPanel.frame) : visibleFrame
    }

    private func screenRect(for localRect: CGRect) -> NSRect {
        guard !localRect.isEmpty else { return .zero }
        return NSRect(
            x: islandPanel.frame.minX + localRect.minX,
            y: islandPanel.frame.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        ).integral
    }

    private var currentVisibleIslandScreenRect: NSRect {
        let localRect: CGRect
        let tolerance: CGFloat

        if islandState.state == .expanded || layoutStore.isCollapseShellOnly {
            localRect = layoutStore.expandedSurfaceFrame
            tolerance = expandedHoverTolerance
        } else {
            localRect = layoutStore.collapsedSurfaceFrame
            tolerance = collapsedHoverTolerance
        }

        let visibleRect = screenRect(for: localRect)
        guard !visibleRect.isEmpty else { return .zero }
        return visibleRect.insetBy(dx: -tolerance, dy: -tolerance)
    }

    private func updateMousePassthrough(at screenPoint: NSPoint = NSEvent.mouseLocation) {
        guard settings.overlayEnabled else {
            islandPanel.ignoresMouseEvents = true
            return
        }

        // Window-level passthrough is the primary click-through control. Returning nil from the
        // hosting view hit-test is kept only as a secondary safeguard because the NSPanel itself
        // can still block clicks for other apps when its frame covers the screen.
        let interactiveRect = currentVisibleIslandScreenRect
        let shouldReceiveMouse = !interactiveRect.isEmpty && interactiveRect.contains(screenPoint)
        islandPanel.ignoresMouseEvents = !shouldReceiveMouse
    }

    private func logCollapseBoundaryCheck(
        source: String,
        mouseLocation: NSPoint,
        canonicalFrame: NSRect,
        paddedFrame: NSRect,
        containsMouse: Bool
    ) {
        #if DEBUG
        let now = CACurrentMediaTime()
        guard !containsMouse || now - lastCollapseDebugLogAt >= 0.35 else {
            return
        }
        lastCollapseDebugLogAt = now
        debugPrint(
            "DynamicIsland collapse check",
            "source=\(source)",
            "state=\(islandState.state)",
            "mouseLocation=\(mouseLocation)",
            "islandPanel.frame=\(islandPanel.frame)",
            "targetExpandedFrame=\(String(describing: targetExpandedFrame))",
            "expandedHoverTolerance=\(expandedHoverTolerance)",
            "canonicalFrame=\(canonicalFrame)",
            "paddedFrame=\(paddedFrame)",
            "contains=\(containsMouse)"
        )
        #endif
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        let line = "DynamicIsland DEBUG \(Date()) \(message)"
        debugPrint(line)
        guard let data = "\(line)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/dynamicisland-debug.log")
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
            _ = try? handle.close()
        } else {
            try? data.write(to: url)
        }
        #endif
    }

    private func beginVisualMorph(for state: IslandPresentationState) {
        morphGeneration += 1
        let generation = morphGeneration
        layoutStore.isShellMorphing = true
        layoutStore.isCollapseShellOnly = (state == .collapsed)

        let clearDelay: DispatchTimeInterval = .milliseconds(state == .collapsed ? 340 : 380)
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) { [weak self] in
            guard let self else { return }
            guard generation == self.morphGeneration else { return }
            self.layoutStore.isShellMorphing = false
            self.layoutStore.isCollapseShellOnly = false
            if state == .collapsed {
                self.layoutStore.isExpandedContentExiting = false
            }
            self.updateWindowVisibility()
        }
    }

    private func expandFromCollapsedPreparingGeometry() {
        guard islandState.state == .collapsed else { return }

        let geometry = geometryService.geometry(
            collapsedSize: settings.collapsedSize,
            expandedSize: settings.expandedSize,
            collapsedMediaActive: modules.media.hasActiveMediaSource
        )

        targetCollapsedFrame = geometry.collapsedFrame
        targetExpandedFrame = geometry.expandedFrame

        updateLayoutWithoutAnimation(
            panelFrame: geometry.expandedFrame,
            collapsedFrame: geometry.collapsedFrame,
            expandedFrame: geometry.expandedFrame,
            hasHardwareNotch: geometry.hasHardwareNotch
        )

        applyFrame(geometry.expandedFrame, to: islandPanel)
        islandPanel.orderFrontRegardless()
        hostingView?.needsLayout = true
        updateMousePassthrough()

        islandState.expand()
    }

    private func requestCollapseWithSequencing() {
        guard islandState.state == .expanded else { return }
        guard !layoutStore.isExpandedContentExiting else { return }

        collapseSequenceGeneration += 1
        let generation = collapseSequenceGeneration

        debugLog("requestCollapseWithSequencing started generation=\(generation)")
        stopMouseContainmentTimer()
        layoutStore.isExpandedContentExiting = true
        updateMousePassthrough()

        DispatchQueue.main.asyncAfter(deadline: .now() + collapseContentExitDelay) { [weak self] in
            guard let self else { return }
            guard generation == self.collapseSequenceGeneration else { return }
            guard self.islandState.state == .expanded else { return }
            self.debugLog("requestCollapseWithSequencing committing collapse generation=\(generation)")
            self.islandState.collapse()
        }
    }

    private func currentInteractiveRegion() -> NSRect {
        let baseRegion: NSRect
        let tolerance: CGFloat

        if islandState.state == .expanded || layoutStore.isCollapseShellOnly {
            baseRegion = layoutStore.expandedSurfaceFrame.integral
            tolerance = 2
        } else {
            baseRegion = layoutStore.collapsedSurfaceFrame.integral
            tolerance = 4
        }

        guard !baseRegion.isEmpty else { return .zero }
        return baseRegion.insetBy(dx: -tolerance, dy: -tolerance)
    }
}

private final class IslandOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onMouseExited: (() -> Void)?
    var interactiveRegionProvider: (() -> NSRect)?
    private var trackingAreaReference: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

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

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
        super.mouseExited(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let interactiveRegion = interactiveRegionProvider?(),
           !interactiveRegion.isEmpty,
           !interactiveRegion.contains(point) {
            return nil
        }

        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
