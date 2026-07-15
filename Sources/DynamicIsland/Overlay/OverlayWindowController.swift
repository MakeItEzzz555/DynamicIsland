import AppKit
import Combine
import CoreGraphics
import CoreVideo
import QuartzCore
import SwiftUI

@MainActor
final class OverlayWindowController {
    private static let useExperimentalSpaceCompensation = false

    private enum OverlayPersistence {
        static let level: NSWindow.Level = .statusBar

        static var collectionBehavior: NSWindow.CollectionBehavior {
            var behavior: NSWindow.CollectionBehavior = [
                .fullScreenAuxiliary,
                .canJoinAllSpaces,
                .ignoresCycle
            ]
            if canJoinAllApplicationsEnabled {
                behavior.insert(.canJoinAllApplications)
            }
            return behavior
        }

        static var canJoinAllApplicationsEnabled: Bool {
            #if DEBUG
            ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_DISABLE_JOIN_ALL_APPLICATIONS"] != "1"
            #else
            true
            #endif
        }
    }

    private enum SpaceLock {
        static let deadzone: CGFloat = 1.0
        static let activeOffsetThreshold: CGFloat = 1.5
        static let frameDedupeTolerance: CGFloat = 0.35
        static let maximumTotalOffsetMultiplier: CGFloat = 1.25
        static let invalidSampleRecoveryThreshold = 8
        static let invalidProbeTranslationRecoveryThreshold = 6
        static let normalProbeTranslationMultiplier: CGFloat = 1.75
        static let absoluteProbeTranslationMultiplier: CGFloat = 2.5
        static let distinctProbeSampleThreshold: CGFloat = 0.1
        static let distinctProbeIntervalEMAAlpha: CGFloat = 0.2
        static let maximumProbeVelocityMultiplier: CGFloat = 6.0
        static let predictionLeadIntervalMultiplier: CGFloat = 0.6
        static let minimumPredictionLead: TimeInterval = 0.008
        static let maximumPredictionLead: TimeInterval = 0.024
        static let maximumPredictionDistanceMultiplier: CGFloat = 0.04
        static let maximumPredictionDistanceCap: CGFloat = 60
        static let predictionRestTranslationThreshold: CGFloat = 8
        static let predictionRestVelocityThreshold: CGFloat = 20
        static let recoveryCooldown: TimeInterval = 0.15
        static let probeBaselineStableTolerance: CGFloat = 2.0
        static let probeBaselineRequiredStableSamples = 10
        static let transitionActivationThreshold: CGFloat = 2.0
        static let transitionCompletionThreshold: CGFloat = 0.5
        static let transitionCompletionRequiredStableSamples = 9
        static let renderTransformDedupeThreshold: CGFloat = 0.1
        static let handoffOverlapDelay: TimeInterval = 1.0 / 120.0
        static let transitionCanvasHorizontalMarginMultiplier: CGFloat = 2.0
        static let recoveryVerificationDelays: [TimeInterval] = [0.10, 0.25]
        static let probeSize = CGSize(width: 2, height: 2)
        static let probeScreenInset: CGFloat = 4
    }

    private struct SpaceProbeMotionSample {
        let translationX: CGFloat
        let timestamp: CFTimeInterval
    }

    private struct SpaceProbePrediction {
        let rawTranslationX: CGFloat
        let predictedTranslationX: CGFloat
        let predictionLead: CFTimeInterval
        let velocityX: CGFloat
    }

    private struct OverlayWindowServerSnapshot {
        let windowNumber: Int
        let bounds: CGRect
        let isOnscreen: Bool
        let layer: Int
        let alpha: Double
        let ownerName: String?
    }

    private let expandedHoverTolerance: CGFloat = 2
    private let collapsedHoverTolerance: CGFloat = 4
    private let collapseContentExitDelay: DispatchTimeInterval = .milliseconds(205)
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
    private let spaceMotionProbePanel: SpaceMotionProbePanel
    private let spaceTransitionRenderPanel: SpaceTransitionRenderPanel
    private let spaceLockDisplayLink = SpaceLockDisplayLink()
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
    private var probeCanonicalFrame: NSRect = .zero
    private var transitionCanvasFrame: NSRect = .zero
    private var spaceLockOffsetX: CGFloat = 0
    private var probeWindowServerXOffset: CGFloat?
    private var probeWindowID: CGWindowID?
    private var lastRawProbeSample: SpaceProbeMotionSample?
    private var previousRawProbeSample: SpaceProbeMotionSample?
    private var lastDistinctProbeSample: SpaceProbeMotionSample?
    private var previousDistinctProbeSample: SpaceProbeMotionSample?
    private var distinctProbeSampleIntervalEMA: CFTimeInterval?
    private var estimatedProbeVelocityX: CGFloat = 0
    private var lastPredictionResult: SpaceProbePrediction?
    private var probeStableSampleCount = 0
    private var probeBaselineCapturePending = false
    private var spaceLockRecoveryUntil: CFTimeInterval = 0
    private var consecutiveInvalidSpaceLockSamples = 0
    private var consecutiveInvalidProbeTranslations = 0
    private var transitionCompletionStableSamples = 0
    private var isSpaceTransitionRenderActive = false
    private var transitionRenderHandoffPending = false
    private var transitionRenderHandoffGeneration = 0
    private var lastAppliedTransitionLayerTranslationX: CGFloat = 0
    private var lastValidProbeTranslationX: CGFloat = 0
    private var spaceLockFrameUpdatePending = false
    private var lastRenderEnqueueTimestamp: CFTimeInterval = 0
    private var lastMainQueueRenderDelay: CFTimeInterval = 0
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
    private var overlayTransitionTraceTimer: Timer?
    private var overlayTransitionTraceStartedAt: CFTimeInterval?
    private var localSystemGestureMonitor: Any?
    private var globalSystemGestureMonitor: Any?
    private var canonicalFrameApplicationWindowStartedAt: CFTimeInterval = 0
    private var canonicalFrameApplicationCount: Int = 0
    private var lastSpaceLockCorrectionLogAt: CFTimeInterval = 0
    private var lastSpaceLockSettledLogAt: CFTimeInterval = 0
    private var lastSpaceProbeTraceLogAt: CFTimeInterval = 0
    private var spaceProbeFrameSampleStartedAt: CFTimeInterval = 0
    private var spaceProbeFrameSampleCount = 0
    private var lastObservedSpaceProbeFPS: Double = 0
    private var lastSpaceMotionMetricsLogAt: CFTimeInterval = 0
    private var lastVisibleIslandErrorSampleAt: CFTimeInterval = 0
    private var visibleIslandErrorSamples: [CGFloat] = []
    private var didLogAtollParityConfiguration = false
    private var didLogSpaceNativeABConfiguration = false
    #endif
    private weak var hostingView: IslandHostingView<IslandRootView>?
    private weak var transitionIslandHostingView: NSHostingView<IslandRootView>?

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

