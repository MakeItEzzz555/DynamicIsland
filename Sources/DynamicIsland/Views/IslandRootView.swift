import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct NotchIntegratedShellEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isNotchIntegratedShell: Bool {
        get { self[NotchIntegratedShellEnvironmentKey.self] }
        set { self[NotchIntegratedShellEnvironmentKey.self] = newValue }
    }
}

extension View {
    func notchIntegrated(_ isNotchIntegrated: Bool) -> some View {
        environment(\.isNotchIntegratedShell, isNotchIntegrated)
    }
}

enum IslandContentTransitionTiming {
    // Content timing is derived from the active shell animation duration. Child content
    // starts only once the shell has fully expanded (ratio 1.0): with the default
    // `.normal` shell timing of 0.40s, expansion content runs from 0.40s to 0.56s.
    static let expansionContentDelayRatio: TimeInterval = 1.0
    static let expansionContentDurationRatio: TimeInterval = 0.40
    static let collapseContentDurationRatio: TimeInterval = 0.40

    @MainActor
    static func shellDuration(settings: AppSettings, reduceMotion: Bool) -> TimeInterval {
        if reduceMotion || settings.reduceExtraMotion {
            return 0.24
        }
        if settings.animationPreset == .instant {
            return 0.01
        }
        return settings.animationPreset.shellDuration / max(settings.shellAnimationSpeed, 0.25)
    }

    static func expansionContentDelay(shellDuration: TimeInterval) -> TimeInterval {
        shellDuration * expansionContentDelayRatio
    }

    static func expansionContentDuration(shellDuration: TimeInterval) -> TimeInterval {
        shellDuration * expansionContentDurationRatio
    }

    static func collapseContentDuration(shellDuration: TimeInterval) -> TimeInterval {
        shellDuration * collapseContentDurationRatio
    }

    // Collapse child exit (InnerBlurScaleCleanModifier removal): the values
    // the modifier animates and the contraction plan sequences against.
    static let collapseExitScale: CGFloat = 0.97
    static let collapseExitBlur: CGFloat = 6
    /// Largest stagger delay the modifier applies before the exit starts.
    static let collapseExitStaggerAllowance: TimeInterval = 0.015
    /// Reduce Motion exit: a short fade only.
    static let reducedCollapseExitDuration: TimeInterval = 0.10
}

private enum IslandContentPhase {
    case compact
    case shellExpanding
    case expandedContentVisible
    case contentCollapsing
    case shellCollapsing
}

private enum RenderedContentMode {
    case compact
    case expanded
}

struct ClipboardHistoryPresentationState: Equatable {
    private(set) var isRequested = false
    private(set) var isMounted = false
    private(set) var isVisible = false
    private(set) var isRemoving = false
    private(set) var generation = 0

    var topmostOverlayPresentation: IslandOverlayPresentation? {
        isMounted ? .clipboardHistory : nil
    }

    @discardableResult
    mutating func open() -> Int {
        generation += 1
        isRequested = true
        isMounted = true
        isVisible = false
        isRemoving = false
        return generation
    }

    @discardableResult
    mutating func reveal(generation expectedGeneration: Int) -> Bool {
        guard expectedGeneration == generation, isRequested, isMounted else { return false }
        isRemoving = false
        isVisible = true
        return true
    }

    @discardableResult
    mutating func beginAnimatedClose() -> Int? {
        guard (isRequested || isMounted), !isRemoving else { return nil }
        generation += 1
        isRequested = false
        isRemoving = isMounted
        isVisible = false
        return generation
    }

    @discardableResult
    mutating func completeAnimatedClose(generation expectedGeneration: Int) -> Bool {
        guard expectedGeneration == generation, !isRequested else { return false }
        isMounted = false
        isVisible = false
        isRemoving = false
        return true
    }

    mutating func closeImmediately() {
        generation += 1
        isRequested = false
        isMounted = false
        isVisible = false
        isRemoving = false
    }
}

enum CollapsedPreviewKind: String {
    case none
    case media
    case timer
    case fileDrop
    case battery
    case liveActivity
}

struct CollapsedPreviewContent: Equatable {
    let rows: [CollapsedPreviewRowContent]

    static func mounted(
        _ content: CollapsedPreviewContent?,
        previewActive: Bool
    ) -> CollapsedPreviewContent? {
        previewActive ? content : nil
    }
}

struct CollapsedPreviewRowContent: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let trailingText: String?
    let symbolName: String
    let fallbackSymbolName: String
    let kind: CollapsedPreviewKind
    let isPrimary: Bool
}

private struct IslandPointerGestureModifier: ViewModifier {
    @ObservedObject var settings: AppSettings
    @ObservedObject var coordinator: IslandGestureCoordinator
    let context: IslandGestureContext
    let callbacks: IslandGestureCallbacks
    let swipeSensitivity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if settings.gesturesEnabled, settings.gestureInputSource == .trackpad {
            content
                .gesture(doubleClickGesture)
                .simultaneousGesture(swipeGesture)
                .simultaneousGesture(longPressGesture)
        } else {
            content
        }
    }

    private var doubleClickGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                coordinator.handle(
                    .doubleClick,
                    settings: settings,
                    context: context,
                    callbacks: callbacks
                )
            }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onEnded { value in
                guard let gesture = IslandPointerGesture.detected(
                    from: value.translation,
                    sensitivity: swipeSensitivity
                ) else {
                    return
                }
                coordinator.handle(
                    gesture,
                    settings: settings,
                    context: context,
                    callbacks: callbacks
                )
            }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.55, maximumDistance: 10)
            .onEnded { completed in
                guard completed else { return }
                coordinator.handle(
                    .longPress,
                    settings: settings,
                    context: context,
                    callbacks: callbacks
                )
            }
    }
}

enum IslandShellLayout {
    static let collapsedHorizontalPadding: CGFloat = 8
    static let floatingExpandedHorizontalPadding: CGFloat = 22
    static let integratedExpandedHorizontalPadding: CGFloat = 41

    static func collapsedHorizontalPadding(isNotchIntegrated: Bool) -> CGFloat {
        collapsedHorizontalPadding
    }

    static func expandedHorizontalPadding(isNotchIntegrated: Bool) -> CGFloat {
        isNotchIntegrated ? integratedExpandedHorizontalPadding : floatingExpandedHorizontalPadding
    }

    static let collapsedTopPadding: CGFloat = 0
    static let collapsedBottomPadding: CGFloat = 6
    static let expandedTopPadding: CGFloat = 14
    static let expandedBottomPadding: CGFloat = 20
}

/// Shell expand/collapse animation shared by the island and its Settings
/// preview, so the preview animates exactly like the island.
@MainActor
enum IslandShellMotion {
    static func shellAnimation(settings: AppSettings, reduceMotion: Bool) -> Animation {
        if reduceMotion || settings.reduceExtraMotion {
            return .easeInOut(duration: 0.24)
        }
        let duration = settings.animationPreset == .instant
            ? 0.01
            : settings.animationPreset.shellDuration / max(settings.shellAnimationSpeed, 0.25)
        return .smooth(duration: duration)
    }
}

struct ExpandedIslandLayoutMetrics {
    let containerSize: CGSize
    let horizontalPadding: CGFloat
    let displayMetrics: ResolvedIslandMetrics

    init(
        containerSize: CGSize,
        horizontalPadding: CGFloat,
        displayMetrics: ResolvedIslandMetrics = .fallback
    ) {
        self.containerSize = containerSize
        self.horizontalPadding = horizontalPadding
        self.displayMetrics = displayMetrics
    }

    var topPadding: CGFloat { 14 * displayMetrics.spacingScale }
    var bottomPadding: CGFloat { 20 * displayMetrics.spacingScale }
    var tabSwitcherHeight: CGFloat { 34 * displayMetrics.compactControlScale }
    var tabToPageSpacing: CGFloat { 10 * displayMetrics.spacingScale }
    var pageColumnSpacing: CGFloat { 10 * displayMetrics.spacingScale }
    var cardSpacing: CGFloat { 10 * displayMetrics.spacingScale }

    var innerWidth: CGFloat { max(containerSize.width - (horizontalPadding * 2), 0) }
    var innerHeight: CGFloat { max(containerSize.height - topPadding - bottomPadding, 0) }
    var pageHeight: CGFloat { max(innerHeight - tabSwitcherHeight - tabToPageSpacing, 0) }
    var responsiveScale: CGFloat {
        let localFit = min(pageHeight / 178, innerWidth / 720)
        return min(max(localFit * displayMetrics.uiScale, 0.76), 1.14)
    }
    var compactScale: CGFloat { responsiveScale }

    var rightStackWidth: CGFloat {
        let spacingBudget = dividerWidth + (pageColumnSpacing * 2)
        let availableColumnWidth = max(innerWidth - spacingBudget, 0)
        let preferredWidth = floor(innerWidth * 0.44)
        let minBase = 360 * displayMetrics.expandedCardScale
        let maxBase = 520 * displayMetrics.expandedCardScale
        let minimumWidth = min(maxBase, max(minBase, availableColumnWidth * 0.40))
        let maximumWidth = min(maxBase, max(availableColumnWidth - minimumMediaColumnWidth, 0))
        return min(max(preferredWidth, minimumWidth), maximumWidth)
    }
    var mediaColumnWidth: CGFloat {
        max(innerWidth - rightStackWidth - dividerWidth - (pageColumnSpacing * 2), 0)
    }
    var minimumMediaColumnWidth: CGFloat {
        min(360 * displayMetrics.expandedCardScale, max(300 * displayMetrics.expandedCardScale, innerWidth * 0.46))
    }
    var shortcutsColumnWidth: CGFloat { rightStackWidth }
    var dividerWidth: CGFloat { displayMetrics.dividerThickness }
    var dividerHeight: CGFloat { min(max(pageHeight - (10 * displayMetrics.spacingScale), 100), pageHeight) }
    var trayAirDropWidth: CGFloat {
        min(max(innerWidth * 0.29, 150 * displayMetrics.expandedCardScale), 188 * displayMetrics.expandedCardScale)
    }
    var timerHeaderHeight: CGFloat { 24 * compactScale }
    var timerControlsHeight: CGFloat { (pageHeight < 150 ? 24 : 28) * compactScale }
    var timerVerticalSpacingTotal: CGFloat { (pageHeight < 150 ? 18 : 20) * displayMetrics.spacingScale }
    var timerReservedHeight: CGFloat { timerHeaderHeight + timerControlsHeight + timerVerticalSpacingTotal }
    var timerRingSize: CGFloat {
        min(max(pageHeight - timerReservedHeight, 86 * compactScale), 118 * displayMetrics.expandedCardScale)
    }
    var mediaMaxHeight: CGFloat { pageHeight }
    var shortcutsMaxHeight: CGFloat { pageHeight }
    var liveActivitiesMaxHeight: CGFloat { pageHeight }
    var rightStackSpacing: CGFloat {
        min(max(14 * compactScale * displayMetrics.spacingScale, 11), 18)
    }
    var rightStackAvailableHeight: CGFloat { max(pageHeight - rightStackSpacing, 0) }
    var liveActivitiesStackHeight: CGFloat { floor(rightStackAvailableHeight * 0.45) }
    var shortcutsStackHeight: CGFloat { max(rightStackAvailableHeight - liveActivitiesStackHeight, 0) }
    var statsCardWidth: CGFloat { max((innerWidth - (cardSpacing * 2)) / 3, 0) }
    var statsHeaderHeight: CGFloat { 25 * compactScale }
    var statsGridAvailableHeight: CGFloat { max(pageHeight - statsHeaderHeight - 8 - 4, 0) }
    var statsTwoRowCardHeight: CGFloat { max((statsGridAvailableHeight - cardSpacing) / 2, 0) }
    var statsUsesScroll: Bool { statsTwoRowCardHeight < (48 * compactScale) }
    var statsCardHeight: CGFloat {
        if statsUsesScroll { return 58 * compactScale }
        return min(statsTwoRowCardHeight, 74 * compactScale)
    }
}


