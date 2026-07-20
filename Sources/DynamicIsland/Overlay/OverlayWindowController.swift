import AppKit
import Combine
import QuartzCore
import SwiftUI

struct OverlayGeometrySignature: Equatable, CustomStringConvertible {
    let collapsedSize: CGSize
    let expandedSize: CGSize
    let collapsedHasActiveContent: Bool
    let useAdaptiveNotchSizing: Bool
    let respectHardwareNotch: Bool

    var description: String {
        "collapsedSize=\(collapsedSize) expandedSize=\(expandedSize) collapsedHasActiveContent=\(collapsedHasActiveContent) useAdaptiveNotchSizing=\(useAdaptiveNotchSizing) respectHardwareNotch=\(respectHardwareNotch)"
    }
}

@MainActor
final class OverlayWindowController {
    private enum OverlayPersistence {
        static let level: NSWindow.Level = .statusBar

        static let collectionBehavior: NSWindow.CollectionBehavior = [
            .fullScreenAuxiliary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
    }

    private let expandedHoverTolerance: CGFloat = 2
    private let collapsedHoverTolerance: CGFloat = 4
    private let collapsedScrollBaseThreshold: CGFloat = 8
    private let collapsedScrollQuietResetDelay: TimeInterval = 0.28
    private let mediaSwipeQuietPeriod: TimeInterval = 0.045
    private let mediaSwipePostCommandLockoutSeconds: TimeInterval = 0.60
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
    private var localScrollWheelMonitor: Any?
    private var globalScrollWheelMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var targetCollapsedFrame: NSRect?
    private var targetExpandedFrame: NSRect?
    private var lastAppliedGeometrySignature: OverlayGeometrySignature?
    private var canonicalPanelFrame: NSRect = .zero
    private var lastOrderedVisibilityState: IslandPresentationState?
    private var lastOverlayEnabled: Bool
    private var visibilityGeneration: Int = 0
    private var morphGeneration: Int = 0
    private var collapseSequenceGeneration: Int = 0
    private var expandedAt: CFTimeInterval = 0
    private var collapsedScrollDelta: CGSize = .zero
    private var collapsedScrollGestureHandled = false
    private var collapsedScrollLastActionAt: CFTimeInterval?
    private var expandedScrollDelta: CGSize = .zero
    private var expandedScrollGestureHandled = false
    private var expandedScrollLastActionAt: CFTimeInterval?
    private var expandedScrollGestureResetWorkItem: DispatchWorkItem?
    private var collapsedScrollGestureResetWorkItem: DispatchWorkItem?
    private var mediaSwipeSessionActive = false
    private var mediaSwipeAccumulatedX: CGFloat = 0
    private var mediaSwipeAccumulatedY: CGFloat = 0
    private var mediaSwipeStartedAt: Date?
    private var mediaSwipeLastEventAt: Date?
    private var mediaSwipeFinishWorkItem: DispatchWorkItem?
    private var mediaSwipeCommandInFlight = false
    private var mediaSwipeLockedUntil: Date = .distantPast
    private var mediaSwipeUnlockWorkItem: DispatchWorkItem?
    private var expandedScrollLockedUntil: Date = .distantPast
    #if DEBUG
    private var lastCollapseDebugLogAt: CFTimeInterval = 0
    private var didLogAtollParityConfiguration = false
    #endif
    private weak var hostingView: IslandHostingView<IslandRootView>?

