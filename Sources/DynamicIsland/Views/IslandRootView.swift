import SwiftUI
import UniformTypeIdentifiers

private let collapseHandoffDebug = false
private let disableCollapsedArtworkDuringHandoff = false
private let disableCollapsedVisualizerDuringHandoff = false

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

private enum IslandShellLayout {
    static let collapsedHorizontalPadding: CGFloat = 8
    static let collapsedTopPadding: CGFloat = 0
    static let collapsedBottomPadding: CGFloat = 6

    static let expandedHorizontalPadding: CGFloat = 22
    static let expandedTopPadding: CGFloat = 14
    static let expandedBottomPadding: CGFloat = 20
}

private struct ExpandedIslandLayoutMetrics {
    let containerSize: CGSize

    let horizontalPadding: CGFloat = IslandShellLayout.expandedHorizontalPadding
    let topPadding: CGFloat = IslandShellLayout.expandedTopPadding
    let bottomPadding: CGFloat = IslandShellLayout.expandedBottomPadding
    let tabSwitcherHeight: CGFloat = 34
    let tabToPageSpacing: CGFloat = 10
    let pageColumnSpacing: CGFloat = 10
    let cardSpacing: CGFloat = 10

    var innerWidth: CGFloat { max(containerSize.width - (horizontalPadding * 2), 0) }
    var innerHeight: CGFloat { max(containerSize.height - topPadding - bottomPadding, 0) }
    var pageHeight: CGFloat { max(innerHeight - tabSwitcherHeight - tabToPageSpacing, 0) }

    var mediaColumnWidth: CGFloat { min(max(innerWidth * 0.52, 228), 272) }
    var shortcutsColumnWidth: CGFloat { min(max(innerWidth * 0.28, 150), 176) }
    var dividerHeight: CGFloat { min(max(pageHeight - 10, 100), pageHeight) }
    var trayAirDropWidth: CGFloat { min(max(innerWidth * 0.29, 150), 188) }
    var timerHeaderHeight: CGFloat { 24 }
    var timerControlsHeight: CGFloat { pageHeight < 150 ? 24 : 28 }
    var timerVerticalSpacingTotal: CGFloat { pageHeight < 150 ? 18 : 20 }
    var timerReservedHeight: CGFloat { timerHeaderHeight + timerControlsHeight + timerVerticalSpacingTotal }
    var timerRingSize: CGFloat { min(max(pageHeight - timerReservedHeight, 86), 118) }
    var mediaMaxHeight: CGFloat { pageHeight }
    var shortcutsMaxHeight: CGFloat { pageHeight }
    var statsCardWidth: CGFloat { max((innerWidth - (cardSpacing * 2)) / 3, 0) }
    var statsCardHeight: CGFloat { min(max((pageHeight - cardSpacing) / 2, 64), 74) }
}