struct IslandRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var islandState: IslandStateStore
    @ObservedObject var layoutStore: IslandLayoutStore
    @ObservedObject var escapeRouter: IslandEscapeRouter
    let modules: IslandModules
    let rendersExpandedVisualContent: Bool
    let onRequestExpand: () -> Void
    let onRequestCollapse: () -> Void
    let onOpenSettings: () -> Void
    @ObservedObject private var media: MediaController
    @ObservedObject private var navigation: IslandNavigationStore
    @ObservedObject private var fileDragSession: FileDragSessionController
    @ObservedObject private var liveActivities: LiveActivityStore
    @ObservedObject private var agentAttention: AgentAttentionCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentPhase: IslandContentPhase = .compact
    @State private var renderedContentMode: RenderedContentMode = .compact
    @State private var contentVisible = false
    @State private var expandedContentMounted = false
    @State private var isContentRemoving = false
    @State private var sequenceGeneration = 0
    @State private var isCollapsedHovering = false
    @State private var collapsedPreviewVisible = false
    @State private var collapsedPreviewGeneration = 0
    @StateObject private var agentGlow = AgentActivityGlowCoordinator()
    @StateObject private var gestureCoordinator = IslandGestureCoordinator()

    init(
        settings: AppSettings,
        islandState: IslandStateStore,
        layoutStore: IslandLayoutStore,
        escapeRouter: IslandEscapeRouter,
        modules: IslandModules,
        rendersExpandedVisualContent: Bool,
        onRequestExpand: @escaping () -> Void,
        onRequestCollapse: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.settings = settings
        self.islandState = islandState
        self.layoutStore = layoutStore
        self.escapeRouter = escapeRouter
        self.modules = modules
        self.rendersExpandedVisualContent = rendersExpandedVisualContent
        self.onRequestExpand = onRequestExpand
        self.onRequestCollapse = onRequestCollapse
        self.onOpenSettings = onOpenSettings
        media = modules.media
        navigation = modules.navigation
        fileDragSession = modules.fileDragSession
        liveActivities = modules.liveActivities
        agentAttention = modules.agentAttention
    }

    private var isExpanded: Bool {
        islandState.state == .expanded
    }

    private var showsExpandedContent: Bool {
        renderedContentMode == .expanded
    }

    private var shellAnimation: Animation {
        if !(reduceMotion || settings.reduceExtraMotion),
           layoutStore.collapsedPresentationProfile.kind == .agentAttention {
            return .interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
        }
        return IslandShellMotion.shellAnimation(settings: settings, reduceMotion: reduceMotion)
    }

    private var shellMorphProgress: CGFloat {
        let collapsedHeight = max(layoutStore.collapsedSize.height, 1)
        let expandedHeight = max(layoutStore.expandedSize.height, collapsedHeight + 1)
        let progress = (surfaceFrame.height - collapsedHeight) / (expandedHeight - collapsedHeight)
        return min(max(progress, 0), 1)
    }

    private var shellVisualProgress: CGFloat {
        shellMorphProgress
    }

    var body: some View {
        animatedIslandCanvas
            .environment(\.islandDisplayMetrics, layoutStore.displayMetrics)
            .environment(\.basketShelfTransfer, BasketShelfTransfer { [presenter = modules.basketPresenter] urls in
                presenter.moveShelfFilesToBasket(urls)
            })
    }

    private var baseIslandCanvas: some View {
        ZStack(alignment: .topLeading) {
            if settings.overlayEnabled {
                IslandSurface(
                    settings: settings,
                    isExpanded: isExpanded,
                    visualProgress: shellVisualProgress,
                    collapsedPresentationProfile: layoutStore.collapsedPresentationProfile,
                    collapsedGlowColor: collapsedAgentGlowColor,
                    collapsedBrightGlowColor: collapsedAgentBrightGlowColor,
                    forcesCollapsedGlow: shouldShowCollapsedAgentGlow,
                    systemHUDActivity: activeInteractiveSystemHUD
                ) {
                    islandSurfaceContent
                }
                .notchIntegrated(layoutStore.hasHardwareNotch)
                .shellMorphing(layoutStore.isShellMorphing)
                .collapseShellOnly(layoutStore.isCollapseShellOnly)
                .frame(width: surfaceSize.width, height: surfaceSize.height)
                .position(
                    x: surfaceFrame.midX,
                    y: layoutStore.canvasSize.height - surfaceFrame.midY
                )
                .id(layoutStore.overlayPresentationGeneration)

                collapsedSidecarOverlay
                trayQuickActionOverlay
            }
        }
        .shellMorphing(layoutStore.isShellMorphing)
        .collapseShellOnly(layoutStore.isCollapseShellOnly)
        .frame(
            width: layoutStore.canvasSize.width,
            height: layoutStore.canvasSize.height,
            alignment: .topLeading
        )
        .coordinateSpace(name: IslandCanvasCoordinateSpace.name)
    }

    private var presentationObservedCanvas: some View {
        baseIslandCanvas
            .onAppear {
                modules.navigation.ensureValidSelection(using: settings)
                synchronizePresentationForCurrentState()
                updateCollapsedPreviewLayout()
                synchronizeCollapsedSidecarGeometry()
            }
            .onChange(of: layoutStore.overlayPresentationGeneration) { _, _ in
                sequenceGeneration += 1
                deactivateCollapsedPreview()
                finalizeCompactPresentation()
            }
            .onChange(of: islandState.state) { _, newValue in
                handleStateChange(newValue)
                synchronizeCollapsedSidecarGeometry()
            }
            .onChange(of: isCollapsedPreviewActive) { _, _ in
                updateCollapsedPreviewLayout()
                synchronizeCollapsedSidecarGeometry()
            }
            .onChange(of: collapsedCompositeGeometry) { _, _ in
                synchronizeCollapsedSidecarGeometry()
            }
            .onChange(of: agentAttention.presentation != nil) { _, _ in
                synchronizeCollapsedSidecarGeometry()
            }
    }

    private var navigationObservedCanvas: some View {
        presentationObservedCanvas
            .onChange(of: collapsedPreviewSurfaceFrame) { _, _ in
                updateCollapsedPreviewLayout()
            }
            .onChange(of: settings.collapsedHoverPreviewEnabled) { _, enabled in
                if !enabled {
                    deactivateCollapsedPreview()
                }
            }
            .onChange(of: navigation.isFileDropTargeted) { _, _ in
                if !isCollapsedPreviewAllowed {
                    deactivateCollapsedPreview()
                } else {
                    updateCollapsedPreviewLayout()
                }
            }
            .onChange(of: media.hasActiveMediaSource) { _, _ in
                if !isCollapsedPreviewAllowed {
                    deactivateCollapsedPreview()
                }
            }
            .onChange(of: layoutStore.isExpandedContentExiting) { _, newValue in
                if newValue {
                    beginContentExitSequence()
                } else if islandState.state == .expanded, contentPhase == .contentCollapsing {
                    // The pending collapse was cancelled by an expansion before
                    // the shell contracted: bring the children back.
                    cancelContentExitSequence()
                }
            }
            .onChange(of: layoutStore.isCollapseShellOnly) { _, newValue in
                if !newValue, islandState.state == .collapsed {
                    finalizeCompactPresentation()
                }
            }
    }

    private var interactionObservedCanvas: some View {
        navigationObservedCanvas
            .onReceive(settings.objectWillChange) { _ in
                DispatchQueue.main.async {
                    modules.navigation.ensureValidSelection(using: settings)
                }
            }
            .onDrop(
                of: FileDropProviderLoader.acceptedTypes,
                isTargeted: fileDropTargetBinding
            ) { providers in
                loadDroppedFilesFromCollapsedIsland(from: providers)
            }
            .onChange(of: activeRoutineAgentProvider) { _, provider in
                agentGlow.update(activeProvider: provider)
            }
            .onDisappear {
                agentGlow.stop()
                fileDragSession.cancel()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("DynamicIsland")
    }

    private var animatedIslandCanvas: some View {
        interactionObservedCanvas
            .animation(shellAnimation, value: islandState.state)
            .animation(shellAnimation, value: layoutStore.isShellMorphing)
            .animation(shellAnimation, value: layoutStore.collapsedSurfaceFrame)
            .animation(shellAnimation, value: layoutStore.collapsedPresentationProfile)
            .animation(collapsedPreviewAnimation, value: isCollapsedPreviewActive)
    }

    @ViewBuilder
    private var islandSurfaceContent: some View {
        if showsExpandedContent {
            ExpandedIslandView(
                settings: settings,
                modules: modules,
                contentVisible: contentVisible,
                shouldRenderContent: expandedContentMounted,
                isContentRemoving: isContentRemoving,
                onShortcutLaunched: onRequestCollapse,
                onTimerStarted: {
                    if settings.collapseAfterStartingTimer {
                        onRequestCollapse()
                    }
                },
                rendersExpandedVisualContent: rendersExpandedVisualContent,
                onOpenSettings: onOpenSettings,
                layoutStore: layoutStore,
                escapeRouter: escapeRouter,
                islandGestureCoordinator: gestureCoordinator,
                islandGestureContext: gestureContext,
                islandGestureCallbacks: gestureCallbacks,
                islandSwipeSensitivity: settings.gestureSensitivity
            )
        } else {
            compactIslandContent
        }
    }

    private var compactIslandContent: some View {
        CompactIslandView(
            settings: settings,
            modules: modules,
            contentMode: collapsedContentMode,
            layoutResolution: collapsedLayoutResolution,
            previewContent: CollapsedPreviewContent.mounted(
                collapsedPreviewContent,
                previewActive: isCollapsedPreviewActive
            ),
            previewActive: isCollapsedPreviewActive,
            hardwareNotchWidth: layoutStore.hardwareNotchWidth,
            collapsedLeftRegionWidth: layoutStore.collapsedLeftRegionWidth,
            collapsedNotchCoreWidth: layoutStore.collapsedNotchCoreWidth,
            collapsedRightRegionWidth: layoutStore.collapsedRightRegionWidth,
            isNotchIntegratedShell: layoutStore.hasHardwareNotch
        )
        .environment(\.agentVisualPreferences, settings.agentVisualPreferences)
        .contentShape(Rectangle())
        .onHover(perform: handleCollapsedHover)
        .onTapGesture {
            guard settings.expandOnClick else { return }
            deactivateCollapsedPreview()
            if let attention = agentAttention.presentation,
               let primary = attention.primary {
                navigation.showAgents()
                modules.agentManagedControl.selectSession(primary.session)
            }
            onRequestExpand()
        }
        .modifier(
            IslandPointerGestureModifier(
                settings: settings,
                coordinator: gestureCoordinator,
                context: gestureContext,
                callbacks: gestureCallbacks,
                swipeSensitivity: settings.gestureSensitivity
            )
        )
    }

    /// Quick actions attached below the expanded shell, Tray page only.
    /// Positioned from the shell frame so they follow it; their frame is
    /// reported to the layout store for hover, hit-test and passthrough.
    @ViewBuilder
    private var trayQuickActionOverlay: some View {
        if showsExpandedContent,
           isExpanded,
           !layoutStore.isExpandedContentExiting,
           navigation.selectedPage == .tray,
           settings.trayEnabled,
           settings.fileShelfEnabled {
            let shell = layoutStore.expandedSurfaceFrame
            ZStack {
                if fileDragSession.isActive {
                    FileDragQuickActionOrbit(
                        session: fileDragSession,
                        layoutStore: layoutStore,
                        reduceMotion: reduceMotion || settings.reduceExtraMotion
                    )
                    .position(
                        x: shell.midX,
                        y: layoutStore.canvasSize.height - shell.minY
                            + FileDragQuickActionMetrics.gap
                            + FileDragQuickActionMetrics.diameter / 2
                    )
                    .transition(.opacity.combined(with: .scale(scale: (reduceMotion || settings.reduceExtraMotion) ? 1 : 0.92)))
                } else {
                    FileTrayQuickActionBar(
                        fileShelf: modules.fileShelf,
                        backgroundOperations: modules.backgroundOperations,
                        backgroundRemoval: modules.productivity.backgroundRemoval,
                        layoutStore: layoutStore,
                        reduceMotion: reduceMotion || settings.reduceExtraMotion
                    )
                    .position(
                        x: shell.midX,
                        y: layoutStore.canvasSize.height - shell.minY
                            + FileTrayQuickActionMetrics.gap
                            + FileTrayQuickActionMetrics.diameter / 2
                    )
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -6)))
                }
            }
            .animation(
                (reduceMotion || settings.reduceExtraMotion) ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.82),
                value: fileDragSession.isActive
            )
        }
    }

    @ViewBuilder
    private var collapsedSidecarOverlay: some View {
        if !showsExpandedContent,
           agentAttention.presentation == nil,
           !isCollapsedPreviewActive {
            LiveActivitySidecarLayer(
                resolution: collapsedLayoutResolution,
                compositeGeometry: collapsedCompositeGeometry,
                canvasHeight: layoutStore.canvasSize.height,
                reduceMotion: reduceMotion,
                onActivate: activateSidecar
            )
            .animation(shellAnimation, value: collapsedLayoutResolution)
        }
    }

    private var activeRoutineAgentProvider: AgentProvider? {
        modules.agentEvents.sessions.first(where: {
            switch $0.state {
            case .working, .runningTool, .runningCommand, .thinking, .planning:
                true
            case .waitingForApproval, .waitingForUser, .planReady,
                 .idle, .completed, .failed, .interrupted:
                false
            }
        })?.id.sessionID.provider
    }

    private var collapsedAgentProvider: AgentProvider? {
        if let provider = agentAttention.presentation?.primary?.session.sessionID.provider {
            return provider
        }
        return activeRoutineAgentProvider ?? agentGlow.provider
    }

    private var shouldShowCollapsedAgentGlow: Bool {
        agentAttention.presentation != nil ||
        activeRoutineAgentProvider != nil ||
        agentGlow.provider != nil
    }

    private var collapsedAgentGlowColor: Color {
        if agentAttention.presentation?.style == .failure {
            return Color(red: 0.9, green: 0.2, blue: 0.2)
        }
        switch collapsedAgentProvider {
        case .codex:
            return Color(red: 0.1, green: 0.3, blue: 0.7)
        case .claude:
            return Color(red: 0.9, green: 0.4, blue: 0.1)
        case .other, .none:
            return Color(red: 0.0, green: 0.8, blue: 1.0)
        }
    }

    private var collapsedAgentBrightGlowColor: Color {
        if agentAttention.presentation?.style == .failure {
            return Color(red: 1.0, green: 0.3, blue: 0.3)
        }
        switch collapsedAgentProvider {
        case .codex:
            return Color(red: 0.2, green: 0.45, blue: 0.9)
        case .claude:
            return Color(red: 1.0, green: 0.55, blue: 0.2)
        case .other, .none:
            return Color(red: 0.4, green: 0.95, blue: 1.0)
        }
    }

    private var surfaceSize: CGSize {
        surfaceFrame.size
    }

    private var gestureContext: IslandGestureContext {
        IslandGestureContext(
            presentationState: islandState.state,
            selectedPage: navigation.selectedPage,
            mediaControlAvailable: collapsedLayoutResolution.primary?.activity.kind == .media &&
                media.isTransportControlAvailable,
            timerIsRunning: modules.timer.isRunning,
            timerCanResume: modules.timer.remainingSeconds > 0,
            collapsedPreviewActive: isCollapsedPreviewActive,
            isShellMorphing: layoutStore.isShellMorphing,
            isCollapseShellOnly: layoutStore.isCollapseShellOnly,
            isExpandedContentExiting: layoutStore.isExpandedContentExiting,
            isFileDropTargeted: navigation.isFileDropTargeted
        )
    }

    private var gestureCallbacks: IslandGestureCallbacks {
        IslandGestureCallbacks(
            expand: {
                deactivateCollapsedPreview()
                onRequestExpand()
            },
            collapse: onRequestCollapse,
            nextTab: {
                navigation.selectNextPage(using: settings)
            },
            previousTab: {
                navigation.selectPreviousPage(using: settings)
            },
            mediaPlayPause: {
                guard media.isTransportControlAvailable else { return }
                media.playPause()
            },
            mediaNextTrack: {
                guard media.isTransportControlAvailable else { return }
                media.nextTrack()
            },
            mediaPreviousTrack: {
                guard media.isTransportControlAvailable else { return }
                media.previousTrack()
            },
            timerStartStop: {
                if modules.timer.isRunning {
                    modules.timer.pause()
                } else if modules.timer.remainingSeconds > 0 {
                    modules.timer.resume()
                }
            },
            openSettings: onOpenSettings
        )
    }

    private var surfaceFrame: CGRect {
        if isExpanded {
            return layoutStore.expandedSurfaceFrame
        }
        if isCollapsedPreviewActive {
            return collapsedPreviewSurfaceFrame
        }
        return layoutStore.collapsedSurfaceFrame
    }

    private var collapsedPreviewSurfaceFrame: CGRect {
        let base = layoutStore.collapsedSurfaceFrame
        let rowCount = collapsedPreviewContent?.rows.count ?? 0
        let liveActivityPreviewHeight = base.height + CGFloat(max(rowCount, 1) * 20) + 8
        let previewHeight = max(base.height, CGFloat(settings.collapsedHoverPreviewHeight), liveActivityPreviewHeight)
        return CGRect(
            x: base.minX,
            y: base.maxY - previewHeight,
            width: base.width,
            height: previewHeight
        ).integral
    }

    private var collapsedPreviewContent: CollapsedPreviewContent? {
        let rows = collapsedPreviewRows
        guard !rows.isEmpty else { return nil }
        return CollapsedPreviewContent(rows: rows)
    }

    private var collapsedSourceToggles: CollapsedLiveActivitySourceToggles {
        CollapsedLiveActivitySourceToggles(
            liveActivitiesEnabled: settings.liveActivitiesEnabled,
            timerEnabled: settings.timerEnabled && settings.showTimerLiveActivity,
            mediaEnabled: settings.mediaEnabled &&
                settings.showMusicLiveActivity &&
                (settings.showMediaWhenPaused || media.isPlaying),
            fileTrayEnabled: settings.trayEnabled &&
                settings.fileShelfEnabled &&
                settings.showFileDropLiveActivity,
            batteryEnabled: settings.showBatteryLiveActivity,
            systemHUDEnabled: settings.systemHUDsEnabled
        )
    }

    private var activeInteractiveSystemHUD: DynamicIslandLiveActivity? {
        liveActivities.activities.first {
            guard $0.id == LiveActivityStore.systemHUDActivityID else { return false }
            return $0.systemHUDKind == .volume || $0.systemHUDKind == .brightness
        }
    }

    private var collapsedLayoutActivities: [DynamicIslandLiveActivity] {
        LiveActivityRuntimeProjection.activities(
            stored: liveActivities.activities,
            priorities: settings.collapsedLiveActivityPrioritySettings,
            toggles: collapsedSourceToggles,
            agentSessions: modules.agentEvents.sessions,
            agentEnabled: settings.agentActivityEnabled && agentAttention.presentation == nil
        )
    }

    private var collapsedLayoutResolution: LiveActivityLayoutResolution {
        LiveActivityLayoutResolver.resolve(
            activities: collapsedLayoutActivities,
            context: LiveActivityLayoutContext(
                availableWidth: max(layoutStore.canvasSize.width, layoutStore.collapsedSurfaceFrame.width),
                hasHardwareNotch: layoutStore.hasHardwareNotch,
                hardwareNotchWidth: layoutStore.hardwareNotchWidth,
                primaryMinimumWidth: max(layoutStore.collapsedSurfaceFrame.width, 172),
                primaryIdealWidth: max(layoutStore.collapsedSurfaceFrame.width, 226),
                sidecarDiameter: LiveActivitySidecarMetrics.diameter,
                sidecarGap: LiveActivitySidecarMetrics.gap,
                allowSimultaneousSidecars: settings.allowSimultaneousLiveActivitySidecars,
                timerSidePreference: settings.timerSidecarPreference
            )
        )
    }

    private var collapsedContentMode: CollapsedIslandContentMode {
        guard let primary = collapsedLayoutResolution.primary?.activity else {
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
        case .backgroundOperation:
            return .generic(primary)
        case .battery:
            return .battery(primary)
        case .system:
            return .inactive
        case .screenRecording:
            return .screenRecording(primary)
        case .voiceRecording:
            return .voiceRecording(primary)
        case .voiceTranscription:
            return .voiceTranscription(primary)
        case .keepAwake, .terminalTask, .windowSnapPreview, .reminder,
             .camera, .backgroundRemoval, .message:
            return .generic(primary)
        }
    }

    private var collapsedCompositeGeometry: LiveActivityCompositeGeometry {
        LiveActivityCompositeGeometry.resolve(
            primaryFrame: layoutStore.collapsedSurfaceFrame,
            canvasSize: layoutStore.canvasSize,
            resolution: collapsedLayoutResolution,
            sidecarDiameter: LiveActivitySidecarMetrics.diameter,
            sidecarGap: LiveActivitySidecarMetrics.gap
        )
    }

    private func activateSidecar(_ presentation: LiveActivityPresentation) {
        switch presentation.activity.kind {
        case .timer:
            navigation.showTimer()
            onRequestExpand()
        case .agent:
            navigation.showAgents()
            onRequestExpand()
        case .media:
            navigation.showIsland()
            onRequestExpand()
        case .fileTray, .backgroundOperation:
            navigation.showTray()
            onRequestExpand()
        case .battery, .system, .keepAwake, .terminalTask, .windowSnapPreview,
             .reminder, .voiceRecording, .voiceTranscription, .camera, .backgroundRemoval:
            break
        case .screenRecording:
            navigation.showIsland()
            modules.rightWorkspace.show(.productivity)
            onRequestExpand()
        case .message:
            navigation.showMessages()
            onRequestExpand()
        }
    }

    private func synchronizeCollapsedSidecarGeometry() {
        if islandState.state == .collapsed,
           agentAttention.presentation == nil,
           !isCollapsedPreviewActive {
            layoutStore.updateCollapsedSidecars(collapsedCompositeGeometry)
        } else {
            layoutStore.updateCollapsedSidecars(
                LiveActivityCompositeGeometry.resolve(
                    primaryFrame: layoutStore.collapsedSurfaceFrame,
                    canvasSize: layoutStore.canvasSize,
                    resolution: .empty,
                    sidecarDiameter: LiveActivitySidecarMetrics.diameter,
                    sidecarGap: LiveActivitySidecarMetrics.gap
                )
            )
        }
    }

    private var isCollapsedPreviewAllowed: Bool {
        islandState.state == .collapsed &&
            settings.collapsedHoverPreviewEnabled &&
            collapsedPreviewContent != nil &&
            !navigation.isFileDropTargeted &&
            !layoutStore.isShellMorphing &&
            !layoutStore.isCollapseShellOnly &&
            !layoutStore.isExpandedContentExiting &&
            contentPhase == .compact
    }

    private var isCollapsedPreviewActive: Bool {
        collapsedPreviewVisible && isCollapsedPreviewAllowed
    }

    private var collapsedPreviewAnimation: Animation {
        if reduceMotion || settings.reduceExtraMotion || settings.animationPreset == .instant {
            return .easeInOut(duration: 0.01)
        }
        let duration = settings.contentAnimationEnabled ? 0.18 / max(settings.shellAnimationSpeed, 0.25) : 0.01
        return .smooth(duration: min(max(duration, 0.12), 0.24))
    }

    private var mediaCollapsedPreviewContent: CollapsedPreviewContent? {
        let rows = mediaCollapsedPreviewRows(isPrimary: true)
        guard !rows.isEmpty else { return nil }
        return CollapsedPreviewContent(rows: rows)
    }

    private var collapsedPreviewRows: [CollapsedPreviewRowContent] {
        let toggles = CollapsedLiveActivitySourceToggles(
            liveActivitiesEnabled: settings.liveActivitiesEnabled,
            timerEnabled: settings.timerEnabled && settings.showTimerLiveActivity,
            mediaEnabled: settings.mediaEnabled &&
                settings.showMusicLiveActivity &&
                settings.collapsedHoverPreviewMediaEnabled &&
                (settings.showMediaWhenPaused || media.isPlaying),
            fileTrayEnabled: settings.trayEnabled && settings.fileShelfEnabled && settings.showFileDropLiveActivity,
            batteryEnabled: settings.showBatteryLiveActivity
        )
        let previewActivities = CollapsedLiveActivitySelector.previewActivities(
            activities: liveActivities.activities,
            priorities: settings.collapsedLiveActivityPrioritySettings,
            toggles: toggles,
            maxCount: 3
        )

        if previewActivities.isEmpty {
            return mediaCollapsedPreviewRows(isPrimary: true)
        }

        return previewActivities.enumerated().compactMap { index, activity in
            previewRow(for: activity, isPrimary: index == 0)
        }
    }

    private func mediaCollapsedPreviewRows(isPrimary: Bool) -> [CollapsedPreviewRowContent] {
        guard settings.mediaEnabled,
              settings.collapsedHoverPreviewMediaEnabled,
              media.hasActiveMediaSource,
              settings.showMediaWhenPaused || media.isPlaying else {
            return []
        }

        let title = settings.collapsedHoverPreviewShowTitle && settings.showMediaTitle
            ? media.title.trimmedForCollapsedPreview
            : nil
        let artist: String?
        if settings.collapsedHoverPreviewShowsArtist {
            let artistCandidate = settings.showMediaArtist
                ? media.artist.trimmedForCollapsedPreview
                : nil
            artist = artistCandidate ?? (
                settings.collapsedHoverPreviewShowsSource && settings.showMediaSourceName
                    ? media.sourceName.trimmedForCollapsedPreview
                    : nil
            )
        } else {
            artist = nil
        }

        guard title != nil || artist != nil else {
            return []
        }

        return [
            CollapsedPreviewRowContent(
                id: LiveActivityStore.mediaActivityID,
                title: title ?? "Now Playing",
                subtitle: artist,
                trailingText: nil,
                symbolName: settings.collapsedHoverPreviewTitleIconName,
                fallbackSymbolName: "music.note",
                kind: .media,
                isPrimary: isPrimary
            )
        ]
    }

    private func previewRow(
        for activity: DynamicIslandLiveActivity,
        isPrimary: Bool
    ) -> CollapsedPreviewRowContent? {
        switch activity.kind {
        case .timer:
            let remainingTime = timerText(for: activity)
            return CollapsedPreviewRowContent(
                id: activity.id,
                title: "Timer",
                subtitle: activity.isActive ? "Running" : "Paused",
                trailingText: remainingTime,
                symbolName: activity.isActive ? "timer" : "pause.circle.fill",
                fallbackSymbolName: "timer",
                kind: .timer,
                isPrimary: isPrimary
            )
        case .media:
            let title = settings.showMediaTitle ? media.title.trimmedForCollapsedPreview : nil
            let subtitle = settings.showMediaArtist
                ? media.artist.trimmedForCollapsedPreview
                : (settings.showMediaSourceName ? media.sourceName.trimmedForCollapsedPreview : nil)
            guard title != nil || subtitle != nil else { return nil }
            return CollapsedPreviewRowContent(
                id: activity.id,
                title: title ?? "Now Playing",
                subtitle: subtitle,
                trailingText: activity.isActive ? "Playing" : "Paused",
                symbolName: "music.note",
                fallbackSymbolName: "music.note",
                kind: .media,
                isPrimary: isPrimary
            )
        case .fileTray:
            return CollapsedPreviewRowContent(
                id: activity.id,
                title: activity.title,
                subtitle: activity.subtitle,
                trailingText: nil,
                symbolName: "tray.and.arrow.down.fill",
                fallbackSymbolName: "tray.full",
                kind: .fileDrop,
                isPrimary: isPrimary
            )
        case .backgroundOperation:
            return CollapsedPreviewRowContent(
                id: activity.id,
                title: activity.title,
                subtitle: activity.subtitle,
                trailingText: activity.progress.map { "\(Int(($0 * 100).rounded()))%" },
                symbolName: activity.symbolName,
                fallbackSymbolName: "archivebox",
                kind: .liveActivity,
                isPrimary: isPrimary
            )
        case .battery:
            return CollapsedPreviewRowContent(
                id: activity.id,
                title: activity.title,
                subtitle: activity.subtitle,
                trailingText: batteryPercentText(for: activity),
                symbolName: activity.symbolName,
                fallbackSymbolName: "battery.75percent",
                kind: .battery,
                isPrimary: isPrimary
            )
        case .agent:
            return CollapsedPreviewRowContent(
                id: activity.id,
                title: activity.title,
                subtitle: activity.subtitle,
                trailingText: nil,
                symbolName: activity.symbolName,
                fallbackSymbolName: "cpu",
                kind: .liveActivity,
                isPrimary: isPrimary
            )
        case .system:
            return nil
        case .keepAwake, .terminalTask, .windowSnapPreview, .reminder,
             .voiceRecording, .voiceTranscription, .camera, .backgroundRemoval,
             .screenRecording, .message:
            return CollapsedPreviewRowContent(
                id: activity.id,
                title: activity.title,
                subtitle: activity.subtitle,
                trailingText: nil,
                symbolName: activity.symbolName,
                fallbackSymbolName: "circle.fill",
                kind: .liveActivity,
                isPrimary: isPrimary
            )
        }
    }

    private func batteryPercentText(for activity: DynamicIslandLiveActivity) -> String? {
        guard let progress = LiveActivityStore.clampedProgress(activity.progress) else { return nil }
        return "\(Int((progress * 100).rounded()))%"
    }

    private func timerText(for activity: DynamicIslandLiveActivity) -> String {
        (activity.subtitle ?? activity.title)
            .replacingOccurrences(of: "Paused • ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var fileDropTargetBinding: Binding<Bool> {
        Binding(
            get: { modules.navigation.isFileDropTargeted },
            set: { isTargeted in
                let accepted = isTargeted &&
                    settings.trayEnabled &&
                    settings.fileShelfEnabled &&
                    settings.allowFileDropsOnCollapsedIsland &&
                    settings.showTrayTab
                fileDragSession.setSourceTargeted(accepted, region: .collapsedIsland)
                if accepted {
                    modules.navigation.showTrayForFileDrag(using: settings)
                    onRequestExpand()
                } else {
                    modules.navigation.endFileDropTargeting()
                }
            }
        )
    }

    private func loadDroppedFilesFromCollapsedIsland(from providers: [NSItemProvider]) -> Bool {
        let loader = FileDropProviderLoader()
        guard islandState.state == .collapsed,
              renderedContentMode == .compact,
              canAcceptCollapsedFileDrop,
              loader.canLoad(providers) else {
            modules.navigation.endFileDropTargeting()
            return false
        }
        modules.navigation.endFileDropTargeting()
        fileDragSession.cancel()

        loader.loadURLs(from: providers) { urls in
            Task { @MainActor in
                guard canAcceptCollapsedFileDrop else {
                    FileShelfTemporaryStorage.shared.removeIfOwned(urls)
                    return
                }
                modules.fileShelf.add(urls)
            }
        }
        return true
    }

    private var canAcceptCollapsedFileDrop: Bool {
        FileDropPolicy.allowsCollapsedDrop(settings: settings)
    }

    private func synchronizePresentationForCurrentState() {
        guard settings.overlayEnabled else { return }
        if islandState.state == .expanded {
            startExpansionSequence()
        } else {
            finalizeCompactPresentation()
        }
    }

    private func handleStateChange(_ state: IslandPresentationState) {
        guard settings.overlayEnabled else {
            sequenceGeneration += 1
            finalizeCompactPresentation()
            return
        }
        switch state {
        case .expanded:
            deactivateCollapsedPreview()
            startExpansionSequence()
        case .collapsed:
            deactivateCollapsedPreview()
            beginShellCollapseSequence()
        }
    }

    private func startExpansionSequence() {
        guard settings.overlayEnabled else { return }
        let sessionGeneration = layoutStore.overlayPresentationGeneration
        sequenceGeneration += 1
        let generation = sequenceGeneration
        if !modules.navigation.isFileDropTargeted {
            if settings.rememberLastSelectedTab {
                modules.navigation.ensureValidSelection(using: settings)
            } else {
                modules.navigation.applyDefaultSelectionIfNeeded(using: settings)
                // Same convention for the right workspace: without "remember
                // last tab", each expansion starts on the default page.
                modules.rightWorkspace.resetToDefaultPage()
            }
        }
        renderedContentMode = .expanded
        expandedContentMounted = true
        contentVisible = false
        isContentRemoving = false
        contentPhase = .shellExpanding

        let shellDuration = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: reduceMotion
        )
        // Children appear only after the shell has fully expanded, including
        // under Reduce Motion (where the shell duration is already short).
        let revealDelay = !settings.contentAnimationEnabled || settings.animationPreset == .instant
            ? 0
            : IslandContentTransitionTiming.expansionContentDelay(shellDuration: shellDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) {
            guard settings.overlayEnabled, sessionGeneration == layoutStore.overlayPresentationGeneration,
                  generation == sequenceGeneration else { return }
            guard islandState.state == .expanded else { return }
            guard !layoutStore.isExpandedContentExiting else { return }
            isContentRemoving = false
            contentVisible = true
            contentPhase = .expandedContentVisible
        }
    }

    private func beginContentExitSequence() {
        sequenceGeneration += 1
        renderedContentMode = .expanded
        contentVisible = false
        isContentRemoving = expandedContentMounted
        contentPhase = .contentCollapsing
    }

    private func cancelContentExitSequence() {
        sequenceGeneration += 1
        renderedContentMode = .expanded
        expandedContentMounted = true
        isContentRemoving = false
        contentVisible = true
        contentPhase = .expandedContentVisible
    }

    private func beginShellCollapseSequence() {
        sequenceGeneration += 1
        renderedContentMode = .expanded
        contentVisible = false
        isContentRemoving = expandedContentMounted
        contentPhase = .shellCollapsing
    }

    private func finalizeCompactPresentation() {
        renderedContentMode = .compact
        expandedContentMounted = false
        contentVisible = false
        isContentRemoving = false
        contentPhase = .compact
        updateCollapsedPreviewLayout()
    }

    private func handleCollapsedHover(_ isHovering: Bool) {
        guard settings.overlayEnabled else { return }
        let sessionGeneration = layoutStore.overlayPresentationGeneration
        isCollapsedHovering = isHovering
        collapsedPreviewGeneration += 1
        let generation = collapsedPreviewGeneration

        guard isHovering else {
            collapsedPreviewVisible = false
            updateCollapsedPreviewLayout()
            return
        }

        guard isCollapsedPreviewAllowed else {
            collapsedPreviewVisible = false
            updateCollapsedPreviewLayout()
            return
        }

        let delay = reduceMotion || settings.reduceExtraMotion || settings.animationPreset == .instant
            ? 0
            : settings.collapsedHoverPreviewDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard settings.overlayEnabled, sessionGeneration == layoutStore.overlayPresentationGeneration,
                  generation == collapsedPreviewGeneration else { return }
            guard isCollapsedHovering, isCollapsedPreviewAllowed else { return }
            collapsedPreviewVisible = true
            updateCollapsedPreviewLayout()
        }
    }

    private func deactivateCollapsedPreview() {
        isCollapsedHovering = false
        collapsedPreviewVisible = false
        collapsedPreviewGeneration += 1
        updateCollapsedPreviewLayout()
    }

    private func updateCollapsedPreviewLayout() {
        let active = isCollapsedPreviewActive
        layoutStore.updateCollapsedPreview(
            active: active,
            frame: active ? collapsedPreviewSurfaceFrame : .zero
        )
    }
}