    init(
        settings: AppSettings,
        islandState: IslandStateStore,
        modules: IslandModules,
        geometryService: NotchGeometryService,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.islandState = islandState
        self.modules = modules
        self.geometryService = geometryService
        self.lastOverlayEnabled = settings.overlayEnabled
        #if DEBUG
        debugPrint(
            "DynamicIsland OverlayWindowController init",
            "mediaInstance=\(ObjectIdentifier(modules.media))"
        )
        #endif

        islandPanel = IslandOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
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
            },
            onOpenSettings: onOpenSettings
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
        hostingView.collapsedScrollGestureRegionProvider = { [weak self] in
            self?.currentCollapsedGestureRegion() ?? .zero
        }
        hostingView.onCollapsedScrollWheel = { [weak self] event, localPoint in
            self?.handleIslandScrollWheel(event, localPoint: localPoint, source: "hostingView") ?? false
        }
        islandPanel.contentView = hostingView
        self.hostingView = hostingView
        debugGesture("Island hosting view installed")

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
                    let overlayEnabled = self.settings.overlayEnabled
                    if overlayEnabled != self.lastOverlayEnabled {
                        self.lastOverlayEnabled = overlayEnabled
                        self.setVisible(overlayEnabled)
                    } else {
                        self.reposition(animated: false, reason: "settingsChanged")
                    }
                }
            }
            .store(in: &cancellables)

        layoutStore.$collapsedPreviewActive
            .combineLatest(layoutStore.$collapsedPreviewSurfaceFrame)
            .sink { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.updateMousePassthrough()
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
                    self?.reposition(animated: true, reason: "mediaActiveChanged")
                }
            }
            .store(in: &cancellables)

        modules.liveActivities.$activities
            .map { [weak self] activities in
                self?.collapsedHasActiveContent(activities: activities) ?? false
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.reposition(animated: true, reason: "collapsedActivityPresenceChanged")
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.debugOverlayPersistence("screen parameters changed")
                self?.reposition(animated: false, reason: "screenParametersChanged", force: true)
            }
            .store(in: &cancellables)

        installMouseDownMonitors()
    }

    func show() {
        islandState.collapse()
        reposition(animated: false, reason: "initialShow", force: true)
        updateWindowVisibility()
        logAtollParityConfigurationIfNeeded()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else {
            debugOverlayWindowState(reason: "ORDERING OUT reason=overlayDisabled before")
            islandPanel.ignoresMouseEvents = true
            debugOverlayWindowOperation(operation: "orderOut", reason: "overlayDisabled")
            islandPanel.orderOut(nil)
            lastOrderedVisibilityState = nil
            debugOverlayWindowState(reason: "ORDERING OUT reason=overlayDisabled after")
        }
        if !visible {
            stopMouseContainmentTimer()
        }
    }

    func reposition(animated: Bool = false, reason: String = "unspecified", force: Bool = false) {
        let signature = currentGeometrySignature
        guard force || signature != lastAppliedGeometrySignature else {
            #if DEBUG
            debugPrint(
                "[OverlayGeometry]",
                "skipped duplicate reposition",
                "reason=\(reason)"
            )
            #endif
            return
        }

        let geometry = geometryService.geometry(
            collapsedSize: settings.collapsedSize,
            expandedSize: settings.expandedSize,
            collapsedMediaActive: collapsedHasActiveContent,
            useAdaptiveNotchSizing: settings.useAdaptiveNotchSizing,
            respectHardwareNotch: settings.respectHardwareNotch
        )
        debugGeometryRefresh(geometry)
        targetCollapsedFrame = geometry.collapsedFrame
        targetExpandedFrame = geometry.expandedFrame
        updateLayoutWithoutAnimation(
            panelFrame: geometry.expandedFrame,
            collapsedFrame: geometry.collapsedFrame,
            expandedFrame: geometry.expandedFrame,
            hasHardwareNotch: geometry.hasHardwareNotch
        )
        applyCanonicalPanelFrame(geometry.expandedFrame, reason: "\(reason) initial animated=\(animated)")
        lastAppliedGeometrySignature = signature
        hostingView?.needsLayout = true
        updateWindowVisibility()
        updateMousePassthrough()

        updateMouseContainmentTimer()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let correctedSignature = self.currentGeometrySignature
            guard force || correctedSignature != self.lastAppliedGeometrySignature else {
                return
            }
            let correctedGeometry = self.geometryService.geometry(
                collapsedSize: self.settings.collapsedSize,
                expandedSize: self.settings.expandedSize,
                collapsedMediaActive: self.collapsedHasActiveContent,
                useAdaptiveNotchSizing: self.settings.useAdaptiveNotchSizing,
                respectHardwareNotch: self.settings.respectHardwareNotch
            )
            if !animated {
                self.debugGeometryRefresh(correctedGeometry)
                self.targetCollapsedFrame = correctedGeometry.collapsedFrame
                self.targetExpandedFrame = correctedGeometry.expandedFrame
                self.updateLayoutWithoutAnimation(
                    panelFrame: correctedGeometry.expandedFrame,
                    collapsedFrame: correctedGeometry.collapsedFrame,
                    expandedFrame: correctedGeometry.expandedFrame,
                    hasHardwareNotch: correctedGeometry.hasHardwareNotch
                )
                self.applyCanonicalPanelFrame(
                    correctedGeometry.expandedFrame,
                    reason: "\(reason) corrected animated=\(animated)"
                )
                self.lastAppliedGeometrySignature = correctedSignature
                self.hostingView?.needsLayout = true
                self.updateWindowVisibility()
                self.updateMousePassthrough()
            }
        }
    }

    private var collapsedHasActiveContent: Bool {
        collapsedContentMode != .inactive
    }

    private func collapsedHasActiveContent(activities: [DynamicIslandLiveActivity]) -> Bool {
        collapsedContentMode(activities: activities) != .inactive
    }

    private var collapsedContentMode: CollapsedIslandContentMode {
        collapsedContentMode(activities: modules.liveActivities.activities)
    }

    private func collapsedContentMode(activities: [DynamicIslandLiveActivity]) -> CollapsedIslandContentMode {
        CollapsedLiveActivitySelector.select(
            activities: activities,
            priorities: settings.collapsedLiveActivityPrioritySettings,
            toggles: CollapsedLiveActivitySourceToggles(
                liveActivitiesEnabled: settings.liveActivitiesEnabled,
                timerEnabled: settings.timerEnabled && settings.showTimerLiveActivity,
                mediaEnabled: settings.mediaEnabled &&
                    settings.showMusicLiveActivity &&
                    (settings.showMediaWhenPaused || modules.media.isPlaying),
                fileTrayEnabled: settings.trayEnabled &&
                    settings.fileShelfEnabled &&
                    settings.showFileDropLiveActivity,
                batteryEnabled: settings.showBatteryLiveActivity
            )
        )
    }

    private var currentGeometrySignature: OverlayGeometrySignature {
        OverlayGeometrySignature(
            collapsedSize: settings.collapsedSize,
            expandedSize: settings.expandedSize,
            collapsedHasActiveContent: collapsedHasActiveContent,
            useAdaptiveNotchSizing: settings.useAdaptiveNotchSizing,
            respectHardwareNotch: settings.respectHardwareNotch
        )
    }

    private static func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.level = OverlayPersistence.level
        panel.collectionBehavior = OverlayPersistence.collectionBehavior
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.sharingType = .readOnly
        panel.isReleasedWhenClosed = false
        panel.canHide = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true

        #if DEBUG
        debugPrint(
            "[OverlayPersistence] configure",
            "level=\(panel.level.rawValue)",
            "collectionBehavior=\(panel.collectionBehavior.rawValue)",
            "behavior.canJoinAllSpaces=\(panel.collectionBehavior.contains(.canJoinAllSpaces))",
            "behavior.fullScreenAuxiliary=\(panel.collectionBehavior.contains(.fullScreenAuxiliary))",
            "behavior.stationary=\(panel.collectionBehavior.contains(.stationary))",
            "behavior.auxiliary=\(panel.collectionBehavior.contains(.auxiliary))"
        )
        #endif
    }

    private func applyCanonicalPanelFrame(_ frame: NSRect, reason: String) {
        guard frame != .zero else { return }
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.size.width.isFinite,
              frame.size.height.isFinite,
              frame.size.width > 0,
              frame.size.height > 0 else {
            return
        }

        canonicalPanelFrame = frame
        applyPhysicalPanelFrame(frame, reason: reason)
        islandPanel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        lastOrderedVisibilityState = nil
    }

    private func applyPhysicalPanelFrame(_ frame: NSRect, reason: String) {
        guard frame != .zero else { return }
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.size.width.isFinite,
              frame.size.height.isFinite,
              frame.size.width > 0,
              frame.size.height > 0 else {
            return
        }

        guard !framesAreApproximatelyEqual(
            frame,
            islandPanel.frame,
            tolerance: 0.35
        ) else {
            return
        }

        islandPanel.animations.removeAll()
        islandPanel.disableScreenUpdatesUntilFlush()
        debugOverlayWindowOperation(operation: "setFrame", reason: reason)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            islandPanel.setFrame(frame, display: true)
        }
    }

    private func framesAreApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect, tolerance: CGFloat) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.size.width - rhs.size.width) <= tolerance &&
            abs(lhs.size.height - rhs.size.height) <= tolerance
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
        if !islandPanel.isVisible {
            debugOverlayWindowOperation(
                operation: "orderFrontRegardless",
                reason: "updateWindowVisibility initial order generation=\(visibilityGeneration)"
            )
            islandPanel.orderFrontRegardless()
        }
        lastOrderedVisibilityState = islandState.state
        updateMousePassthrough()
        updateMouseContainmentTimer()
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

        localScrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
    guard let self else { return event }

    self.debugScrollWheelReceived(event, source: "localScrollMonitor")
    if self.handleExpandedScrollWheelFromMonitor(event, source: "localScrollMonitor") {
        return nil
    }

    if event.window === self.islandPanel {
        return event
    }

    if self.handleCollapsedScrollWheelFromMonitor(event, source: "localScrollMonitor") {
        return nil
    }

    return event
}

globalScrollWheelMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
    Task { @MainActor in
        guard let self else { return }

        self.debugScrollWheelReceived(event, source: "globalScrollMonitor")
        if self.handleExpandedScrollWheelFromMonitor(event, source: "globalScrollMonitor") {
            return
        }

        _ = self.handleCollapsedScrollWheelFromMonitor(event, source: "globalScrollMonitor")
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
        guard settings.collapseOnMouseLeave, settings.autoCollapseEnabled else {
            debugLog("collapse check ignored; auto collapse disabled")
            return
        }
        let elapsedSinceExpansion = CACurrentMediaTime() - expandedAt
        guard elapsedSinceExpansion >= settings.effectiveAutoCollapseGraceSeconds else {
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
        let referenceFrame = visualReferencePanelFrame
        return NSRect(
            x: referenceFrame.minX + localRect.minX,
            y: referenceFrame.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        ).integral
    }

    private var visualReferencePanelFrame: NSRect {
        canonicalPanelFrame.isEmpty ? islandPanel.frame : canonicalPanelFrame
    }

    private var currentVisibleIslandScreenRect: NSRect {
        let localRect: CGRect
        let tolerance: CGFloat

        if islandState.state == .expanded || layoutStore.isCollapseShellOnly {
            localRect = layoutStore.expandedSurfaceFrame
            tolerance = expandedHoverTolerance
        } else {
            localRect = collapsedInteractiveSurfaceFrame
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

    private func debugGeometryRefresh(_ geometry: IslandGeometry) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" else { return }
        debugPrint(
            "DynamicIsland geometry refresh",
            "collapsedSize=\(settings.collapsedSize)",
            "expandedSize=\(settings.expandedSize)",
            "collapsedFrame=\(geometry.collapsedFrame)",
            "expandedFrame=\(geometry.expandedFrame)",
            "panelFrame=\(geometry.expandedFrame)",
            "canvasSize=\(geometry.canvas.frame.size)",
            "useAdaptiveNotchSizing=\(settings.useAdaptiveNotchSizing)",
            "respectHardwareNotch=\(settings.respectHardwareNotch)"
        )
        #endif
    }

    private func beginVisualMorph(for state: IslandPresentationState) {
        morphGeneration += 1
        let generation = morphGeneration
        layoutStore.isShellMorphing = true
        layoutStore.isCollapseShellOnly = (state == .collapsed)

        let shellDuration = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: false
        )
        let clearDelay = shellDuration + (state == .collapsed ? 0.025 : 0)
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
            collapsedMediaActive: collapsedHasActiveContent,
            useAdaptiveNotchSizing: settings.useAdaptiveNotchSizing,
            respectHardwareNotch: settings.respectHardwareNotch
        )

        debugGeometryRefresh(geometry)
        targetCollapsedFrame = geometry.collapsedFrame
        targetExpandedFrame = geometry.expandedFrame

        updateLayoutWithoutAnimation(
            panelFrame: geometry.expandedFrame,
            collapsedFrame: geometry.collapsedFrame,
            expandedFrame: geometry.expandedFrame,
            hasHardwareNotch: geometry.hasHardwareNotch
        )

        applyCanonicalPanelFrame(geometry.expandedFrame, reason: "expandFromCollapsedPreparingGeometry")
        lastAppliedGeometrySignature = currentGeometrySignature
        debugOverlayWindowOperation(operation: "orderFrontRegardless", reason: "expandFromCollapsedPreparingGeometry")
        islandPanel.orderFrontRegardless()
        lastOrderedVisibilityState = islandState.state
        hostingView?.needsLayout = true
        updateMousePassthrough()

        islandState.expand()
    }

    private func requestCollapseWithSequencing() {
        guard islandState.state == .expanded else { return }
        guard !layoutStore.isExpandedContentExiting else { return }

        collapseSequenceGeneration += 1
        let generation = collapseSequenceGeneration
        let shellDuration = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: false
        )
        let collapseShellDelay = IslandContentTransitionTiming.collapseShellDelay(
            shellDuration: shellDuration
        )
        debugLog("requestCollapseWithSequencing started generation=\(generation)")
        stopMouseContainmentTimer()
        layoutStore.isExpandedContentExiting = true
        updateMousePassthrough()

        DispatchQueue.main.asyncAfter(deadline: .now() + collapseShellDelay) { [weak self] in
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
            baseRegion = collapsedInteractiveSurfaceFrame.integral
            tolerance = 4
        }

        guard !baseRegion.isEmpty else { return .zero }
        return baseRegion.insetBy(dx: -tolerance, dy: -tolerance)
    }

    private var collapsedInteractiveSurfaceFrame: CGRect {
        if layoutStore.collapsedPreviewActive,
           !layoutStore.collapsedPreviewSurfaceFrame.isEmpty {
            return layoutStore.collapsedPreviewSurfaceFrame
        }
        return layoutStore.collapsedSurfaceFrame
    }

    private var collapsedGestureCandidateRegion: NSRect {
        collapsedInteractiveSurfaceFrame.integral
    }

    private var collapsedGestureCandidateScreenRegion: NSRect {
        let localRect = collapsedInteractiveSurfaceFrame
        let screenFrame = screenRect(for: localRect)
        guard !screenFrame.isEmpty else { return .zero }
        return screenFrame.insetBy(dx: -8, dy: -8)
    }

    private func currentCollapsedGestureRegion() -> NSRect {
        guard islandState.state == .collapsed,
              !layoutStore.isShellMorphing,
              !layoutStore.isCollapseShellOnly,
              !layoutStore.isExpandedContentExiting,
              !modules.navigation.isFileDropTargeted else {
            return .zero
        }
        return collapsedGestureCandidateRegion
    }

    private func handleIslandScrollWheelFromMonitor(_ event: NSEvent, source: String) -> Bool {
        switch islandState.state {
        case .collapsed:
            return handleCollapsedScrollWheelFromMonitor(event, source: source)
        case .expanded:
            return handleExpandedScrollWheelFromMonitor(event, source: source)
        }
    }

    private func handleIslandScrollWheel(_ event: NSEvent, localPoint: NSPoint, source: String) -> Bool {
        switch islandState.state {
        case .collapsed:
            return handleCollapsedScrollWheel(event, localPoint: localPoint, source: source)
        case .expanded:
            return handleExpandedScrollWheel(event, source: source)
        }
    }

    private func handleExpandedScrollWheelFromMonitor(_ event: NSEvent, source: String) -> Bool {
        guard settings.gesturesEnabled,
              settings.gestureInputSource == .trackpad,
              islandState.state == .expanded,
              !layoutStore.isShellMorphing,
              !layoutStore.isCollapseShellOnly,
              !layoutStore.isExpandedContentExiting else {
            resetExpandedScrollTrackingIfNeeded(for: event)
            return false
        }

        let screenPoint = NSEvent.mouseLocation
        let hitFrame = visibleExpandedShellScreenFrame().insetBy(dx: -8, dy: -8)
        guard !hitFrame.isEmpty, hitFrame.contains(screenPoint) else {
            resetExpandedScrollTrackingIfNeeded(for: event)
            return false
        }

        updateMousePassthrough(at: screenPoint)
        return handleExpandedScrollWheel(event, source: source)
    }

    private func handleExpandedScrollWheel(_ event: NSEvent, source: String) -> Bool {
        guard settings.gesturesEnabled,
              settings.gestureInputSource == .trackpad,
              islandState.state == .expanded,
              event.hasPreciseScrollingDeltas,
              abs(event.scrollingDeltaX) > 0 || abs(event.scrollingDeltaY) > 0 else {
            resetExpandedScrollTrackingIfNeeded(for: event)
            return false
        }

        // Prevent the momentum/tail of the collapsed swipe-down expansion gesture
        // from being interpreted immediately as an expanded swipe-up collapse before
        // the expanded content has appeared.
        guard CACurrentMediaTime() - expandedAt >= 0.42 else {
            resetExpandedScrollTracking()
            debugGesture("expanded scroll blocked reason=recent-expansion-tail source=\(source)")
            return true
        }

        guard expandedScrollCooldownAllowsAction() else {
            return true
        }

        scheduleExpandedScrollGestureReset()

        expandedScrollDelta.width += event.scrollingDeltaX
        expandedScrollDelta.height += event.scrollingDeltaY

        guard !expandedScrollGestureHandled,
              let gesture = collapsedScrollGesture(from: expandedScrollDelta) else {
            return true
        }

        var action = expandedAction(for: gesture)
        if gesture == .swipeUp, action == .none {
            debugGesture("expanded swipe up fallback collapse because saved action is none")
            action = .collapse
        }
        debugGesture("expanded scroll resolved gesture=\(gesture.rawValue) action=\(action.rawValue) source=\(source)")

        guard !settings.requireGestureConfirmation else {
            debugGesture("expanded scroll blocked reason=require-confirmation")
            return true
        }

        switch action {
        case .collapse:
            requestCollapseWithSequencing()
            expandedScrollGestureHandled = true
            expandedScrollLastActionAt = CACurrentMediaTime()
            expandedScrollDelta = .zero
            return true
        case .toggleExpanded:
            requestCollapseWithSequencing()
            expandedScrollGestureHandled = true
            expandedScrollLastActionAt = CACurrentMediaTime()
            expandedScrollDelta = .zero
            return true
        case .nextTab:
            guard settings.nextTabGestureEnabled else { return true }
            modules.navigation.selectNextPage(using: settings)
            expandedScrollGestureHandled = true
            expandedScrollLastActionAt = CACurrentMediaTime()
            expandedScrollDelta = .zero
            return true
        case .previousTab:
            guard settings.previousTabGestureEnabled else { return true }
            modules.navigation.selectPreviousPage(using: settings)
            expandedScrollGestureHandled = true
            expandedScrollLastActionAt = CACurrentMediaTime()
            expandedScrollDelta = .zero
            return true
        case .mediaPlayPause:
            guard settings.mediaEnabled,
                  settings.mediaPlayPauseGestureEnabled,
                  modules.media.isTransportControlAvailable else { return true }
            modules.media.playPause()
            expandedScrollGestureHandled = true
            expandedScrollLastActionAt = CACurrentMediaTime()
            expandedScrollDelta = .zero
            return true
        case .timerStartStop:
            guard settings.timerEnabled,
                  settings.timerStartStopGestureEnabled else { return true }
            if modules.timer.isRunning {
                modules.timer.pause()
            } else if modules.timer.remainingSeconds > 0 {
                modules.timer.resume()
            }
            expandedScrollGestureHandled = true
            expandedScrollLastActionAt = CACurrentMediaTime()
            expandedScrollDelta = .zero
            return true
        case .mediaNextTrack:
            guard settings.mediaEnabled,
                  modules.media.isTransportControlAvailable else { return true }
            modules.media.requestGestureArtworkFlip(direction: .next)
            modules.media.nextTrack()
            scheduleMediaRefreshAfterTransportGesture(reason: "expandedGestureNext")
            expandedScrollGestureHandled = true
            expandedScrollLastActionAt = CACurrentMediaTime()
            expandedScrollDelta = .zero
            return true
        case .mediaPreviousTrack:
            guard settings.mediaEnabled,
                  modules.media.isTransportControlAvailable else { return true }
            modules.media.requestGestureArtworkFlip(direction: .previous)
            modules.media.previousTrack()
            scheduleMediaRefreshAfterTransportGesture(reason: "expandedGesturePrevious")
            expandedScrollGestureHandled = true
            expandedScrollLastActionAt = CACurrentMediaTime()
            expandedScrollDelta = .zero
            return true
        case .openSettings:
            onOpenSettingsFromGesture()
            expandedScrollGestureHandled = true
            expandedScrollLastActionAt = CACurrentMediaTime()
            expandedScrollDelta = .zero
            return true
        case .expand, .none:
            return true
        }
    }

    private func expandedAction(for gesture: IslandPointerGesture) -> IslandGestureAction {
        switch gesture {
        case .swipeLeft:
            return settings.expandedSwipeLeftAction
        case .swipeRight:
            return settings.expandedSwipeRightAction
        case .swipeDown:
            return settings.expandedSwipeDownAction
        case .swipeUp:
            return settings.expandedSwipeUpAction
        case .doubleClick:
            return settings.expandedDoubleClickAction
        case .longPress:
            return settings.expandedLongPressAction
        }
    }

    private func onOpenSettingsFromGesture() {
        // OverlayWindowController does not own the settings window callback directly outside IslandRootView.
        // Keep this as a no-op safety fallback for scroll gestures; long press in SwiftUI still opens Settings.
        debugGesture("expanded scroll openSettings ignored: no overlay callback owner")
    }

    private func expandedScrollCooldownAllowsAction() -> Bool {
        guard let expandedScrollLastActionAt else { return true }
        return CACurrentMediaTime() - expandedScrollLastActionAt >= settings.gestureCooldownSeconds
    }

    private func resetExpandedScrollTrackingIfNeeded(for event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.phase.contains(.began) {
            resetExpandedScrollTracking()
        }
    }

    private func resetExpandedScrollTracking() {
        expandedScrollGestureResetWorkItem?.cancel()
        expandedScrollGestureResetWorkItem = nil
        expandedScrollDelta = .zero
        expandedScrollGestureHandled = false
    }

    private func scheduleExpandedScrollGestureReset() {
        expandedScrollGestureResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.expandedScrollDelta = .zero
                self?.expandedScrollGestureHandled = false
                self?.expandedScrollGestureResetWorkItem = nil
                self?.debugGesture("expanded scroll quiet reset fired")
            }
        }
        expandedScrollGestureResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: workItem)
    }

    private func handleCollapsedScrollWheelFromMonitor(_ event: NSEvent, source: String) -> Bool {
        debugGesture("entering collapsed scroll handler source=\(source)")
        logCollapsedScrollSettingsAndState()
        debugCollapsedScrollRegion(screenPoint: NSEvent.mouseLocation)

        guard settings.gesturesEnabled,
              settings.gestureInputSource == .trackpad,
              islandState.state == .collapsed,
              !layoutStore.isShellMorphing,
              !layoutStore.isCollapseShellOnly,
              !layoutStore.isExpandedContentExiting,
              !modules.navigation.isFileDropTargeted else {
            debugGesture("blocked reason=settings-or-state source=\(source)")
            resetCollapsedScrollTrackingIfNeeded(for: event)
            return false
        }

        let screenPoint = NSEvent.mouseLocation
        let hitResult = collapsedScrollScreenHitResult(screenPoint: screenPoint)
        debugCollapsedScrollRegion(screenPoint: screenPoint, hitResult: hitResult)

        guard hitResult.inside else {
            debugGesture("blocked reason=outside-collapsed-region source=\(source)")
            resetCollapsedScrollTrackingIfNeeded(for: event)
            return false
        }

        updateMousePassthrough(at: screenPoint)
        return handleCollapsedScrollWheel(event, localPoint: hitResult.localPoint, source: source)
    }

    private func handleCollapsedScrollWheel(_ event: NSEvent, localPoint: NSPoint, source: String) -> Bool {
        debugGesture("entering collapsed scroll handler source=\(source)")
        debugScrollWheelReceived(event, source: source)
        logCollapsedScrollSettingsAndState()

        guard settings.gesturesEnabled else {
            debugGesture("blocked reason=gestures-disabled")
            resetCollapsedScrollTrackingIfNeeded(for: event)
            return false
        }
        guard settings.gestureInputSource == .trackpad else {
            debugGesture("blocked reason=input-source-\(settings.gestureInputSource.rawValue)")
            resetCollapsedScrollTrackingIfNeeded(for: event)
            return false
        }
        guard islandState.state == .collapsed else {
            debugGesture("blocked reason=state-\(islandState.state.rawValue)")
            resetCollapsedScrollTrackingIfNeeded(for: event)
            return false
        }
        guard event.hasPreciseScrollingDeltas else {
            debugGesture("blocked reason=non-precise-scroll")
            resetCollapsedScrollTrackingIfNeeded(for: event)
            return false
        }
        guard abs(event.scrollingDeltaX) > 0 || abs(event.scrollingDeltaY) > 0 else {
            debugGesture("blocked reason=zero-delta")
            resetCollapsedScrollTrackingIfNeeded(for: event)
            return false
        }
        scheduleCollapsedScrollGestureReset()

        let hitResult = collapsedScrollScreenHitResult(screenPoint: NSEvent.mouseLocation)
        debugCollapsedScrollRegion(screenPoint: NSEvent.mouseLocation, rawLocalPoint: localPoint, hitResult: hitResult)
        guard hitResult.inside else {
            debugGesture("blocked reason=outside-collapsed-region")
            resetCollapsedScrollTrackingIfNeeded(for: event)
            return false
        }

        if mediaSwipeLockoutIsActive() {
            collapsedScrollDelta = .zero
            debugGesture("media swipe ignored: post-command lockout active remaining=\(String(format: "%.2f", mediaSwipeLockoutRemaining()))")
            return true
        }

        if collapsedScrollGestureHandled {
            debugGesture("ignored duplicate/momentum event after action fired")
            return true
        }

        if event.phase.contains(.began) {
            collapsedScrollDelta = .zero
            collapsedScrollGestureHandled = false
            resetMediaSwipeSession()
        }

        guard collapsedScrollCooldownAllowsAction() || mediaSwipeSessionActive else {
            debugGesture("blocked reason=cooldown-before-accumulation")
            return true
        }

        collapsedScrollDelta.width += event.scrollingDeltaX
        collapsedScrollDelta.height += event.scrollingDeltaY
        updateMediaSwipeSession(with: event, source: source)
        let resolvedGesture = collapsedScrollGesture(from: collapsedScrollDelta)
        if abs(collapsedScrollDelta.height) >= abs(collapsedScrollDelta.width),
           abs(collapsedScrollDelta.height) >= collapsedScrollThreshold {
            debugGesture(
                "vertical rawY=\(collapsedScrollDelta.height) interpretedPhysicalDirection=\(resolvedGesture == .swipeDown ? "down" : "up")"
            )
        }
        debugGesture(
            "accumulatedX=\(collapsedScrollDelta.width) accumulatedY=\(collapsedScrollDelta.height) threshold=\(collapsedScrollThreshold) resolved=\(resolvedGesture?.rawValue ?? "nil")"
        )

        if !collapsedScrollGestureHandled,
           let gesture = resolvedGesture {
            let action = collapsedMediaPillAction(for: gesture)
            if isHorizontalMediaTrackAction(action), abs(collapsedScrollDelta.width) >= abs(collapsedScrollDelta.height) {
                debugGesture("horizontal media swipe threshold reached; waiting for quiet finish action=\(action.rawValue)")
                return true
            }

            if gesture == .swipeDown || gesture == .swipeUp {
                resetMediaSwipeSession()
            }

            let handled = handleCollapsedMediaPillGesture(gesture)
            collapsedScrollGestureHandled = handled
            debugGesture("resolved=\(gesture.rawValue) handled=\(handled)")
            if handled {
                collapsedScrollDelta = .zero
                return true
            }
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            if mediaSwipeSessionActive {
                scheduleMediaSwipeFinish()
            } else {
                resetCollapsedScrollTracking()
            }
        }

        return true
    }

    private func resetCollapsedScrollTrackingIfNeeded(for event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.phase.contains(.began) {
            resetCollapsedScrollTracking()
        }
    }

    private func resetCollapsedScrollTracking() {
        collapsedScrollGestureResetWorkItem?.cancel()
        collapsedScrollGestureResetWorkItem = nil
        collapsedScrollDelta = .zero
        collapsedScrollGestureHandled = false
    }

    private func scheduleCollapsedScrollGestureReset() {
        collapsedScrollGestureResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.collapsedScrollDelta = .zero
                self?.collapsedScrollGestureHandled = false
                self?.collapsedScrollGestureResetWorkItem = nil
                self?.debugGesture("quiet reset fired")
            }
        }
        collapsedScrollGestureResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + collapsedScrollQuietResetDelay,
            execute: workItem
        )
    }

    private func collapsedScrollScreenHitResult(
        screenPoint: NSPoint
    ) -> (inside: Bool, localPoint: NSPoint, hitFrame: NSRect, collapsedFrame: NSRect, previewFrame: NSRect) {
        let collapsedFrame = screenRect(for: layoutStore.collapsedSurfaceFrame)
        let previewFrame = screenRect(for: layoutStore.collapsedPreviewSurfaceFrame)
        let hitFrame = collapsedGestureCandidateScreenRegion
        let referenceFrame = visualReferencePanelFrame
        let localPoint = NSPoint(
            x: screenPoint.x - referenceFrame.minX,
            y: screenPoint.y - referenceFrame.minY
        )
        return (
            inside: !hitFrame.isEmpty && hitFrame.contains(screenPoint),
            localPoint: localPoint,
            hitFrame: hitFrame,
            collapsedFrame: collapsedFrame,
            previewFrame: previewFrame
        )
    }

    private func collapsedScrollGesture(from delta: CGSize) -> IslandPointerGesture? {
        let threshold = collapsedScrollThreshold
        let absoluteX = abs(delta.width)
        let absoluteY = abs(delta.height)
        guard max(absoluteX, absoluteY) >= threshold else { return nil }

        if absoluteX >= absoluteY {
            return delta.width < 0 ? .swipeLeft : .swipeRight
        }
        return delta.height > 0 ? .swipeDown : .swipeUp
    }

    private var collapsedScrollThreshold: CGFloat {
        let clampedSensitivity = min(max(settings.gestureSensitivity, 0), 1)
        return collapsedScrollBaseThreshold / max(0.4, CGFloat(clampedSensitivity))
    }

    private func updateMediaSwipeSession(with event: NSEvent, source: String) {
        let now = Date()
        if !mediaSwipeSessionActive {
            mediaSwipeSessionActive = true
            mediaSwipeStartedAt = now
            mediaSwipeAccumulatedX = 0
            mediaSwipeAccumulatedY = 0
        }

        mediaSwipeAccumulatedX += event.scrollingDeltaX
        mediaSwipeAccumulatedY += event.scrollingDeltaY
        mediaSwipeLastEventAt = now
        debugGesture(
            "media swipe session update source=\(source) dx=\(event.scrollingDeltaX) dy=\(event.scrollingDeltaY) accumulatedX=\(mediaSwipeAccumulatedX) accumulatedY=\(mediaSwipeAccumulatedY)"
        )
        scheduleMediaSwipeFinish()
    }

    private func scheduleMediaSwipeFinish() {
        mediaSwipeFinishWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.finishCollapsedMediaSwipeSession()
            }
        }
        mediaSwipeFinishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + mediaSwipeQuietPeriod, execute: workItem)
        debugGesture("media swipe finish scheduled quiet=\(String(format: "%.2f", mediaSwipeQuietPeriod))")
    }

    private func finishCollapsedMediaSwipeSession() {
        guard mediaSwipeSessionActive else {
            return
        }

        let accumulatedX = mediaSwipeAccumulatedX
        let accumulatedY = mediaSwipeAccumulatedY
        let threshold = collapsedScrollThreshold
        resetMediaSwipeSession()
        collapsedScrollDelta = .zero
        collapsedScrollGestureHandled = false

        debugGesture(
            "media swipe finish x=\(accumulatedX) y=\(accumulatedY) threshold=\(threshold)"
        )

        guard settings.gesturesEnabled,
              settings.gestureInputSource == .trackpad,
              islandState.state == .collapsed,
              !layoutStore.isShellMorphing,
              !layoutStore.isCollapseShellOnly,
              !layoutStore.isExpandedContentExiting,
              !modules.navigation.isFileDropTargeted else {
            debugGesture("media swipe finish ignored: settings-or-state")
            return
        }

        guard abs(accumulatedX) >= threshold else {
            debugGesture("media swipe finish ignored: below threshold")
            return
        }

        guard abs(accumulatedX) > abs(accumulatedY) else {
            debugGesture("media swipe finish ignored: not horizontal dominant")
            return
        }

        let gesture: IslandPointerGesture = accumulatedX < 0 ? .swipeLeft : .swipeRight
        let action = collapsedMediaPillAction(for: gesture)
        guard isHorizontalMediaTrackAction(action) else {
            debugGesture("media swipe finish ignored: action-not-media-track action=\(action.rawValue)")
            return
        }
        guard !settings.requireGestureConfirmation else {
            debugGesture("media swipe finish ignored: require-confirmation action=\(action.rawValue)")
            return
        }
        guard collapsedScrollCooldownAllowsAction() else {
            debugGesture("media swipe finish ignored: cooldown action=\(action.rawValue)")
            return
        }
        guard settings.mediaEnabled,
              modules.media.isTransportControlAvailable else {
            debugGesture("media swipe finish ignored: media-track-unavailable action=\(action.rawValue) mediaEnabled=\(settings.mediaEnabled) transport=\(modules.media.isTransportControlAvailable)")
            return
        }

        startMediaSwipePostCommandLockout(action: action)
        collapsedScrollLastActionAt = CACurrentMediaTime()

        switch action {
        case .mediaNextTrack:
            debugGesture("media swipe finish quiet=\(String(format: "%.2f", mediaSwipeQuietPeriod)) x=\(accumulatedX) y=\(accumulatedY) action=\(action.rawValue)")
            debugGesture("media swipe finished; ACTION mediaNextTrack")
            modules.media.requestGestureArtworkFlip(direction: .next)
            modules.media.nextTrack()
            scheduleMediaRefreshAfterTransportGesture(reason: "gestureNext")
        case .mediaPreviousTrack:
            debugGesture("media swipe finish quiet=\(String(format: "%.2f", mediaSwipeQuietPeriod)) x=\(accumulatedX) y=\(accumulatedY) action=\(action.rawValue)")
            debugGesture("media swipe finished; ACTION mediaPreviousTrack")
            modules.media.requestGestureArtworkFlip(direction: .previous)
            modules.media.previousTrack()
            scheduleMediaRefreshAfterTransportGesture(reason: "gesturePrevious")
        default:
            break
        }
    }

    private func resetMediaSwipeSession() {
        mediaSwipeFinishWorkItem?.cancel()
        mediaSwipeFinishWorkItem = nil
        mediaSwipeSessionActive = false
        mediaSwipeAccumulatedX = 0
        mediaSwipeAccumulatedY = 0
        mediaSwipeStartedAt = nil
        mediaSwipeLastEventAt = nil
        debugGesture("media swipe session reset")
    }

    private func mediaSwipeLockoutRemaining(now: Date = Date()) -> TimeInterval {
        max(0, mediaSwipeLockedUntil.timeIntervalSince(now))
    }

    private func mediaSwipeLockoutIsActive(now: Date = Date()) -> Bool {
        if now < mediaSwipeLockedUntil {
            return true
        }

        if mediaSwipeCommandInFlight {
            mediaSwipeCommandInFlight = false
            mediaSwipeUnlockWorkItem = nil
        }

        return false
    }

    private func startMediaSwipePostCommandLockout(action: IslandGestureAction) {
        mediaSwipeCommandInFlight = true
        mediaSwipeLockedUntil = Date().addingTimeInterval(mediaSwipePostCommandLockoutSeconds)
        mediaSwipeUnlockWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard Date() >= self.mediaSwipeLockedUntil else {
                    self.debugGesture("media swipe unlock skipped; lockout extended")
                    return
                }
                self.mediaSwipeCommandInFlight = false
                self.mediaSwipeUnlockWorkItem = nil
                self.debugGesture("media swipe post-command lockout released")
            }
        }
        mediaSwipeUnlockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + mediaSwipePostCommandLockoutSeconds, execute: workItem)
        debugGesture("media swipe post-command lockout started action=\(action.rawValue) duration=\(String(format: "%.2f", mediaSwipePostCommandLockoutSeconds))")
    }

    private func isHorizontalMediaTrackAction(_ action: IslandGestureAction) -> Bool {
        action == .mediaNextTrack || action == .mediaPreviousTrack
    }

    private func handleCollapsedMediaPillGesture(_ gesture: IslandPointerGesture) -> Bool {
        guard !settings.requireGestureConfirmation else {
            debugGesture("blocked reason=require-confirmation gesture=\(gesture.rawValue)")
            return false
        }

        let action = collapsedMediaPillAction(for: gesture)
        debugGesture("resolved gesture=\(gesture.rawValue) action=\(action.rawValue)")
        guard action != .none else {
            debugGesture("blocked reason=action-none gesture=\(gesture.rawValue)")
            return false
        }
        guard collapsedScrollCooldownAllowsAction() else {
            debugGesture("blocked reason=cooldown gesture=\(gesture.rawValue) action=\(action.rawValue)")
            return false
        }

        switch action {
        case .expand:
            debugGesture("executing action=\(action.rawValue)")
            expandFromCollapsedPreparingGeometry()
            collapsedScrollLastActionAt = CACurrentMediaTime()
            return true
        case .mediaNextTrack:
            debugGesture("deferred action=\(action.rawValue) to media swipe finish")
            return true
        case .mediaPreviousTrack:
            debugGesture("deferred action=\(action.rawValue) to media swipe finish")
            return true
        case .mediaPlayPause:
            guard settings.mediaEnabled,
                  settings.mediaPlayPauseGestureEnabled,
                  modules.media.isTransportControlAvailable else {
                debugGesture("blocked reason=media-play-pause-unavailable mediaEnabled=\(settings.mediaEnabled) enabled=\(settings.mediaPlayPauseGestureEnabled) transport=\(modules.media.isTransportControlAvailable)")
                return false
            }
            debugGesture("executing action=\(action.rawValue)")
            modules.media.playPause()
            collapsedScrollLastActionAt = CACurrentMediaTime()
            return true
        case .openSettings:
            // Long press still owns Settings. Two-finger scroll gestures intentionally do not.
            debugGesture("blocked reason=open-settings-not-scroll-action")
            return false
        case .collapse, .toggleExpanded, .nextTab, .previousTab, .timerStartStop, .none:
            debugGesture("blocked reason=unsupported-collapsed-scroll-action action=\(action.rawValue)")
            return false
        }
    }

    private func collapsedScrollCooldownAllowsAction() -> Bool {
        guard let collapsedScrollLastActionAt else { return true }
        return CACurrentMediaTime() - collapsedScrollLastActionAt >= settings.gestureCooldownSeconds
    }

    private func scheduleMediaRefreshAfterTransportGesture(reason: String) {
        debugGesture("scheduling media refresh sequence reason=\(reason)")
        debugGesture("media refresh scheduled reason=\(reason)")
        debugMedia("artwork refresh requested reason=\(reason)")
        modules.media.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.debugGesture("media refresh firing reason=\(reason) delayed=0.25")
            self.debugMedia("artwork refresh requested reason=\(reason) delayed=0.25")
            self.modules.media.refresh()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self else { return }
            self.debugGesture("media refresh firing reason=\(reason) delayed=0.75")
            self.debugMedia("artwork refresh requested reason=\(reason) delayed=0.75")
            self.modules.media.refresh()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.20) { [weak self] in
            guard let self else { return }
            self.debugGesture("media refresh firing reason=\(reason) delayed=1.20")
            self.debugMedia("artwork refresh requested reason=\(reason) delayed=1.20")
            self.modules.media.refresh()
        }
    }

    private func collapsedMediaPillAction(for gesture: IslandPointerGesture) -> IslandGestureAction {
        switch gesture {
        case .swipeLeft:
            return settings.collapsedSwipeLeftAction
        case .swipeRight:
            return settings.collapsedSwipeRightAction
        case .swipeDown:
            return settings.collapsedSwipeDownAction
        case .swipeUp:
            return settings.collapsedSwipeUpAction
        case .doubleClick:
            return settings.collapsedDoubleClickAction
        case .longPress:
            return settings.collapsedLongPressAction
        }
    }

    private func debugScrollWheelReceived(_ event: NSEvent, source: String) {
        #if DEBUG
        print(
            "[GestureDebug] scrollWheel received source=\(source) deltaX=\(event.scrollingDeltaX) deltaY=\(event.scrollingDeltaY) phase=\(event.phase.rawValue) momentum=\(event.momentumPhase.rawValue) precise=\(event.hasPreciseScrollingDeltas)"
        )
        #endif
    }

    private func debugCollapsedScrollRegion(
        screenPoint: NSPoint,
        rawLocalPoint: NSPoint? = nil,
        hitResult: (inside: Bool, localPoint: NSPoint, hitFrame: NSRect, collapsedFrame: NSRect, previewFrame: NSRect)? = nil
    ) {
        #if DEBUG
        let result = hitResult ?? collapsedScrollScreenHitResult(screenPoint: screenPoint)
        let localPoint = rawLocalPoint ?? result.localPoint
        print(
            "[GestureDebug] screenPoint=\(screenPoint) localPoint=\(localPoint) collapsedScreenFrame=\(result.collapsedFrame) previewScreenFrame=\(result.previewFrame) hitFrame=\(result.hitFrame) inside=\(result.inside) panelFrame=\(islandPanel.frame)"
        )
        #endif
    }

    private func logCollapsedScrollSettingsAndState() {
        #if DEBUG
        print(
            "[GestureDebug] settings gesturesEnabled=\(settings.gesturesEnabled) input=\(settings.gestureInputSource) left=\(settings.collapsedSwipeLeftAction) right=\(settings.collapsedSwipeRightAction) down=\(settings.collapsedSwipeDownAction)"
        )
        print(
            "[GestureDebug] islandState=\(islandState.state) isShellMorphing=\(layoutStore.isShellMorphing) isCollapseShellOnly=\(layoutStore.isCollapseShellOnly) isExpandedContentExiting=\(layoutStore.isExpandedContentExiting) previewActive=\(layoutStore.collapsedPreviewActive) fileDropTargeted=\(modules.navigation.isFileDropTargeted)"
        )
        #endif
    }

    private func debugGesture(_ message: String) {
        #if DEBUG
        print("[GestureDebug] \(message)")
        #endif
    }

    private func debugMedia(_ message: String) {
        #if DEBUG
        print("[MediaDebug] \(message)")
        #endif
    }

    private func debugOverlayWindowOperation(operation: String, reason: String) {
        #if DEBUG
        print(
            "[OverlayWindowOperation]",
            "operation=\(operation)",
            "reason=\(reason)",
            "t=\(String(format: "%.3f", CACurrentMediaTime()))",
            "windowNumber=\(islandPanel.windowNumber)",
            "visible=\(islandPanel.isVisible)",
            "onActiveSpace=\(islandPanel.isOnActiveSpace)",
            "level=\(islandPanel.level.rawValue)",
            "frame=\(islandPanel.frame)"
        )
        #endif
    }

    private func debugOverlayPersistence(_ message: String) {
        #if DEBUG
        print("[OverlayPersistence] \(message)")
        #endif
    }

    private func logAtollParityConfigurationIfNeeded() {
        #if DEBUG
        guard !didLogAtollParityConfiguration else { return }

        didLogAtollParityConfiguration = true
        print(
            "[AtollParity]",
            "level=\(islandPanel.level.rawValue)",
            "collectionBehavior=\(islandPanel.collectionBehavior.rawValue)",
            "frame=\(islandPanel.frame)",
            "containsFullScreenAuxiliary=\(islandPanel.collectionBehavior.contains(.fullScreenAuxiliary))",
            "containsCanJoinAllSpaces=\(islandPanel.collectionBehavior.contains(.canJoinAllSpaces))",
            "containsIgnoresCycle=\(islandPanel.collectionBehavior.contains(.ignoresCycle))",
            "containsStationary=\(islandPanel.collectionBehavior.contains(.stationary))",
            "islandVisible=\(islandPanel.isVisible)"
        )
        #endif
    }

    private func debugOverlayWindowState(reason: String) {
        #if DEBUG
        print(
            "[OverlayPersistence]",
            "reason=\(reason)",
            "visible=\(islandPanel.isVisible)",
            "onActiveSpace=\(islandPanel.isOnActiveSpace)",
            "occlusion=\(islandPanel.occlusionState.rawValue)",
            "level=\(islandPanel.level.rawValue)",
            "collectionBehavior=\(islandPanel.collectionBehavior.rawValue)",
            "frame=\(islandPanel.frame)",
            "ignoresMouseEvents=\(islandPanel.ignoresMouseEvents)",
            "islandState=\(islandState.state.rawValue)"
        )
        #endif
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
    var collapsedScrollGestureRegionProvider: (() -> NSRect)?
    var onCollapsedScrollWheel: ((NSEvent, NSPoint) -> Bool)?
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

    override func scrollWheel(with event: NSEvent) {
        #if DEBUG
        print(
            "[GestureDebug] IslandHostingView.scrollWheel override fired deltaX=\(event.scrollingDeltaX) deltaY=\(event.scrollingDeltaY) phase=\(event.phase.rawValue) momentum=\(event.momentumPhase.rawValue)"
        )
        #endif
        let localPoint = convert(event.locationInWindow, from: nil)
        if onCollapsedScrollWheel?(event, localPoint) == true {
            return
        }

        super.scrollWheel(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