struct IslandRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var islandState: IslandStateStore
    @ObservedObject var layoutStore: IslandLayoutStore
    let modules: IslandModules
    let rendersExpandedVisualContent: Bool
    let onRequestExpand: () -> Void
    let onRequestCollapse: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentPhase: IslandContentPhase = .compact
    @State private var renderedContentMode: RenderedContentMode = .compact
    @State private var contentVisible = false
    @State private var expandedContentMounted = false
    @State private var isContentRemoving = false
    @State private var sequenceGeneration = 0

    private var isExpanded: Bool {
        islandState.state == .expanded
    }

    private var showsExpandedContent: Bool {
        renderedContentMode == .expanded
    }

    private var shellAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.24)
        }
        return .smooth(duration: 0.40)
    }

    private var shellMorphProgress: CGFloat {
        let collapsedHeight = max(layoutStore.collapsedSize.height, 1)
        let expandedHeight = max(layoutStore.expandedSize.height, collapsedHeight + 1)
        let progress = (surfaceFrame.height - collapsedHeight) / (expandedHeight - collapsedHeight)
        return min(max(progress, 0), 1)
    }

    private var shellBottomRadius: CGFloat {
        let collapsedRadius: CGFloat = 22
        let expandedRadius: CGFloat = 36
        let interpolated = collapsedRadius + ((expandedRadius - collapsedRadius) * shellMorphProgress)
        return min(interpolated, surfaceFrame.height / 2)
    }

    private var shellVisualProgress: CGFloat {
        shellMorphProgress
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            IslandSurface(
                isExpanded: isExpanded,
                bottomRadius: shellBottomRadius,
                visualProgress: shellVisualProgress
            ) {
                if showsExpandedContent {
                    ExpandedIslandView(
                        modules: modules,
                        contentVisible: contentVisible,
                        shouldRenderContent: expandedContentMounted,
                        isContentRemoving: isContentRemoving,
                        onShortcutLaunched: onRequestCollapse,
                        rendersExpandedVisualContent: rendersExpandedVisualContent
                    )
                } else {
                    CompactIslandView(modules: modules)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onRequestExpand()
                        }
                }
            }
            .notchIntegrated(layoutStore.hasHardwareNotch)
            .shellMorphing(layoutStore.isShellMorphing)
            .collapseShellOnly(layoutStore.isCollapseShellOnly)
            .frame(width: surfaceSize.width, height: surfaceSize.height)
            .position(x: surfaceFrame.midX, y: layoutStore.canvasSize.height - surfaceFrame.midY)
        }
        .shellMorphing(layoutStore.isShellMorphing)
        .collapseShellOnly(layoutStore.isCollapseShellOnly)
        .frame(width: layoutStore.canvasSize.width, height: layoutStore.canvasSize.height, alignment: .topLeading)
        .onAppear {
            synchronizePresentationForCurrentState()
        }
        .onChange(of: islandState.state) { _, newValue in
            handleStateChange(newValue)
        }
        .onChange(of: layoutStore.isExpandedContentExiting) { _, newValue in
            if newValue {
                beginContentExitSequence()
            }
        }
        .onChange(of: layoutStore.isCollapseShellOnly) { _, newValue in
            if !newValue, islandState.state == .collapsed {
                finalizeCompactPresentation()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: fileDropTargetBinding) { providers in
            loadDroppedFiles(from: providers)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DynamicIsland")
        .animation(shellAnimation, value: islandState.state)
        .animation(shellAnimation, value: layoutStore.isShellMorphing)
    }

    private var surfaceSize: CGSize {
        surfaceFrame.size
    }

    private var surfaceFrame: CGRect {
        isExpanded ? layoutStore.expandedSurfaceFrame : layoutStore.collapsedSurfaceFrame
    }

    private var fileDropTargetBinding: Binding<Bool> {
        Binding(
            get: { modules.navigation.isFileDropTargeted },
            set: { isTargeted in
                if isTargeted {
                    modules.navigation.showTrayForFileDrag()
                    onRequestExpand()
                } else {
                    modules.navigation.setFileDropTargeted(false)
                }
            }
        )
    }

    private func loadDroppedFiles(from providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
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
                    Task { @MainActor in
                        modules.fileShelf.add([url])
                        modules.navigation.setFileDropTargeted(false)
                    }
                }
            }
        }
    }

    private func synchronizePresentationForCurrentState() {
        if islandState.state == .expanded {
            startExpansionSequence()
        } else {
            finalizeCompactPresentation()
        }
    }

    private func handleStateChange(_ state: IslandPresentationState) {
        switch state {
        case .expanded:
            startExpansionSequence()
        case .collapsed:
            beginShellCollapseSequence()
        }
    }

    private func startExpansionSequence() {
        sequenceGeneration += 1
        let generation = sequenceGeneration
        renderedContentMode = .expanded
        expandedContentMounted = false
        contentVisible = false
        isContentRemoving = false
        contentPhase = .shellExpanding

        let mountDelay: DispatchTimeInterval = reduceMotion ? .milliseconds(40) : .milliseconds(240)
        DispatchQueue.main.asyncAfter(deadline: .now() + mountDelay) {
            guard generation == sequenceGeneration else { return }
            guard islandState.state == .expanded else { return }
            guard !layoutStore.isExpandedContentExiting else { return }
            expandedContentMounted = true
            contentVisible = false
            isContentRemoving = false
            let revealDelay: DispatchTimeInterval = reduceMotion ? .milliseconds(0) : .milliseconds(20)
            DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) {
                guard generation == sequenceGeneration else { return }
                guard islandState.state == .expanded else { return }
                guard expandedContentMounted else { return }
                guard !layoutStore.isExpandedContentExiting else { return }
                contentVisible = true
                isContentRemoving = false
                contentPhase = .expandedContentVisible
            }
        }
    }

    private func beginContentExitSequence() {
        sequenceGeneration += 1
        renderedContentMode = .expanded
        contentVisible = false
        isContentRemoving = expandedContentMounted
        contentPhase = .contentCollapsing
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
private struct InnerBlurScaleCleanModifier: ViewModifier {
    let isVisible: Bool
    let isRemoval: Bool
    let delay: Double
    let reduceMotion: Bool

    private var scale: CGFloat {
        if reduceMotion { return 1.0 }
        if isVisible { return 1.0 }
        return isRemoval ? 0.97 : 0.955
    }

    private var blur: CGFloat {
        if reduceMotion { return 0 }
        if isVisible { return 0 }
        return isRemoval ? 6 : 8
    }

    private var opacity: Double {
        if isVisible { return 1 }
        return isRemoval ? 0 : 1
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .center)
            .opacity(opacity)
            .animation(animation, value: isVisible)
    }

    private var animation: Animation {
        if isVisible {
            return .easeOut(duration: reduceMotion ? 0.10 : 0.22)
                .delay(reduceMotion ? 0 : delay)
        }

        return .easeIn(duration: reduceMotion ? 0.10 : 0.18)
            .delay(reduceMotion ? 0 : max(0, delay * 0.35))
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

private extension View {
    func innerBlurScaleClean(
        isVisible: Bool,
        isRemoval: Bool,
        index: Int,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            InnerBlurScaleCleanModifier(
                isVisible: isVisible,
                isRemoval: isRemoval,
                delay: Double(index) * 0.035,
                reduceMotion: reduceMotion
            )
        )
    }
}

struct IslandSurface<Content: View>: View {
    let isExpanded: Bool
    let bottomRadius: CGFloat
    let visualProgress: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.isNotchIntegratedShell) private var isNotchIntegratedShell
    @Environment(\.isShellMorphing) private var isShellMorphing
    @Environment(\.isCollapseShellOnly) private var isCollapseShellOnly

    var body: some View {
        let shellColor = Color(red: 0.001, green: 0.001, blue: 0.002)
        let shellShape = IslandShellShape(bottomRadius: bottomRadius)
        let shouldShowShoulderBlend = notchShoulderBlendEnabled && isNotchIntegratedShell
        let usesExpandedContentPadding = isExpanded || isCollapseShellOnly
        let strokeOpacity = 0.035 + ((0.07 - 0.035) * Double(visualProgress))
        let shadowOpacity = isShellMorphing ? 0.22 : 0.34
        let collapsedShadowRadius: CGFloat = isShellMorphing ? 5 : 8
        let expandedShadowRadius: CGFloat = isShellMorphing ? 14 : 22
        let collapsedShadowY: CGFloat = isShellMorphing ? 2 : 3
        let expandedShadowY: CGFloat = isShellMorphing ? 6 : 10
        let shadowRadius = collapsedShadowRadius + ((expandedShadowRadius - collapsedShadowRadius) * visualProgress)
        let shadowY = collapsedShadowY + ((expandedShadowY - collapsedShadowY) * visualProgress)

        ZStack {
            if shouldShowShoulderBlend {
                NotchShoulderBlend(isExpanded: isExpanded, shellColor: shellColor)
            }

            shellShape
                .fill(shellColor)
                .overlay {
                    shellShape
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                }
                .shadow(
                    color: .black.opacity(shadowOpacity),
                    radius: shadowRadius,
                    y: shadowY
                )

            content
                .padding(.horizontal, usesExpandedContentPadding ? 0 : IslandShellLayout.collapsedHorizontalPadding)
                .padding(.top, usesExpandedContentPadding ? 0 : IslandShellLayout.collapsedTopPadding)
                .padding(.bottom, usesExpandedContentPadding ? 0 : IslandShellLayout.collapsedBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(shellShape)
        }
    }
}

private struct IslandShellShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, min(rect.width, rect.height) / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct CompactIslandView: View {
    let modules: IslandModules
    @ObservedObject private var media: MediaController
    @ObservedObject private var accentCache = ArtworkAccentColorCache.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(modules: IslandModules) {
        self.modules = modules
        media = modules.media
    }

    var body: some View {
        let activeBranch = media.hasActiveMediaSource
        let visualizerColor = accentCache.color(for: media.artworkKey, image: media.artworkImage)
        let _ = Self.debugRender(
            hasActiveMediaSource: media.hasActiveMediaSource,
            isPlaying: media.isPlaying,
            title: media.title,
            sourceName: media.sourceName,
            branch: activeBranch ? "active compact" : "inactive compact"
        )

        ZStack {
            if activeBranch {
                HStack(spacing: 10) {
                    CompactMediaView(media: media)
                    Spacer(minLength: 0)
                    AudioVisualizerView(
                        isPlaying: media.isPlaying,
                        isActive: media.hasActiveMediaSource,
                        accentColor: visualizerColor,
                        variant: .compact
                    )
                }
                .transition(.compactMediaContent)
            } else {
                Color.clear
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(compactContentAnimation, value: media.hasActiveMediaSource)
    }

    private var compactContentAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .easeInOut(duration: 0.28)
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

struct ExpandedIslandView: View {
    let modules: IslandModules
    let contentVisible: Bool
    let shouldRenderContent: Bool
    let isContentRemoving: Bool
    let onShortcutLaunched: () -> Void
    let rendersExpandedVisualContent: Bool
    @ObservedObject private var navigation: IslandNavigationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isCollapseShellOnly) private var isCollapseShellOnly

    @State private var isAirDropTargeted = false
    @State private var isFilesTargeted = false

    init(
        modules: IslandModules,
        contentVisible: Bool,
        shouldRenderContent: Bool,
        isContentRemoving: Bool,
        onShortcutLaunched: @escaping () -> Void,
        rendersExpandedVisualContent: Bool = true
    ) {
        self.modules = modules
        self.contentVisible = contentVisible
        self.shouldRenderContent = shouldRenderContent
        self.isContentRemoving = isContentRemoving
        self.onShortcutLaunched = onShortcutLaunched
        self.rendersExpandedVisualContent = rendersExpandedVisualContent
        navigation = modules.navigation
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = ExpandedIslandLayoutMetrics(containerSize: proxy.size)

            VStack(alignment: .leading, spacing: metrics.tabToPageSpacing) {
                ZStack(alignment: .leading) {
                    if rendersExpandedVisualContent && shouldRenderContent && !isCollapseShellOnly {
                        ExpandedIslandPageSwitcher(navigation: navigation)
                            .innerBlurScaleClean(
                                isVisible: contentVisible,
                                isRemoval: isContentRemoving,
                                index: 0,
                                reduceMotion: reduceMotion
                            )
                    }
                }
                .frame(height: metrics.tabSwitcherHeight)

                ZStack(alignment: .topLeading) {
                    if !rendersExpandedVisualContent || !shouldRenderContent {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        switch navigation.selectedPage {
                        case .island:
                            islandPage(metrics: metrics)
                                .transition(pageTransition)
                        case .tray:
                            trayPage(metrics: metrics)
                                .transition(pageTransition)
                        case .timer:
                            timerPage(metrics: metrics)
                                .transition(pageTransition)
                        case .stats:
                            statsPage(metrics: metrics)
                                .transition(pageTransition)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: metrics.pageHeight, alignment: .topLeading)
                .clipped()
                .animation(pageAnimation, value: navigation.selectedPage)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.topPadding)
            .padding(.bottom, metrics.bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func islandPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        HStack(spacing: metrics.pageColumnSpacing) {
            MediaModuleView(
                media: modules.media,
                availableHeight: metrics.mediaMaxHeight,
                onLauncherActivated: onShortcutLaunched,
                onMediaSourceOpened: onShortcutLaunched
            )
                .frame(width: metrics.mediaColumnWidth, height: metrics.mediaMaxHeight, alignment: .topLeading)
                .clipped()
                .innerBlurScaleClean(
                    isVisible: contentVisible,
                    isRemoval: isContentRemoving,
                    index: 1,
                    reduceMotion: reduceMotion
                )

            Divider()
                .frame(height: metrics.dividerHeight)
                .overlay(.white.opacity(0.10))
                .opacity(contentVisible ? 1 : 0)

            ShortcutsModuleView(
                shortcuts: modules.shortcuts,
                onShortcutLaunched: onShortcutLaunched
            )
                .frame(width: metrics.shortcutsColumnWidth, height: metrics.shortcutsMaxHeight, alignment: .topLeading)
                .clipped()
                .innerBlurScaleClean(
                    isVisible: contentVisible,
                    isRemoval: isContentRemoving,
                    index: 2,
                    reduceMotion: reduceMotion
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func trayPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: metrics.pageColumnSpacing) {
                AirDropDropZoneView(
                    isTargeted: isAirDropTargeted,
                    reduceMotion: reduceMotion
                )
                .frame(width: min(max(metrics.trayAirDropWidth, 142), proxy.size.width * 0.36), height: proxy.size.height, alignment: .topLeading)
                .onDrop(of: [.fileURL], isTargeted: airDropTargetBinding) { providers in
                    shareDroppedFiles(from: providers)
                    return true
                }
                .innerBlurScaleClean(
                    isVisible: contentVisible,
                    isRemoval: isContentRemoving,
                    index: 1,
                    reduceMotion: reduceMotion
                )

                FileShelfModuleView(fileShelf: modules.fileShelf)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if isFilesTargeted || (navigation.isFileDropTargeted && !isAirDropTargeted) {
                            FileDropHighlightView(reduceMotion: reduceMotion)
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: filesTargetBinding) { providers in
                        loadDroppedFiles(from: providers)
                        return true
                    }
                    .innerBlurScaleClean(
                        isVisible: contentVisible,
                        isRemoval: isContentRemoving,
                        index: 2,
                        reduceMotion: reduceMotion
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func timerPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        DedicatedTimerPageView(
            timer: modules.timer,
            ringSize: metrics.timerRingSize,
            pageHeight: metrics.pageHeight
        )
            .innerBlurScaleClean(
                isVisible: contentVisible,
                isRemoval: isContentRemoving,
                index: 1,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statsPage(metrics: ExpandedIslandLayoutMetrics) -> some View {
        StatsPageView(stats: modules.stats, metrics: metrics)
            .innerBlurScaleClean(
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
                if isTargeted {
                    navigation.showTrayForFileDrag()
                } else {
                    navigation.setFileDropTargeted(false)
                }
            }
        )
    }

    private var airDropTargetBinding: Binding<Bool> {
        Binding(
            get: { isAirDropTargeted },
            set: { isTargeted in
                isAirDropTargeted = isTargeted
                if isTargeted {
                    navigation.showTrayForFileDrag()
                }
            }
        )
    }

    private var filesTargetBinding: Binding<Bool> {
        Binding(
            get: { isFilesTargeted },
            set: { isTargeted in
                isFilesTargeted = isTargeted
                if isTargeted {
                    navigation.showTrayForFileDrag()
                }
            }
        )
    }

    private func loadDroppedFiles(from providers: [NSItemProvider]) {
        loadFileURLs(from: providers) { urls in
            Task { @MainActor in
                if !urls.isEmpty {
                    modules.fileShelf.add(urls)
                }
                isFilesTargeted = false
                navigation.setFileDropTargeted(false)
            }
        }
    }

    private func shareDroppedFiles(from providers: [NSItemProvider]) {
        loadFileURLs(from: providers) { urls in
            Task { @MainActor in
                if !urls.isEmpty {
                    AirDropService.share(urls: urls)
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
        let accumulator = FileDropURLAccumulator()

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

    private var pageTransition: AnyTransition {
        if reduceMotion {
            return .identity
        }

        return .asymmetric(
            insertion: .modifier(
                active: BlurBounceModifier(blur: 8, scale: 0.96, opacity: 1),
                identity: BlurBounceModifier(blur: 0, scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: BlurBounceModifier(blur: 6, scale: 0.97, opacity: 1),
                identity: BlurBounceModifier(blur: 0, scale: 1, opacity: 1)
            )
        )
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.20)
    }
}

private struct CompactHandoffGhostView: View {
    let modules: IslandModules
    @ObservedObject private var media: MediaController
    @ObservedObject private var accentCache = ArtworkAccentColorCache.shared

    init(modules: IslandModules) {
        self.modules = modules
        media = modules.media
    }

    var body: some View {
        let accentColor = accentCache.color(for: media.artworkKey, image: media.artworkImage)

        ZStack {
            if media.hasActiveMediaSource {
                HStack(spacing: 10) {
                    if disableCollapsedArtworkDuringHandoff {
                        Color.clear
                            .frame(width: 14, height: 14)
                    } else {
                        CompactMediaView(media: media)
                    }

                    Spacer(minLength: 0)

                    if disableCollapsedVisualizerDuringHandoff {
                        Color.clear
                            .frame(width: AudioVisualizerVariant.compact.size.width, height: AudioVisualizerVariant.compact.size.height)
                    } else {
                        AudioVisualizerView(
                            isPlaying: media.isPlaying,
                            isActive: media.hasActiveMediaSource,
                            accentColor: accentColor,
                            variant: .compact
                        )
                    }
                }
            } else {
                Color.clear
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if collapseHandoffDebug {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.red.opacity(0.9), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.green.opacity(0.22))
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

private final class FileDropURLAccumulator: @unchecked Sendable {
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

private struct ExpandedIslandPageSwitcher: View {
    @ObservedObject var navigation: IslandNavigationStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ExpandedIslandPage.allCases, id: \.self) { page in
                Button {
                    switch page {
                    case .island:
                        navigation.showIsland()
                    case .tray:
                        navigation.showTray()
                    case .timer:
                        navigation.showTimer()
                    case .stats:
                        navigation.showStats()
                    }
                } label: {
                    Image(systemName: page.symbolName)
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 26)
                        .foregroundStyle(.white.opacity(navigation.selectedPage == page ? 1 : 0.48))
                        .background {
                            if navigation.selectedPage == page {
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.14))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.accessibilityLabel)
                .help(page.title)
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

private struct StatsPageView: View {
    @ObservedObject var stats: SystemStatsController
    let metrics: ExpandedIslandLayoutMetrics

    var body: some View {
        let snapshot = stats.snapshot

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Stats", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                LiveStatusIndicator()
                Spacer(minLength: 0)
                Text(batteryStatusText(snapshot))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            VStack(spacing: metrics.cardSpacing) {
                HStack(spacing: metrics.cardSpacing) {
                    StatsMetricCard(
                        title: "CPU",
                        symbol: "cpu",
                        value: "\(Int((snapshot.cpuUsage * 100).rounded()))%",
                        detail: "System load",
                        accent: .cyan,
                        fraction: snapshot.cpuUsage,
                        history: snapshot.cpuHistory,
                        width: metrics.statsCardWidth,
                        height: metrics.statsCardHeight
                    )

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
                        height: metrics.statsCardHeight
                    )

                    StatsMetricCard(
                        title: "GPU",
                        symbol: "display",
                        value: "Unavailable",
                        detail: "No reliable API",
                        accent: .orange,
                        fraction: nil,
                        history: [],
                        width: metrics.statsCardWidth,
                        height: metrics.statsCardHeight
                    )
                }

                HStack(spacing: metrics.cardSpacing) {
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
                        height: metrics.statsCardHeight
                    )

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
                        height: metrics.statsCardHeight
                    )

                    StatsMetricCard(
                        title: "Battery",
                        symbol: "battery.75percent",
                        value: batteryText(snapshot),
                        detail: batteryDetail(snapshot),
                        secondary: "Uptime \(uptimeText(snapshot.uptimeSeconds))",
                        accent: .mint,
                        fraction: snapshot.batteryPercent,
                        history: batteryHistory(snapshot),
                        width: metrics.statsCardWidth,
                        height: metrics.statsCardHeight
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent.opacity(0.95))
                    .frame(width: 22, height: 22)
                    .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
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
            .frame(height: 13)

            HStack(spacing: 5) {
                Text(detail)
                if let secondary {
                    Spacer(minLength: 3)
                    Text(secondary)
                }
            }
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.42))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(8)
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

private struct AirDropDropZoneView: View {
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
                Text("Drop files here to share")
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

private struct DedicatedTimerPageView: View {
    @ObservedObject var timer: TimerController
    let ringSize: CGFloat
    let pageHeight: CGFloat
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

            TimerProgressRingView(
                progress: TimerProgressFormatting.progress(
                    remainingSeconds: timer.remainingSeconds,
                    totalSeconds: timer.totalSeconds
                ),
                remainingText: timer.displayText,
                isRunning: timer.isRunning,
                ringSize: ringSize
            )
            .frame(maxWidth: .infinity)

            ViewThatFits(in: .horizontal) {
                timerControlRow
                timerControlStack
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var timerControlRow: some View {
        HStack(spacing: controlsSpacing) {
            Button("5m") { timer.start(minutes: 5) }
            Button("10m") { timer.start(minutes: 10) }
            Button("15m") { timer.start(minutes: 15) }

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
                Button("5m") { timer.start(minutes: 5) }
                Button("10m") { timer.start(minutes: 10) }
                Button("15m") { timer.start(minutes: 15) }
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
}

private struct TimerProgressRingView: View {
    let progress: Double
    let remainingText: String
    let isRunning: Bool
    let ringSize: CGFloat
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
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: clampedProgress)

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
