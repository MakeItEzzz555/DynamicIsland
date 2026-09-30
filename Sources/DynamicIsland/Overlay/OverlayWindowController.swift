import AppKit
import Combine
import QuartzCore
import SwiftUI

struct OverlayGeometrySignature: Equatable, CustomStringConvertible {
    let collapsedSize: CGSize
    let expandedSize: CGSize
    let expandedPresentationKind: ExpandedPresentationKind
    let collapsedActivityProfile: CollapsedActivityLayoutProfile?
    let collapsedPresentationProfile: CollapsedPresentationProfile
    let useAdaptiveNotchSizing: Bool
    let respectHardwareNotch: Bool

    var description: String {
        "collapsedSize=\(collapsedSize) expandedSize=\(expandedSize) expandedPresentation=\(expandedPresentationKind.rawValue) collapsedActivityProfile=\(String(describing: collapsedActivityProfile)) collapsedPresentationProfile=\(collapsedPresentationProfile.kind.rawValue) useAdaptiveNotchSizing=\(useAdaptiveNotchSizing) respectHardwareNotch=\(respectHardwareNotch)"
    }
}

enum ExpandedScrollEventRoute: Equatable {
    case islandGesture
    case passThroughToContent
}

struct ExpandedScrollEventRoutingPolicy {
    static func route(
        isSuppressed: Bool,
        isExpanded: Bool,
        gesturesEnabled: Bool,
        usesTrackpad: Bool,
        contentScrollHit: Bool = false,
        contentScrollSequenceActive: Bool = false
    ) -> ExpandedScrollEventRoute {
        guard gesturesEnabled, usesTrackpad else {
            return .passThroughToContent
        }
        guard !isExpanded || (!isSuppressed && !contentScrollHit && !contentScrollSequenceActive) else {
            return .passThroughToContent
        }
        return .islandGesture
    }
}

/// Classifies scroll intent from trackpad deltas.
///
/// Returns nil while the movement is too small to judge, so a noisy first
/// frame cannot decide ownership. Over a registered content region (the
/// Agents transcript) a gesture only counts as horizontal, and therefore as
/// an island page/close gesture, when horizontal movement clearly dominates.
enum ExpandedScrollIntent {
    static let minimumDelta: CGFloat = 1.5
    static let contentHorizontalDominance: CGFloat = 1.8

    static func isVertical(deltaX: CGFloat, deltaY: CGFloat, insideContent: Bool) -> Bool? {
        let x = abs(deltaX)
        let y = abs(deltaY)
        guard max(x, y) >= minimumDelta else { return nil }
        if insideContent {
            return x <= y * contentHorizontalDominance
        }
        return y >= x
    }
}

/// Camera Mirror must suppress only island-level vertical swipe actions. It
/// never consumes vertical input itself, so the native ScrollView remains the
/// event owner. Strong horizontal intent remains eligible for workspace/tab
/// navigation through the normal gesture router.
enum CameraMirrorScrollRoutingPolicy {
    static func shouldPassThroughToContent(
        mirrorActive: Bool,
        pointerInsideRightWorkspace: Bool,
        deltaX: CGFloat,
        deltaY: CGFloat
    ) -> Bool {
        guard mirrorActive, pointerInsideRightWorkspace else { return false }
        return ExpandedScrollIntent.isVertical(
            deltaX: deltaX,
            deltaY: deltaY,
            insideContent: true
        ) != false
    }
}

enum ExpandedContentScrollSequencePhase: Equatable {
    case physicalBegan
    case physicalChanged
    case physicalEnded
    case physicalCancelled
    case momentumBegan
    case momentumChanged
    case momentumEnded
    case momentumCancelled
    case phaseLess
}

struct ExpandedContentScrollSequenceOwnership: Equatable {
    enum Owner: Equatable {
        case content
        case island
    }

    private(set) var owner: Owner?
    private var startedInsideContent = false
    private var hasPhysicalStart = false

    mutating func route(
        phase: ExpandedContentScrollSequencePhase,
        startsInsideContent: Bool,
        verticalIntent: Bool?
    ) -> ExpandedScrollEventRoute {
        if phase == .physicalBegan {
            owner = nil
            startedInsideContent = startsInsideContent
            hasPhysicalStart = true
        } else if owner == nil,
                  !hasPhysicalStart,
                  phase == .physicalChanged || phase == .phaseLess {
            startedInsideContent = startsInsideContent
        }

        if owner == nil, let verticalIntent {
            owner = startedInsideContent && verticalIntent ? .content : .island
        }
        if owner == nil, phase == .momentumBegan || phase == .momentumChanged {
            owner = .island
        }

        // While intent is still undecided, a sequence that began inside the
        // content region scrolls the content instead of feeding island gestures.
        let route: ExpandedScrollEventRoute =
            owner == .content || (owner == nil && startedInsideContent)
            ? .passThroughToContent
            : .islandGesture

        if phase == .physicalCancelled || phase == .momentumEnded || phase == .momentumCancelled {
            reset()
        }
        return route
    }

    mutating func reset() {
        owner = nil
        startedInsideContent = false
        hasPhysicalStart = false
    }
}

// Enablement stays in AppSettings; only transient callback/input ownership lives here.
struct OverlayPresentationSession {
    private(set) var generation = 0
    private var resumedAt: TimeInterval = 0
    private var lastScrollAt: TimeInterval?
    private var waitingForFreshScroll = false

    mutating func invalidate(at timestamp: TimeInterval) {
        generation += 1
        resumedAt = timestamp
        lastScrollAt = timestamp
        waitingForFreshScroll = true
    }

    func allowsWork(overlayEnabled: Bool, generation callbackGeneration: Int? = nil) -> Bool {
        overlayEnabled && (callbackGeneration == nil || callbackGeneration == generation)
    }

