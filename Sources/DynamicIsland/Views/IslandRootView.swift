import SwiftUI
import UniformTypeIdentifiers

struct IslandRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var islandState: IslandStateStore
    @ObservedObject var layoutStore: IslandLayoutStore
    let modules: IslandModules
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool {
        islandState.state == .expanded
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            IslandSurface(isExpanded: isExpanded) {
                if isExpanded {
                    ExpandedIslandView(
                        modules: modules,
                        isPresented: isExpanded,
                        onShortcutLaunched: { islandState.collapse() }
                    )
                        .transition(.blurBounce)
                } else {
                    CompactIslandView(modules: modules)
                        .transition(.blurBounce)
                }
            }
            .frame(width: surfaceSize.width, height: surfaceSize.height)
            .position(x: surfaceFrame.midX, y: layoutStore.canvasSize.height - surfaceFrame.midY)
        }
        .frame(width: layoutStore.canvasSize.width, height: layoutStore.canvasSize.height, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: fileDropTargetBinding) { providers in
            loadDroppedFiles(from: providers)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DynamicIsland")
        .animation(contentAnimation, value: islandState.state)
        .animation(contentAnimation, value: layoutStore.collapsedSize)
        .animation(contentAnimation, value: layoutStore.collapsedSurfaceFrame)
    }

    private var surfaceSize: CGSize {
        surfaceFrame.size
    }

    private var surfaceFrame: CGRect {
        isExpanded ? layoutStore.expandedSurfaceFrame : layoutStore.collapsedSurfaceFrame
    }

    /// Keep the main tray/container elastic. This is intentionally separate from
    /// the inner module animation below.
    private var contentAnimation: Animation {
        if reduceMotion {
            .easeInOut(duration: 0.75)
        } else {
            .spring(response: 0.58, dampingFraction: 0.76, blendDuration: 0.25)
        }
    }

    private var fileDropTargetBinding: Binding<Bool> {
        Binding(
            get: { modules.navigation.isFileDropTargeted },
            set: { modules.navigation.setFileDropTargeted($0) }
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
}

private struct BlurBounceModifier: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale)
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
        return isRemoval ? 0.86 : 0.74
    }

    private var blur: CGFloat {
        if reduceMotion { return 0 }
        if isVisible { return 0 }
        return isRemoval ? 10 : 16
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .center)
            .opacity(isVisible ? 1 : 0)
            .animation(animation, value: isVisible)
    }

    private var animation: Animation {
        if isVisible {
            return .easeOut(duration: reduceMotion ? 0.25 : 0.5)
                .delay(reduceMotion ? 0 : delay)
        }

        return .easeIn(duration: reduceMotion ? 0.25 : 0.5)
            .delay(reduceMotion ? 0 : max(0, delay * 0.35))
    }
}

private extension AnyTransition {
    static var blurBounce: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurBounceModifier(blur: 100, scale: 0.1, opacity: 0.0),
                identity: BlurBounceModifier(blur: 0, scale: 1.0, opacity: 1.0)
            ),
            removal: .modifier(
                active: BlurBounceModifier(blur: 100, scale: 0.1, opacity: 0.0),
                identity: BlurBounceModifier(blur: 0, scale: 1.0, opacity: 1.0)
            )
        )
    }

    static var compactMediaContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurBounceModifier(blur: 10, scale: 0.72, opacity: 0.0),
                identity: BlurBounceModifier(blur: 0, scale: 1.0, opacity: 1.0)
            ),
            removal: .modifier(
                active: BlurBounceModifier(blur: 8, scale: 0.82, opacity: 0.0),
                identity: BlurBounceModifier(blur: 0, scale: 1.0, opacity: 1.0)
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
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, isExpanded ? 22 : 8)
            .padding(.top, isExpanded ? 42 : 0)
            .padding(.bottom, isExpanded ? 20 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: isExpanded ? 36 : 22,
                    bottomTrailingRadius: isExpanded ? 36 : 22,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color(red: 0.001, green: 0.001, blue: 0.002))
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: isExpanded ? 36 : 22,
                        bottomTrailingRadius: isExpanded ? 36 : 22,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(isExpanded ? 0.07 : 0.035), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.34), radius: isExpanded ? 22 : 8, y: isExpanded ? 10 : 3)
            }
    }
}

struct CompactIslandView: View {
    let modules: IslandModules
    @ObservedObject private var media: MediaController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(modules: IslandModules) {
        self.modules = modules
        media = modules.media
    }