        spaceMotionProbePanel = SpaceMotionProbePanel(
            contentRect: NSRect(origin: .zero, size: SpaceLock.probeSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        Self.configure(spaceMotionProbePanel)
        Self.configureSpaceMotionProbe(spaceMotionProbePanel)

        spaceTransitionRenderPanel = SpaceTransitionRenderPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        Self.configure(spaceTransitionRenderPanel)
        Self.configureSpaceTransitionRenderPanel(spaceTransitionRenderPanel)

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

        let transitionRootView = IslandRootView(
            settings: settings,
            islandState: islandState,
            layoutStore: layoutStore,
            modules: modules,
            rendersExpandedVisualContent: true,
            onRequestExpand: {},
            onRequestCollapse: {},
            onOpenSettings: {}
        )
        let transitionHostingView = NSHostingView(rootView: transitionRootView)
        transitionHostingView.wantsLayer = true
        transitionHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        transitionHostingView.layer?.opacity = 0
        transitionHostingView.autoresizingMask = []
        spaceTransitionRenderPanel.contentView?.addSubview(transitionHostingView)
        self.transitionIslandHostingView = transitionHostingView

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
                if self?.spaceCompensationEnabled == true {
                    self?.pauseProbeDrivenTrackingForScreenChange()
                }
                self?.reposition(animated: false, reason: "screenParametersChanged", force: true)
                if self?.spaceCompensationEnabled == true {
                    self?.prepareSpaceMotionProbe(reason: "screenParametersChanged")
                    self?.reassertOverlayPresence(reason: "screenParametersChanged")
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.debugOverlayPersistence("workspace woke")
                if self?.spaceCompensationEnabled == true {
                    self?.reposition(animated: false, reason: "workspaceDidWake", force: true)
                    self?.reassertOverlayPresence(reason: "workspaceDidWake")
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in
                self?.debugOverlayPersistence("active app changed")
                if self?.spaceCompensationEnabled == true {
                    self?.requestProbeDrivenSpaceLockUpdate(reason: "activeApplicationChanged")
                    self?.startOverlayTransitionTrace(reason: "activeApplicationChanged")
                    self?.reassertOverlayPresence(reason: "activeApplicationChanged")
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.debugOverlayPersistence("active space changed")
                if self?.spaceCompensationEnabled == true {
                    self?.requestProbeDrivenSpaceLockUpdate(reason: "activeSpaceChanged")
                    self?.scheduleSpaceLockRecoveryVerification(reason: "activeSpaceChanged")
                    self?.startOverlayTransitionTrace(reason: "activeSpaceChanged")
                    self?.reassertOverlayPresence(reason: "activeSpaceChanged")
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.debugOverlayPersistence("app became active")
                if self?.spaceCompensationEnabled == true {
                    self?.startOverlayTransitionTrace(reason: "appBecameActive")
                    self?.reassertOverlayPresence(reason: "appBecameActive")
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.debugOverlayPersistence("app resigned active")
                if self?.spaceCompensationEnabled == true {
                    self?.startOverlayTransitionTrace(reason: "appResignedActive")
                    self?.reassertOverlayPresence(reason: "appResignedActive")
                }
            }
            .store(in: &cancellables)

        installMouseDownMonitors()
    }

    func show() {
        islandState.collapse()
        reposition(animated: false, reason: "initialShow", force: true)
        if spaceCompensationEnabled {
            prepareSpaceMotionProbe(reason: "initialShow")
            startSpaceLockWatchdog()
        } else {
            disableExperimentalSpaceCompensationPanels(reason: "initialShow")
        }
        updateWindowVisibility()
        logAtollParityConfigurationIfNeeded()
        logSpaceNativeABConfigurationIfNeeded()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else {
            debugOverlayWindowState(reason: "ORDERING OUT reason=overlayDisabled before")
            islandPanel.ignoresMouseEvents = true
            debugOverlayWindowOperation(operation: "orderOut", reason: "overlayDisabled")
            islandPanel.orderOut(nil)
            spaceMotionProbePanel.orderOut(nil)
            spaceTransitionRenderPanel.orderOut(nil)
            lastOrderedVisibilityState = nil
            debugOverlayWindowState(reason: "ORDERING OUT reason=overlayDisabled after")
        }
        if !visible {
            stopMouseContainmentTimer()
            stopSpaceLockWatchdog()
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

    private var spaceCompensationEnabled: Bool {
        #if DEBUG
        Self.useExperimentalSpaceCompensation ||
            ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_ENABLE_SPACE_COMPENSATION"] == "1"
        #else
        Self.useExperimentalSpaceCompensation
        #endif
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
            "behavior.canJoinAllApplications=\(panel.collectionBehavior.contains(.canJoinAllApplications))",
            "behavior.canJoinAllSpaces=\(panel.collectionBehavior.contains(.canJoinAllSpaces))",
            "behavior.fullScreenAuxiliary=\(panel.collectionBehavior.contains(.fullScreenAuxiliary))",
            "behavior.stationary=\(panel.collectionBehavior.contains(.stationary))",
            "behavior.auxiliary=\(panel.collectionBehavior.contains(.auxiliary))"
        )
        #endif
    }

    private static func configureSpaceMotionProbe(_ panel: SpaceMotionProbePanel) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 1
        panel.acceptsMouseMovedEvents = false

        let contentView = NSView(frame: NSRect(origin: .zero, size: SpaceLock.probeSize))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = contentView
    }

    private static func configureSpaceTransitionRenderPanel(_ panel: SpaceTransitionRenderPanel) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 1
        panel.acceptsMouseMovedEvents = false

        let contentView = NSView(frame: .zero)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = contentView
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
        spaceLockOffsetX = 0
        recordCanonicalFrameApplication(reason: reason)
        applyPhysicalPanelFrame(frame, reason: reason)
        islandPanel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        if spaceCompensationEnabled {
            prepareSpaceTransitionRenderPanel(reason: reason)
        }
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
            tolerance: SpaceLock.frameDedupeTolerance
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
        if !spaceCompensationEnabled {
            if !islandPanel.isVisible {
                debugOverlayWindowOperation(
                    operation: "orderFrontRegardless",
                    reason: "updateWindowVisibility parity initial order generation=\(visibilityGeneration)"
                )
                islandPanel.orderFrontRegardless()
            }
            lastOrderedVisibilityState = islandState.state
            updateMousePassthrough()
            updateMouseContainmentTimer()
            return
        }

        if islandPanel.isVisible, lastOrderedVisibilityState == islandState.state {
            #if DEBUG
            debugPrint(
                "[OverlayWindowOperation]",
                "operation=orderFrontRegardlessSkipped",
                "reason=visibilityStateAlreadyOrdered",
                "state=\(islandState.state.rawValue)",
                "generation=\(visibilityGeneration)"
            )
            #endif
            updateMousePassthrough()
            updateMouseContainmentTimer()
            return
        }

        if islandState.state == .expanded {
            debugOverlayWindowOperation(
                operation: "orderFrontRegardless",
                reason: "updateWindowVisibility expanded generation=\(visibilityGeneration)"
            )
            islandPanel.orderFrontRegardless()
            lastOrderedVisibilityState = .expanded
            startMouseContainmentTimer()
        } else {
            debugLog("updateWindowVisibility received collapsed")
            debugOverlayWindowOperation(
                operation: "orderFrontRegardless",
                reason: "updateWindowVisibility collapsed generation=\(visibilityGeneration)"
            )
            islandPanel.orderFrontRegardless()
            lastOrderedVisibilityState = .collapsed
            stopMouseContainmentTimer()
        }
        updateMousePassthrough()
    }

    private func reassertOverlayPresence(reason: String) {
        guard settings.overlayEnabled else { return }
        guard spaceCompensationEnabled else {
            debugOverlayPersistence("reassert skipped reason=\(reason) mode=atollParity")
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_DISABLE_PERSISTENCE_REASSERT"] == "1" {
            debugOverlayPersistence("reassert skipped reason=\(reason) env=DYNAMIC_ISLAND_DISABLE_PERSISTENCE_REASSERT")
            debugOverlayWindowState(reason: "skipped reassert \(reason)")
            return
        }
        #endif
        debugOverlayWindowState(reason: "before reassert \(reason)")
        Self.configure(islandPanel)
        debugOverlayWindowOperation(operation: "orderFrontRegardless", reason: "reassert \(reason)")
        islandPanel.orderFrontRegardless()
        lastOrderedVisibilityState = islandState.state
        updateMousePassthrough()
        debugOverlayWindowState(reason: "after reassert \(reason)")
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

        #if DEBUG
        localSystemGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe, .gesture]) { [weak self] event in
            self?.startOverlayTransitionTraceIfEventIsOutsideIsland(event)
            return event
        }

        globalSystemGestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.swipe, .gesture]) { [weak self] event in
            Task { @MainActor in
                self?.startOverlayTransitionTraceIfEventIsOutsideIsland(event)
            }
        }
        #endif

        localScrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
    guard let self else { return event }

    self.debugScrollWheelReceived(event, source: "localScrollMonitor")
    self.startOverlayTransitionTraceIfEventIsOutsideIsland(event)

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
        self.startOverlayTransitionTraceIfEventIsOutsideIsland(event)

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

        guard abs(spaceLockOffsetX) <= SpaceLock.activeOffsetThreshold else {
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

    private func startSpaceLockWatchdog() {
        guard spaceCompensationEnabled else { return }
        guard !spaceLockDisplayLink.isRunning else { return }

        spaceLockDisplayLink.start { [weak self] frameTimestamp in
            self?.requestProbeDrivenSpaceLockUpdate(reason: "displayLink", frameTimestamp: frameTimestamp)
        }
        debugSpaceProbe(
            "displayLinkStarted",
            "nominalFPS=\(spaceLockDisplayLink.nominalFramesPerSecond.map { String(format: "%.1f", $0) } ?? "unknown")"
        )
    }

    private func stopSpaceLockWatchdog() {
        let displayLinkWasRunning = spaceLockDisplayLink.isRunning
        spaceLockDisplayLink.stop()
        spaceLockFrameUpdatePending = false
        spaceLockOffsetX = 0
        probeWindowServerXOffset = nil
        probeWindowID = nil
        resetProbeMotionState()
        probeStableSampleCount = 0
        probeBaselineCapturePending = false
        spaceLockRecoveryUntil = 0
        consecutiveInvalidSpaceLockSamples = 0
        consecutiveInvalidProbeTranslations = 0
        transitionCompletionStableSamples = 0
        isSpaceTransitionRenderActive = false
        transitionRenderHandoffPending = false
        transitionRenderHandoffGeneration += 1
        lastAppliedTransitionLayerTranslationX = 0
        lastValidProbeTranslationX = 0
        lastPredictionResult = nil
        setMainIslandContentVisible(true)
        setTransitionIslandVisible(false)
        resetTransitionLayerTransform()
        if displayLinkWasRunning || spaceCompensationEnabled {
            debugSpaceProbe("displayLinkStopped")
        }
    }

    private func disableExperimentalSpaceCompensationPanels(reason: String) {
        stopSpaceLockWatchdog()
        spaceMotionProbePanel.orderOut(nil)
        spaceTransitionRenderPanel.orderOut(nil)
        setMainIslandContentVisible(true)
        updateMousePassthrough()
        debugOverlayPersistence("space compensation disabled reason=\(reason)")
    }

    private func pauseProbeDrivenTrackingForScreenChange() {
        guard spaceCompensationEnabled else { return }
        spaceLockDisplayLink.stop()
        spaceLockFrameUpdatePending = false
        spaceLockOffsetX = 0
        probeWindowServerXOffset = nil
        probeWindowID = nil
        resetProbeMotionState()
        probeStableSampleCount = 0
        probeBaselineCapturePending = true
        consecutiveInvalidSpaceLockSamples = 0
        consecutiveInvalidProbeTranslations = 0
        transitionCompletionStableSamples = 0
        endSpaceTransitionRendering(reason: "screenChangePause")
    }

    private func prepareSpaceMotionProbe(reason: String) {
        guard spaceCompensationEnabled else { return }
        guard settings.overlayEnabled,
              !canonicalPanelFrame.isEmpty else {
            return
        }

        let targetScreen = targetScreenForSpaceMotionProbe()
        let frame = canonicalProbeFrame(on: targetScreen)
        probeCanonicalFrame = frame
        probeWindowServerXOffset = nil
        requestProbeBaselineCapture(reason: reason, invalidateExistingBaseline: true)
        consecutiveInvalidSpaceLockSamples = 0
        consecutiveInvalidProbeTranslations = 0

        applyProbeCanonicalFrame(frame, reason: reason)
        debugOverlayWindowOperation(operation: "orderFrontRegardless", reason: "spaceMotionProbe \(reason)")
        spaceMotionProbePanel.orderFrontRegardless()
        if spaceMotionProbePanel.windowNumber > 0 {
            probeWindowID = CGWindowID(spaceMotionProbePanel.windowNumber)
        }
        prepareSpaceTransitionRenderPanel(reason: reason)
        startSpaceLockWatchdog()
    }

    private func targetScreenForSpaceMotionProbe() -> NSScreen {
        let canonicalMidPoint = NSPoint(x: canonicalPanelFrame.midX, y: canonicalPanelFrame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(canonicalMidPoint) }) {
            return screen
        }
        return islandPanel.screen ?? NSScreen.main ?? NSScreen.screens.first!
    }

    private func canonicalProbeFrame(on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.minX + SpaceLock.probeScreenInset,
            y: screen.frame.maxY - SpaceLock.probeScreenInset - SpaceLock.probeSize.height,
            width: SpaceLock.probeSize.width,
            height: SpaceLock.probeSize.height
        )
    }