private extension String {
    var trimmedForCollapsedPreview: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != "Nothing Playing",
              trimmed != "Open Spotify or Music" else {
            return nil
        }
        return trimmed
    }
}

private struct BlurBounceModifier: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double
    var anchor: UnitPoint = .top

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: anchor)
            .opacity(opacity)
    }
}

/// Drives the "materialize in place" animation for the inner tray content only.
/// The tray shell still uses the bouncy spring from IslandRootView.
struct InnerBlurScaleCleanModifier: ViewModifier {
    let isVisible: Bool
    let isRemoval: Bool
    let delay: Double
    let entranceDuration: TimeInterval
    let exitDuration: TimeInterval
    let reduceMotion: Bool
    let animationsEnabled: Bool
    let useBlurTransitions: Bool
    let useScaleTransitions: Bool

    private var scale: CGFloat {
        if reduceMotion || !animationsEnabled || !useScaleTransitions { return 1.0 }
        if isVisible { return 1.0 }
        return isRemoval ? IslandContentTransitionTiming.collapseExitScale : 0.955
    }

    private var blur: CGFloat {
        if reduceMotion || !animationsEnabled || !useBlurTransitions { return 0 }
        if isVisible { return 0 }
        return isRemoval ? IslandContentTransitionTiming.collapseExitBlur : 8
    }

    private var opacity: Double {
        isVisible ? 1 : 0
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .center)
            .opacity(opacity)
            .animation(animation, value: isVisible)
    }

    private var animation: Animation {
        guard animationsEnabled else {
            return .linear(duration: 0.01)
        }
        if isVisible {
            return .easeOut(duration: reduceMotion ? 0.10 : entranceDuration)
                .delay(reduceMotion ? 0 : delay)
        }

        return .easeIn(duration: reduceMotion ? IslandContentTransitionTiming.reducedCollapseExitDuration : exitDuration)
            .delay(reduceMotion ? 0 : min(max(0, delay * 0.35), IslandContentTransitionTiming.collapseExitStaggerAllowance))
    }
}

private extension AnyTransition {
static var blurBounce: AnyTransition {
    .asymmetric(
        insertion: .modifier(
            active: BlurBounceModifier(
                blur: 50,
                scale: 0.18,
                opacity: 1.0,
                anchor: .top
            ),
            identity: BlurBounceModifier(
                blur: 0,
                scale: 1.0,
                opacity: 1.0,
                anchor: .top
            )
        ),
        removal: .modifier(
            active: BlurBounceModifier(
                blur: 50,
                scale: 0.16,
                opacity: 1.0,
                anchor: .top
            ),
            identity: BlurBounceModifier(
                blur: 0,
                scale: 1.0,
                opacity: 1.0,
                anchor: .top
            )
        )
    )
}

    static var compactMediaContent: AnyTransition {
    .asymmetric(
        insertion: .modifier(
            active: BlurBounceModifier(
                blur: 50,
                scale: 0.10,
                opacity: 1.0,
                anchor: .top
            ),
            identity: BlurBounceModifier(
                blur: 0,
                scale: 1.0,
                opacity: 1.0,
                anchor: .top
            )
        ),
        removal: .modifier(
            active: BlurBounceModifier(
                blur: 50,
                scale: 0.10,
                opacity: 1.0,
                anchor: .top
            ),
            identity: BlurBounceModifier(
                blur: 0,
                scale: 1.0,
                opacity: 1.0,
                anchor: .top
            )
        )
    )
}
}

extension View {
    func innerBlurScaleClean(
        settings: AppSettings,
        isVisible: Bool,
        isRemoval: Bool,
        index: Int,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            InnerBlurScaleCleanModifier(
                isVisible: isVisible,
                isRemoval: isRemoval,
                delay: settings.contentStaggerEnabled
                    ? min(Double(index) * 0.01 * min(max(settings.contentStaggerAmount, 0), 1.5), 0.04)
                    : 0,
                entranceDuration: IslandContentTransitionTiming.expansionContentDuration(
                    shellDuration: IslandContentTransitionTiming.shellDuration(
                        settings: settings,
                        reduceMotion: reduceMotion
                    )
                ),
                exitDuration: IslandContentTransitionTiming.collapseContentDuration(
                    shellDuration: IslandContentTransitionTiming.shellDuration(
                        settings: settings,
                        reduceMotion: reduceMotion
                    )
                ),
                reduceMotion: reduceMotion,
                animationsEnabled: settings.contentAnimationEnabled,
                useBlurTransitions: settings.useBlurTransitions,
                useScaleTransitions: settings.useScaleTransitions
            )
        )
    }
}

struct IslandSurface<Content: View>: View {
    @ObservedObject var settings: AppSettings
    let isExpanded: Bool
    let visualProgress: CGFloat
    var collapsedPresentationProfile: CollapsedPresentationProfile = .normal
    var collapsedGlowColor: Color = .cyan
    var collapsedBrightGlowColor: Color = .white
    var forcesCollapsedGlow = false
    var systemHUDActivity: DynamicIslandLiveActivity? = nil
    @ViewBuilder var content: Content
    @Environment(\.isNotchIntegratedShell) private var isNotchIntegratedShell
    @Environment(\.isShellMorphing) private var isShellMorphing
    @Environment(\.isCollapseShellOnly) private var isCollapseShellOnly

