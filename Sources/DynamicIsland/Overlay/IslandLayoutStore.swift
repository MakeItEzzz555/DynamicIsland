import Foundation

enum ExpandedAccessoryOwner: Hashable, Sendable {
    case trayQuickActions
    case fileDragOrbit
}

enum IslandCanvasCoordinateSpace {
    static let name = "DynamicIslandCanvas"

    static func appKitLocalRect(fromSwiftUI frame: CGRect, canvasHeight: CGFloat) -> CGRect {
        guard canvasHeight.isFinite, canvasHeight > 0 else { return .zero }
        return CGRect(
            x: frame.minX,
            y: canvasHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}

enum TransientInteractionOwner: Hashable, Sendable {
    case workspaceEditor
    case agentsLauncher
    case calendarDatePicker
    case unspecified
}

enum IslandWorkspaceAction: Equatable {
    case edit
    case clipboard
}

struct IslandWorkspaceActionRequest: Equatable {
    let generation: Int
    let action: IslandWorkspaceAction
}

@MainActor
final class IslandLayoutStore: ObservableObject {
    /// Transient delivery to the existing expanded view, which still owns
    /// Clipboard presentation and the editor transaction.
    @Published private(set) var workspaceActionRequest: IslandWorkspaceActionRequest?
    private var workspaceActionGeneration = 0
    private var requestedExpansionPage: ExpandedIslandPage?

    func preservePageForNextExpansion(_ page: ExpandedIslandPage) {
        requestedExpansionPage = page
    }
    func consumeExpansionPage() -> ExpandedIslandPage? {
        defer { requestedExpansionPage = nil }
        return requestedExpansionPage
    }
    func requestWorkspaceAction(_ action: IslandWorkspaceAction) {
        workspaceActionGeneration += 1
        workspaceActionRequest = IslandWorkspaceActionRequest(generation: workspaceActionGeneration, action: action)
    }
    func consumeWorkspaceAction(generation: Int) -> IslandWorkspaceAction? {
        guard let request = workspaceActionRequest, request.generation == generation else { return nil }
        workspaceActionRequest = nil
        return request.action
    }
    func cancelWorkspaceActionRequests() {
        workspaceActionGeneration += 1
        workspaceActionRequest = nil
        requestedExpansionPage = nil
    }
    struct WorkspaceLayoutPreview: Equatable {
        let configuration: WorkspaceConfiguration
        let surface: WorkspaceSurface
    }
    @Published private(set) var workspaceLayoutPreview: WorkspaceLayoutPreview?
    @Published private(set) var workspaceGeometryTransition = WorkspaceGeometryTransition()
    @Published private(set) var nativeControlRegions: [UUID: CGRect] = [:]
    @Published var expandedChildExitGeneration = 0
    @Published private(set) var expandedChildExitAcknowledgement = 0
    func acknowledgeExpandedChildExit(generation: Int) {
        guard generation == expandedChildExitGeneration, expandedChildExitAcknowledgement != generation else { return }
        expandedChildExitAcknowledgement = generation
    }
    func expandedPresentationSize(desired: CGSize, committed: CGSize, isExpanded: Bool) -> CGSize {
        if (isExpanded && isExpandedContentExiting) || workspaceGeometryTransition.phase == .childrenExiting {
            return committed
        }
        return desired
    }

    func setWorkspaceLayoutPreview(_ configuration: WorkspaceConfiguration?, surface: WorkspaceSurface) {
        if configuration == nil && workspaceLayoutPreview?.surface != surface { return }
        let next = configuration.map { WorkspaceLayoutPreview(configuration: $0, surface: surface) }
        if workspaceLayoutPreview != next { workspaceLayoutPreview = next }
    }
    /// While a widget drag is in flight the shell may grow for the prospective
    /// layout but never shrinks below its drag-start size: shrinking would pull
    /// the surface out from under the pointer (drop exit -> preview revert ->
    /// regrow -> oscillation). Cleared on drop/cancel so the exact committed
    /// geometry applies.
    @Published private(set) var workspaceDragFloor: CGSize?
    func setWorkspaceDragActive(_ active: Bool) {
        let next: CGSize? = active ? (workspaceDragFloor ?? expandedSize) : nil
        if next != workspaceDragFloor { workspaceDragFloor = next }
    }
    static func dragFloored(_ size: CGSize, floor: CGSize?) -> CGSize {
        guard let floor else { return size }
        return CGSize(width: max(size.width, floor.width), height: max(size.height, floor.height))
    }
    func requestWorkspaceGeometry(_ size: CGSize) { workspaceGeometryTransition.request(size) }
    func workspaceChildrenExited(generation: Int) {
        var next = workspaceGeometryTransition
        if next.childrenExited(generation: generation) { workspaceGeometryTransition = next }
    }
    func finishWorkspaceGeometry(generation: Int) {
        var next = workspaceGeometryTransition
        next.complete(generation: generation)
        if next != workspaceGeometryTransition { workspaceGeometryTransition = next }
    }
    func cancelWorkspaceGeometry() {
        guard workspaceGeometryTransition.phase != .idle else { return }
        workspaceGeometryTransition.cancel()
    }
    /// SwiftUI canvas coordinates. Owners remove only their own control, so a
    /// retiring ruler cannot clear a newly mounted widget's input claim.
    func setNativeControlRegion(_ frame: CGRect?, owner: UUID) {
        var next = nativeControlRegions
        if let frame, !frame.isEmpty, !frame.isNull, !frame.isInfinite { next[owner] = frame.integral }
        else { next.removeValue(forKey: owner) }
        if next != nativeControlRegions { nativeControlRegions = next }
    }
    func containsNativeControlPoint(_ point: CGPoint) -> Bool {
        nativeControlRegions.values.contains { $0.contains(point) }
    }
    @Published var overlayPresentationGeneration = 0
    @Published var canvasSize: CGSize = CGSize(width: 760, height: 260)
    @Published var collapsedSurfaceFrame: CGRect = CGRect(x: 272, y: 226, width: 216, height: 34)
    @Published var expandedSurfaceFrame: CGRect = CGRect(x: 0, y: 0, width: 760, height: 260)
    @Published var collapsedSize: CGSize = CGSize(width: 216, height: 34)
    @Published var expandedSize: CGSize = CGSize(width: 760, height: 260)
    @Published var hasHardwareNotch = true
    @Published private(set) var hardwareNotchWidth: CGFloat = 0
    @Published private(set) var collapsedLeftRegionWidth: CGFloat = 0
    @Published private(set) var collapsedNotchCoreWidth: CGFloat = 0
    @Published private(set) var collapsedRightRegionWidth: CGFloat = 0
    @Published private(set) var collapsedPresentationProfile: CollapsedPresentationProfile = .normal
    @Published var compactPermissionHovered = false
    @Published var isShellMorphing = false
    /// The header mode for the committed shell geometry. Set by the overlay
    /// controller in the same (animated) update as the shell frames, so the
    /// header row and the shell move as one transition.
    @Published var expandedHeaderLayout: ExpandedHeaderLayout = .winged
    @Published var isCollapseShellOnly = false
    @Published var isExpandedContentExiting = false
    @Published var collapsedPreviewActive = false
    @Published var collapsedPreviewSurfaceFrame: CGRect = .zero
    @Published private(set) var collapsedLeadingSidecarFrame: CGRect = .zero
    @Published private(set) var collapsedTrailingSidecarFrame: CGRect = .zero
    @Published private(set) var collapsedCompositeInteractionFrame: CGRect = .zero
    @Published var panelFrame: CGRect = .zero
    @Published private(set) var displayMetrics: ResolvedIslandMetrics = .fallback
    @Published private(set) var isExpandedScrollGestureSuppressed = false
    @Published private(set) var expandedContentScrollRegion: CGRect = .zero
    /// A second viewport inside the same expanded shell (Agents Feed/Terminal).
    /// Separate from the transcript: neither viewport may steal the other's
    /// trackpad sequence or turn vertical history scrolling into shell collapse.
    @Published private(set) var agentWorkspaceScrollRegion: CGRect = .zero
    @Published private(set) var agentStackSwipeRegion: CGRect = .zero
    var agentStackSwipeAction: ((Int) -> Void)?
    private var agentStackSwipeOwner: UUID?

    func installAgentStackSwipe(owner: UUID, action: @escaping (Int) -> Void) {
        agentStackSwipeOwner = owner
        agentStackSwipeAction = action
    }

    func setAgentStackSwipeRegion(_ region: CGRect, owner: UUID) {
        guard agentStackSwipeOwner == owner else { return }
        setAgentStackSwipeRegion(region)
    }

    func removeAgentStackSwipe(owner: UUID) {
        guard agentStackSwipeOwner == owner else { return }
        agentStackSwipeOwner = nil
        agentStackSwipeAction = nil
        setAgentStackSwipeRegion(.zero)
    }

    func setAgentStackSwipeRegion(_ region: CGRect) {
        let next = region.isNull || region.isInfinite || region.width <= 0 || region.height <= 0 ? .zero : region.integral
        if agentStackSwipeRegion != next { agentStackSwipeRegion = next }
    }
    /// Owners of an in-island transient interaction (Agents launcher,
    /// Calendar date popover). The island stays expanded while any owner is
    /// active; each owner clears only its own claim, so two surfaces can
    /// never leave the island stuck or release each other's hold.
    @Published private(set) var transientInteractionOwners: Set<TransientInteractionOwner> = []

    var isTransientInteractionActive: Bool {
        get { !transientInteractionOwners.isEmpty }
        set { setTransientInteraction(newValue, owner: .unspecified) }
    }

    func setTransientInteraction(_ active: Bool, owner: TransientInteractionOwner) {
        if active {
            guard !transientInteractionOwners.contains(owner) else { return }
            transientInteractionOwners.insert(owner)
        } else {
            guard transientInteractionOwners.contains(owner) else { return }
            transientInteractionOwners.remove(owner)
        }
    }
    /// Visible accessories attached below the expanded shell (panel-local,
    /// AppKit coordinates). They own hover, hit-testing and passthrough
    /// exactly like the shell, and only their own area.
    @Published private(set) var expandedAccessoryFrames: [CGRect] = []
    private var expandedAccessoryFramesByOwner: [ExpandedAccessoryOwner: [CGRect]] = [:]
    /// Panel-local region of the Island page's right workspace; horizontal
    /// swipes that start inside it page the workspace.
    @Published private(set) var rightWorkspaceRegion: CGRect = .zero
    /// True only while the real Camera Mirror surface is visible on the active
    /// right-workspace page. The overlay uses this to reject island-level
    /// vertical actions without consuming native vertical scrolling.
    @Published private(set) var isRightWorkspaceMirrorActive = false

    func setDisplayMetrics(_ metrics: ResolvedIslandMetrics) {
        guard displayMetrics != metrics else { return }
        displayMetrics = metrics
    }

    func setRightWorkspaceMirrorActive(_ active: Bool) {
        guard isRightWorkspaceMirrorActive != active else { return }
        isRightWorkspaceMirrorActive = active
    }

    func setRightWorkspaceRegion(_ frame: CGRect) {
        let next = frame.isEmpty || frame.isNull || frame.isInfinite ? .zero : frame.integral
        guard next != rightWorkspaceRegion else { return }
        rightWorkspaceRegion = next
    }

    func setExpandedAccessoryFrames(_ frames: [CGRect], owner: ExpandedAccessoryOwner) {
        let valid = frames
            .filter { !$0.isNull && !$0.isInfinite && $0.width > 0 && $0.height > 0 }
            .map(\.integral)
        if valid.isEmpty {
            expandedAccessoryFramesByOwner.removeValue(forKey: owner)
        } else {
            expandedAccessoryFramesByOwner[owner] = valid
        }
        let combined = ExpandedAccessoryOwnerOrder.allCases.flatMap { expandedAccessoryFramesByOwner[$0.owner] ?? [] }
        guard expandedAccessoryFrames != combined else { return }
        expandedAccessoryFrames = combined
    }

    private enum ExpandedAccessoryOwnerOrder: Int, CaseIterable {
        case trayQuickActions
        case fileDragOrbit

        var owner: ExpandedAccessoryOwner {
            switch self {
            case .trayQuickActions: .trayQuickActions
            case .fileDragOrbit: .fileDragOrbit
            }
        }
    }

    /// An in-island text editor (Agents composer) is first responder.
    @Published private(set) var isTextInputFocused = false

    func setTextInputFocused(_ focused: Bool) {
        guard isTextInputFocused != focused else { return }
        isTextInputFocused = focused
    }

    func setExpandedScrollGestureSuppressed(_ suppressed: Bool) {
        guard isExpandedScrollGestureSuppressed != suppressed else { return }
        isExpandedScrollGestureSuppressed = suppressed
        #if DEBUG
        print(
            suppressed
                ? "[GestureDebug] expanded scroll suppression enabled"
                : "[GestureDebug] expanded scroll suppression disabled"
        )
        #endif
    }

    func setExpandedContentScrollRegion(_ region: CGRect) {
        let next = region.isNull || region.isInfinite || region.width <= 0 || region.height <= 0
            ? CGRect.zero
            : region.integral
        guard expandedContentScrollRegion != next else { return }
        expandedContentScrollRegion = next
        #if DEBUG
        if ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" {
            debugPrint("[GestureDebug] expanded content scroll region", next)
        }
        #endif
    }

    func setAgentWorkspaceScrollRegion(_ region: CGRect) {
        let next = region.isNull || region.isInfinite || region.width <= 0 || region.height <= 0 ? .zero : region.integral
        if agentWorkspaceScrollRegion != next { agentWorkspaceScrollRegion = next }
    }

    func containsExpandedScrollPoint(_ point: CGPoint) -> Bool {
        [expandedContentScrollRegion, agentWorkspaceScrollRegion].contains { !$0.isEmpty && $0.contains(point) }
    }

    func update(
        canvas: IslandCanvasGeometry,
        hasHardwareNotch: Bool,
        hardwareNotchWidth: CGFloat,
        collapsedLeftRegionWidth: CGFloat,
        collapsedNotchCoreWidth: CGFloat,
        collapsedRightRegionWidth: CGFloat,
        collapsedPresentationProfile: CollapsedPresentationProfile = .normal
    ) {
        panelFrame = canvas.frame
        canvasSize = canvas.frame.size
        collapsedSurfaceFrame = canvas.collapsedSurfaceFrame
        expandedSurfaceFrame = canvas.expandedSurfaceFrame
        collapsedPreviewActive = false
        collapsedPreviewSurfaceFrame = .zero
        collapsedLeadingSidecarFrame = .zero
        collapsedTrailingSidecarFrame = .zero
        collapsedCompositeInteractionFrame = collapsedSurfaceFrame
        collapsedSize = collapsedSurfaceFrame.size
        expandedSize = canvas.expandedSurfaceFrame.size
        self.hasHardwareNotch = hasHardwareNotch
        self.hardwareNotchWidth = hasHardwareNotch ? max(hardwareNotchWidth, 0) : 0
        self.collapsedLeftRegionWidth = max(collapsedLeftRegionWidth, 0)
        self.collapsedNotchCoreWidth = max(collapsedNotchCoreWidth, 0)
        self.collapsedRightRegionWidth = max(collapsedRightRegionWidth, 0)
        self.collapsedPresentationProfile = collapsedPresentationProfile
    }

    func updateLocal(
        panelFrame: CGRect,
        collapsedScreenFrame: CGRect,
        expandedScreenFrame: CGRect,
        hasHardwareNotch: Bool,
        hardwareNotchWidth: CGFloat,
        collapsedLeftRegionWidth: CGFloat,
        collapsedNotchCoreWidth: CGFloat,
        collapsedRightRegionWidth: CGFloat,
        collapsedPresentationProfile: CollapsedPresentationProfile = .normal
    ) {
        let integralPanelFrame = panelFrame.integral
        let localCollapsedFrame = CGRect(
            x: collapsedScreenFrame.minX - integralPanelFrame.minX,
            y: collapsedScreenFrame.minY - integralPanelFrame.minY,
            width: collapsedScreenFrame.width,
            height: collapsedScreenFrame.height
        ).integral
        let localExpandedFrame = CGRect(
            x: expandedScreenFrame.minX - integralPanelFrame.minX,
            y: expandedScreenFrame.minY - integralPanelFrame.minY,
            width: expandedScreenFrame.width,
            height: expandedScreenFrame.height
        ).integral

        self.panelFrame = integralPanelFrame
        canvasSize = integralPanelFrame.size
        collapsedSurfaceFrame = localCollapsedFrame
        expandedSurfaceFrame = localExpandedFrame
        if !collapsedPreviewActive {
            collapsedPreviewSurfaceFrame = .zero
        }
        collapsedLeadingSidecarFrame = .zero
        collapsedTrailingSidecarFrame = .zero
        collapsedCompositeInteractionFrame = collapsedSurfaceFrame
        collapsedSize = collapsedSurfaceFrame.size
        expandedSize = localExpandedFrame.size
        self.hasHardwareNotch = hasHardwareNotch
        self.hardwareNotchWidth = hasHardwareNotch ? max(hardwareNotchWidth, 0) : 0
        self.collapsedLeftRegionWidth = max(collapsedLeftRegionWidth, 0)
        self.collapsedNotchCoreWidth = max(collapsedNotchCoreWidth, 0)
        self.collapsedRightRegionWidth = max(collapsedRightRegionWidth, 0)
        self.collapsedPresentationProfile = collapsedPresentationProfile
        debugLocalLayout(
            panelFrame: integralPanelFrame,
            collapsedScreenFrame: collapsedScreenFrame,
            expandedScreenFrame: expandedScreenFrame,
            collapsedSurfaceFrame: localCollapsedFrame,
            expandedSurfaceFrame: localExpandedFrame
        )
    }

    private func debugLocalLayout(
        panelFrame: CGRect,
        collapsedScreenFrame: CGRect,
        expandedScreenFrame: CGRect,
        collapsedSurfaceFrame: CGRect,
        expandedSurfaceFrame: CGRect
    ) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" else { return }
        debugPrint(
            "DynamicIsland local layout",
            "panelFrame=\(panelFrame)",
            "collapsedScreenFrame=\(collapsedScreenFrame)",
            "expandedScreenFrame=\(expandedScreenFrame)",
            "collapsedSurfaceFrame=\(collapsedSurfaceFrame)",
            "expandedSurfaceFrame=\(expandedSurfaceFrame)",
            "collapsedMidX=\(collapsedSurfaceFrame.midX)",
            "expandedMidX=\(expandedSurfaceFrame.midX)"
        )
        if abs(collapsedSurfaceFrame.midX - expandedSurfaceFrame.midX) > 1 {
            debugPrint(
                "DynamicIsland local layout warning",
                "collapsed and expanded local midX differ by more than 1pt"
            )
        }
        #endif
    }