    mutating func acceptsScroll(
        overlayEnabled: Bool, timestamp: TimeInterval, phase: NSEvent.Phase,
        quietPeriod: TimeInterval
    ) -> Bool {
        guard allowsWork(overlayEnabled: overlayEnabled), timestamp >= resumedAt else { return false }
        guard waitingForFreshScroll else { return true }
        let followsQuietGap = lastScrollAt.map { timestamp - $0 > quietPeriod } ?? true
        lastScrollAt = timestamp
        // Explicit beginnings, or the existing quiet boundary for phase-less devices,
        // distinguish a new swipe from the previous session's continuing tail.
        guard phase.contains(.began) || phase.contains(.mayBegin) || (phase.isEmpty && followsQuietGap) else { return false }
        waitingForFreshScroll = false
        return true
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

    private let expandedHoverTolerance: CGFloat = ExpandedHoverContainment.tolerance
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
    private let escapeRouter = IslandEscapeRouter()
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
    private var presentationSession = OverlayPresentationSession()
    private var visibilityGeneration: Int = 0
    private var morphGeneration: Int = 0
    private var expandedAt: CFTimeInterval = 0
    private var nativeMenuTrackingDepth = 0
    private var collapsedScrollDelta: CGSize = .zero
    private var collapsedScrollGestureHandled = false
    private var collapsedScrollLastActionAt: CFTimeInterval?
    private var expandedScrollDelta: CGSize = .zero
    private var expandedScrollGestureHandled = false
    private var rightWorkspaceSwipe = RightWorkspaceSwipeRecognizer()
    private var expandedScrollLastActionAt: CFTimeInterval?
    private var expandedScrollGestureResetWorkItem: DispatchWorkItem?
    private var expandedContentScrollOwnership = ExpandedContentScrollSequenceOwnership()
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
    private var didLogExpandedScrollPassThrough = false
    #endif
    private weak var hostingView: IslandHostingView<TopPinnedHostRoot<IslandRootView>>?

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
            escapeRouter: escapeRouter,
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
        // NSHostingView centers a root whose size differs from its bounds.
        // While the panel's frame animates, the canvas and the window can
        // differ for a frame or more; top-pinning the root keeps the shell's
        // top edge on the notch in every frame instead of drifting by half
        // the size difference (the Agents <-> tab "detach" bug).
        let hostingView = IslandHostingView(rootView: TopPinnedHostRoot(content: rootView))
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.onMouseExited = { [weak self] in
            self?.collapseIfExpandedMouseOutsideAfterGrace()
        }
        hostingView.interactiveRegionProvider = { [weak self] in
            self?.currentInteractiveRegion() ?? .zero
        }
        hostingView.accessoryRegionsProvider = { [weak self] in
            self?.currentAccessoryInteractiveRegions() ?? []
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

        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                self?.nativeMenuTrackingDepth += 1
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.nativeMenuTrackingDepth = max(self.nativeMenuTrackingDepth - 1, 0)
            }
            .store(in: &cancellables)

        islandState.$state
            .sink { [weak self] _ in
                let generation = self?.presentationSession.generation
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.allowsOverlayWork(generation: generation) else { return }
                    let state = self.islandState.state
                    self.debugLog("state committed as \(state)")
                    self.debugLog("state changed to \(state)")
                    if state == .expanded {
                        self.layoutStore.isExpandedContentExiting = false
                    } else {
                        self.resetExpandedContentScrollTracking()
                        self.layoutStore.setExpandedContentScrollRegion(.zero)
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

        modules.agentAttention.$presentation
            .combineLatest(modules.agentEvents.$sessions, settings.$agentActivityEnabled)
            .map { presentation, sessions, enabled in
                if let presentation {
                    let session = presentation.primary.flatMap { primary in
                        sessions.first { $0.id == primary.session }
                    }
                    return AgentCollapsedShellPresentation.attention(presentation, session: session)
                }
                return AgentCollapsedShellPresentation.routine(sessions: sessions, enabled: enabled) ?? .normal
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                let generation = self?.presentationSession.generation
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.allowsOverlayWork(generation: generation) else { return }
                    self.beginCollapsedPresentationMorph()
                    self.reposition(animated: true, reason: "agentCollapsedPresentationChanged", force: true)
                }
            }
            .store(in: &cancellables)

        layoutStore.$isExpandedScrollGestureSuppressed
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resetExpandedScrollTracking()
                #if DEBUG
                self?.didLogExpandedScrollPassThrough = false
                #endif
            }
            .store(in: &cancellables)

        modules.navigation.$selectedPage
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] page in
                guard let self else { return }
                let sessionGeneration = self.presentationSession.generation

                // @Published emits its new value before the backing property is
                // committed. Repositioning synchronously from this sink can
                // therefore force AppKit/SwiftUI layout while selectedPage still
                // contains the previous page, producing the exact "one page
                // behind" navigation highlight and geometry profile seen on-device.
                // Defer one main-run-loop turn, then reject stale queued page
                // changes so the newest selection owns both content and geometry.
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.allowsOverlayWork(generation: sessionGeneration),
                          self.modules.navigation.selectedPage == page else {
                        return
                    }