    private func applyProbeCanonicalFrame(_ frame: NSRect, reason: String) {
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
            spaceMotionProbePanel.frame,
            tolerance: SpaceLock.frameDedupeTolerance
        ) else {
            return
        }

        debugSpaceProbe("probeSetFrame", "reason=\(reason)", "frame=\(frame)")
        spaceMotionProbePanel.setFrame(frame, display: false)
        spaceMotionProbePanel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func prepareSpaceTransitionRenderPanel(reason: String) {
        guard spaceCompensationEnabled else { return }
        guard settings.overlayEnabled,
              !canonicalPanelFrame.isEmpty else {
            return
        }

        let targetScreen = targetScreenForSpaceMotionProbe()
        let canvasFrame = transitionCanvasFrame(on: targetScreen)
        transitionCanvasFrame = canvasFrame
        applyTransitionCanvasFrame(canvasFrame, reason: reason)
        layoutTransitionIslandRenderer()
        setTransitionIslandVisible(isSpaceTransitionRenderActive)
        debugOverlayWindowOperation(operation: "orderFrontRegardless", reason: "spaceTransitionRender \(reason)")
        spaceTransitionRenderPanel.orderFrontRegardless()
    }

    private func transitionCanvasFrame(on screen: NSScreen) -> NSRect {
        let horizontalMargin = screen.frame.width * SpaceLock.transitionCanvasHorizontalMarginMultiplier
        return NSRect(
            x: screen.frame.minX - horizontalMargin,
            y: canonicalPanelFrame.minY,
            width: screen.frame.width + horizontalMargin * 2,
            height: canonicalPanelFrame.height
        )
    }

    private func applyTransitionCanvasFrame(_ frame: NSRect, reason: String) {
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
            spaceTransitionRenderPanel.frame,
            tolerance: SpaceLock.frameDedupeTolerance
        ) else {
            return
        }

        debugSpaceRender("canvasSetFrame", "reason=\(reason)", "frame=\(frame)")
        spaceTransitionRenderPanel.setFrame(frame, display: false)
        spaceTransitionRenderPanel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func layoutTransitionIslandRenderer() {
        guard let transitionIslandHostingView,
              !transitionCanvasFrame.isEmpty,
              !canonicalPanelFrame.isEmpty else {
            return
        }

        let localFrame = NSRect(
            x: canonicalPanelFrame.minX - transitionCanvasFrame.minX,
            y: canonicalPanelFrame.minY - transitionCanvasFrame.minY,
            width: canonicalPanelFrame.width,
            height: canonicalPanelFrame.height
        )
        transitionIslandHostingView.frame = localFrame
        transitionIslandHostingView.layer?.anchorPoint = CGPoint(x: 0, y: 0)
        transitionIslandHostingView.layer?.position = CGPoint(x: localFrame.minX, y: localFrame.minY)
    }

    private func requestProbeBaselineCapture(reason: String, invalidateExistingBaseline: Bool) {
        if invalidateExistingBaseline {
            probeWindowServerXOffset = nil
        }
        resetProbeMotionState()
        probeBaselineCapturePending = true
        probeStableSampleCount = 0
        debugSpaceProbe("BASELINE_PENDING", "reason=\(reason)")
    }