    func updateCollapsedSidecars(_ geometry: LiveActivityCompositeGeometry) {
        let leading = geometry.leadingSidecarFrame?.integral ?? .zero
        let trailing = geometry.trailingSidecarFrame?.integral ?? .zero
        let interaction = geometry.interactionFrame.integral

        if collapsedLeadingSidecarFrame != leading {
            collapsedLeadingSidecarFrame = leading
        }
        if collapsedTrailingSidecarFrame != trailing {
            collapsedTrailingSidecarFrame = trailing
        }
        if collapsedCompositeInteractionFrame != interaction {
            collapsedCompositeInteractionFrame = interaction
        }
    }

    func updateCollapsedPreview(active: Bool, frame: CGRect) {
        let nextFrame = active ? frame.integral : .zero
        if collapsedPreviewActive != active {
            collapsedPreviewActive = active
        }
        if collapsedPreviewSurfaceFrame != nextFrame {
            collapsedPreviewSurfaceFrame = nextFrame
        }
    }
}

/// Whether the next workspace geometry change follows the shell live (edit
/// preview) instead of the committed-layout
/// children-exit -> resize -> reveal handoff, which blanks the content while
/// the shell moves. Fed from the *emitted* publisher values: `@Published`
/// subscribers run in willSet, before the store holds the new value, so
/// reading the store there saw no preview on edit entry and the editor
/// opened on a pitch-black shell.
struct WorkspaceGeometryLiveness: Equatable {
    private(set) var editPreview = false

    mutating func previewChanged(isPresent: Bool) {
        // Present: editing geometry is live. Absent: the change that ends
        // editing (Apply/Cancel) is still live; `consume` clears it after.
        if isPresent { editPreview = true }
    }

    /// Liveness for one geometry check: while a preview exists plus the
    /// change that ends it.
    mutating func consume(previewPresent: Bool) -> Bool {
        let live = editPreview || previewPresent
        if !previewPresent { editPreview = false }
        return live
    }
}