    var body: some View {
        let activeBranch = media.hasActiveMediaSource
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
                    AudioVisualizerView(isPlaying: media.isPlaying)
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
        reduceMotion ? .easeInOut(duration: 0.16) : .easeInOut(duration: 0.24)
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
    let isPresented: Bool
    let onShortcutLaunched: () -> Void
    @ObservedObject private var navigation: IslandNavigationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showInnerContent = false
    @State private var isRemovingInnerContent = false
    @State private var presentationGeneration: Int = 0

    init(
        modules: IslandModules,
        isPresented: Bool,
        onShortcutLaunched: @escaping () -> Void
    ) {
        self.modules = modules
        self.isPresented = isPresented
        self.onShortcutLaunched = onShortcutLaunched
        navigation = modules.navigation
    }

    var body: some View {
        VStack(spacing: 14) {
            ExpandedIslandPageSwitcher(navigation: navigation)
                .opacity(showInnerContent ? 1 : 0)
                .animation(
                    .easeOut(duration: reduceMotion ? 0.10 : 0.20),
                    value: showInnerContent
                )

            Group {
                if navigation.selectedPage == .island {
                    islandPage
                        .transition(pageTransition)
                } else {
                    trayPage
                        .transition(pageTransition)
                }
            }
            .animation(pageAnimation, value: navigation.selectedPage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: fileDropTargetBinding) { providers in
            loadDroppedFiles(from: providers)
            return true
        }
        .onAppear {
            updateInnerPresentation(isPresented)
        }
        .onChange(of: isPresented) { _, newValue in
            updateInnerPresentation(newValue)
        }
    }

    private var islandPage: some View {
        HStack(spacing: 16) {
            MediaModuleView(
                media: modules.media,
                onLauncherActivated: onShortcutLaunched,
                onMediaSourceOpened: onShortcutLaunched
            )
                .frame(width: 300, alignment: .leading)
                .innerBlurScaleClean(
                    isVisible: showInnerContent,
                    isRemoval: isRemovingInnerContent,
                    index: 0,
                    reduceMotion: reduceMotion
                )

            Divider()
                .frame(height: 220)
                .overlay(.white.opacity(0.10))
                .opacity(showInnerContent ? 1 : 0)
                .animation(
                    .easeOut(duration: reduceMotion ? 0.10 : 0.22)
                        .delay(reduceMotion ? 0 : 0.075),
                    value: showInnerContent
                )

            ShortcutsModuleView(
                shortcuts: modules.shortcuts,
                onShortcutLaunched: onShortcutLaunched
            )
                .frame(width: 148)
                .innerBlurScaleClean(
                    isVisible: showInnerContent,
                    isRemoval: isRemovingInnerContent,
                    index: 1,
                    reduceMotion: reduceMotion
                )

            Divider()
                .frame(height: 220)
                .overlay(.white.opacity(0.10))
                .opacity(showInnerContent ? 1 : 0)
                .animation(
                    .easeOut(duration: reduceMotion ? 0.10 : 0.22)
                        .delay(reduceMotion ? 0 : 0.110),
                    value: showInnerContent
                )

            VStack(spacing: 14) {
                TimerModuleView(timer: modules.timer)
                    .innerBlurScaleClean(
                        isVisible: showInnerContent,
                        isRemoval: isRemovingInnerContent,
                        index: 2,
                        reduceMotion: reduceMotion
                    )
                Spacer(minLength: 0)
            }
            .frame(width: 168)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var trayPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Tray", systemImage: "tray.full")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Files you add will appear here")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .innerBlurScaleClean(
                isVisible: showInnerContent,
                isRemoval: isRemovingInnerContent,
                index: 0,
                reduceMotion: reduceMotion
            )

            FileShelfModuleView(fileShelf: modules.fileShelf)
                .frame(maxWidth: .infinity)
                .overlay {
                    if navigation.isFileDropTargeted {
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
                .innerBlurScaleClean(
                    isVisible: showInnerContent,
                    isRemoval: isRemovingInnerContent,
                    index: 1,
                    reduceMotion: reduceMotion
                )

            Spacer(minLength: 0)
        }
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

    private func loadDroppedFiles(from providers: [NSItemProvider]) {
        var acceptedProvider = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            acceptedProvider = true
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

                Task { @MainActor in
                    if let url {
                        modules.fileShelf.add([url])
                    }
                    navigation.setFileDropTargeted(false)
                }
            }
        }

        if !acceptedProvider {
            navigation.setFileDropTargeted(false)
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .modifier(
                active: BlurBounceModifier(blur: 0, scale: 0.985, opacity: 0),
                identity: BlurBounceModifier(blur: 0, scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: BlurBounceModifier(blur: 0, scale: 0.992, opacity: 0),
                identity: BlurBounceModifier(blur: 0, scale: 1, opacity: 1)
            )
        )
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.16)
    }

    private func updateInnerPresentation(_ presented: Bool) {
        presentationGeneration += 1
        let generation = presentationGeneration

        if presented {
            if !navigation.isFileDropTargeted {
                navigation.showIsland()
            }
            isRemovingInnerContent = false
            showInnerContent = false

            let delay: DispatchTimeInterval = reduceMotion ? .milliseconds(0) : .milliseconds(75)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard generation == presentationGeneration, isPresented else { return }
                isRemovingInnerContent = false
                showInnerContent = true
            }
        } else {
            isRemovingInnerContent = true
            showInnerContent = false
        }
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
                    }
                } label: {
                    Label(page.title, systemImage: page.symbolName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
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