    var body: some View {
        let radii = IslandShellRadii.interpolated(
            progress: visualProgress,
            isNotchIntegrated: isNotchIntegratedShell,
            collapsedBottom: collapsedPresentationProfile.bottomCornerRadius
        )
        let shellShape = IslandShellShape(
            topCornerRadius: radii.top,
            bottomCornerRadius: radii.bottom
        )
        let usesExpandedContentPadding = isExpanded || isCollapseShellOnly
        let collapsedHorizontalPadding = collapsedPresentationProfile.kind == .normal
            ? IslandShellLayout.collapsedHorizontalPadding(isNotchIntegrated: isNotchIntegratedShell)
            : collapsedPresentationProfile.horizontalContentInset
        let strokeOpacity = 0.035 + ((0.07 - 0.035) * Double(visualProgress))

        ZStack {
            IslandSurfaceBackground(
                theme: settings.islandThemeStyle,
                isExpanded: isExpanded,
                isShellMorphing: isShellMorphing,
                opacity: settings.shellOpacity,
                shape: shellShape
            )
                .overlay {
                    if settings.shellStrokeEnabled {
                        shellShape
                            .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                    }
                }
                .overlay {
                    if !isExpanded, collapsedPresentationProfile.glowStrength > 0 || forcesCollapsedGlow {
                        AgentNotchGlowBorder(
                            topCornerRadius: radii.top,
                            bottomCornerRadius: radii.bottom,
                            glowColor: collapsedGlowColor,
                            brightColor: collapsedBrightGlowColor
                        )
                        .opacity(
                            collapsedPresentationProfile.glowStrength > 0
                                ? collapsedPresentationProfile.glowStrength
                                : (forcesCollapsedGlow ? 1 : 0)
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.5), value: forcesCollapsedGlow)

            if !isExpanded,
               collapsedPresentationProfile.kind == .systemHUD,
               let systemHUDActivity {
                SystemHUDBottomOuterGlow(activity: systemHUDActivity)
                    .transition(.opacity)
                    .zIndex(3)
            }

            content
                .padding(.horizontal, usesExpandedContentPadding ? 0 : collapsedHorizontalPadding)
                .padding(.top, usesExpandedContentPadding ? 0 : IslandShellLayout.collapsedTopPadding)
                .padding(.bottom, usesExpandedContentPadding ? 0 : IslandShellLayout.collapsedBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(shellShape)
        }
    }
}

private struct SystemHUDBottomOuterGlow: View {
    let activity: DynamicIslandLiveActivity

    var body: some View {
        GeometryReader { proxy in
            let progress = LiveActivityStore.clampedProgress(activity.progress) ?? 0
            let kind = activity.systemHUDKind ?? .volume
            let components = SystemHUDAccentComponents.resolve(
                kind: kind,
                value: progress,
                isMuted: kind == .volume && progress <= 0.0001
            )
            let color = Color(
                red: components.red,
                green: components.green,
                blue: components.blue
            )
            let strength = 0.18 + (components.glowStrength * 0.82)

            Capsule(style: .continuous)
                .fill(color.opacity(0.12 * strength))
                .frame(width: max(proxy.size.width - 34, 1), height: 1.2)
                .position(x: proxy.size.width / 2, y: proxy.size.height + 0.6)
                .shadow(
                    color: color.opacity(0.62 * strength),
                    radius: 4 + (8 * progress),
                    y: 3 + (3 * progress)
                )
                .shadow(
                    color: color.opacity(0.25 * strength),
                    radius: 10 + (9 * progress),
                    y: 7 + (4 * progress)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AgentNotchGlowBorder: View {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let glowColor: Color
    let brightColor: Color

    private var frameInterval: Double {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? (1.0 / 15.0) : (1.0 / 25.0)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rotation = (time.truncatingRemainder(dividingBy: 2.0)) / 2.0 * 360
            IslandShellShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: glowColor.opacity(0.3), location: 0.1),
                        .init(color: glowColor, location: 0.2),
                        .init(color: brightColor, location: 0.3),
                        .init(color: glowColor, location: 0.4),
                        .init(color: glowColor.opacity(0.3), location: 0.5),
                        .init(color: .clear, location: 0.6),
                        .init(color: .clear, location: 1.0)
                    ],
                    center: .center,
                    startAngle: .degrees(rotation),
                    endAngle: .degrees(rotation + 360)
                ),
                lineWidth: 2.5
            )
            .shadow(color: glowColor.opacity(0.7), radius: 8)
            .shadow(color: glowColor.opacity(0.4), radius: 16)
            .shadow(color: glowColor.opacity(0.2), radius: 24)
            .mask {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 4)
                    Color.white
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct IslandShellRadii: Equatable {
    static let collapsedTop: CGFloat = 6
    static let expandedTop: CGFloat = 19
    static let collapsedBottom: CGFloat = 14
    static let expandedBottom: CGFloat = 24

    let top: CGFloat
    let bottom: CGFloat

    static func interpolated(
        progress: CGFloat,
        isNotchIntegrated: Bool,
        collapsedBottom: CGFloat = IslandShellRadii.collapsedBottom
    ) -> IslandShellRadii {
        let clampedProgress = progress.isFinite ? min(max(progress, 0), 1) : 0
        let top = collapsedTop + ((expandedTop - collapsedTop) * clampedProgress)
        let resolvedCollapsedBottom = collapsedBottom.isFinite ? max(collapsedBottom, 0) : Self.collapsedBottom
        let bottom = resolvedCollapsedBottom + ((expandedBottom - resolvedCollapsedBottom) * clampedProgress)
        return IslandShellRadii(
            top: isNotchIntegrated ? top : 0,
            bottom: bottom
        )
    }
}

private struct IslandShellShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite,
              rect.height.isFinite,
              rect.width > 0,
              rect.height > 0 else {
            return Path()
        }

        let requestedTop = topCornerRadius.isFinite ? max(topCornerRadius, 0) : 0
        let topRadius = min(requestedTop, rect.width / 2, rect.height)
        let requestedBottom = bottomCornerRadius.isFinite ? max(bottomCornerRadius, 0) : 0
        let bottomRadius = min(
            requestedBottom,
            max(rect.height - topRadius, 0),
            max((rect.width / 2) - topRadius, 0)
        )

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

struct CompactIslandView: View {
    @ObservedObject var settings: AppSettings
    let modules: IslandModules
    let contentMode: CollapsedIslandContentMode
    let layoutResolution: LiveActivityLayoutResolution
    let previewContent: CollapsedPreviewContent?
    let previewActive: Bool
    let hardwareNotchWidth: CGFloat
    let collapsedLeftRegionWidth: CGFloat
    let collapsedNotchCoreWidth: CGFloat
    let collapsedRightRegionWidth: CGFloat
    let isNotchIntegratedShell: Bool
    @ObservedObject private var media: MediaController
    @ObservedObject private var liveActivities: LiveActivityStore
    @ObservedObject private var agentAttention: AgentAttentionCoordinator
    @ObservedObject private var agentEvents: AgentEventStore
    @ObservedObject private var accentCache = ArtworkAccentColorCache.shared
    @ObservedObject private var artworkPresentation: ArtworkPresentationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        settings: AppSettings,
        modules: IslandModules,
        contentMode: CollapsedIslandContentMode = .inactive,
        layoutResolution: LiveActivityLayoutResolution = .empty,
        previewContent: CollapsedPreviewContent? = nil,
        previewActive: Bool = false,
        hardwareNotchWidth: CGFloat = 0,
        collapsedLeftRegionWidth: CGFloat = 0,
        collapsedNotchCoreWidth: CGFloat = 0,
        collapsedRightRegionWidth: CGFloat = 0,
        isNotchIntegratedShell: Bool = false
    ) {
        self.settings = settings
        self.modules = modules
        self.contentMode = contentMode
        self.layoutResolution = layoutResolution
        self.previewContent = previewContent
        self.previewActive = previewActive
        self.hardwareNotchWidth = hardwareNotchWidth
        self.collapsedLeftRegionWidth = collapsedLeftRegionWidth
        self.collapsedNotchCoreWidth = collapsedNotchCoreWidth
        self.collapsedRightRegionWidth = collapsedRightRegionWidth
        self.isNotchIntegratedShell = isNotchIntegratedShell
        media = modules.media
        liveActivities = modules.liveActivities
        agentAttention = modules.agentAttention
        agentEvents = modules.agentEvents
        artworkPresentation = modules.media.artworkPresentation
    }

    var body: some View {
        let activeBranch = contentMode == .media && shouldShowMediaSession
        let visualizerColor = visualizerAccentColor
        let attentionPresentation = agentAttention.presentation
        let attentionSession = attentionPresentation?.primary.flatMap { agentEvents.session(for: $0.session) }
        let attentionAccent: Color = switch attentionPresentation?.style {
        case .success: .green
        case .actionRequired: .orange
        case .failure: .red
        case .informational, .none: .cyan
        }
        let attentionSymbol: String = switch attentionPresentation?.style {
        case .success: "checkmark"
        case .actionRequired: "hand.raised.fill"
        case .failure: "exclamationmark"
        case .informational: "sparkles"
        case .none: "circle.fill"
        }
        let _ = Self.debugRender(
            hasActiveMediaSource: media.hasActiveMediaSource,
            isPlaying: media.isPlaying,
            title: media.title,
            sourceName: media.sourceName,
            branch: activeBranch ? "active compact" : "inactive compact"
        )

        ZStack(alignment: .bottom) {
            if let attentionPresentation, let primary = attentionPresentation.primary {
                VStack(spacing: 0) {
                    sideSlotLayout {
                        AgentCompactAttentionLeadingView(
                            provider: primary.session.sessionID.provider,
                            project: attentionSession?.project.displayName,
                            session: attentionSession
                        )
                    } right: {
                        AgentCompactAttentionTrailingView(
                            text: attentionPresentation.totalCount > 1
                                ? "\(attentionPresentation.totalCount) agents"
                                : titleForAttention(primary.reason),
                            accent: attentionAccent,
                            symbol: attentionSymbol
                        )
                    }
                    .frame(height: 22)

                    Spacer(minLength: 4)

                    AgentCompactPeekNotificationView(
                        presentation: attentionPresentation,
                        session: attentionSession
                    )
                }
                .padding(.bottom, 5)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else {
                compactContentRow(activeBranch: activeBranch, visualizerColor: visualizerColor)
                    .frame(height: 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: previewActive ? .top : .center)
                    .padding(.top, previewActive ? 2 : 0)

                if previewActive, let previewContent {
                    CollapsedPreviewRow(content: previewContent)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(previewRowAnimation, value: previewActive)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(compactContentAnimation, value: media.hasActiveMediaSource)
        .animation(compactContentAnimation, value: liveActivities.activities)
        .animation(compactContentAnimation, value: contentMode)
        .animation(compactContentAnimation, value: previewActive)
    }

    private func titleForAttention(_ reason: AgentAttentionReason) -> String {
        switch reason {
        case .approvalRequired: "Permission required"
        case .userInputRequired: "Input required"
        case .completed: "Task Complete"
        case .failed: "Task Failed"
        case .planReady: "Plan ready"
        case .interrupted: "Interrupted"
        }
    }

    @ViewBuilder
    private func compactContentRow(activeBranch: Bool, visualizerColor: Color) -> some View {
        ZStack {
            persistentCompactContent(activeBranch: activeBranch, visualizerColor: visualizerColor)

            if let overlay = layoutResolution.overlayTransient?.activity {
                CollapsedSystemHUDCompactView(
                    activity: overlay,
                    layout: sideSlotGeometry,
                    controller: modules.systemHUD
                )
                .background(Color.black.opacity(0.97))
                .transition(.compactMediaContent)
                .zIndex(10)
            }
        }
    }

    @ViewBuilder
    private func persistentCompactContent(activeBranch: Bool, visualizerColor: Color) -> some View {
        switch contentMode {
        case .media where activeBranch:
            sideSlotLayout {
                if settings.showAlbumArtwork {
                    CompactMediaView(media: media)
                }
            } right: {
                if settings.showVisualizer && settings.showCollapsedVisualizer {
                    AudioVisualizerView(
                        isPlaying: media.isPlaying,
                        isActive: media.hasActiveMediaSource,
                        accentColor: visualizerColor,
                        variant: .compact,
                        barCount: 7,
                        pauseDuringShellMorph: settings.disableVisualizerDuringMorph
                    )
                }
            }
            .transition(.compactMediaContent)

        case .agent:
            if let presentation = AgentCompactPresentation.make(
                sessions: agentEvents.sessions,
                enabled: settings.agentActivityEnabled
            ), let primary = presentation.sessions.first {
                sideSlotLayout {
                    AgentCompactRoutineLeadingView(session: primary)
                } right: {
                    AgentCompactRoutineTrailingView(session: primary)
                }
                .transition(.compactMediaContent)
            } else {
                Color.clear
            }

        case .system(let activity):
            CollapsedSystemHUDCompactView(
                activity: activity,
                layout: sideSlotGeometry,
                controller: modules.systemHUD
            )
            .transition(.compactMediaContent)

        case .timer(let activity):
            CollapsedTimerActivityCompactView(
                activity: activity,
                layout: sideSlotGeometry
            )
            .transition(.compactMediaContent)

        case .fileTray(let activity):
            CollapsedFileActivityCompactView(
                activity: activity,
                layout: sideSlotGeometry
            )
            .transition(.compactMediaContent)

        case .battery(let activity):
            CollapsedBatteryActivityCompactView(
                activity: activity,
                layout: sideSlotGeometry
            )
            .transition(.compactMediaContent)

        case .screenRecording:
            CollapsedScreenRecordingActivityView(
                controller: modules.productivity.screenRecording,
                layout: sideSlotGeometry
            )
            .transition(.compactMediaContent)

        case .voiceRecording(let activity), .voiceTranscription(let activity):
            CollapsedVoiceBeamCompactView(
                controller: modules.productivity.voice,
                activity: activity
            )
            .transition(.compactMediaContent)

        case .generic(let activity):
            CollapsedGenericActivityCompactView(
                activity: activity,
                layout: sideSlotGeometry
            )
            .transition(.compactMediaContent)

        case .inactive:
            if agentAttention.presentation == nil,
               let presentation = AgentCompactPresentation.make(
                   sessions: agentEvents.sessions,
                   enabled: settings.agentActivityEnabled
               ), let primary = presentation.sessions.first {
                sideSlotLayout {
                    AgentCompactRoutineLeadingView(session: primary)
                } right: {
                    AgentCompactRoutineTrailingView(session: primary)
                }
                .transition(.opacity)
            } else {
                Color.clear
                    .transition(.opacity)
            }

        case .media:
            Color.clear
                .transition(.opacity)
        }
    }

    private var sideSlotGeometry: CompactCollapsedSideSlotGeometry {
        CompactCollapsedSideSlotGeometry(
            isNotchIntegrated: isNotchIntegratedShell,
            leftRegionWidth: collapsedLeftRegionWidth,
            notchCoreWidth: hardwareNotchWidth > 0 ? collapsedNotchCoreWidth : 0,
            rightRegionWidth: collapsedRightRegionWidth
        )
    }

    private func sideSlotLayout<Left: View, Right: View>(
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) -> some View {
        CompactCollapsedSideSlotLayout(
            geometry: sideSlotGeometry,
            left: left,
            right: right
        )
    }

    private var compactContentAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .easeInOut(duration: 0.28)
    }

    private var previewRowAnimation: Animation {
        guard !reduceMotion, settings.contentAnimationEnabled else {
            return .easeInOut(duration: 0.01)
        }
        switch settings.animationPreset {
        case .instant:
            return .easeInOut(duration: 0.01)
        case .subtle:
            return .easeInOut(duration: 0.12)
        case .normal:
            return .easeInOut(duration: 0.22).delay(0.035)
        case .slow:
            return .easeInOut(duration: 0.24)
        }
    }

    private var shouldShowMediaSession: Bool {
        guard settings.mediaEnabled else { return false }
        guard media.hasActiveMediaSource else { return false }
        return settings.showMediaWhenPaused || media.isPlaying
    }

    private var visualizerAccentColor: Color {
        switch settings.visualizerAccentMode {
        case .artwork:
            if settings.useArtworkAccentColor {
                return accentCache.color(
                    for: artworkPresentation.displayedSnapshot?.fingerprint,
                    image: artworkPresentation.displayedSnapshot?.image
                )
            }
            return .white
        case .white:
            return .white
        case .system:
            return .accentColor
        }
    }

    private static func debugRender(
        hasActiveMediaSource: Bool,
        isPlaying: Bool,
        title: String,
        sourceName: String,
        branch: String
    ) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" else { return }
        debugPrint(
            "DynamicIsland CompactIslandView render",
            "hasActiveMediaSource=\(hasActiveMediaSource)",
            "isPlaying=\(isPlaying)",
            "title=\(title)",
            "source=\(sourceName)",
            "branch=\(branch)"
        )
        #endif
    }
}

struct CompactCollapsedSideSlotGeometry {
    let isNotchIntegrated: Bool
    let leftRegionWidth: CGFloat
    let notchCoreWidth: CGFloat
    let rightRegionWidth: CGFloat

    var usesPhysicalNotchRegions: Bool {
        isNotchIntegrated && notchCoreWidth > 0
    }
}

struct CompactCollapsedSideSlotLayout<Left: View, Right: View>: View {
    let geometry: CompactCollapsedSideSlotGeometry
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    var body: some View {
        if geometry.usesPhysicalNotchRegions {
            HStack(spacing: 0) {
                left()
                    .padding(.leading, CollapsedActivityLayoutProfile.leadingContentPadding)
                    .frame(width: geometry.leftRegionWidth, alignment: .leading)
                Color.clear
                    .frame(width: geometry.notchCoreWidth)
                right()
                    .frame(width: geometry.rightRegionWidth, alignment: .trailing)
            }
        } else {
            HStack(spacing: 10) {
                left()
                Spacer(minLength: 0)
                right()
            }
        }
    }
}


enum LiveActivitySidecarMetrics {
    static let diameter: CGFloat = 30
    static let gap: CGFloat = 7
}

struct RadialActivityProgressView<Content: View>: View {
    let progress: Double
    let content: Content

    init(
        progress: Double,
        @ViewBuilder content: () -> Content
    ) {
        self.progress = min(max(progress, 0), 1)
        self.content = content()
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 1.6)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    .white.opacity(0.88),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            content
        }
        .animation(.easeInOut(duration: 0.18), value: progress)
    }
}

struct CircleSidecarView: View {
    let symbolName: String
    let accessibilityLabel: String

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.98))
            Circle().stroke(.white.opacity(0.12), lineWidth: 1)
            SafeSystemImage(symbolName: symbolName, fallbackSymbolName: "circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ProgressCircleSidecarView: View {
    let activity: DynamicIslandLiveActivity

    var body: some View {
        RadialActivityProgressView(progress: progress) {
            if activity.kind == .timer {
                Image(systemName: activity.isActive ? "timer" : "pause.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(activity.isActive ? .orange : .white.opacity(0.86))
            } else {
                SafeSystemImage(
                    symbolName: activity.symbolName,
                    fallbackSymbolName: "circle.fill"
                )
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(sidecarAccent)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.98), in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }

    private var progress: Double {
        LiveActivityStore.clampedProgress(activity.progress) ?? 0
    }

    private var sidecarAccent: Color {
        switch activity.kind {
        case .battery:
            switch activity.batteryState {
            case .low: .orange
            case .charging, .pluggedIn: .green
            case .full, .none: .white.opacity(0.86)
            }
        default:
            .white.opacity(0.86)
        }
    }

    private var accessibilityLabel: String {
        [activity.title, activity.subtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

struct CompactCapsuleSidecarView: View {
    let activity: DynamicIslandLiveActivity

    var body: some View {
        HStack(spacing: 3) {
            SafeSystemImage(
                symbolName: activity.symbolName,
                fallbackSymbolName: "circle.fill"
            )
            .font(.system(size: 8, weight: .bold))

            if let subtitle = activity.subtitle {
                Text(subtitle)
                    .font(.system(size: 6.8, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.98), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.11), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [activity.title, activity.subtitle]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }
}

struct LiveActivitySidecarLayer: View {
    let resolution: LiveActivityLayoutResolution
    let compositeGeometry: LiveActivityCompositeGeometry
    let canvasHeight: CGFloat
    let reduceMotion: Bool
    let onActivate: (LiveActivityPresentation) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let leading = resolution.leadingSidecar,
               let frame = compositeGeometry.leadingSidecarFrame {
                sidecarButton(leading)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: canvasHeight - frame.midY)
                    .transition(sidecarTransition)
            }

            if let trailing = resolution.trailingSidecar,
               let frame = compositeGeometry.trailingSidecarFrame {
                sidecarButton(trailing)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: canvasHeight - frame.midY)
                    .transition(sidecarTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func sidecarButton(_ presentation: LiveActivityPresentation) -> some View {
        Button {
            onActivate(presentation)
        } label: {
            sidecarView(presentation)
        }
        .buttonStyle(.plain)
        .help(sidecarHelp(presentation.activity))
        .accessibilityLabel(sidecarHelp(presentation.activity))
    }

    @ViewBuilder
    private func sidecarView(_ presentation: LiveActivityPresentation) -> some View {
        switch presentation.descriptor.compactShape {
        case .circle:
            if presentation.activity.progress != nil {
                ProgressCircleSidecarView(activity: presentation.activity)
            } else {
                CircleSidecarView(
                    symbolName: presentation.activity.symbolName,
                    accessibilityLabel: sidecarHelp(presentation.activity)
                )
            }
        case .capsule, .progressPill:
            CompactCapsuleSidecarView(activity: presentation.activity)
        case .notchWing, .elongatedPill:
            CircleSidecarView(
                symbolName: presentation.activity.symbolName,
                accessibilityLabel: sidecarHelp(presentation.activity)
            )
        }
    }

    private var sidecarTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .scale(scale: 0.82))
    }

    private func sidecarHelp(_ activity: DynamicIslandLiveActivity) -> String {
        [activity.title, activity.subtitle]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct CollapsedGenericActivityCompactView: View {
    let activity: DynamicIslandLiveActivity
    let layout: CompactCollapsedSideSlotGeometry

    var body: some View {
        CompactCollapsedSideSlotLayout(geometry: layout) {
            SafeSystemImage(symbolName: activity.symbolName, fallbackSymbolName: "circle.fill")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(
                    width: CollapsedActivityLayoutProfile.genericActivityLeftContentWidth,
                    height: CollapsedActivityLayoutProfile.genericActivityLeftContentWidth
                )
        } right: {
            Text(activity.subtitle ?? activity.title)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(
                    width: CollapsedActivityLayoutProfile.genericActivityRightContentWidth,
                    alignment: .trailing
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [activity.title, activity.subtitle]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }
}

struct CollapsedSystemHUDCompactView: View {
    let activity: DynamicIslandLiveActivity
    let layout: CompactCollapsedSideSlotGeometry
    var controller: SystemHUDController? = nil

    @Environment(\.islandDisplayMetrics) private var displayMetrics
    @State private var confirmedProgress: Double = 0
    @State private var interactionSupported: Bool? = nil
    @State private var lastWriteUptime: TimeInterval = 0

    var body: some View {
        VStack(spacing: 0) {
            CompactCollapsedSideSlotLayout(geometry: layout) {
                SafeSystemImage(symbolName: activity.symbolName, fallbackSymbolName: "slider.horizontal.3")
                    .font(.system(size: displayMetrics.icon(11), weight: .bold))
                    .foregroundStyle(accentColor.opacity(0.96))
                    .frame(
                        width: max(CollapsedActivityLayoutProfile.systemHUDLeftContentWidth * displayMetrics.collapsedSideContentScale, 16),
                        height: max(CollapsedActivityLayoutProfile.systemHUDLeftContentWidth * displayMetrics.collapsedSideContentScale, 16)
                    )
                    .contentTransition(.symbolEffect(.replace.byLayer))
            } right: {
                if sliderKind != nil {
                    Text(SystemHUDFormatting.percentage(confirmedProgress))
                        .font(.system(size: displayMetrics.font(8.2, minimum: 7.4, maximum: 10), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accentColor.opacity(0.96))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 30 * displayMetrics.compactControlScale, alignment: .trailing)
                } else {
                    Text(activity.subtitle ?? activity.title)
                        .font(.system(size: displayMetrics.font(7.4, minimum: 7.2, maximum: 9.4), weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(
                            width: CollapsedActivityLayoutProfile.systemHUDRightContentWidth * displayMetrics.collapsedSideContentScale,
                            alignment: .trailing
                        )
                }
            }
            // Row band: the physical top band (notch height or collapsed
            // height), so the icon and percentage stay beside the notch.
            .frame(maxHeight: .infinity)

            if sliderKind != nil {
                // Slider band hanging below the top band. The shell's bottom
                // padding is part of the band, so the slider is centered
                // between the notch edge and the shell's bottom edge.
                let sliderHeight = displayMetrics.hudSliderHeight
                let band = CollapsedPresentationProfile.systemHUDSliderBandHeight
                SystemHUDCompactSlider(
                    value: confirmedProgress,
                    accent: accentColor,
                    isEnabled: interactionSupported == true,
                    height: sliderHeight,
                    trackTopInset: max((band - sliderHeight) / 2, 0),
                    hitHeight: band - IslandShellLayout.collapsedBottomPadding,
                    onChange: { requested, force in
                        writeInteractiveValue(requested, force: force)
                    }
                )
                .padding(.horizontal, max(8 * displayMetrics.spacingScale, 7))
                .help(interactionSupported == false ? unsupportedHelp : "Adjust \(activity.title)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            [activity.title, activity.subtitle].compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityValue(sliderKind == nil ? (activity.subtitle ?? "") : SystemHUDFormatting.percentage(confirmedProgress))
        .onAppear(perform: synchronizeFromAuthority)
        .onChange(of: activity.progress) { _, _ in synchronizeFromActivity() }
        .onChange(of: activity.systemHUDKind) { _, _ in synchronizeFromAuthority() }
    }

    private var sliderKind: SystemHUDKind? {
        guard activity.progress != nil else { return nil }
        switch resolvedKind {
        case .volume, .brightness:
            return resolvedKind
        case .capsLock, .battery, .audioDevice, .focus, nil:
            return nil
        }
    }

    private var resolvedKind: SystemHUDKind? {
        if let exact = activity.systemHUDKind { return exact }
        switch activity.title.lowercased() {
        case let title where title.contains("volume") || title.contains("muted"):
            return .volume
        case let title where title.contains("brightness"):
            return .brightness
        default:
            return nil
        }
    }

    private var accentComponents: SystemHUDAccentComponents {
        SystemHUDAccentComponents.resolve(
            kind: resolvedKind ?? .volume,
            value: confirmedProgress,
            isMuted: resolvedKind == .volume && confirmedProgress <= 0.0001
        )
    }

    private var accentColor: Color {
        Color(
            red: accentComponents.red,
            green: accentComponents.green,
            blue: accentComponents.blue,
            opacity: accentComponents.opacity
        )
    }

    private var unsupportedHelp: String {
        resolvedKind == .brightness
            ? "Brightness control is unavailable for this display"
            : "Volume control is unavailable for this output device"
    }

    private func synchronizeFromActivity() {
        guard let progress = activity.progress else { return }
        confirmedProgress = min(max(progress, 0), 1)
    }

    private func synchronizeFromAuthority() {
        synchronizeFromActivity()
        guard let controller, let kind = sliderKind else {
            interactionSupported = controller == nil ? nil : false
            return
        }
        if let snapshot = controller.currentInteractiveSnapshot(kind: kind) {
            confirmedProgress = min(max(snapshot.value, 0), 1)
            interactionSupported = true
        } else {
            interactionSupported = false
        }
    }

    private func writeInteractiveValue(_ requested: Double, force: Bool) {
        guard let controller, let kind = sliderKind, interactionSupported == true else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastWriteUptime >= (1.0 / 30.0) else { return }
        lastWriteUptime = now
        guard let snapshot = controller.setInteractiveValue(kind: kind, value: requested) else {
            interactionSupported = false
            synchronizeFromActivity()
            return
        }
        confirmedProgress = min(max(snapshot.value, 0), 1)
    }
}

/// The production collapsed HUD shell (IslandSurface, shape, bottom glow and
/// CollapsedSystemHUDCompactView) at the geometry NotchGeometryService
/// resolves for a reference notched display. Settings previews use this so
/// they can never drift from the island's own HUD geometry.
struct SystemHUDShellPreview: View {
    @ObservedObject var settings: AppSettings
    let activity: DynamicIslandLiveActivity

    /// 14-inch-class notched display (1512×982 pt, 32 pt safe-area top).
    static let referenceScreen: ScreenSnapshot = {
        let size = CGSize(width: 1512, height: 982)
        let notchHeight: CGFloat = 32
        return ScreenSnapshot(
            frame: CGRect(origin: .zero, size: size),
            visibleFrame: CGRect(x: 0, y: 0, width: size.width, height: size.height - notchHeight),
            safeAreaInsets: NSEdgeInsets(top: notchHeight, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: size.height - notchHeight, width: (size.width - 180) / 2, height: notchHeight),
            auxiliaryTopRightArea: CGRect(x: (size.width + 180) / 2, y: size.height - notchHeight, width: (size.width - 180) / 2, height: notchHeight)
        )
    }()

    static func geometry(settings: AppSettings, activity: DynamicIslandLiveActivity) -> IslandGeometry {
        let isInteractive = activity.systemHUDKind == .volume || activity.systemHUDKind == .brightness
        return NotchGeometryService().geometry(
            for: referenceScreen,
            collapsedSize: settings.collapsedSize,
            expandedSize: settings.expandedSize,
            collapsedActivityProfile: .systemHUD,
            collapsedPresentationProfile: isInteractive ? .systemHUD(value: activity.progress ?? 0) : .normal,
            useAdaptiveNotchSizing: true,
            respectHardwareNotch: true
        )
    }

    var body: some View {
        let geometry = Self.geometry(settings: settings, activity: activity)
        let isInteractive = geometry.collapsedPresentationProfile.kind == .systemHUD
        IslandSurface(
            settings: settings,
            isExpanded: false,
            visualProgress: 0,
            collapsedPresentationProfile: geometry.collapsedPresentationProfile,
            systemHUDActivity: isInteractive ? activity : nil
        ) {
            CollapsedSystemHUDCompactView(
                activity: activity,
                layout: CompactCollapsedSideSlotGeometry(
                    isNotchIntegrated: true,
                    leftRegionWidth: geometry.collapsedLeftRegionWidth,
                    notchCoreWidth: geometry.collapsedNotchCoreWidth,
                    rightRegionWidth: geometry.collapsedRightRegionWidth
                )
            )
        }
        .notchIntegrated(true)
        .frame(width: geometry.collapsedFrame.width, height: geometry.collapsedFrame.height)
    }
}

private struct SystemHUDCompactSlider: View {
    let value: Double
    let accent: Color
    let isEnabled: Bool
    let height: CGFloat
    /// Distance from the top of the hit area to the visual track.
    var trackTopInset: CGFloat = 0
    /// Interactive height; the drag target spans the whole slider band
    /// instead of only the thin visual track.
    var hitHeight: CGFloat? = nil
    let onChange: (_ value: Double, _ force: Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(isEnabled ? 0.13 : 0.07))
                    Capsule(style: .continuous)
                        .fill(accent)
                        .frame(width: width * CGFloat(min(max(value, 0), 1)))
                }
                .frame(height: height)
                .padding(.top, trackTopInset)
            }
            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        onChange(min(max(gesture.location.x / width, 0), 1), false)
                    }
                    .onEnded { gesture in
                        guard isEnabled else { return }
                        onChange(min(max(gesture.location.x / width, 0), 1), true)
                    }
            )
        }
        .frame(height: max(hitHeight ?? height, height + trackTopInset))
        .opacity(isEnabled ? 1 : 0.48)
        .animation(.smooth(duration: 0.10), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System level")
        .accessibilityValue(SystemHUDFormatting.percentage(value))
    }
}

private struct CollapsedTimerActivityCompactView: View {
    let activity: DynamicIslandLiveActivity
    let layout: CompactCollapsedSideSlotGeometry

    var body: some View {
        CompactCollapsedSideSlotLayout(geometry: layout) {
            timerIcon
                .frame(
                    width: CollapsedActivityLayoutProfile.timerLeftContentWidth,
                    height: CollapsedActivityLayoutProfile.timerLeftContentWidth
                )
        } right: {
            Text(formattedCompactRemainingTime)
                .monospacedDigit()
                .font(.system(size: 8.8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .allowsTightening(true)
                .frame(
                    width: CollapsedActivityLayoutProfile.timerRightContentWidth,
                    alignment: .trailing
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .clipped()
        .accessibilityLabel(accessibilityLabel)
    }

    private var timerIcon: some View {
        ZStack(alignment: .center) {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)

            Image(systemName: activity.isActive ? "timer" : "pause.fill")
                .font(.system(size: activity.isActive ? 6.5 : 6, weight: .bold))
                .foregroundStyle(activity.isActive ? .orange : .white.opacity(0.82))
        }
    }

    private var formattedCompactRemainingTime: String {
        let text = activity.subtitle ?? activity.title
        return text
            .replacingOccurrences(of: "Paused • ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var accessibilityLabel: String {
        [activity.title, activity.subtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct CollapsedFileActivityCompactView: View {
    let activity: DynamicIslandLiveActivity
    let layout: CompactCollapsedSideSlotGeometry

    var body: some View {
        CompactCollapsedSideSlotLayout(geometry: layout) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 12, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.cyan.opacity(0.90))
                .frame(
                    width: CollapsedActivityLayoutProfile.fileLeftContentWidth,
                    height: CollapsedActivityLayoutProfile.fileLeftContentWidth
                )
        } right: {
            Text(fileText)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(
                    width: CollapsedActivityLayoutProfile.fileRightContentWidth,
                    alignment: .trailing
                )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel(accessibilityLabel)
    }

    private var fileText: String {
        let text = activity.subtitle ?? activity.title
        return text
            .replacingOccurrences(of: " in Tray", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var accessibilityLabel: String {
        [activity.title, activity.subtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct CollapsedBatteryActivityCompactView: View {
    let activity: DynamicIslandLiveActivity
    let layout: CompactCollapsedSideSlotGeometry

    var body: some View {
        CompactCollapsedSideSlotLayout(geometry: layout) {
            SafeSystemImage(symbolName: activity.symbolName, fallbackSymbolName: "battery.75percent")
                .font(.system(size: 12, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(
                    width: CollapsedActivityLayoutProfile.batteryLeftContentWidth,
                    height: CollapsedActivityLayoutProfile.batteryLeftContentWidth
                )
        } right: {
            Text(percentText)
                .font(.system(size: 8.8, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .allowsTightening(true)
                .frame(
                    width: CollapsedActivityLayoutProfile.batteryRightContentWidth,
                    alignment: .trailing
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityLabel(accessibilityLabel)
    }

    private var percentText: String {
        guard let progress = LiveActivityStore.clampedProgress(activity.progress) else { return "--%" }
        return "\(Int((progress * 100).rounded()))%"
    }

    private var iconColor: Color {
        switch activity.batteryState {
        case .low:
            return .orange.opacity(0.92)
        case .charging, .pluggedIn:
            return .green.opacity(0.86)
        case .full:
            return .white.opacity(0.76)
        case nil:
            return .white.opacity(0.68)
        }
    }

    private var accessibilityLabel: String {
        [activity.title, activity.subtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

struct CollapsedPreviewRow: View {
    let content: CollapsedPreviewContent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(content.rows.prefix(3)) { row in
                CollapsedPreviewActivityRow(row: row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.bottom, 3)
    }
}

private struct CollapsedPreviewActivityRow: View {
    let row: CollapsedPreviewRowContent

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            SafeSystemImage(symbolName: row.symbolName, fallbackSymbolName: row.fallbackSymbolName)
                .font(.system(size: row.isPrimary ? 10 : 9, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 13, height: 13)

            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(.system(size: row.isPrimary ? 10 : 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(row.isPrimary ? 0.90 : 0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            if let trailingText = row.trailingText {
                Text(trailingText)
                    .monospacedDigit()
                    .font(.system(size: row.isPrimary ? 10 : 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(row.isPrimary ? 0.86 : 0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .frame(minWidth: 42, alignment: .trailing)
            }
        }
        .frame(height: row.subtitle == nil ? 15 : 18)
    }

    private var iconColor: Color {
        switch row.kind {
        case .timer:
            .orange.opacity(row.isPrimary ? 0.90 : 0.68)
        case .fileDrop:
            .cyan.opacity(row.isPrimary ? 0.86 : 0.62)
        case .media:
            .white.opacity(row.isPrimary ? 0.72 : 0.54)
        case .battery:
            .green.opacity(row.isPrimary ? 0.84 : 0.62)
        case .none, .liveActivity:
            .white.opacity(row.isPrimary ? 0.68 : 0.48)
        }
    }
}

private struct CollapsedPreviewLabel: View {
    let text: String
    let symbolName: String
    let fallbackSymbolName: String

    var body: some View {
        HStack(spacing: 4) {
            SafeSystemImage(symbolName: symbolName, fallbackSymbolName: fallbackSymbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 11, height: 11)

            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 0)
    }
}

private struct SafeSystemImage: View {
    let symbolName: String
    let fallbackSymbolName: String

    var body: some View {
        Image(systemName: resolvedSymbolName)
    }

    private var resolvedSymbolName: String {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) == nil
            ? fallbackSymbolName
            : symbolName
    }
}

struct ExpandedIslandView: View {
    @ObservedObject var settings: AppSettings
    let modules: IslandModules
    let contentVisible: Bool
    let shouldRenderContent: Bool
    let isContentRemoving: Bool
    let onShortcutLaunched: () -> Void
    let onTimerStarted: () -> Void
    let rendersExpandedVisualContent: Bool
    let onOpenSettings: () -> Void
    @ObservedObject var layoutStore: IslandLayoutStore
    @ObservedObject var escapeRouter: IslandEscapeRouter
    @ObservedObject var islandGestureCoordinator: IslandGestureCoordinator
    let islandGestureContext: IslandGestureContext
    let islandGestureCallbacks: IslandGestureCallbacks
    let islandSwipeSensitivity: Double
    @ObservedObject private var navigation: IslandNavigationStore
    @ObservedObject private var liveActivities: LiveActivityStore
    @ObservedObject private var agentEvents: AgentEventStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isCollapseShellOnly) private var isCollapseShellOnly
    @Environment(\.isNotchIntegratedShell) private var isNotchIntegratedShell

    @State private var isAirDropTargeted = false
    @State private var isFilesTargeted = false
    @State private var clipboardPresentation = ClipboardHistoryPresentationState()
    @State private var pagePresentation: ExpandedPageTransitionState

    init(
        settings: AppSettings,
        modules: IslandModules,
        contentVisible: Bool,
        shouldRenderContent: Bool,
        isContentRemoving: Bool,
        onShortcutLaunched: @escaping () -> Void,
        onTimerStarted: @escaping () -> Void,
        rendersExpandedVisualContent: Bool = true,
        onOpenSettings: @escaping () -> Void = {},
        layoutStore: IslandLayoutStore,
        escapeRouter: IslandEscapeRouter,
        islandGestureCoordinator: IslandGestureCoordinator,
        islandGestureContext: IslandGestureContext,
        islandGestureCallbacks: IslandGestureCallbacks,
        islandSwipeSensitivity: Double
    ) {
        self.settings = settings
        self.modules = modules
        self.contentVisible = contentVisible
        self.shouldRenderContent = shouldRenderContent
        self.isContentRemoving = isContentRemoving
        self.onShortcutLaunched = onShortcutLaunched
        self.onTimerStarted = onTimerStarted
        self.rendersExpandedVisualContent = rendersExpandedVisualContent
        self.onOpenSettings = onOpenSettings
        self.layoutStore = layoutStore
        self.escapeRouter = escapeRouter
        self.islandGestureCoordinator = islandGestureCoordinator
        self.islandGestureContext = islandGestureContext
        self.islandGestureCallbacks = islandGestureCallbacks
        self.islandSwipeSensitivity = islandSwipeSensitivity
        navigation = modules.navigation
        liveActivities = modules.liveActivities
        agentEvents = modules.agentEvents
        _pagePresentation = State(initialValue: ExpandedPageTransitionState(page: modules.navigation.selectedPage))
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = ExpandedIslandLayoutMetrics(
                containerSize: proxy.size,
                horizontalPadding: IslandShellLayout.expandedHorizontalPadding(
                    isNotchIntegrated: isNotchIntegratedShell
                ),
                displayMetrics: layoutStore.displayMetrics
            )

            ZStack(alignment: .topLeading) {
                expandedBaseLayer(metrics: metrics)
                    .modifier(
                        IslandPointerGestureModifier(
                            settings: settings,
                            coordinator: islandGestureCoordinator,
                            context: islandGestureContext,
                            callbacks: islandGestureCallbacks,
                            swipeSensitivity: islandSwipeSensitivity
                        )
                    )

                if clipboardPresentation.isMounted {
                    clipboardHistoryOverlay(metrics: metrics)
                        .frame(width: metrics.innerWidth, height: metrics.pageHeight)
                        .offset(
                            x: metrics.horizontalPadding,
                            y: metrics.topPadding
                                + metrics.tabSwitcherHeight
                                + metrics.tabToPageSpacing
                        )
                        .allowsHitTesting(clipboardPresentation.isMounted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            synchronizeExpandedScrollSuppression()
            synchronizeClipboardEscapeRegistration()
            synchronizeStatsPolling()
        }
        .onChange(of: navigation.selectedPage) { _, page in
            handleSelectedPageChange(page)
            closeClipboardHistoryImmediately()
            synchronizeExpandedScrollSuppression()
            synchronizeStatsPolling()
        }
        .onChange(of: contentVisible) { _, isVisible in
            if !isVisible {
                closeClipboardHistoryImmediately()
            }
            // Expansion/collapse owns content visibility; never leave a tab
            // handoff pending across it.
            pagePresentation.snap(to: navigation.selectedPage)
            synchronizeStatsPolling()
        }
        .onChange(of: shouldRenderContent) { _, shouldRender in
            if !shouldRender {
                closeClipboardHistoryImmediately()
                pagePresentation.snap(to: navigation.selectedPage)
            }
            synchronizeStatsPolling()
        }
        .onChange(of: isCollapseShellOnly) { _, collapseOnly in
            if collapseOnly {
                closeClipboardHistoryImmediately()
                pagePresentation.snap(to: navigation.selectedPage)
            }
            synchronizeStatsPolling()
        }
        .onDisappear {
            closeClipboardHistoryImmediately()
            escapeRouter.setTopmostPresentation(nil)
            layoutStore.setExpandedScrollGestureSuppressed(false)
            modules.stats.stopPolling()
        }
        .onChange(of: settings.clipboardHistoryEnabled) { _, enabled in
            if !enabled {
                closeClipboardHistoryImmediately()
            }
        }
        .onChange(of: escapeRouter.dismissalRequestGeneration) { _, _ in
            guard clipboardPresentation.isMounted || clipboardPresentation.isRequested else {
                return
            }
            closeClipboardHistoryAnimated()
        }
        .onExitCommand {
            closeClipboardHistoryAnimated()
        }
    }

    private func expandedBaseLayer(metrics: ExpandedIslandLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.tabToPageSpacing) {
            HStack(alignment: .center, spacing: 8) {
                ZStack(alignment: .leading) {
                    if rendersExpandedVisualContent && shouldRenderContent && !isCollapseShellOnly {
                        ExpandedIslandPageSwitcher(settings: settings, navigation: navigation)
                            .innerBlurScaleClean(
                                settings: settings,
                                isVisible: contentVisible,
                                isRemoval: isContentRemoving,
                                index: 0,
                                reduceMotion: reduceMotion
                            )
                    }
                }
                .frame(height: metrics.tabSwitcherHeight)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    if rendersExpandedVisualContent && shouldRenderContent && !isCollapseShellOnly {
                        if settings.clipboardHistoryEnabled {
                            ExpandedHeaderButton(
                                systemImage: "clipboard",
                                help: "Clipboard History",
                                accessibilityLabel: "Open Clipboard History"
                            ) {
                                toggleClipboardHistory()
                            }
                        }
                        SettingsGearButton {
                            closeClipboardHistoryAnimated()
                            onOpenSettings()
                        }
                    }
                }
                .innerBlurScaleClean(
                    settings: settings,
                    isVisible: contentVisible,
                    isRemoval: isContentRemoving,
                    index: 0,
                    reduceMotion: reduceMotion
                )
                .frame(height: metrics.tabSwitcherHeight)
            }
            .frame(height: metrics.tabSwitcherHeight)

            // Top-centered: pages are laid out at the target metrics while the
            // shell still morphs around its horizontal center, so an incoming
            // page overflows (or insets) symmetrically instead of detaching
            // toward the leading edge. Identical once the morph settles.
            ZStack(alignment: .top) {
                if !rendersExpandedVisualContent || !shouldRenderContent {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if let page = pagePresentation.mountedPage {
                        pageView(page, metrics: metrics)
                            .expandedPageMotion(
                                pageMotionPlan,
                                animatesEntrance: pagePresentation.animatesEntrance,
                                mountID: ExpandedPageMountID(page: page, generation: pagePresentation.mountGeneration)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: metrics.pageHeight, alignment: .top)
            .clipped()
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func pageView(_ page: ExpandedIslandPage, metrics: ExpandedIslandLayoutMetrics) -> some View {
        switch page {
        case .island:
            islandPage(metrics: metrics)
        case .agents:
            agentActivityPage(metrics: metrics)
        case .tray:
            trayPage(metrics: metrics)
        case .timer:
            timerPage(metrics: metrics)
        case .stats:
            statsPage(metrics: metrics)
        case .tools:
            toolsPage(metrics: metrics)
        case .messages:
            messagesPage(metrics: metrics)
        }
    }

    private var pageMotionPlan: ExpandedIslandMotion.Plan {
        ExpandedIslandMotion.plan(settings: settings, reduceMotion: reduceMotion)
    }

    /// Routes a committed page selection through the shared choreography:
    /// the outgoing page leaves now, the incoming page mounts on handoff.
    private func handleSelectedPageChange(_ page: ExpandedIslandPage) {
        guard rendersExpandedVisualContent, shouldRenderContent, contentVisible, !isCollapseShellOnly else {
            pagePresentation.snap(to: page)
            return
        }
        var presentation = pagePresentation
        let plan = pageMotionPlan
        // Toward a smaller shell the outgoing page leaves first, the shell
        // contracts, and only then does the incoming page mount.
        let shrinks = ExpandedIslandMotion.pageChangeShrinksShell(
            from: presentation.targetPage,
            to: page,
            expandedSize: settings.expandedSize
        )
        let effect = presentation.select(
            page,
            plan: plan,
            handoffDelay: shrinks ? ExpandedIslandMotion.shrinkingPagePlan(plan).incomingHandoffDelay : nil
        )
        pagePresentation = presentation
        guard case let .scheduleHandoff(generation, delay) = effect else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            var presentation = pagePresentation
            guard presentation.completeHandoff(generation: generation) else { return }
            pagePresentation = presentation
        }
    }

    private var contentVisibilityAnimation: Animation {
        guard settings.contentAnimationEnabled else {
            return .linear(duration: 0.01)
        }

        let shellDuration = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: reduceMotion
        )
        if contentVisible {
            let duration = IslandContentTransitionTiming.expansionContentDuration(shellDuration: shellDuration)
            return .easeOut(duration: reduceMotion ? 0.10 : duration)
        }

        let duration = IslandContentTransitionTiming.collapseContentDuration(shellDuration: shellDuration)
        return .easeIn(duration: reduceMotion ? 0.10 : duration)
    }

    private func openClipboardHistory() {
        let sessionGeneration = layoutStore.overlayPresentationGeneration
        guard settings.overlayEnabled, settings.clipboardHistoryEnabled else { return }
        var presentation = clipboardPresentation
        let generation = presentation.open()
        updateClipboardPresentation(presentation)

        let shellDuration = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: reduceMotion
        )
        let revealDelay = reduceMotion
            || settings.reduceExtraMotion
            || !settings.contentAnimationEnabled
            || settings.animationPreset == .instant
            ? 0
            : IslandContentTransitionTiming.expansionContentDelay(shellDuration: shellDuration)

        DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) {
            guard settings.overlayEnabled, sessionGeneration == layoutStore.overlayPresentationGeneration else { return }
            guard settings.clipboardHistoryEnabled,
                  contentVisible,
                  shouldRenderContent,
                  !isCollapseShellOnly else {
                return
            }
            var presentation = clipboardPresentation
            guard presentation.reveal(generation: generation) else { return }
            updateClipboardPresentation(presentation)
        }
    }

    private func closeClipboardHistoryAnimated() {
        let sessionGeneration = layoutStore.overlayPresentationGeneration
        var presentation = clipboardPresentation
        guard let generation = presentation.beginAnimatedClose() else { return }
        updateClipboardPresentation(presentation)

        let shellDuration = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: reduceMotion
        )
        let exitDuration = reduceMotion
            || settings.reduceExtraMotion
            || !settings.contentAnimationEnabled
            || settings.animationPreset == .instant
            ? 0.01
            : IslandContentTransitionTiming.collapseContentDuration(shellDuration: shellDuration)

        DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration + 0.025) {
            guard settings.overlayEnabled, sessionGeneration == layoutStore.overlayPresentationGeneration else { return }
            var presentation = clipboardPresentation
            guard presentation.completeAnimatedClose(generation: generation) else { return }
            updateClipboardPresentation(presentation)
        }
    }

    private func closeClipboardHistoryImmediately() {
        var presentation = clipboardPresentation
        presentation.closeImmediately()
        updateClipboardPresentation(presentation)
        escapeRouter.setTopmostPresentation(nil)
    }

    private func updateClipboardPresentation(_ presentation: ClipboardHistoryPresentationState) {
        clipboardPresentation = presentation
        synchronizeExpandedScrollSuppression()
        synchronizeClipboardEscapeRegistration()
    }

    private func synchronizeExpandedScrollSuppression() {
        layoutStore.setExpandedScrollGestureSuppressed(clipboardPresentation.isMounted)
        if navigation.selectedPage != .agents {
            layoutStore.setExpandedContentScrollRegion(.zero)
        }
    }

    private func synchronizeClipboardEscapeRegistration() {
        escapeRouter.setTopmostPresentation(
            clipboardPresentation.topmostOverlayPresentation
        )
    }

    private func toggleClipboardHistory() {
        if clipboardPresentation.isRequested {
            closeClipboardHistoryAnimated()
        } else {
            openClipboardHistory()
        }
    }

    private func clipboardHistoryOverlay(metrics: ExpandedIslandLayoutMetrics) -> some View {
        let availableWidth = max(0, metrics.innerWidth)
        let preferredWidth = metrics.innerWidth * 0.46
        let cardWidth = min(max(preferredWidth, 320), min(410, availableWidth))

        return ZStack(alignment: .topTrailing) {
            Color.black
                .opacity(clipboardPresentation.isVisible ? 0.34 : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard clipboardPresentation.isRequested else { return }
                    closeClipboardHistoryAnimated()
                }
                .accessibilityLabel("Close Clipboard History")
                .animation(clipboardBackdropAnimation, value: clipboardPresentation.isVisible)
                .allowsHitTesting(clipboardPresentation.isMounted)

            ClipboardHistoryView(
                store: modules.clipboardHistory,
                onClose: {
                    closeClipboardHistoryAnimated()
                },
                externalActions: ClipboardHistoryExternalActions(
                    addFilesToShelf: { urls in modules.fileShelf.add(urls) },
                    addFilesToBasket: { urls in modules.basketPresenter.addClipboardFilesToBasket(urls) }
                )
            )
            .frame(width: cardWidth, height: metrics.pageHeight)
            .innerBlurScaleClean(
                settings: settings,
                isVisible: clipboardPresentation.isVisible,
                isRemoval: clipboardPresentation.isRemoving,
                index: 0,
                reduceMotion: reduceMotion
            )
            .allowsHitTesting(
                clipboardPresentation.isRequested && clipboardPresentation.isVisible
            )
        }
        .frame(maxWidth: .infinity, maxHeight: metrics.pageHeight)
        .allowsHitTesting(clipboardPresentation.isMounted)
    }

    private var clipboardBackdropAnimation: Animation {
        guard settings.contentAnimationEnabled else {
            return .linear(duration: 0.01)
        }
        let shellDuration = IslandContentTransitionTiming.shellDuration(
            settings: settings,
            reduceMotion: reduceMotion
        )
        if clipboardPresentation.isVisible {
            return .easeOut(
                duration: reduceMotion
                    ? 0.10
                    : IslandContentTransitionTiming.expansionContentDuration(
                        shellDuration: shellDuration
                    )
            )
        }
        return .easeIn(
            duration: reduceMotion
                ? 0.10
                : IslandContentTransitionTiming.collapseContentDuration(
                    shellDuration: shellDuration
                )
        )
    }

    private func synchronizeStatsPolling() {
        let shouldPoll = settings.overlayEnabled && rendersExpandedVisualContent &&
            shouldRenderContent &&
            contentVisible &&
            !isCollapseShellOnly &&
            navigation.selectedPage == .stats
        if shouldPoll {
            modules.stats.startPolling()
        } else {
            modules.stats.stopPolling()
        }
    }

    private func islandPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        let visibility = ExpandedIslandRightStackVisibility.resolve(
            liveActivitiesEnabled: settings.liveActivitiesEnabled,
            showExpandedLiveActivitiesSection: settings.showExpandedLiveActivitiesSection,
            shortcutsEnabled: settings.shortcutsEnabled
        )
        let showsRightStack = visibility.showsRightStack
            || modules.rightWorkspace.configuration.visiblePages.contains { $0 != .overview }

        return HStack(spacing: metrics.pageColumnSpacing) {
            if settings.mediaEnabled {
                MediaModuleView(
                    settings: settings,
                    media: modules.media,
                    availableHeight: metrics.mediaMaxHeight,
                    onLauncherActivated: {
                        if settings.collapseAfterMediaLauncher {
                            onShortcutLaunched()
                        }
                    },
                    onMediaSourceOpened: {
                        if settings.collapseAfterOpeningMediaSource {
                            onShortcutLaunched()
                        }
                    }
                )
                    .frame(width: showsRightStack ? metrics.mediaColumnWidth : nil, height: metrics.mediaMaxHeight, alignment: .topLeading)
                    .clipped()
                    .innerBlurScaleClean(
                        settings: settings,
                        isVisible: contentVisible,
                        isRemoval: isContentRemoving,
                        index: 1,
                        reduceMotion: reduceMotion
                    )
            }

            if settings.mediaEnabled && showsRightStack {
                Divider()
                    .frame(height: metrics.dividerHeight)
                    .overlay(.white.opacity(0.10))
                    .opacity(contentVisible ? 1 : 0)
                    .animation(contentVisibilityAnimation, value: contentVisible)
            }

            if showsRightStack {
                // The page indicator's band comes out of the overview stack
                // proportionally so no card is covered.
                let indicatorBand = RightWorkspaceView<EmptyView, EmptyView, EmptyView>
                    .showsIndicator(modules.rightWorkspace.configuration)
                    ? RightWorkspaceView<EmptyView, EmptyView, EmptyView>.indicatorBand
                    : 0
                let overviewScale = metrics.pageHeight > 0
                    ? max(metrics.pageHeight - indicatorBand, 0) / metrics.pageHeight
                    : 1
                let liveActivitiesHeight = (visibility.showsShortcuts
                    ? metrics.liveActivitiesStackHeight
                    : metrics.pageHeight) * overviewScale
                let shortcutsHeight = (visibility.showsLiveActivities
                    ? metrics.shortcutsStackHeight
                    : metrics.pageHeight) * overviewScale

                RightWorkspaceView(
                    store: modules.rightWorkspace,
                    layoutStore: layoutStore,
                    reduceMotion: reduceMotion || settings.reduceExtraMotion,
                    overview: {
                        if visibility.showsRightStack {
                            VStack(spacing: metrics.rightStackSpacing) {
                                if visibility.showsLiveActivities {
                                    LiveActivitiesModuleView(
                                        liveActivities: liveActivities,
                                        navigation: navigation,
                                        rightWorkspace: modules.rightWorkspace,
                                        settings: settings,
                                        availableHeight: liveActivitiesHeight,
                                        compactScale: metrics.compactScale
                                    )
                                    .frame(height: liveActivitiesHeight, alignment: .topLeading)
                                }

                                if visibility.showsShortcuts {
                                    ShortcutsModuleView(
                                        shortcuts: modules.shortcuts,
                                        availableHeight: shortcutsHeight,
                                        compactScale: metrics.compactScale,
                                        onShortcutLaunched: onShortcutLaunched
                                    )
                                    .frame(height: shortcutsHeight, alignment: .topLeading)
                                }
                            }
                        } else {
                            Text("Live Activities and Shortcuts are turned off")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    },
                    productivity: {
                        ProductivityDeckView(
                            productivity: modules.productivity,
                            fileShelf: modules.fileShelf,
                            tools: modules.rightWorkspace.configuration.visibleTools,
                            reduceMotion: reduceMotion || settings.reduceExtraMotion,
                            layoutStore: layoutStore
                        )
                    },
                    appsMedia: {
                        AppsMediaDeckView(
                            services: modules.workspaceServices,
                            media: modules.media,
                            sections: modules.rightWorkspace.configuration.visibleSections,
                            layoutStore: layoutStore,
                            onOpenSettings: onOpenSettings
                        )
                    }
                )
                .frame(width: settings.mediaEnabled ? metrics.rightStackWidth : nil, height: metrics.pageHeight, alignment: .topLeading)
                .clipped()
                .innerBlurScaleClean(
                    settings: settings,
                    isVisible: contentVisible,
                    isRemoval: isContentRemoving,
                    index: 2,
                    reduceMotion: reduceMotion
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func agentActivityPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        AgentActivityDashboardView(
            settings: settings,
            agentEvents: agentEvents,
            projects: modules.agentProjects,
            approvalControl: modules.agentApprovalControl,
            managedControl: modules.agentManagedControl,
            layoutStore: layoutStore,
            activityRecorder: modules.agentActivityRecorder,
            availableHeight: metrics.pageHeight,
            contentVisible: contentVisible,
            isContentRemoving: isContentRemoving
        )
        .environment(\.agentVisualPreferences, settings.agentVisualPreferences)
        .frame(maxWidth: .infinity, maxHeight: metrics.pageHeight, alignment: .topLeading)
    }

    private func trayPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: metrics.pageColumnSpacing) {
                if settings.airDropZoneEnabled {
                    AirDropDropZoneView(
                        settings: settings,
                        isTargeted: isAirDropTargeted,
                        reduceMotion: reduceMotion
                    )
                    .frame(width: min(max(metrics.trayAirDropWidth, 142), proxy.size.width * 0.36), height: proxy.size.height, alignment: .topLeading)
                    .onDrop(of: [.fileURL], isTargeted: airDropTargetBinding) { providers in
                        shareDroppedFiles(from: providers)
                        return true
                    }
                    .innerBlurScaleClean(
                        settings: settings,
                        isVisible: contentVisible,
                        isRemoval: isContentRemoving,
                        index: 1,
                        reduceMotion: reduceMotion
                    )
                }

                if settings.fileShelfEnabled {
                    FileShelfModuleView(
                        settings: settings,
                        fileShelf: modules.fileShelf,
                        backgroundOperations: modules.backgroundOperations,
                        dragExplanation: modules.fileDragSession.explanatoryAction?.explanation
                            ?? modules.fileDragSession.outcomeMessage
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay {
                            if isFilesTargeted || (navigation.isFileDropTargeted && !isAirDropTargeted) {
                                FileDropHighlightView(reduceMotion: reduceMotion)
                            }
                        }
                        .onDrop(of: FileDropProviderLoader.acceptedTypes, isTargeted: filesTargetBinding) { providers in
                            loadDroppedFiles(from: providers)
                        }
                        .innerBlurScaleClean(
                            settings: settings,
                            isVisible: contentVisible,
                            isRemoval: isContentRemoving,
                            index: 2,
                            reduceMotion: reduceMotion
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func timerPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        DedicatedTimerPageView(
            settings: settings,
            timer: modules.timer,
            ringSize: metrics.timerRingSize,
            pageHeight: metrics.pageHeight,
            onTimerStarted: onTimerStarted
        )
            .innerBlurScaleClean(
                settings: settings,
                isVisible: contentVisible,
                isRemoval: isContentRemoving,
                index: 1,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func messagesPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        MessagingPageView(
            controller: modules.messaging,
            layoutStore: layoutStore,
            pageHeight: metrics.pageHeight
        )
            .innerBlurScaleClean(
                settings: settings,
                isVisible: contentVisible,
                isRemoval: isContentRemoving,
                index: 1,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toolsPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        ProductivityToolsPageView(productivity: modules.productivity, pageHeight: metrics.pageHeight)
            .innerBlurScaleClean(
                settings: settings,
                isVisible: contentVisible,
                isRemoval: isContentRemoving,
                index: 1,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statsPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        StatsPageView(settings: settings, stats: modules.stats, metrics: metrics)
            .innerBlurScaleClean(
                settings: settings,
                isVisible: contentVisible,
                isRemoval: isContentRemoving,
                index: 1,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fileDropTargetBinding: Binding<Bool> {
        Binding(
            get: { navigation.isFileDropTargeted },
            set: { isTargeted in
                if isTargeted,
                   settings.trayEnabled,
                   settings.fileShelfEnabled,
                   settings.allowFileDropsOnExpandedTray,
                   settings.showTrayTab {
                    navigation.showTrayForFileDrag(using: settings)
                } else {
                    navigation.endFileDropTargeting()
                }
            }
        )
    }

    private var airDropTargetBinding: Binding<Bool> {
        Binding(
            get: { isAirDropTargeted },
            set: { isTargeted in
                isAirDropTargeted = isTargeted
                let accepted = isTargeted && settings.airDropZoneEnabled && settings.showTrayTab
                modules.fileDragSession.setSourceTargeted(accepted, region: .trayAirDrop)
                if accepted {
                    navigation.showTrayForFileDrag(using: settings)
                }
            }
        )
    }

    private var filesTargetBinding: Binding<Bool> {
        Binding(
            get: { isFilesTargeted },
            set: { isTargeted in
                isFilesTargeted = isTargeted
                let accepted = isTargeted &&
                    settings.trayEnabled &&
                    settings.fileShelfEnabled &&
                    settings.allowFileDropsOnExpandedTray &&
                    settings.showTrayTab
                modules.fileDragSession.setSourceTargeted(accepted, region: .trayShelf)
                if accepted {
                    navigation.showTrayForFileDrag(using: settings)
                } else {
                    navigation.endFileDropTargeting()
                }
            }
        )
    }

    private func loadDroppedFiles(from providers: [NSItemProvider]) -> Bool {
        let loader = FileDropProviderLoader()
        guard canAcceptExpandedFileDrop, loader.canLoad(providers) else {
            isFilesTargeted = false
            navigation.endFileDropTargeting()
            return false
        }
        isFilesTargeted = false
        navigation.endFileDropTargeting()
        modules.fileDragSession.cancel()

        loader.loadURLs(from: providers) { urls in
            Task { @MainActor in
                guard canAcceptExpandedFileDrop else {
                    FileShelfTemporaryStorage.shared.removeIfOwned(urls)
                    return
                }
                modules.fileShelf.add(urls)
            }
        }
        return true
    }

    private var canAcceptExpandedFileDrop: Bool {
        FileDropPolicy.allowsExpandedDrop(settings: settings)
    }

    private func shareDroppedFiles(from providers: [NSItemProvider]) {
        guard settings.airDropZoneEnabled else {
            isAirDropTargeted = false
            navigation.setFileDropTargeted(false)
            return
        }
        loadFileURLs(from: providers) { urls in
            Task { @MainActor in
                modules.fileDragSession.setSourceTargeted(false, region: .trayAirDrop)
                if !urls.isEmpty {
                    AirDropService.share(
                        urls: urls,
                        fallbackRevealInFinder: settings.airDropFallbackRevealInFinder
                    )
                }
                isAirDropTargeted = false
                navigation.setFileDropTargeted(false)
            }
        }
    }

    private func loadFileURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let accumulator = AirDropURLAccumulator()

        for provider in fileProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data,
                   let fileURL = URL(dataRepresentation: data, relativeTo: nil) {
                    url = fileURL
                } else if let fileURL = item as? URL {
                    url = fileURL
                } else {
                    url = nil
                }

                if let url {
                    accumulator.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            completion(accumulator.urls)
        }
    }

}

private final class AirDropURLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

private struct SettingsGearButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.62))
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(.white.opacity(isHovering ? 0.14 : 0.08))
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(isHovering ? 0.12 : 0.07), lineWidth: 1)
                }
                .scaleEffect(isHovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .help("Settings")
        .accessibilityLabel("Open Settings")
    }
}

private struct ExpandedHeaderButton: View {
    let systemImage: String
    let help: String
    let accessibilityLabel: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.62))
                .frame(width: 30, height: 30)
                .background {
                    Circle().fill(.white.opacity(isHovering ? 0.14 : 0.08))
                }
                .overlay {
                    Circle().stroke(.white.opacity(isHovering ? 0.12 : 0.07), lineWidth: 1)
                }
                .scaleEffect(isHovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ExpandedIslandPageSwitcher: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var navigation: IslandNavigationStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(navigation.availablePages(using: settings), id: \.self) { page in
                ExpandedIslandPageButton(
                    page: page,
                    selected: navigation.selectedPage == page
                ) {
                    navigation.select(page)
                }
            }
        }
        .padding(4)
        .background(.white.opacity(0.07), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExpandedIslandPageButton: View {
    let page: ExpandedIslandPage
    let selected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: page.symbolName)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 26)
                .foregroundStyle(.white.opacity(foregroundOpacity))
                .background {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(backgroundOpacity))
                }
                .scaleEffect(hoverScale)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(hoverAnimation, value: isHovering)
        .animation(selectionAnimation, value: selected)
        .accessibilityLabel(page.accessibilityLabel)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(page.title)
    }

    private var foregroundOpacity: Double {
        selected ? 1 : (isHovering ? 0.78 : 0.48)
    }

    private var backgroundOpacity: Double {
        selected ? 0.14 : (isHovering ? 0.075 : 0)
    }

    private var hoverScale: CGFloat {
        guard isHovering, !selected, !reduceMotion else { return 1 }
        return 1.06
    }

    private var hoverAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.14)
    }

    private var selectionAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.16)
    }
}

struct ExpandedIslandRightStackVisibility: Equatable {
    let showsLiveActivities: Bool
    let showsShortcuts: Bool

    static func resolve(
        liveActivitiesEnabled: Bool,
        showExpandedLiveActivitiesSection: Bool,
        shortcutsEnabled: Bool
    ) -> Self {
        Self(
            showsLiveActivities: liveActivitiesEnabled && showExpandedLiveActivitiesSection,
            showsShortcuts: shortcutsEnabled
        )
    }

    var showsRightStack: Bool {
        showsLiveActivities || showsShortcuts
    }
}

struct LiveActivitiesModuleView: View {
    @ObservedObject var liveActivities: LiveActivityStore
    @ObservedObject var navigation: IslandNavigationStore
    @ObservedObject var rightWorkspace: RightWorkspaceStore
    @ObservedObject var settings: AppSettings
    var availableHeight: CGFloat? = nil
    var compactScale: CGFloat = 1

    private var visibleActivities: [DynamicIslandLiveActivity] {
        if liveActivities.activities.count > 4 {
            return Array(liveActivities.activities.prefix(3))
        }
        return Array(liveActivities.activities.prefix(4))
    }

    private var remainingActivityCount: Int {
        max(liveActivities.activities.count - visibleActivities.count, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: max(5, 8 * compactScale)) {
            HStack(spacing: 7) {
                Label("Live Activities", systemImage: "waveform.path.ecg")
                    .font(.system(size: 13 * compactScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if visibleActivities.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No current activity")
                        .font(.system(size: 10.5 * compactScale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                    Text("Timer, media, files, and battery show here.")
                        .font(.system(size: 8.5 * compactScale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                GeometryReader { proxy in
                    liveActivityGrid(size: proxy.size)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(max(7, 10 * compactScale))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.070), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.055), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func liveActivityGrid(size: CGSize) -> some View {
        let itemCount = visibleActivities.count + (remainingActivityCount > 0 ? 1 : 0)
        let columns = itemCount <= 1 ? 1 : 2
        let rows = max(1, min(2, Int(ceil(Double(itemCount) / Double(columns)))))
        let spacing = max(5, 8 * compactScale)
        let itemWidth = floor(max(size.width - (CGFloat(columns - 1) * spacing), 0) / CGFloat(columns))
        let itemHeight = floor(max(size.height - (CGFloat(rows - 1) * spacing), 0) / CGFloat(rows))
        let itemScale = min(max(min(itemWidth / 168, itemHeight / 56) * compactScale, 0.70), 1)

        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = (row * columns) + column

                        if index < visibleActivities.count {
                            let activity = visibleActivities[index]
                            LiveActivityCard(
                                activity: activity,
                                compactScale: itemScale,
                                showsProgress: itemHeight >= 48
                            ) {
                                openDestination(for: activity)
                            }
                            .frame(width: itemWidth, height: itemHeight, alignment: .topLeading)
                        } else if index == visibleActivities.count && remainingActivityCount > 0 {
                            ExtraLiveActivityCard(
                                count: remainingActivityCount,
                                compactScale: itemScale
                            )
                            .frame(width: itemWidth, height: itemHeight, alignment: .center)
                        } else {
                            Color.clear
                                .frame(width: itemWidth, height: itemHeight)
                        }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func openDestination(for activity: DynamicIslandLiveActivity) {
        switch activity.kind {
        case .timer:
            if settings.timerEnabled, settings.showTimerTab {
                navigation.showTimer()
            }
        case .fileTray, .backgroundOperation:
            if settings.trayEnabled, settings.showTrayTab {
                navigation.showTray()
            }
        case .media:
            navigation.showIsland()
        case .battery:
            break
        case .agent:
            if settings.agentActivityEnabled, settings.showAgentsTab {
                navigation.showAgents()
            }
        case .system:
            break
        case .message:
            navigation.showMessages()
        case .keepAwake, .terminalTask, .windowSnapPreview, .reminder,
             .voiceRecording, .voiceTranscription, .camera, .backgroundRemoval:
            break
        case .screenRecording:
            navigation.showIsland()
            rightWorkspace.show(.productivity)
        }
    }
}

private struct LiveActivityCard: View {
    let activity: DynamicIslandLiveActivity
    var compactScale: CGFloat = 1
    var showsProgress = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: max(6, 8 * compactScale)) {
                Image(systemName: activity.symbolName)
                    .font(.system(size: 12 * compactScale, weight: .bold))
                    .foregroundStyle(activity.isActive ? .green : .white.opacity(0.58))
                    .frame(width: 22 * compactScale, height: 22 * compactScale)
                    .background(.white.opacity(0.085), in: Circle())

                VStack(alignment: .leading, spacing: max(2, 3 * compactScale)) {
                    HStack(spacing: 6) {
                        Text(activity.title)
                            .font(.system(size: 11.5 * compactScale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Spacer(minLength: 0)
                    }

                    if showsProgress, let subtitle = activity.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 9.5 * compactScale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    if showsProgress, let progress = LiveActivityStore.clampedProgress(activity.progress) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.12))
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.62))
                                    .frame(width: max(proxy.size.width * progress, 3))
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
            .padding(.horizontal, max(6, 8 * compactScale))
            .padding(.vertical, max(5, 7 * compactScale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.white.opacity(0.082), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.055), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activityAccessibilityLabel)
    }

    private var activityAccessibilityLabel: String {
        if let subtitle = activity.subtitle, !subtitle.isEmpty {
            return "\(activity.title), \(subtitle)"
        }
        return activity.title
    }
}

private struct ExtraLiveActivityCard: View {
    let count: Int
    let compactScale: CGFloat

    var body: some View {
        Text("+\(count)")
            .font(.system(size: max(12, 16 * compactScale), weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.070), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.055), lineWidth: 1)
            }
            .accessibilityLabel("\(count) more live activities")
    }
}

struct StatsPageView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var stats: SystemStatsController
    let metrics: ExpandedIslandLayoutMetrics

    var body: some View {
        let snapshot = stats.snapshot

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Stats", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if settings.showActivityIndicator {
                    LiveStatusIndicator()
                }
                Spacer(minLength: 0)
                Text(batteryStatusText(snapshot))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            if metrics.statsUsesScroll {
                ScrollView(.vertical, showsIndicators: false) {
                    statsGrid(snapshot)
                        .padding(.bottom, 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                statsGrid(snapshot)
                    .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statsGrid(_ snapshot: SystemStatsSnapshot) -> some View {
        VStack(spacing: metrics.cardSpacing) {
            HStack(spacing: metrics.cardSpacing) {
                if settings.showCPU {
                    StatsMetricCard(
                        title: "CPU",
                        symbol: "cpu",
                        value: "\(Int((snapshot.cpuUsage * 100).rounded()))%",
                        detail: "System load",
                        accent: .cyan,
                        fraction: snapshot.cpuUsage,
                        history: snapshot.cpuHistory,
                        width: metrics.statsCardWidth,
                        height: metrics.statsCardHeight,
                        compactScale: metrics.compactScale
                    )
                }

                if settings.showMemory {
                    StatsMetricCard(
                        title: "Memory",
                        symbol: "memorychip",
                        value: percentText(fraction(used: snapshot.memoryUsedBytes, total: snapshot.memoryTotalBytes)),
                        detail: usedTotalText(used: snapshot.memoryUsedBytes, total: snapshot.memoryTotalBytes),
                        secondary: "Cached \(SystemStatsFormatting.formatBytes(snapshot.memoryCachedBytes))",
                        accent: .purple,
                        fraction: fraction(used: snapshot.memoryUsedBytes, total: snapshot.memoryTotalBytes),
                        history: snapshot.memoryHistory,
                        width: metrics.statsCardWidth,
                        height: metrics.statsCardHeight,
                        compactScale: metrics.compactScale
                    )
                }

                if settings.showGPU {
                    StatsMetricCard(
                        title: "GPU",
                        symbol: "display",
                        value: "Unavailable",
                        detail: "No reliable API",
                        accent: .orange,
                        fraction: nil,
                        history: [],
                        width: metrics.statsCardWidth,
                        height: metrics.statsCardHeight,
                        compactScale: metrics.compactScale
                    )
                }
            }

            HStack(spacing: metrics.cardSpacing) {
                if settings.showNetwork {
                    StatsMetricCard(
                        title: "Network",
                        symbol: "network",
                        value: networkText(snapshot),
                        detail: "Current transfer",
                        secondary: "↑ \(SystemStatsFormatting.formatBytesPerSecond(snapshot.networkUploadBytesPerSecond))",
                        accent: .green,
                        fraction: nil,
                        history: snapshot.networkDownloadHistory,
                        secondaryHistory: snapshot.networkUploadHistory,
                        width: metrics.statsCardWidth,
                        height: metrics.statsCardHeight,
                        compactScale: metrics.compactScale
                    )
                }

                if settings.showDisk {
                    StatsMetricCard(
                        title: "Disk",
                        symbol: "internaldrive",
                        value: percentText(fraction(used: snapshot.diskUsedBytes, total: snapshot.diskTotalBytes)),
                        detail: usedTotalText(used: snapshot.diskUsedBytes, total: snapshot.diskTotalBytes),
                        secondary: "Startup volume",
                        accent: .blue,
                        fraction: fraction(used: snapshot.diskUsedBytes, total: snapshot.diskTotalBytes),
                        history: snapshot.diskHistory,
                        width: metrics.statsCardWidth,
                        height: metrics.statsCardHeight,
                        compactScale: metrics.compactScale
                    )
                }

                if settings.showBattery || settings.showUptime {
                    StatsMetricCard(
                        title: settings.showBattery ? "Battery" : "Uptime",
                        symbol: settings.showBattery ? "battery.75percent" : "clock",
                        value: settings.showBattery ? batteryText(snapshot) : uptimeText(snapshot.uptimeSeconds),
                        detail: settings.showBattery ? batteryDetail(snapshot) : "System uptime",
                        secondary: settings.showUptime ? "Uptime \(uptimeText(snapshot.uptimeSeconds))" : nil,
                        accent: .mint,
                        fraction: settings.showBattery ? snapshot.batteryPercent : nil,
                        history: settings.showBattery ? batteryHistory(snapshot) : [],
                        width: metrics.statsCardWidth,
                        height: metrics.statsCardHeight,
                        compactScale: metrics.compactScale
                    )
                }
            }
        }
    }

    private func usedTotalText(used: UInt64, total: UInt64) -> String {
        guard total > 0 else { return "Unavailable" }
        return "\(SystemStatsFormatting.formatBytes(used)) / \(SystemStatsFormatting.formatBytes(total))"
    }

    private func fraction(used: UInt64, total: UInt64) -> Double? {
        guard total > 0 else { return nil }
        return SystemStatsFormatting.clampedFraction(Double(used) / Double(total))
    }

    private func percentText(_ fraction: Double?) -> String {
        guard let fraction else { return "Unavailable" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    private func networkText(_ snapshot: SystemStatsSnapshot) -> String {
        let down = SystemStatsFormatting.formatBytesPerSecond(snapshot.networkDownloadBytesPerSecond)
        return "↓ \(down)"
    }

    private func batteryStatusText(_ snapshot: SystemStatsSnapshot) -> String {
        guard let percent = snapshot.batteryPercent else { return "Stats live" }
        return "\(Int((percent * 100).rounded()))% \(snapshot.isCharging == true ? "Charging" : "Battery")"
    }

    private func batteryText(_ snapshot: SystemStatsSnapshot) -> String {
        guard let percent = snapshot.batteryPercent else { return "Unavailable" }
        return "\(Int((percent * 100).rounded()))%"
    }

    private func batteryDetail(_ snapshot: SystemStatsSnapshot) -> String {
        guard let isCharging = snapshot.isCharging else { return "Battery status" }
        return isCharging ? "Charging" : "On battery"
    }

    private func uptimeText(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let days = hours / 24
        let remainingHours = hours % 24
        if days > 0 {
            return "\(days)d \(remainingHours)h"
        }
        return "\(remainingHours)h"
    }

    private func batteryHistory(_ snapshot: SystemStatsSnapshot) -> [Double] {
        guard let percent = snapshot.batteryPercent else { return [] }
        return [percent, percent]
    }
}

private struct StatsMetricCard: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    var secondary: String?
    let accent: Color
    let fraction: Double?
    let history: [Double]
    var secondaryHistory: [Double] = []
    let width: CGFloat
    let height: CGFloat
    let compactScale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: max(3, 4 * compactScale)) {
            HStack(spacing: max(5, 7 * compactScale)) {
                Image(systemName: symbol)
                    .font(.system(size: 12 * compactScale, weight: .bold))
                    .foregroundStyle(accent.opacity(0.95))
                    .frame(width: 22 * compactScale, height: 22 * compactScale)
                    .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11 * compactScale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 17 * compactScale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.56)
                }
                Spacer(minLength: 0)
            }

            StatsLineChart(
                values: history,
                secondaryValues: secondaryHistory,
                accent: accent
            )
            .frame(height: max(8, 13 * compactScale))

            HStack(spacing: 5) {
                Text(detail)
                if let secondary {
                    Spacer(minLength: 3)
                    Text(secondary)
                }
            }
            .font(.system(size: 8 * compactScale, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.42))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(max(5, 8 * compactScale))
        .frame(width: width, height: height, alignment: .topLeading)
        .background(.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(accent.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct StatsLineChart: View {
    let values: [Double]
    var secondaryValues: [Double] = []
    let accent: Color
    @Environment(\.isShellMorphing) private var isShellMorphing

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                chartPath(values: chartSamples(values), size: proxy.size)
                    .stroke(accent.opacity(0.86), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if !isShellMorphing, !secondaryValues.isEmpty {
                    chartPath(values: chartSamples(secondaryValues), size: proxy.size)
                        .stroke(.white.opacity(0.42), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func chartSamples(_ values: [Double]) -> [Double] {
        guard isShellMorphing, values.count > 12 else { return values }
        return values.enumerated().compactMap { index, value in
            index.isMultiple(of: 2) ? value : nil
        }
    }

    private func chartPath(values: [Double], size: CGSize) -> Path {
        var path = Path()
        let samples = values.isEmpty ? [0, 0] : values
        let maxIndex = max(samples.count - 1, 1)

        for index in samples.indices {
            let x = size.width * CGFloat(index) / CGFloat(maxIndex)
            let y = size.height * (1 - CGFloat(SystemStatsFormatting.clampedFraction(samples[index])))
            if index == samples.startIndex {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

private struct LiveStatusIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text("Live")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.white.opacity(0.08), in: Capsule(style: .continuous))
    }
}

private struct ShellMorphingEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

private struct CollapseShellOnlyEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isShellMorphing: Bool {
        get { self[ShellMorphingEnvironmentKey.self] }
        set { self[ShellMorphingEnvironmentKey.self] = newValue }
    }

    var isCollapseShellOnly: Bool {
        get { self[CollapseShellOnlyEnvironmentKey.self] }
        set { self[CollapseShellOnlyEnvironmentKey.self] = newValue }
    }
}

extension View {
    func shellMorphing(_ isShellMorphing: Bool) -> some View {
        environment(\.isShellMorphing, isShellMorphing)
    }

    func collapseShellOnly(_ isCollapseShellOnly: Bool) -> some View {
        environment(\.isCollapseShellOnly, isCollapseShellOnly)
    }
}

struct AirDropDropZoneView: View {
    @ObservedObject var settings: AppSettings
    let isTargeted: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.cyan.opacity(0.92))
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("AirDrop")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(isTargeted ? 0.13 : 0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.cyan.opacity(isTargeted ? 0.78 : 0.12), lineWidth: isTargeted ? 2 : 1)
                .shadow(color: .cyan.opacity(isTargeted && !reduceMotion ? 0.28 : 0), radius: reduceMotion ? 0 : 8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeOut(duration: reduceMotion ? 0.01 : 0.14), value: isTargeted)
        .accessibilityLabel("AirDrop")
        .accessibilityHint("Drop files here to share with AirDrop")
    }

    private var subtitle: String {
        settings.airDropFallbackRevealInFinder
            ? "Drop files here to share"
            : "Drop files here to share if available"
    }
}

private struct FileDropHighlightView: View {
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.cyan.opacity(0.10))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.cyan.opacity(0.78), lineWidth: 2)
                .shadow(color: .cyan.opacity(reduceMotion ? 0 : 0.35), radius: reduceMotion ? 0 : 10)
            Text("Drop files here")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.42), in: Capsule(style: .continuous))
        }
        .allowsHitTesting(false)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
    }
}

struct DedicatedTimerPageView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var timer: TimerController
    let ringSize: CGFloat
    let pageHeight: CGFloat
    let onTimerStarted: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesCompactLayout: Bool {
        pageHeight < 150 || ringSize < 96
    }

    private var controlsFontSize: CGFloat {
        usesCompactLayout ? 11 : 12
    }

    private var controlsSpacing: CGFloat {
        usesCompactLayout ? 6 : 8
    }

    private var titleFontSize: CGFloat {
        usesCompactLayout ? 16 : 18
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactLayout ? 7 : 8) {
            Label("Timer", systemImage: "timer")
                .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if settings.showTimerProgressRing {
                TimerProgressRingView(
                    progress: TimerProgressFormatting.progress(
                        remainingSeconds: timer.remainingSeconds,
                        totalSeconds: timer.totalSeconds
                    ),
                    remainingText: timer.displayText,
                    isRunning: timer.isRunning,
                    ringSize: ringSize,
                    animationEnabled: settings.timerRingAnimationEnabled
                )
                .frame(maxWidth: .infinity)
            }

            if settings.timerPresetsEnabled {
                ViewThatFits(in: .horizontal) {
                    timerControlRow
                    timerControlStack
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var timerControlRow: some View {
        HStack(spacing: controlsSpacing) {
            Button("\(settings.timerPreset1Minutes)m") { startTimer(settings.timerPreset1Minutes) }
            Button("\(settings.timerPreset2Minutes)m") { startTimer(settings.timerPreset2Minutes) }
            Button("\(settings.timerPreset3Minutes)m") { startTimer(settings.timerPreset3Minutes) }

            Divider()
                .frame(height: usesCompactLayout ? 18 : 20)
                .overlay(.white.opacity(0.12))

            Button(timer.isRunning ? "Pause" : "Resume") {
                timer.isRunning ? timer.pause() : timer.resume()
            }
            .disabled(timer.remainingSeconds <= 0)

            Button("Reset") { timer.reset() }
                .disabled(timer.remainingSeconds <= 0)
        }
        .buttonStyle(.borderless)
        .font(.system(size: controlsFontSize, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var timerControlStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: controlsSpacing) {
                Button("\(settings.timerPreset1Minutes)m") { startTimer(settings.timerPreset1Minutes) }
                Button("\(settings.timerPreset2Minutes)m") { startTimer(settings.timerPreset2Minutes) }
                Button("\(settings.timerPreset3Minutes)m") { startTimer(settings.timerPreset3Minutes) }
            }

            HStack(spacing: controlsSpacing) {
                Button(timer.isRunning ? "Pause" : "Resume") {
                    timer.isRunning ? timer.pause() : timer.resume()
                }
                .disabled(timer.remainingSeconds <= 0)

                Button("Reset") { timer.reset() }
                    .disabled(timer.remainingSeconds <= 0)
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: controlsFontSize, weight: .bold, design: .rounded))
    }

    private func startTimer(_ minutes: Int) {
        timer.start(minutes: minutes)
        onTimerStarted()
    }
}

private struct TimerProgressRingView: View {
    let progress: Double
    let remainingText: String
    let isRunning: Bool
    let ringSize: CGFloat
    let animationEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedProgress: Double {
        TimerProgressFormatting.progress(
            remainingSeconds: Int((progress * 10_000).rounded()),
            totalSeconds: 10_000
        )
    }

    private var ringColor: Color {
        TimerRingColor.color(for: clampedProgress)
    }

    private var lineWidth: CGFloat {
        ringSize < 100 ? 9 : 11
    }

    private var timerFontSize: CGFloat {
        ringSize < 100 ? max(24, ringSize * 0.24) : max(28, ringSize * 0.28)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.10), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(reduceMotion ? 0 : 0.32), radius: reduceMotion ? 0 : 10)
                .animation(reduceMotion || !animationEnabled ? nil : .easeInOut(duration: 0.42), value: clampedProgress)

            VStack(spacing: 3) {
                Text(remainingText)
                    .font(.system(size: timerFontSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(isRunning ? "Running" : "Ready")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
            }
            .padding(.horizontal, 18)
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(remainingText)
    }
}

private enum TimerRingColor {
    static func color(for progress: Double) -> Color {
        let clampedProgress = min(max(progress, 0), 1)
        let hue: Double
        if clampedProgress > 0.5 {
            let segment = (clampedProgress - 0.5) / 0.5
            hue = 0.10 + (0.23 * segment)
        } else {
            let segment = clampedProgress / 0.5
            hue = 0.02 + (0.08 * segment)
        }
        return Color(hue: hue, saturation: 0.92, brightness: 0.98)
    }
}