    private func requestProbeDrivenSpaceLockUpdate(reason: String, frameTimestamp: CFTimeInterval = CACurrentMediaTime()) {
        guard spaceCompensationEnabled else { return }
        lastRenderEnqueueTimestamp = frameTimestamp
        guard !spaceLockFrameUpdatePending else { return }
        spaceLockFrameUpdatePending = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.spaceLockFrameUpdatePending = false
            let renderTimestamp = CACurrentMediaTime()
            self.lastMainQueueRenderDelay = max(0, renderTimestamp - self.lastRenderEnqueueTimestamp)
            self.performProbeDrivenSpaceLockTick(reason: reason, renderTimestamp: renderTimestamp)
        }
    }

    private func performProbeDrivenSpaceLockTick(reason: String, renderTimestamp: CFTimeInterval = CACurrentMediaTime()) {
        guard spaceCompensationEnabled else { return }
        guard settings.overlayEnabled,
              islandPanel.isVisible,
              !canonicalPanelFrame.isEmpty else {
            return
        }

        let now = renderTimestamp
        recordSpaceProbeFrame(now: now)
        guard now >= spaceLockRecoveryUntil else {
            return
        }

        let screenWidth = effectiveSpaceLockScreenWidth
        let maximumTotalOffset = maximumSpaceLockOffset(screenWidth: screenWidth)
        let currentPhysicalX = islandPanel.frame.minX
        guard let currentPhysicalOffset = SpaceTransitionCompensationMath.physicalOffset(
            canonicalX: canonicalPanelFrame.minX,
            physicalX: currentPhysicalX
        ) else {
            recoverSpaceLockFromRunaway(reason: "nonFinitePhysicalFrame", actualCGX: nil)
            return
        }

        if SpaceTransitionCompensationMath.exceedsMaximumOffset(
            currentPhysicalOffset,
            maximumOffset: maximumTotalOffset
        ) {
            recoverSpaceLockFromRunaway(reason: "physicalOffsetExceeded \(reason)", actualCGX: currentWindowServerSnapshot()?.bounds.minX)
            return
        }

        if probeBaselineCapturePending || probeWindowServerXOffset == nil {
            updateProbeBaselineCaptureIfStable(reason: reason)
            guard probeWindowServerXOffset != nil else {
                restoreCanonicalMainIslandWhileProbeBaselineUnavailable(reason: reason)
                return
            }
        }

        guard let rawTranslationX = sampleProbeSpaceTranslation(reason: reason, timestamp: now) else {
            handleInvalidSpaceLockSample(reason: "probeUnavailable \(reason)")
            return
        }

        guard rawTranslationX.isFinite else {
            handleInvalidSpaceLockSample(reason: "nonFiniteProbeTranslation \(reason)")
            return
        }

        let normalProbeTranslationMaximum = screenWidth * SpaceLock.normalProbeTranslationMultiplier
        let absoluteProbeTranslationMaximum = screenWidth * SpaceLock.absoluteProbeTranslationMultiplier
        if SpaceTransitionCompensationMath.exceedsMaximumOffset(
            rawTranslationX,
            maximumOffset: absoluteProbeTranslationMaximum
        ) {
            handleInvalidProbeTranslation(reason: reason, translationX: rawTranslationX)
            return
        }

        consecutiveInvalidSpaceLockSamples = 0
        if SpaceTransitionCompensationMath.exceedsMaximumOffset(
            rawTranslationX,
            maximumOffset: normalProbeTranslationMaximum
        ) {
            consecutiveInvalidProbeTranslations += 1
            throttledSpaceProbeInvalidTranslationLog(
                reason: "heldBeyondNormalRange \(reason)",
                translationX: rawTranslationX,
                count: consecutiveInvalidProbeTranslations
            )
            applySpaceTransitionRenderTransform(
                layerCompensationX: -lastValidProbeTranslationX,
                renderedProbeTranslationX: lastValidProbeTranslationX,
                rawProbeTranslationX: lastValidProbeTranslationX,
                reason: "heldBeyondNormalRange \(reason)"
            )
            return
        }

        consecutiveInvalidProbeTranslations = 0
        lastValidProbeTranslationX = rawTranslationX

        let prediction = predictedProbeTranslationX(at: now) ?? SpaceProbePrediction(
            rawTranslationX: rawTranslationX,
            predictedTranslationX: rawTranslationX,
            predictionLead: 0,
            velocityX: 0
        )
        lastPredictionResult = prediction
        let layerCompensationX = -prediction.predictedTranslationX
        applySpaceTransitionRenderTransform(
            layerCompensationX: layerCompensationX,
            renderedProbeTranslationX: prediction.predictedTranslationX,
            rawProbeTranslationX: rawTranslationX,
            reason: reason
        )
    }

    private func updateProbeBaselineCaptureIfStable(reason: String) {
        guard settings.overlayEnabled,
              spaceMotionProbePanel.isVisible,
              !probeCanonicalFrame.isEmpty,
              let snapshot = currentProbeWindowServerSnapshot(),
              snapshot.isOnscreen else {
            probeStableSampleCount = 0
            handleInvalidSpaceLockSample(reason: "probeBaselineUnavailable \(reason)")
            return
        }

        let rawOffset = snapshot.bounds.minX - probeCanonicalFrame.minX
        guard rawOffset.isFinite else {
            probeStableSampleCount = 0
            handleInvalidSpaceLockSample(reason: "probeBaselineNonFinite \(reason)")
            return
        }

        guard abs(rawOffset) <= SpaceLock.probeBaselineStableTolerance else {
            probeStableSampleCount = 0
            debugSpaceProbe(
                "BASELINE_PENDING",
                "reason=moving \(reason)",
                "rawOffset=\(rawOffset)"
            )
            return
        }

        probeStableSampleCount += 1
        debugSpaceProbe(
            "BASELINE_STABLE_SAMPLE",
            "reason=\(reason)",
            "count=\(probeStableSampleCount)",
            "rawOffset=\(rawOffset)"
        )
        guard probeStableSampleCount >= SpaceLock.probeBaselineRequiredStableSamples else {
            return
        }

        probeWindowServerXOffset = rawOffset
        probeBaselineCapturePending = false
        probeStableSampleCount = 0
        consecutiveInvalidSpaceLockSamples = 0
        debugSpaceProbe(
            "BASELINE_CAPTURED",
            "reason=\(reason)",
            "offset=\(rawOffset)",
            "probeCGX=\(snapshot.bounds.minX)",
            "probeCanonicalX=\(probeCanonicalFrame.minX)"
        )
    }

    private func resetProbeMotionState() {
        lastRawProbeSample = nil
        previousRawProbeSample = nil
        lastDistinctProbeSample = nil
        previousDistinctProbeSample = nil
        distinctProbeSampleIntervalEMA = nil
        estimatedProbeVelocityX = 0
        lastPredictionResult = nil
        #if DEBUG
        visibleIslandErrorSamples.removeAll(keepingCapacity: true)
        #endif
    }

    private func sampleProbeSpaceTranslation(reason: String, timestamp: CFTimeInterval) -> CGFloat? {
        guard let translationX = currentProbeSpaceTranslationX(reason: reason) else {
            return nil
        }

        ingestProbeMotionSample(
            SpaceProbeMotionSample(
                translationX: translationX,
                timestamp: timestamp
            )
        )
        return translationX
    }

    private func currentProbeSpaceTranslationX(reason: String) -> CGFloat? {
        guard let probeWindowServerXOffset,
              !probeCanonicalFrame.isEmpty else {
            return nil
        }
        guard let snapshot = currentProbeWindowServerSnapshot(),
              snapshot.isOnscreen else {
            return nil
        }

        let translationX = SpaceTransitionCompensationMath.probeSpaceTranslationX(
            probeCanonicalX: probeCanonicalFrame.minX,
            actualProbeCGX: snapshot.bounds.minX,
            probeWindowServerXOffset: probeWindowServerXOffset
        )
        #if DEBUG
        if let translationX {
            lastProbeSnapshotForTrace = (
                canonicalX: probeCanonicalFrame.minX,
                actualCGX: snapshot.bounds.minX,
                translationX: translationX
            )
        }
        #endif
        return translationX
    }

    private func ingestProbeMotionSample(_ sample: SpaceProbeMotionSample) {
        previousRawProbeSample = lastRawProbeSample
        lastRawProbeSample = sample

        guard let previousRawProbeSample else {
            lastDistinctProbeSample = sample
            estimatedProbeVelocityX = 0
            return
        }

        guard abs(sample.translationX - previousRawProbeSample.translationX) > SpaceLock.distinctProbeSampleThreshold else {
            return
        }

        let oldLastDistinct = lastDistinctProbeSample
        let oldPreviousDistinct = previousDistinctProbeSample
        var detectedReversal = false
        if let oldLastDistinct, let oldPreviousDistinct {
            let oldDelta = oldLastDistinct.translationX - oldPreviousDistinct.translationX
            let newDelta = sample.translationX - oldLastDistinct.translationX
            detectedReversal = SpaceTransitionCompensationMath.didReverseDirection(
                previousDelta: oldDelta,
                currentDelta: newDelta,
                threshold: SpaceLock.distinctProbeSampleThreshold
            )
        }

        if detectedReversal {
            previousDistinctProbeSample = nil
            lastDistinctProbeSample = sample
            estimatedProbeVelocityX = 0
            return
        }

        previousDistinctProbeSample = oldLastDistinct
        lastDistinctProbeSample = sample

        guard let previousDistinctProbeSample else {
            estimatedProbeVelocityX = 0
            return
        }

        let interval = sample.timestamp - previousDistinctProbeSample.timestamp
        guard interval.isFinite, interval > 0 else {
            estimatedProbeVelocityX = 0
            return
        }

        distinctProbeSampleIntervalEMA = SpaceTransitionCompensationMath.exponentialMovingAverage(
            previous: distinctProbeSampleIntervalEMA,
            newValue: interval,
            alpha: SpaceLock.distinctProbeIntervalEMAAlpha
        )

        let velocityX = (sample.translationX - previousDistinctProbeSample.translationX) / CGFloat(interval)
        let maximumVelocity = effectiveSpaceLockScreenWidth * SpaceLock.maximumProbeVelocityMultiplier
        estimatedProbeVelocityX = abs(velocityX) <= maximumVelocity ? velocityX : 0
    }

    private func predictedProbeTranslationX(at renderTimestamp: CFTimeInterval) -> SpaceProbePrediction? {
        guard let lastDistinctProbeSample else {
            guard let lastRawProbeSample else { return nil }
            return SpaceProbePrediction(
                rawTranslationX: lastRawProbeSample.translationX,
                predictedTranslationX: lastRawProbeSample.translationX,
                predictionLead: 0,
                velocityX: 0
            )
        }

        let rawX = lastDistinctProbeSample.translationX
        let sampleAge = max(0, renderTimestamp - lastDistinctProbeSample.timestamp)
        let sensorInterval = distinctProbeSampleIntervalEMA ?? (1.0 / 120.0)
        let maximumPredictionDistance = min(
            effectiveSpaceLockScreenWidth * SpaceLock.maximumPredictionDistanceMultiplier,
            SpaceLock.maximumPredictionDistanceCap
        )
        guard let prediction = SpaceTransitionCompensationMath.boundedPredictedTranslationX(
            rawTranslationX: rawX,
            velocityX: estimatedProbeVelocityX,
            sampleAge: sampleAge,
            sensorInterval: sensorInterval,
            leadIntervalMultiplier: SpaceLock.predictionLeadIntervalMultiplier,
            minimumLead: SpaceLock.minimumPredictionLead,
            maximumLead: SpaceLock.maximumPredictionLead,
            maximumPredictionDistance: maximumPredictionDistance,
            restTranslationThreshold: SpaceLock.predictionRestTranslationThreshold,
            restVelocityThreshold: SpaceLock.predictionRestVelocityThreshold,
            predictionDisabled: spacePredictionDisabled
        ) else {
            return nil
        }
        return SpaceProbePrediction(
            rawTranslationX: rawX,
            predictedTranslationX: prediction.translationX,
            predictionLead: prediction.lead,
            velocityX: prediction.lead > 0 ? estimatedProbeVelocityX : 0
        )
    }

    private func applySpaceTransitionRenderTransform(
        layerCompensationX: CGFloat,
        renderedProbeTranslationX: CGFloat,
        rawProbeTranslationX: CGFloat,
        reason: String
    ) {
        guard layerCompensationX.isFinite,
              renderedProbeTranslationX.isFinite,
              rawProbeTranslationX.isFinite else {
            handleInvalidSpaceLockSample(reason: "nonFiniteLayerCompensation \(reason)")
            return
        }

        let isNearBaseline = abs(rawProbeTranslationX) <= SpaceLock.transitionCompletionThreshold
        if isNearBaseline {
            transitionCompletionStableSamples += 1
        } else {
            transitionCompletionStableSamples = 0
        }

        if !isSpaceTransitionRenderActive,
           abs(rawProbeTranslationX) > SpaceLock.transitionActivationThreshold {
            activateSpaceTransitionRendering(
                layerCompensationX: layerCompensationX,
                probeTranslationX: rawProbeTranslationX,
                reason: reason
            )
        } else if isSpaceTransitionRenderActive,
                  abs(rawProbeTranslationX) > SpaceLock.transitionCompletionThreshold {
            applyTransitionIslandLayerTransform(layerCompensationX)
        } else if isSpaceTransitionRenderActive,
                  transitionCompletionStableSamples >= SpaceLock.transitionCompletionRequiredStableSamples {
            endSpaceTransitionRendering(reason: "completed \(reason)")
        } else if isSpaceTransitionRenderActive {
            applyTransitionIslandLayerTransform(layerCompensationX)
        }

        recordSpaceMotionMetrics(
            reason: reason,
            rawProbeTranslationX: rawProbeTranslationX,
            predictedProbeTranslationX: renderedProbeTranslationX,
            layerCompensationX: layerCompensationX
        )
    }

    private func activateSpaceTransitionRendering(
        layerCompensationX: CGFloat,
        probeTranslationX: CGFloat,
        reason: String
    ) {
        transitionRenderHandoffPending = false
        transitionRenderHandoffGeneration += 1
        prepareSpaceTransitionRenderPanel(reason: "activate \(reason)")
        layoutTransitionIslandRenderer()
        applyTransitionIslandLayerTransform(layerCompensationX)
        setTransitionIslandVisible(true)
        setMainIslandContentVisible(false)
        islandPanel.ignoresMouseEvents = true
        isSpaceTransitionRenderActive = true
        transitionCompletionStableSamples = 0
        debugSpaceRender(
            "ACTIVATED",
            "reason=\(reason)",
            "probeTranslationX=\(probeTranslationX)",
            "layerCompensationX=\(layerCompensationX)"
        )
    }

    private func endSpaceTransitionRendering(reason: String) {
        guard isSpaceTransitionRenderActive ||
              transitionRenderHandoffPending ||
              transitionIslandHostingView?.layer?.opacity != 0 ||
              abs(lastAppliedTransitionLayerTranslationX) > SpaceLock.renderTransformDedupeThreshold else {
            setMainIslandContentVisible(true)
            updateMousePassthrough()
            return
        }

        spaceLockOffsetX = 0
        applyPhysicalPanelFrame(canonicalPanelFrame, reason: "spaceRender handoff \(reason)")
        applyTransitionIslandLayerTransform(0)
        setMainIslandContentVisible(true)
        isSpaceTransitionRenderActive = false
        transitionRenderHandoffPending = true
        transitionRenderHandoffGeneration += 1
        let generation = transitionRenderHandoffGeneration
        transitionCompletionStableSamples = 0
        debugSpaceRender("HANDOFF_OVERLAP", "reason=\(reason)", "mainPanelFrameX=\(islandPanel.frame.minX)")

        DispatchQueue.main.asyncAfter(deadline: .now() + SpaceLock.handoffOverlapDelay) { [weak self] in
            guard let self else { return }
            guard self.transitionRenderHandoffPending,
                  !self.isSpaceTransitionRenderActive,
                  generation == self.transitionRenderHandoffGeneration else {
                return
            }
            self.finishSpaceTransitionRenderHandoff(reason: reason)
        }
    }

    private func finishSpaceTransitionRenderHandoff(reason: String) {
        setTransitionIslandVisible(false)
        resetTransitionLayerTransform()
        transitionRenderHandoffPending = false
        updateMousePassthrough()
        debugSpaceRender("COMPLETED", "reason=\(reason)", "mainPanelFrameX=\(islandPanel.frame.minX)")
    }

    private func restoreCanonicalMainIslandWhileProbeBaselineUnavailable(reason: String) {
        spaceLockOffsetX = 0
        applyPhysicalPanelFrame(canonicalPanelFrame, reason: "probeBaselineUnavailable \(reason)")
        setMainIslandContentVisible(true)
        setTransitionIslandVisible(false)
        resetTransitionLayerTransform()
        isSpaceTransitionRenderActive = false
        transitionRenderHandoffPending = false
        updateMousePassthrough()
    }

    private func applyTransitionIslandLayerTransform(_ translationX: CGFloat) {
        guard let layer = transitionIslandHostingView?.layer else { return }
        guard abs(translationX - lastAppliedTransitionLayerTranslationX) >= SpaceLock.renderTransformDedupeThreshold else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(CGAffineTransform(translationX: translationX, y: 0))
        CATransaction.commit()
        lastAppliedTransitionLayerTranslationX = translationX
    }

    private func resetTransitionLayerTransform() {
        guard let layer = transitionIslandHostingView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(.identity)
        CATransaction.commit()
        lastAppliedTransitionLayerTranslationX = 0
    }

    private func setMainIslandContentVisible(_ visible: Bool) {
        guard let layer = islandPanel.contentView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = visible ? 1 : 0
        CATransaction.commit()
    }

    private func setTransitionIslandVisible(_ visible: Bool) {
        guard let layer = transitionIslandHostingView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = visible ? 1 : 0
        CATransaction.commit()
    }

    #if DEBUG
    private var lastProbeSnapshotForTrace: (canonicalX: CGFloat, actualCGX: CGFloat, translationX: CGFloat)?
    #endif

    private func handleInvalidProbeTranslation(reason: String, translationX: CGFloat) {
        consecutiveInvalidProbeTranslations += 1
        throttledSpaceProbeInvalidTranslationLog(
            reason: reason,
            translationX: translationX,
            count: consecutiveInvalidProbeTranslations
        )
        guard consecutiveInvalidProbeTranslations >= SpaceLock.invalidProbeTranslationRecoveryThreshold else {
            return
        }

        recoverSpaceLockFromRunaway(reason: "invalidProbeTranslation \(reason)", actualCGX: currentWindowServerSnapshot()?.bounds.minX)
    }

    private var effectiveSpaceLockScreenWidth: CGFloat {
        let width = islandPanel.screen?.frame.width ?? NSScreen.main?.frame.width ?? 1_440
        guard width.isFinite, width > 0 else { return 1_440 }
        return width
    }

    private var spacePredictionDisabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_DISABLE_SPACE_PREDICTION"] == "1"
        #else
        false
        #endif
    }

    private func maximumSpaceLockOffset(screenWidth: CGFloat) -> CGFloat {
        SpaceTransitionCompensationMath.maximumTotalOffset(
            screenWidth: screenWidth,
            multiplier: SpaceLock.maximumTotalOffsetMultiplier
        ) ?? (1_440 * SpaceLock.maximumTotalOffsetMultiplier)
    }

    private func handleInvalidSpaceLockSample(reason: String) {
        consecutiveInvalidSpaceLockSamples += 1
        guard consecutiveInvalidSpaceLockSamples >= SpaceLock.invalidSampleRecoveryThreshold else {
            return
        }

        recoverSpaceLockFromRunaway(reason: "invalidWindowServerSamples \(reason)", actualCGX: nil)
    }

    private func recoverSpaceLockFromRunaway(reason: String, actualCGX: CGFloat?) {
        guard spaceCompensationEnabled else { return }
        let screenWidth = effectiveSpaceLockScreenWidth
        let physicalX = islandPanel.frame.minX
        let offsetX = physicalX - canonicalPanelFrame.minX
        debugSpaceProbeRecovery(
            reason: reason,
            canonicalX: canonicalPanelFrame.minX,
            physicalX: physicalX,
            actualCGX: actualCGX,
            offsetX: offsetX,
            screenWidth: screenWidth
        )

        spaceLockOffsetX = 0
        consecutiveInvalidSpaceLockSamples = 0
        consecutiveInvalidProbeTranslations = 0
        applyPhysicalPanelFrame(canonicalPanelFrame, reason: "spaceLock recovery \(reason)")
        debugOverlayWindowOperation(operation: "orderFrontRegardless", reason: "spaceLock recovery \(reason)")
        islandPanel.orderFrontRegardless()
        updateMousePassthrough()
        spaceLockRecoveryUntil = CACurrentMediaTime() + SpaceLock.recoveryCooldown
        prepareSpaceMotionProbe(reason: "recovery \(reason)")

        #if DEBUG
        debugSpaceProbe(
            "RECOVERED",
            "canonicalX=\(canonicalPanelFrame.minX)",
            "physicalX=\(islandPanel.frame.minX)"
        )
        #endif
    }

    private func scheduleSpaceLockRecoveryVerification(reason: String) {
        guard spaceCompensationEnabled else { return }
        for delay in SpaceLock.recoveryVerificationDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.verifySpaceLockRecovery(reason: "\(reason) delay=\(delay)")
            }
        }
    }

    private func verifySpaceLockRecovery(reason: String) {
        guard spaceCompensationEnabled else { return }
        guard settings.overlayEnabled,
              islandPanel.isVisible,
              !canonicalPanelFrame.isEmpty else {
            return
        }

        let screenWidth = effectiveSpaceLockScreenWidth
        let maximumTotalOffset = maximumSpaceLockOffset(screenWidth: screenWidth)
        let physicalOffset = islandPanel.frame.minX - canonicalPanelFrame.minX
        if SpaceTransitionCompensationMath.exceedsMaximumOffset(
            physicalOffset,
            maximumOffset: maximumTotalOffset
        ) {
            recoverSpaceLockFromRunaway(reason: "verificationPhysicalOffsetExceeded \(reason)", actualCGX: currentWindowServerSnapshot()?.bounds.minX)
            return
        }

        guard let translationX = currentProbeSpaceTranslationX(reason: "verification \(reason)") else {
            return
        }

        guard abs(translationX) <= SpaceLock.deadzone,
              abs(physicalOffset) > SpaceLock.activeOffsetThreshold else {
            return
        }

        spaceLockOffsetX = 0
        consecutiveInvalidProbeTranslations = 0
        applyPhysicalPanelFrame(canonicalPanelFrame, reason: "spaceLock verification restored \(reason)")
        updateMousePassthrough()
        debugSpaceProbe(
            "RECOVERED",
            "reason=verification",
            "canonicalX=\(canonicalPanelFrame.minX)",
            "physicalX=\(islandPanel.frame.minX)",
            "translationX=\(translationX)"
        )
    }

    private func currentWindowServerSnapshot() -> OverlayWindowServerSnapshot? {
        currentWindowServerSnapshot(for: islandPanel)
    }

    private func currentProbeWindowServerSnapshot() -> OverlayWindowServerSnapshot? {
        if probeWindowID == nil, spaceMotionProbePanel.windowNumber > 0 {
            probeWindowID = CGWindowID(spaceMotionProbePanel.windowNumber)
        }
        guard let probeWindowID,
              probeWindowID > 0 else {
            return nil
        }
        return currentWindowServerSnapshot(windowID: probeWindowID)
    }

    private func currentWindowServerSnapshot(for window: NSWindow) -> OverlayWindowServerSnapshot? {
        let requestedWindowNumber = window.windowNumber
        guard requestedWindowNumber > 0 else { return nil }
        return currentWindowServerSnapshot(windowID: CGWindowID(requestedWindowNumber))
    }

    private func currentWindowServerSnapshot(windowID: CGWindowID) -> OverlayWindowServerSnapshot? {
        let requestedWindowNumber = Int(windowID)
        guard requestedWindowNumber > 0,
              let windows = CGWindowListCopyWindowInfo(
                  [.optionIncludingWindow],
                  windowID
              ) as? [[String: Any]],
              let windowInfo = windows.first,
              let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
              bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }

        return OverlayWindowServerSnapshot(
            windowNumber: intValue(windowInfo[kCGWindowNumber as String]) ?? requestedWindowNumber,
            bounds: bounds,
            isOnscreen: boolValue(windowInfo[kCGWindowIsOnscreen as String]) ?? false,
            layer: intValue(windowInfo[kCGWindowLayer as String]) ?? 0,
            alpha: doubleValue(windowInfo[kCGWindowAlpha as String]) ?? 0,
            ownerName: windowInfo[kCGWindowOwnerName as String] as? String
        )
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func throttledSpaceProbeTrace(
        reason: String,
        translationX: CGFloat,
        desiredIslandOffsetX: CGFloat,
        physicalIslandX: CGFloat
    ) {
        #if DEBUG
        let shouldTraceEveryFrame = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS_VERBOSE"] == "1"
        let now = CACurrentMediaTime()
        guard shouldTraceEveryFrame || now - lastSpaceProbeTraceLogAt >= 0.05 else {
            return
        }
        lastSpaceProbeTraceLogAt = now

        let probeSnapshot = lastProbeSnapshotForTrace
        let islandActualCGX = currentWindowServerSnapshot()?.bounds.minX
        debugSpaceProbe(
            "track",
            "reason=\(reason)",
            "probeCanonicalX=\(probeSnapshot?.canonicalX ?? probeCanonicalFrame.minX)",
            "probeActualCGX=\(probeSnapshot?.actualCGX ?? .nan)",
            "translationX=\(translationX)",
            "desiredIslandOffsetX=\(desiredIslandOffsetX)",
            "canonicalIslandX=\(canonicalPanelFrame.minX)",
            "physicalIslandX=\(physicalIslandX)",
            "islandActualCGX=\(String(describing: islandActualCGX))"
        )
        #endif
    }

    private func recordSpaceMotionMetrics(
        reason: String,
        rawProbeTranslationX: CGFloat,
        predictedProbeTranslationX: CGFloat,
        layerCompensationX: CGFloat
    ) {
        #if DEBUG
        guard spaceTraceEnabled else { return }
        let now = CACurrentMediaTime()
        if now - lastVisibleIslandErrorSampleAt >= 0.05 {
            lastVisibleIslandErrorSampleAt = now
            if let islandActualCGX = currentWindowServerSnapshot()?.bounds.minX {
                visibleIslandErrorSamples.append(abs(islandActualCGX - canonicalPanelFrame.minX))
                if visibleIslandErrorSamples.count > 240 {
                    visibleIslandErrorSamples.removeFirst(visibleIslandErrorSamples.count - 240)
                }
            }
        }

        guard now - lastSpaceMotionMetricsLogAt >= 0.25 else {
            return
        }
        lastSpaceMotionMetricsLogAt = now

        let distinctProbeSampleHz = distinctProbeSampleIntervalEMA.map { $0 > 0 ? 1.0 / $0 : 0 } ?? 0
        let predictionLeadMs = (lastPredictionResult?.predictionLead ?? 0) * 1_000
        let velocityX = lastPredictionResult?.velocityX ?? 0
        let sortedErrors = visibleIslandErrorSamples.sorted()
        let p95Error: CGFloat
        if sortedErrors.isEmpty {
            p95Error = 0
        } else {
            let index = min(sortedErrors.count - 1, Int(Double(sortedErrors.count - 1) * 0.95))
            p95Error = sortedErrors[index]
        }
        let maxError = visibleIslandErrorSamples.max() ?? 0

        debugSpaceRender(
            "track",
            "reason=\(reason)",
            "displayFPS=\(String(format: "%.1f", lastObservedSpaceProbeFPS))",
            "distinctProbeSampleHz=\(String(format: "%.1f", distinctProbeSampleHz))",
            "rawTranslationX=\(rawProbeTranslationX)",
            "predictedTranslationX=\(predictedProbeTranslationX)",
            "predictionLeadMilliseconds=\(String(format: "%.2f", predictionLeadMs))",
            "velocityX=\(velocityX)",
            "layerCompensationX=\(layerCompensationX)",
            "mainQueueRenderDelayMilliseconds=\(String(format: "%.2f", lastMainQueueRenderDelay * 1_000))",
            "p95VisualErrorX=\(p95Error)",
            "maxVisualErrorX=\(maxError)",
            "transitionActive=\(isSpaceTransitionRenderActive)",
            "mainPanelFrameX=\(islandPanel.frame.minX)",
            "mainContentVisible=\((islandPanel.contentView?.layer?.opacity ?? 1) > 0)",
            "transitionContentVisible=\((transitionIslandHostingView?.layer?.opacity ?? 0) > 0)"
        )
        #endif
    }

    private func recordSpaceProbeFrame(now: CFTimeInterval) {
        #if DEBUG
        if spaceProbeFrameSampleStartedAt == 0 {
            spaceProbeFrameSampleStartedAt = now
            spaceProbeFrameSampleCount = 0
        }

        spaceProbeFrameSampleCount += 1
        let elapsed = now - spaceProbeFrameSampleStartedAt
        guard elapsed >= 1 else { return }

        lastObservedSpaceProbeFPS = Double(spaceProbeFrameSampleCount) / elapsed
        if spaceTraceEnabled {
            debugSpaceProbe(
                "observedFPS",
                "fps=\(String(format: "%.1f", lastObservedSpaceProbeFPS))"
            )
        }
        spaceProbeFrameSampleStartedAt = now
        spaceProbeFrameSampleCount = 0
        #endif
    }

    private func throttledSpaceProbeInvalidTranslationLog(
        reason: String,
        translationX: CGFloat,
        count: Int
    ) {
        #if DEBUG
        let now = CACurrentMediaTime()
        guard now - lastSpaceLockCorrectionLogAt >= 0.15 else {
            return
        }
        lastSpaceLockCorrectionLogAt = now
        debugSpaceProbe(
            "invalidTranslationHeld",
            "reason=\(reason)",
            "translationX=\(translationX)",
            "count=\(count)"
        )
        #endif
    }

    private func debugSpaceProbeRecovery(
        reason: String,
        canonicalX: CGFloat,
        physicalX: CGFloat,
        actualCGX: CGFloat?,
        offsetX: CGFloat,
        screenWidth: CGFloat
    ) {
        #if DEBUG
        debugSpaceProbe(
            "PROBE_RECOVERY",
            "reason=\(reason)",
            "canonicalX=\(canonicalX)",
            "physicalX=\(physicalX)",
            "actualCGX=\(String(describing: actualCGX))",
            "offsetX=\(offsetX)",
            "screenWidth=\(screenWidth)"
        )
        #endif
    }

    private func debugSpaceProbe(_ event: String, _ fields: String...) {
        #if DEBUG
        guard spaceTraceEnabled || [
            "displayLinkStarted",
            "displayLinkStopped",
            "BASELINE_CAPTURED",
            "PROBE_RECOVERY",
            "RECOVERED"
        ].contains(event) else {
            return
        }
        print("[SpaceProbe]", event, fields.joined(separator: " "))
        #endif
    }

    private func debugSpaceRender(_ event: String, _ fields: String...) {
        #if DEBUG
        guard spaceTraceEnabled || [
            "canvasSetFrame",
            "ACTIVATED",
            "HANDOFF_OVERLAP",
            "COMPLETED"
        ].contains(event) else {
            return
        }
        print("[SpaceRender]", event, fields.joined(separator: " "))
        #endif
    }

    private func debugSpaceLock(_ event: String, _ fields: String...) {
        #if DEBUG
        print("[SpaceLock]", event, fields.joined(separator: " "))
        #endif
    }

    #if DEBUG
    private var spaceTraceEnabled: Bool {
        ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS"] == "1" ||
            ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS_VERBOSE"] == "1"
    }
    #endif

    private func recordCanonicalFrameApplication(reason: String) {
        #if DEBUG
        let now = CACurrentMediaTime()
        if now - canonicalFrameApplicationWindowStartedAt > 1 {
            canonicalFrameApplicationWindowStartedAt = now
            canonicalFrameApplicationCount = 0
        }

        canonicalFrameApplicationCount += 1
        if canonicalFrameApplicationCount > 6 {
            debugPrint(
                "[OverlayGeometry]",
                "WARNING excessive canonical frame applications",
                "count=\(canonicalFrameApplicationCount)",
                "reason=\(reason)",
                "signature=\(String(describing: lastAppliedGeometrySignature ?? currentGeometrySignature))"
            )
        }
        #endif
    }

    private func startOverlayTransitionTrace(reason: String) {
        #if DEBUG
        guard spaceCompensationEnabled else { return }
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_TRACE_SPACE_TRANSITIONS"] == "1" else {
            return
        }
        guard overlayTransitionTraceTimer == nil else { return }

        let startedAt = CACurrentMediaTime()
        overlayTransitionTraceStartedAt = startedAt
        logOverlayTransitionTraceSample(reason: reason, elapsed: 0)

        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleOverlayTransitionTraceTimer(reason: reason)
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        overlayTransitionTraceTimer = timer
        #endif
    }

    private func handleOverlayTransitionTraceTimer(reason: String) {
        #if DEBUG
        guard let traceStartedAt = overlayTransitionTraceStartedAt else {
            overlayTransitionTraceTimer?.invalidate()
            overlayTransitionTraceTimer = nil
            return
        }

        let elapsed = CACurrentMediaTime() - traceStartedAt
        guard elapsed <= 2.5 else {
            overlayTransitionTraceTimer?.invalidate()
            overlayTransitionTraceTimer = nil
            overlayTransitionTraceStartedAt = nil
            return
        }

        logOverlayTransitionTraceSample(reason: reason, elapsed: elapsed)
        #endif
    }

    private func startOverlayTransitionTraceIfEventIsOutsideIsland(_ event: NSEvent) {
        #if DEBUG
        guard spaceCompensationEnabled else { return }
        if event.type == .scrollWheel,
           !event.phase.isEmpty,
           !event.phase.contains(.began) {
            return
        }

        let screenPoint = NSEvent.mouseLocation
        let visibleIslandRect = currentVisibleIslandScreenRect
        guard visibleIslandRect.isEmpty || !visibleIslandRect.contains(screenPoint) else {
            return
        }

        startOverlayTransitionTrace(reason: "systemGesture")
        #endif
    }

    private func logOverlayTransitionTraceSample(reason: String, elapsed: CFTimeInterval) {
        #if DEBUG
        let cgWindowInfo = overlayCGWindowInfo()
        print(
            "[OverlayTransitionTrace]",
            "t=\(String(format: "%.3f", elapsed))",
            "reason=\(reason)",
            "windowNumber=\(islandPanel.windowNumber)",
            "appKitVisible=\(islandPanel.isVisible)",
            "onActiveSpace=\(islandPanel.isOnActiveSpace)",
            "occlusion=\(islandPanel.occlusionState.rawValue)",
            "level=\(islandPanel.level.rawValue)",
            "collectionBehavior=\(islandPanel.collectionBehavior.rawValue)",
            "frame=\(islandPanel.frame)",
            "alpha=\(islandPanel.alphaValue)",
            "ignoresMouseEvents=\(islandPanel.ignoresMouseEvents)",
            "cgOnscreen=\(cgWindowInfo.onscreen)",
            "cgLayer=\(cgWindowInfo.layer)",
            "cgAlpha=\(cgWindowInfo.alpha)",
            "cgBounds=\(cgWindowInfo.bounds)",
            "cgOwnerName=\(cgWindowInfo.ownerName)",
            "cgWindowNumber=\(cgWindowInfo.windowNumber)"
        )
        #endif
    }

    private func overlayCGWindowInfo() -> (
        onscreen: String,
        layer: String,
        alpha: String,
        bounds: String,
        ownerName: String,
        windowNumber: String
    ) {
        #if DEBUG
        guard let snapshot = currentWindowServerSnapshot() else {
            return ("nil", "nil", "nil", "nil", "nil", "nil")
        }

        return (
            "\(snapshot.isOnscreen ? 1 : 0)",
            "\(snapshot.layer)",
            "\(snapshot.alpha)",
            "\(snapshot.bounds)",
            snapshot.ownerName ?? "nil",
            "\(snapshot.windowNumber)"
        )
        #else
        return ("nil", "nil", "nil", "nil", "nil", "nil")
        #endif
    }

    private func debugWindowBoundsString(_ value: Any?) -> String {
        #if DEBUG
        guard let boundsDictionary = value as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
            return debugString(value)
        }
        return "\(rect)"
        #else
        return "nil"
        #endif
    }

    private func debugString(_ value: Any?) -> String {
        #if DEBUG
        guard let value else { return "nil" }
        return "\(value)"
        #else
        return "nil"
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
        guard !spaceCompensationEnabled,
              !didLogAtollParityConfiguration else {
            return
        }

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
            "containsCanJoinAllApplications=\(islandPanel.collectionBehavior.contains(.canJoinAllApplications))",
            "spaceDisplayLinkRunning=\(spaceLockDisplayLink.isRunning)",
            "probeVisible=\(spaceMotionProbePanel.isVisible)",
            "transitionRenderVisible=\(spaceTransitionRenderPanel.isVisible)",
            "islandVisible=\(islandPanel.isVisible)"
        )
        #endif
    }

    private func logSpaceNativeABConfigurationIfNeeded() {
        #if DEBUG
        guard !spaceCompensationEnabled,
              !didLogSpaceNativeABConfiguration else {
            return
        }

        didLogSpaceNativeABConfiguration = true
        print(
            "[SpaceNativeAB]",
            "canJoinAllApplications=\(islandPanel.collectionBehavior.contains(.canJoinAllApplications))",
            "level=\(islandPanel.level.rawValue)",
            "collectionBehavior=\(islandPanel.collectionBehavior.rawValue)"
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

private final class SpaceMotionProbePanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class SpaceTransitionRenderPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class SpaceLockDisplayLink: @unchecked Sendable {
    private var displayLink: CVDisplayLink?
    private let stateLock = NSLock()
    private var updatePending = false
    private var frameHandler: ((CFTimeInterval) -> Void)?

    var isRunning: Bool {
        guard let displayLink else { return false }
        return CVDisplayLinkIsRunning(displayLink)
    }

    var nominalFramesPerSecond: Double? {
        guard let displayLink else { return nil }
        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink)
        guard period.timeValue > 0,
              period.timeScale > 0 else {
            return nil
        }
        return Double(period.timeScale) / Double(period.timeValue)
    }

    func start(frameHandler: @escaping (CFTimeInterval) -> Void) {
        self.frameHandler = frameHandler

        if let displayLink {
            if !CVDisplayLinkIsRunning(displayLink) {
                CVDisplayLinkStart(displayLink)
            }
            return
        }

        var createdLink: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&createdLink) == kCVReturnSuccess,
              let createdLink else {
            return
        }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkSetOutputCallback(
            createdLink,
            { _, _, _, _, _, context in
                guard let context else { return kCVReturnSuccess }
                let displayLink = Unmanaged<SpaceLockDisplayLink>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                displayLink.enqueueFrame()
                return kCVReturnSuccess
            },
            context
        )
        displayLink = createdLink
        CVDisplayLinkStart(createdLink)
    }

    func stop() {
        if let displayLink, CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStop(displayLink)
        }
        stateLock.lock()
        updatePending = false
        stateLock.unlock()
    }

    private func enqueueFrame() {
        let frameTimestamp = CACurrentMediaTime()
        stateLock.lock()
        if updatePending {
            stateLock.unlock()
            return
        }
        updatePending = true
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            self.updatePending = false
            let handler = self.frameHandler
            self.stateLock.unlock()
            handler?(frameTimestamp)
        }
    }

    deinit {
        stop()
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