                    self.resetExpandedContentScrollTracking()
                    if page != .agents {
                        self.layoutStore.setExpandedContentScrollRegion(.zero)
                    }
                    guard self.islandState.state == .expanded else { return }
                    self.beginExpandedPageMorph()
                    self.reposition(
                        animated: true,
                        reason: "expandedPageChanged",
                        force: true
                    )
                }
            }
            .store(in: &cancellables)

        settings.$overlayEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                // Published emits before commit. Suspend immediately; enabling is deferred
                // until the preference commits, with the new session guarding the callback.
                self?.setVisible(enabled)
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                let generation = self?.presentationSession.generation
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.allowsOverlayWork(generation: generation) else { return }
                    self.reposition(animated: false, reason: "settingsChanged")
                }
            }
            .store(in: &cancellables)

        layoutStore.$collapsedPreviewActive
            .combineLatest(layoutStore.$collapsedPreviewSurfaceFrame)
            .sink { [weak self] _, _ in
                let generation = self?.presentationSession.generation
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.allowsOverlayWork(generation: generation) else { return }
                    self.updateMousePassthrough()
                }
            }
            .store(in: &cancellables)

        modules.media.$hasActiveMediaSource
            .removeDuplicates()
            .sink { [weak self] hasActiveMediaSource in
                let generation = self?.presentationSession.generation
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.allowsOverlayWork(generation: generation) else { return }
                    #if DEBUG
                    debugPrint(
                        "DynamicIsland Overlay media active changed",
                        "hasActiveMediaSource=\(hasActiveMediaSource)",
                        "mediaInstance=\(ObjectIdentifier(modules.media))"
                    )
                    #endif
                    self.reposition(animated: true, reason: "mediaActiveChanged")
                }
            }
            .store(in: &cancellables)

        modules.liveActivities.$activities
            .map { [weak self] activities in
                self?.collapsedActivityLayoutProfile(activities: activities)
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                let generation = self?.presentationSession.generation
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.allowsOverlayWork(generation: generation) else { return }
                    self.reposition(animated: true, reason: "collapsedActivityPresenceChanged")
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

    private var canPresentOverlay: Bool {
        presentationSession.allowsWork(overlayEnabled: settings.overlayEnabled)
    }

    private func allowsOverlayWork(generation: Int?) -> Bool {
        guard let generation else { return false }
        return presentationSession.allowsWork(overlayEnabled: settings.overlayEnabled, generation: generation)
    }

    private func acceptsOverlayScroll(_ event: NSEvent) -> Bool {
        presentationSession.acceptsScroll(
            overlayEnabled: settings.overlayEnabled, timestamp: event.timestamp,
            phase: event.phase, quietPeriod: collapsedScrollQuietResetDelay
        )
    }

    func show() {
        guard canPresentOverlay else { return }
        islandState.collapse()
        reposition(animated: false, reason: "initialShow", force: true)
        updateWindowVisibility()
        logAtollParityConfigurationIfNeeded()
    }

    func setVisible(_ visible: Bool) {
        presentationSession.invalidate(at: ProcessInfo.processInfo.systemUptime)
        layoutStore.overlayPresentationGeneration = presentationSession.generation
        if visible {
            let generation = presentationSession.generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.allowsOverlayWork(generation: generation) else { return }
                self.show()
            }
        } else {
            morphGeneration += 1
            visibilityGeneration += 1
            stopMouseContainmentTimer()
            modules.stats.stopPolling()
            resetExpandedScrollTracking()
            resetCollapsedScrollTracking()
            resetMediaSwipeSession()
            mediaSwipeUnlockWorkItem?.cancel()
            mediaSwipeUnlockWorkItem = nil
            mediaSwipeCommandInFlight = false
            mediaSwipeLockedUntil = .distantPast
            expandedScrollLockedUntil = .distantPast
            collapsedScrollLastActionAt = nil
            expandedScrollLastActionAt = nil
            layoutStore.isShellMorphing = false
            layoutStore.isCollapseShellOnly = false
            layoutStore.isExpandedContentExiting = false
            layoutStore.updateCollapsedPreview(active: false, frame: .zero)
            layoutStore.setExpandedScrollGestureSuppressed(false)
            escapeRouter.setTopmostPresentation(nil)
            modules.navigation.setFileDropTargeted(false)
            islandState.collapse()
            islandPanel.ignoresMouseEvents = true
            islandPanel.orderOut(nil)
            lastOrderedVisibilityState = nil
        }
    }

    func reposition(
        animated: Bool = false,
        reason: String = "unspecified",
        force: Bool = false
    ) {
        guard canPresentOverlay else { return }
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
            expandedSize: resolvedExpandedSize,
            collapsedActivityProfile: collapsedActivityLayoutProfile,
            collapsedPresentationProfile: collapsedPresentationProfile,
            useAdaptiveNotchSizing: settings.useAdaptiveNotchSizing,
            respectHardwareNotch: settings.respectHardwareNotch
        )
        debugGeometryRefresh(geometry)
        targetCollapsedFrame = geometry.collapsedFrame
        targetExpandedFrame = geometry.expandedFrame
        updateLayout(
            panelFrame: expandedPresentationProfile.panelFrame(forExpandedFrame: geometry.expandedFrame),
            collapsedFrame: geometry.collapsedFrame,
            expandedFrame: geometry.expandedFrame,
            hasHardwareNotch: geometry.hasHardwareNotch,
            hardwareNotchWidth: geometry.hardwareNotchWidth,
            collapsedLeftRegionWidth: geometry.collapsedLeftRegionWidth,
            collapsedNotchCoreWidth: geometry.collapsedNotchCoreWidth,
            collapsedRightRegionWidth: geometry.collapsedRightRegionWidth,
            collapsedPresentationProfile: geometry.collapsedPresentationProfile,
            animated: animated
        )
        applyCanonicalPanelFrame(
            expandedPresentationProfile.panelFrame(forExpandedFrame: geometry.expandedFrame),
            reason: "\(reason) initial animated=\(animated)",
            animated: animated
        )
        lastAppliedGeometrySignature = signature
        hostingView?.needsLayout = true
        updateWindowVisibility()
        updateMousePassthrough()

        updateMouseContainmentTimer()

        let sessionGeneration = presentationSession.generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.allowsOverlayWork(generation: sessionGeneration) else { return }
            let correctedSignature = self.currentGeometrySignature
            guard force || correctedSignature != self.lastAppliedGeometrySignature else {
                return
            }
            let correctedGeometry = self.geometryService.geometry(
                collapsedSize: self.settings.collapsedSize,
                expandedSize: self.resolvedExpandedSize,
                collapsedActivityProfile: self.collapsedActivityLayoutProfile,
                collapsedPresentationProfile: self.collapsedPresentationProfile,
                useAdaptiveNotchSizing: self.settings.useAdaptiveNotchSizing,
                respectHardwareNotch: self.settings.respectHardwareNotch
            )
            if !animated {
                self.debugGeometryRefresh(correctedGeometry)
                self.targetCollapsedFrame = correctedGeometry.collapsedFrame
                self.targetExpandedFrame = correctedGeometry.expandedFrame
                self.updateLayout(
                    panelFrame: self.expandedPresentationProfile.panelFrame(forExpandedFrame: correctedGeometry.expandedFrame),
                    collapsedFrame: correctedGeometry.collapsedFrame,
                    expandedFrame: correctedGeometry.expandedFrame,
                    hasHardwareNotch: correctedGeometry.hasHardwareNotch,
                    hardwareNotchWidth: correctedGeometry.hardwareNotchWidth,
                    collapsedLeftRegionWidth: correctedGeometry.collapsedLeftRegionWidth,
                    collapsedNotchCoreWidth: correctedGeometry.collapsedNotchCoreWidth,
                    collapsedRightRegionWidth: correctedGeometry.collapsedRightRegionWidth,
                    collapsedPresentationProfile: correctedGeometry.collapsedPresentationProfile,
                    animated: false
                )
                self.applyCanonicalPanelFrame(
                    self.expandedPresentationProfile.panelFrame(forExpandedFrame: correctedGeometry.expandedFrame),
                    reason: "\(reason) corrected animated=\(animated)"
                )
                self.lastAppliedGeometrySignature = correctedSignature
                self.hostingView?.needsLayout = true
                self.updateWindowVisibility()
                self.updateMousePassthrough()
            }
        }
    }

    private var collapsedContentMode: CollapsedIslandContentMode {
        collapsedContentMode(activities: modules.liveActivities.activities)
    }

    private var collapsedActivityLayoutProfile: CollapsedActivityLayoutProfile? {
        collapsedActivityLayoutProfile(activities: modules.liveActivities.activities)
    }

    private var collapsedPresentationProfile: CollapsedPresentationProfile {
        if let attention = modules.agentAttention.presentation {
            let session = attention.primary.flatMap { modules.agentEvents.session(for: $0.session) }
            return AgentCollapsedShellPresentation.attention(attention, session: session)
        }
        switch collapsedContentMode {
        case .inactive, .agent:
            return AgentCollapsedShellPresentation.routine(
                sessions: modules.agentEvents.sessions,
                enabled: settings.agentActivityEnabled
            ) ?? .normal
        default:
            return .normal
        }
    }

    private func collapsedActivityLayoutProfile(
        activities: [DynamicIslandLiveActivity]
    ) -> CollapsedActivityLayoutProfile? {
        let resolution = collapsedLayoutResolution(activities: activities)
        if resolution.primary == nil, resolution.overlayTransient != nil {
            return .systemHUD
        }

        guard let primary = resolution.primary?.activity else { return nil }
        switch primary.kind {
        case .media:
            return .media(
                showsArtwork: settings.showAlbumArtwork,
                showsVisualizer: settings.showVisualizer && settings.showCollapsedVisualizer
            )
        case .agent:
            return nil
        case .timer:
            return .timer
        case .fileTray:
            return .file
        case .battery:
            return .battery
        case .system:
            return .systemHUD
        case .keepAwake, .terminalTask, .reminder, .voiceRecording,
             .voiceTranscription, .camera, .backgroundRemoval, .message:
            return .genericActivity
        case .windowSnapPreview:
            return .systemHUD
        }
    }

    private func collapsedContentMode(activities: [DynamicIslandLiveActivity]) -> CollapsedIslandContentMode {
        guard let primary = collapsedLayoutResolution(activities: activities).primary?.activity else {
            return .inactive
        }
        switch primary.kind {
        case .media:
            return .media
        case .agent:
            return .agent(primary)
        case .timer:
            return .timer(primary)
        case .fileTray:
            return .fileTray(primary)
        case .battery:
            return .battery(primary)
        case .system:
            return .inactive
        case .keepAwake, .terminalTask, .windowSnapPreview, .reminder,
             .voiceRecording, .voiceTranscription, .camera, .backgroundRemoval, .message:
            return .generic(primary)
        }
    }

    private func collapsedLayoutResolution(
        activities: [DynamicIslandLiveActivity]
    ) -> LiveActivityLayoutResolution {
        let toggles = CollapsedLiveActivitySourceToggles(
            liveActivitiesEnabled: settings.liveActivitiesEnabled,
            timerEnabled: settings.timerEnabled && settings.showTimerLiveActivity,
            mediaEnabled: settings.mediaEnabled &&
                settings.showMusicLiveActivity &&
                (settings.showMediaWhenPaused || modules.media.isPlaying),
            fileTrayEnabled: settings.trayEnabled &&
                settings.fileShelfEnabled &&
                settings.showFileDropLiveActivity,
            batteryEnabled: settings.showBatteryLiveActivity,
            systemHUDEnabled: settings.systemHUDsEnabled
        )
        let projected = LiveActivityRuntimeProjection.activities(
            stored: activities,
            priorities: settings.collapsedLiveActivityPrioritySettings,
            toggles: toggles,
            agentSessions: modules.agentEvents.sessions,
            agentEnabled: settings.agentActivityEnabled &&
                modules.agentAttention.presentation == nil
        )
        return LiveActivityLayoutResolver.resolve(
            activities: projected,
            context: LiveActivityLayoutContext(
                availableWidth: max(resolvedExpandedSize.width, settings.collapsedSize.width),
                hasHardwareNotch: layoutStore.hasHardwareNotch,
                hardwareNotchWidth: layoutStore.hardwareNotchWidth,
                primaryMinimumWidth: max(settings.collapsedSize.width, 172),
                primaryIdealWidth: max(settings.collapsedSize.width, 226),
                sidecarDiameter: LiveActivitySidecarMetrics.diameter,
                sidecarGap: LiveActivitySidecarMetrics.gap,
                allowSimultaneousSidecars: settings.allowSimultaneousLiveActivitySidecars,
                timerSidePreference: settings.timerSidecarPreference
            )
        )
    }

    private var expandedPresentationProfile: ExpandedPresentationProfile {
        ExpandedPresentationProfile.resolve(for: modules.navigation.selectedPage)
    }

    private var resolvedExpandedSize: CGSize {
        expandedPresentationProfile.resolvedSize(from: settings.expandedSize)
    }

    private var currentGeometrySignature: OverlayGeometrySignature {
        OverlayGeometrySignature(
            collapsedSize: settings.collapsedSize,
            expandedSize: resolvedExpandedSize,
            expandedPresentationKind: expandedPresentationProfile.kind,
            collapsedActivityProfile: collapsedActivityLayoutProfile,
            collapsedPresentationProfile: collapsedPresentationProfile,
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

    private func applyCanonicalPanelFrame(
        _ frame: NSRect,
        reason: String,
        animated: Bool = false
    ) {
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
        applyPhysicalPanelFrame(frame, reason: reason, animated: animated)
        if !animated {
            islandPanel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        }
        lastOrderedVisibilityState = nil
    }

    private func applyPhysicalPanelFrame(
        _ frame: NSRect,
        reason: String,
        animated: Bool = false
    ) {
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
        debugOverlayWindowOperation(operation: "setFrame", reason: reason)

        let reduceMotion = settings.reduceExtraMotion ||
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldAnimate = animated &&
            !reduceMotion &&
            settings.animationPreset != .instant

        guard shouldAnimate else {
            islandPanel.disableScreenUpdatesUntilFlush()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                islandPanel.setFrame(frame, display: true)
            }
            return
        }

        let duration = expandedPageMorphDuration
        #if DEBUG
        if reason.contains("expandedPageChanged") {
            let topDrift = abs(frame.maxY - islandPanel.frame.maxY)
            assert(
                topDrift <= 1.0,
                "Expanded page morph must preserve the physical top edge; drift=\(topDrift)"
            )
        }
        #endif
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = ExpandedShellMorph.panelTimingFunction
            context.allowsImplicitAnimation = true
            islandPanel.animator().setFrame(frame, display: true)
        }
    }

    private func framesAreApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect, tolerance: CGFloat) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.size.width - rhs.size.width) <= tolerance &&
            abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private var expandedPageMorphDuration: TimeInterval {
        let reduceMotion = settings.reduceExtraMotion ||
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        return IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: reduceMotion
        )
    }

    private func updateLayout(
        panelFrame: NSRect,
        collapsedFrame: NSRect,
        expandedFrame: NSRect,
        hasHardwareNotch: Bool,
        hardwareNotchWidth: CGFloat,
        collapsedLeftRegionWidth: CGFloat,
        collapsedNotchCoreWidth: CGFloat,
        collapsedRightRegionWidth: CGFloat,
        collapsedPresentationProfile: CollapsedPresentationProfile,
        animated: Bool
    ) {
        let updates = { [self] in
            self.layoutStore.updateLocal(
                panelFrame: panelFrame,
                collapsedScreenFrame: collapsedFrame,
                expandedScreenFrame: expandedFrame,
                hasHardwareNotch: hasHardwareNotch,
                hardwareNotchWidth: hardwareNotchWidth,
                collapsedLeftRegionWidth: collapsedLeftRegionWidth,
                collapsedNotchCoreWidth: collapsedNotchCoreWidth,
                collapsedRightRegionWidth: collapsedRightRegionWidth,
                collapsedPresentationProfile: collapsedPresentationProfile
            )
        }
        if animated {
            let reduceMotion = settings.reduceExtraMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let duration = reduceMotion || settings.animationPreset == .instant
                ? 0.01
                : expandedPageMorphDuration
            // Same curve and duration as the NSPanel frame animation in
            // applyCanonicalPanelFrame, so the SwiftUI canvas tracks the
            // physical window on every frame.
            withAnimation(ExpandedShellMorph.canvasAnimation(duration: duration)) {
                updates()
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                updates()
            }
        }
    }

    private func updateWindowVisibility() {
        guard canPresentOverlay else { return }
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
        guard canPresentOverlay else {
            stopMouseContainmentTimer()
            return
        }
        switch islandState.state {
        case .collapsed:
            stopMouseContainmentTimer()
        case .expanded:
            startMouseContainmentTimer()
        }
    }

    private func startMouseContainmentTimer() {
        guard canPresentOverlay else { return }
        guard mouseContainmentTimer == nil else {
            debugLog("timer start skipped; already running")
            return
        }
        debugLog("timer started")
        let generation = presentationSession.generation
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.allowsOverlayWork(generation: generation) else { return }
                self.debugLog("timer fired state=\(self.islandState.state.rawValue) mouse=\(self.currentMouseScreenLocation())")
                self.updateMousePassthrough()
                self.collapseIfExpandedMouseOutsideAfterGrace(source: "timer")
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
            let generation = self?.presentationSession.generation
            Task { @MainActor in
                guard let self, self.allowsOverlayWork(generation: generation) else { return }
                self.updateMousePassthrough()
                self.collapseIfExpandedMouseOutsideAfterGrace(source: "globalMouseMonitor")
            }
        }

        localScrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self else { return event }

            self.debugScrollWheelReceived(event, source: "localScrollMonitor")

            // Panel events are routed exactly once by IslandHostingView. Running
            // expanded routing here as well advances sequence ownership twice and
            // can consume the momentum tail before SwiftUI's ScrollView sees it.
            if event.window === self.islandPanel {
                return event
            }

            if self.handleExpandedScrollWheelFromMonitor(event, source: "localScrollMonitor") {
                return nil
            }

            if self.handleCollapsedScrollWheelFromMonitor(event, source: "localScrollMonitor") {
                return nil
            }

            return event
        }

        globalScrollWheelMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            let generation = self?.presentationSession.generation
            Task { @MainActor in
                guard let self, self.allowsOverlayWork(generation: generation) else { return }

                self.debugScrollWheelReceived(event, source: "globalScrollMonitor")
                if self.handleExpandedScrollWheelFromMonitor(event, source: "globalScrollMonitor") {
                    return
                }

                _ = self.handleCollapsedScrollWheelFromMonitor(event, source: "globalScrollMonitor")
            }
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.canPresentOverlay else { return event }
            guard event.keyCode == 53 else {
                return event
            }
            guard self.islandState.state == .expanded else {
                return event
            }
            switch IslandEscapeRoutingPolicy.route(
                islandState: self.islandState.state,
                topmostPresentation: self.escapeRouter.topmostPresentation
            ) {
            case .dismissPresentation:
                guard self.escapeRouter.requestDismissTopmost() else {
                    return event
                }
                self.debugLog("[EscapeRouting] requested topmost dismissal")
                return nil
            case .collapseIsland:
                self.debugLog("[EscapeRouting] no presentation; requesting Island collapse")
                self.requestCollapseWithSequencing()
                return nil
            case .passThrough:
                return event
            }
        }
    }

    private func currentMouseScreenLocation() -> NSPoint {
        NSEvent.mouseLocation
    }

    private func collapseIfExpandedMouseOutsideAfterGrace(source: String = "event") {
        guard canPresentOverlay else { return }
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
        // The safe region is the full rendered shell for the current page
        // profile. There is deliberately no absolute "distance below the
        // screen top" test: the Agents workspace is taller than that, and
        // its composer and Send button must remain reachable.
        let decision = ExpandedHoverContainment.decide(
            pointer: mouseLocation,
            shellFrame: canonicalFrame,
            accessoryFrames: visibleExpandedAccessoryScreenFrames(),
            holds: currentExpandedHoverHolds
        )
        logCollapseBoundaryCheck(
            source: source,
            mouseLocation: mouseLocation,
            canonicalFrame: canonicalFrame,
            paddedFrame: ExpandedHoverContainment.safeRegion(shellFrame: canonicalFrame),
            containsMouse: decision != .collapse
        )
        debugLog("collapse hover decision=\(decision)")

        if decision == .collapse {
            debugLog("mouse outside expanded shell; requesting sequenced collapse")
            updateMousePassthrough(at: mouseLocation)
            requestCollapseWithSequencing()
        }
    }

    private var currentExpandedHoverHolds: ExpandedHoverContainment.Holds {
        var holds: ExpandedHoverContainment.Holds = []
        if nativeMenuTrackingDepth > 0 { holds.insert(.menuTracking) }
        if layoutStore.isTransientInteractionActive { holds.insert(.transientInteraction) }
        if layoutStore.isTextInputFocused, islandPanel.isKeyWindow { holds.insert(.textInput) }
        return holds
    }

    /// Attached accessories (File Tray quick actions) in screen space.
    private func visibleExpandedAccessoryScreenFrames() -> [NSRect] {
        guard islandState.state == .expanded else { return [] }
        return layoutStore.expandedAccessoryFrames.map(screenRect(for:)).filter { !$0.isEmpty }
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
        guard canPresentOverlay else {
            islandPanel.ignoresMouseEvents = true
            return
        }

        // Window-level passthrough is the primary click-through control. Returning nil from the
        // hosting view hit-test is kept only as a secondary safeguard because the NSPanel itself
        // can still block clicks for other apps when its frame covers the screen.
        let shouldReceiveMouse: Bool
        if islandState.state == .expanded || layoutStore.isCollapseShellOnly {
            let interactiveRect = currentVisibleIslandScreenRect
            let shellFrame = visibleExpandedShellScreenFrame()
            let overAccessory = ExpandedHoverContainment.accessoryRegions(
                shellFrame: shellFrame,
                accessoryFrames: visibleExpandedAccessoryScreenFrames()
            ).contains { $0.contains(screenPoint) }
            shouldReceiveMouse = (!interactiveRect.isEmpty && interactiveRect.contains(screenPoint)) || overAccessory
        } else {
            shouldReceiveMouse = collapsedVisibleLocalFrames.contains { frame in
                let screenFrame = screenRect(for: frame)
                guard !screenFrame.isEmpty else { return false }
                return screenFrame
                    .insetBy(dx: -collapsedHoverTolerance, dy: -collapsedHoverTolerance)
                    .contains(screenPoint)
            }
        }
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
            "expandedSize=\(resolvedExpandedSize)",
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
        guard canPresentOverlay else { return }
        let sessionGeneration = presentationSession.generation
        morphGeneration += 1
        let generation = morphGeneration
        layoutStore.isShellMorphing = true
        layoutStore.isCollapseShellOnly = (state == .collapsed)

        let reduceMotion = settings.reduceExtraMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shellDuration = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: reduceMotion
        )
        let clearDelay = shellDuration + (state == .collapsed ? 0.025 : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) { [weak self] in
            guard let self else { return }
            guard self.allowsOverlayWork(generation: sessionGeneration), generation == self.morphGeneration else { return }
            self.layoutStore.isShellMorphing = false
            self.layoutStore.isCollapseShellOnly = false
            if state == .collapsed {
                self.layoutStore.isExpandedContentExiting = false
            }
            self.updateWindowVisibility()
        }
    }

    /// Marks an expanded tab-to-tab geometry change as one coordinated shell
    /// morph. The physical NSPanel frame is the sole geometry animation; inner
    /// content has its own transition but the shell itself is never scaled.
    private func beginExpandedPageMorph() {
        guard canPresentOverlay, islandState.state == .expanded else { return }
        let sessionGeneration = presentationSession.generation
        morphGeneration += 1
        let generation = morphGeneration
        layoutStore.isShellMorphing = true
        layoutStore.isCollapseShellOnly = false

        let reduceMotion = settings.reduceExtraMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let clearDelay = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: reduceMotion
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) { [weak self] in
            guard let self else { return }
            guard self.allowsOverlayWork(generation: sessionGeneration), generation == self.morphGeneration else { return }
            self.layoutStore.isShellMorphing = false
            self.updateWindowVisibility()
        }
    }

    private func beginCollapsedPresentationMorph() {
        guard canPresentOverlay, islandState.state == .collapsed else { return }
        let sessionGeneration = presentationSession.generation
        morphGeneration += 1
        let generation = morphGeneration
        layoutStore.isShellMorphing = true
        layoutStore.isCollapseShellOnly = false

        let reduceMotion = settings.reduceExtraMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let clearDelay = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: reduceMotion
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) { [weak self] in
            guard let self else { return }
            guard self.allowsOverlayWork(generation: sessionGeneration), generation == self.morphGeneration else { return }
            self.layoutStore.isShellMorphing = false
            self.updateWindowVisibility()
        }
    }

    private func expandFromCollapsedPreparingGeometry() {
        guard canPresentOverlay else { return }
        guard islandState.state == .collapsed else { return }

        let geometry = geometryService.geometry(
            collapsedSize: settings.collapsedSize,
            expandedSize: resolvedExpandedSize,
            collapsedActivityProfile: collapsedActivityLayoutProfile,
            collapsedPresentationProfile: collapsedPresentationProfile,
            useAdaptiveNotchSizing: settings.useAdaptiveNotchSizing,
            respectHardwareNotch: settings.respectHardwareNotch
        )

        debugGeometryRefresh(geometry)
        targetCollapsedFrame = geometry.collapsedFrame
        targetExpandedFrame = geometry.expandedFrame

        updateLayout(
            panelFrame: expandedPresentationProfile.panelFrame(forExpandedFrame: geometry.expandedFrame),
            collapsedFrame: geometry.collapsedFrame,
            expandedFrame: geometry.expandedFrame,
            hasHardwareNotch: geometry.hasHardwareNotch,
            hardwareNotchWidth: geometry.hardwareNotchWidth,
            collapsedLeftRegionWidth: geometry.collapsedLeftRegionWidth,
            collapsedNotchCoreWidth: geometry.collapsedNotchCoreWidth,
            collapsedRightRegionWidth: geometry.collapsedRightRegionWidth,
            collapsedPresentationProfile: geometry.collapsedPresentationProfile,
            animated: false
        )

        applyCanonicalPanelFrame(
            expandedPresentationProfile.panelFrame(forExpandedFrame: geometry.expandedFrame),
            reason: "expandFromCollapsedPreparingGeometry"
        )
        lastAppliedGeometrySignature = currentGeometrySignature
        updateWindowVisibility()
        hostingView?.needsLayout = true
        updateMousePassthrough()

        islandState.expand()
    }

    private func requestCollapseWithSequencing() {
        guard canPresentOverlay else { return }
        guard islandState.state == .expanded else { return }
        guard !layoutStore.isExpandedContentExiting else { return }

        debugLog("requestCollapseWithSequencing started")
        stopMouseContainmentTimer()
        layoutStore.isExpandedContentExiting = true
        resetExpandedContentScrollTracking()
        layoutStore.setExpandedContentScrollRegion(.zero)
        updateMousePassthrough()
        islandState.collapse()
    }

    /// Panel-local regions for attached accessories, including the bridge
    /// to the shell, so clicks there reach SwiftUI.
    private func currentAccessoryInteractiveRegions() -> [NSRect] {
        guard islandState.state == .expanded else { return [] }
        return ExpandedHoverContainment.accessoryRegions(
            shellFrame: layoutStore.expandedSurfaceFrame,
            accessoryFrames: layoutStore.expandedAccessoryFrames,
            tolerance: 2
        )
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

    private var collapsedVisibleLocalFrames: [CGRect] {
        if layoutStore.collapsedPreviewActive,
           !layoutStore.collapsedPreviewSurfaceFrame.isEmpty {
            return [layoutStore.collapsedPreviewSurfaceFrame]
        }

        var frames = [layoutStore.collapsedSurfaceFrame]
        if !layoutStore.collapsedLeadingSidecarFrame.isEmpty {
            frames.append(layoutStore.collapsedLeadingSidecarFrame)
        }
        if !layoutStore.collapsedTrailingSidecarFrame.isEmpty {
            frames.append(layoutStore.collapsedTrailingSidecarFrame)
        }
        return frames
    }

    private var collapsedInteractiveSurfaceFrame: CGRect {
        if layoutStore.collapsedPreviewActive,
           !layoutStore.collapsedPreviewSurfaceFrame.isEmpty {
            return layoutStore.collapsedPreviewSurfaceFrame
        }
        if !layoutStore.collapsedCompositeInteractionFrame.isEmpty {
            return layoutStore.collapsedCompositeInteractionFrame
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
        guard canPresentOverlay, islandState.state == .collapsed,
              !layoutStore.isShellMorphing,
              !layoutStore.isCollapseShellOnly,
              !layoutStore.isExpandedContentExiting,
              !modules.navigation.isFileDropTargeted else {
            return .zero
        }
        return collapsedGestureCandidateRegion
    }

    private func handleIslandScrollWheelFromMonitor(_ event: NSEvent, source: String) -> Bool {
        guard acceptsOverlayScroll(event) else { return false }
        switch islandState.state {
        case .collapsed:
            return handleCollapsedScrollWheelFromMonitor(event, source: source)
        case .expanded:
            return handleExpandedScrollWheelFromMonitor(event, source: source)
        }
    }

    private func handleIslandScrollWheel(_ event: NSEvent, localPoint: NSPoint, source: String) -> Bool {
        guard acceptsOverlayScroll(event) else { return false }
        switch islandState.state {
        case .collapsed:
            return handleCollapsedScrollWheel(event, localPoint: localPoint, source: source)
        case .expanded:
            return handleExpandedScrollWheel(event, source: source)
        }
    }

    private func handleExpandedScrollWheelFromMonitor(_ event: NSEvent, source: String) -> Bool {
        guard acceptsOverlayScroll(event) else { return false }

        // The right workspace owns its own two-axis gesture arbitration.
        // Ask it first so vertical intent can be delivered to its nested
        // ScrollViews without leaking into global expanded-island actions.
        if let workspaceRoute = routeRightWorkspaceSwipe(event) {
            return workspaceRoute
        }

        guard !shouldPassExpandedScrollThroughToContent(event) else {
            return false
        }

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
        guard acceptsOverlayScroll(event) else { return false }

        if let workspaceRoute = routeRightWorkspaceSwipe(event) {
            return workspaceRoute
        }

        guard !shouldPassExpandedScrollThroughToContent(event) else {
            return false
        }

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
            modules.media.nextTrack()
            expandedScrollGestureHandled = true
            expandedScrollLastActionAt = CACurrentMediaTime()
            expandedScrollDelta = .zero
            return true
        case .mediaPreviousTrack:
            guard settings.mediaEnabled,
                  modules.media.isTransportControlAvailable else { return true }
            modules.media.previousTrack()
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

    /// Two-finger horizontal swipes that start over the Island page's right
    /// workspace page it (Droppy semantics, one page per gesture). Returns
    /// nil when the event is not a workspace swipe so the existing expanded
    /// gestures (media, tabs, collapse) keep their behavior.
    private func routeRightWorkspaceSwipe(_ event: NSEvent) -> Bool? {
        let workspace = modules.rightWorkspace
        let pages = workspace.configuration.visiblePages
        guard settings.gesturesEnabled,
              settings.gestureInputSource == .trackpad,
              islandState.state == .expanded,
              event.hasPreciseScrollingDeltas,
              modules.navigation.selectedPage == .island,
              workspace.configuration.swipeEnabled,
              pages.count > 1 else {
            rightWorkspaceSwipe.reset()
            return nil
        }
        if !rightWorkspaceSwipe.ownsSequence {
            let region = screenRect(for: layoutStore.rightWorkspaceRegion)
            guard !region.isEmpty, region.contains(NSEvent.mouseLocation) else {
                return nil
            }
        }
        let phase: RightWorkspaceSwipeRecognizer.Phase
        if !event.momentumPhase.isEmpty {
            phase = .momentum
        } else if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            phase = .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else if event.phase.contains(.changed) {
            phase = .changed
        } else {
            phase = .none
        }
        let outcome = rightWorkspaceSwipe.handle(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            phase: phase,
            at: event.timestamp
        )
        let momentumEnded = event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
        defer {
            if momentumEnded {
                rightWorkspaceSwipe.reset()
            }
        }

        switch outcome {
        case .ignored:
            return nil
        case .passThrough:
            // Vertical ownership mutes every global expanded gesture for this
            // sequence while still letting the native ScrollView receive it.
            resetExpandedScrollTracking()
            return false
        case .consumed:
            resetExpandedScrollTracking()
            return true
        case .next, .previous:
            resetExpandedScrollTracking()
            let changed = outcome == .next ? workspace.showNext() : workspace.showPrevious()
            debugGesture("right workspace swipe outcome=\(outcome) changed=\(changed) page=\(workspace.currentPage.rawValue)")
            return true
        }
    }

    private func shouldPassExpandedScrollThroughToContent(_ event: NSEvent) -> Bool {
        let isExpanded = islandState.state == .expanded
        if layoutStore.isExpandedScrollGestureSuppressed, isExpanded {
            resetExpandedScrollTracking()
            resetExpandedContentScrollTracking()
            logExpandedScrollPassThroughIfNeeded(reason: "global-suppression")
            return true
        }

        if isExpanded,
           settings.gesturesEnabled,
           settings.gestureInputSource == .trackpad,
           event.hasPreciseScrollingDeltas {
            let rightRegion = screenRect(for: layoutStore.rightWorkspaceRegion)
            let insideRightWorkspace = !rightRegion.isEmpty && rightRegion.contains(NSEvent.mouseLocation)
            if CameraMirrorScrollRoutingPolicy.shouldPassThroughToContent(
                mirrorActive: layoutStore.isRightWorkspaceMirrorActive,
                pointerInsideRightWorkspace: insideRightWorkspace,
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY
            ) {
                resetExpandedScrollTracking()
                resetExpandedContentScrollTracking()
                logExpandedScrollPassThroughIfNeeded(reason: "camera-mirror-vertical")
                return true
            }
        }

        var contentSequenceActive = false
        if isExpanded,
           settings.gesturesEnabled,
           settings.gestureInputSource == .trackpad,
           event.hasPreciseScrollingDeltas {
            let region = screenRect(for: layoutStore.expandedContentScrollRegion)
            let startsInsideContent = !region.isEmpty && region.contains(NSEvent.mouseLocation)
            let verticalIntent = ExpandedScrollIntent.isVertical(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                insideContent: startsInsideContent
            )
            contentSequenceActive = expandedContentScrollOwnership.route(
                phase: expandedContentSequencePhase(for: event),
                startsInsideContent: startsInsideContent,
                verticalIntent: verticalIntent
            ) == .passThroughToContent
        }

        let route = ExpandedScrollEventRoutingPolicy.route(
            isSuppressed: false,
            isExpanded: isExpanded,
            gesturesEnabled: settings.gesturesEnabled,
            usesTrackpad: settings.gestureInputSource == .trackpad,
            contentScrollSequenceActive: contentSequenceActive
        )
        guard route == .passThroughToContent, isExpanded else {
            return false
        }

        if contentSequenceActive {
            resetExpandedScrollTracking()
            logExpandedScrollPassThroughIfNeeded(reason: "registered-content-region")
            return true
        }

        return false
    }

    private func expandedContentSequencePhase(for event: NSEvent) -> ExpandedContentScrollSequencePhase {
        if event.momentumPhase.contains(.began) { return .momentumBegan }
        if event.momentumPhase.contains(.changed) { return .momentumChanged }
        if event.momentumPhase.contains(.ended) { return .momentumEnded }
        if event.momentumPhase.contains(.cancelled) { return .momentumCancelled }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { return .physicalBegan }
        if event.phase.contains(.changed) { return .physicalChanged }
        if event.phase.contains(.ended) { return .physicalEnded }
        if event.phase.contains(.cancelled) { return .physicalCancelled }
        return .phaseLess
    }

    private func resetExpandedContentScrollTracking() {
        expandedContentScrollOwnership.reset()
    }

    private func logExpandedScrollPassThroughIfNeeded(reason: String) {
        #if DEBUG
        if !didLogExpandedScrollPassThrough {
            print("[GestureDebug] expanded scroll passed through to content reason=\(reason)")
            didLogExpandedScrollPassThrough = true
        }
        #endif
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
        let generation = presentationSession.generation
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.allowsOverlayWork(generation: generation) else { return }
                self.expandedScrollDelta = .zero
                self.expandedScrollGestureHandled = false
                self.expandedScrollGestureResetWorkItem = nil
                self.debugGesture("expanded scroll quiet reset fired")
            }
        }
        expandedScrollGestureResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: workItem)
    }

    private func handleCollapsedScrollWheelFromMonitor(_ event: NSEvent, source: String) -> Bool {
        guard acceptsOverlayScroll(event) else { return false }
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
        guard acceptsOverlayScroll(event) else { return false }
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
        let generation = presentationSession.generation
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.allowsOverlayWork(generation: generation) else { return }
                self.collapsedScrollDelta = .zero
                self.collapsedScrollGestureHandled = false
                self.collapsedScrollGestureResetWorkItem = nil
                self.debugGesture("quiet reset fired")
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
        let generation = presentationSession.generation
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.allowsOverlayWork(generation: generation) else { return }
                self.finishCollapsedMediaSwipeSession()
            }
        }
        mediaSwipeFinishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + mediaSwipeQuietPeriod, execute: workItem)
        debugGesture("media swipe finish scheduled quiet=\(String(format: "%.2f", mediaSwipeQuietPeriod))")
    }

    private func finishCollapsedMediaSwipeSession() {
        guard canPresentOverlay else { return }
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
            modules.media.nextTrack()
        case .mediaPreviousTrack:
            debugGesture("media swipe finish quiet=\(String(format: "%.2f", mediaSwipeQuietPeriod)) x=\(accumulatedX) y=\(accumulatedY) action=\(action.rawValue)")
            debugGesture("media swipe finished; ACTION mediaPreviousTrack")
            modules.media.previousTrack()
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

        let generation = presentationSession.generation
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.allowsOverlayWork(generation: generation) else { return }
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
        guard canPresentOverlay else { return false }
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
    var accessoryRegionsProvider: (() -> [NSRect])?
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
           !interactiveRegion.contains(point),
           !(accessoryRegionsProvider?() ?? []).contains(where: { $0.contains(point) }) {
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
