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
            .notchIntegrated(layoutStore.hasHardwareNotch)
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
    @Environment(\.isNotchIntegratedShell) private var isNotchIntegratedShell

    var body: some View {
        let shellColor = Color(red: 0.001, green: 0.001, blue: 0.002)
        let shellShape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: isExpanded ? 36 : 22,
            bottomTrailingRadius: isExpanded ? 36 : 22,
            topTrailingRadius: 0,
            style: .continuous
        )
        let shouldShowShoulderBlend = notchShoulderBlendEnabled && isNotchIntegratedShell

        content
            .padding(.horizontal, isExpanded ? 22 : 8)
            .padding(.top, isExpanded ? 14 : 0)
            .padding(.bottom, isExpanded ? 20 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    if shouldShowShoulderBlend {
                        NotchShoulderBlend(isExpanded: isExpanded, color: shellColor)
                    }

                    shellShape
                        .fill(shellColor)
                        .overlay {
                            shellShape
                                .stroke(Color.white.opacity(isExpanded ? 0.07 : 0.035), lineWidth: 1)
                        }
                }
                .shadow(color: .black.opacity(0.34), radius: isExpanded ? 22 : 8, y: isExpanded ? 10 : 3)
            }
    }
}

private let notchShoulderBlendEnabled = true

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
    @State private var isAirDropTargeted = false
    @State private var isFilesTargeted = false

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
        VStack(alignment: .leading, spacing: 8) {
            ExpandedIslandPageSwitcher(navigation: navigation)
                .opacity(showInnerContent ? 1 : 0)
                .animation(
                    .easeOut(duration: reduceMotion ? 0.10 : 0.20),
                    value: showInnerContent
                )

            Group {
                switch navigation.selectedPage {
                case .island:
                    islandPage
                        .transition(pageTransition)
                case .tray:
                    trayPage
                        .transition(pageTransition)
                case .timer:
                    timerPage
                        .transition(pageTransition)
                case .stats:
                    statsPage
                        .transition(pageTransition)
                }
            }
            .animation(pageAnimation, value: navigation.selectedPage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                .frame(width: 190)
                .innerBlurScaleClean(
                    isVisible: showInnerContent,
                    isRemoval: isRemovingInnerContent,
                    index: 1,
                    reduceMotion: reduceMotion
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var trayPage: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 14) {
                AirDropDropZoneView(
                    isTargeted: isAirDropTargeted,
                    reduceMotion: reduceMotion
                )
                .frame(width: max(180, proxy.size.width * 0.32), height: proxy.size.height, alignment: .topLeading)
                .onDrop(of: [.fileURL], isTargeted: airDropTargetBinding) { providers in
                    shareDroppedFiles(from: providers)
                    return true
                }
                .innerBlurScaleClean(
                    isVisible: showInnerContent,
                    isRemoval: isRemovingInnerContent,
                    index: 0,
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
                        isVisible: showInnerContent,
                        isRemoval: isRemovingInnerContent,
                        index: 1,
                        reduceMotion: reduceMotion
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var timerPage: some View {
        DedicatedTimerPageView(timer: modules.timer)
            .innerBlurScaleClean(
                isVisible: showInnerContent,
                isRemoval: isRemovingInnerContent,
                index: 0,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statsPage: some View {
        StatsPageView(stats: modules.stats)
            .innerBlurScaleClean(
                isVisible: showInnerContent,
                isRemoval: isRemovingInnerContent,
                index: 0,
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

    var body: some View {
        let snapshot = stats.snapshot

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Stats", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                LiveStatusIndicator()
                Spacer(minLength: 0)
                Text(batteryStatusText(snapshot))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatsMetricCard(
                        title: "CPU",
                        symbol: "cpu",
                        value: "\(Int((snapshot.cpuUsage * 100).rounded()))%",
                        detail: "System load",
                        accent: .cyan,
                        fraction: snapshot.cpuUsage,
                        history: snapshot.cpuHistory
                    )

                    StatsMetricCard(
                        title: "Memory",
                        symbol: "memorychip",
                        value: percentText(fraction(used: snapshot.memoryUsedBytes, total: snapshot.memoryTotalBytes)),
                        detail: usedTotalText(used: snapshot.memoryUsedBytes, total: snapshot.memoryTotalBytes),
                        secondary: "Cached \(SystemStatsFormatting.formatBytes(snapshot.memoryCachedBytes))",
                        accent: .purple,
                        fraction: fraction(used: snapshot.memoryUsedBytes, total: snapshot.memoryTotalBytes),
                        history: snapshot.memoryHistory
                    )

                    StatsMetricCard(
                        title: "GPU",
                        symbol: "display",
                        value: "Unavailable",
                        detail: "No reliable API",
                        accent: .orange,
                        fraction: nil,
                        history: []
                    )
                }

                HStack(spacing: 12) {
                    StatsMetricCard(
                        title: "Network",
                        symbol: "network",
                        value: networkText(snapshot),
                        detail: "Current transfer",
                        secondary: "↑ \(SystemStatsFormatting.formatBytesPerSecond(snapshot.networkUploadBytesPerSecond))",
                        accent: .green,
                        fraction: nil,
                        history: snapshot.networkDownloadHistory,
                        secondaryHistory: snapshot.networkUploadHistory
                    )

                    StatsMetricCard(
                        title: "Disk",
                        symbol: "internaldrive",
                        value: percentText(fraction(used: snapshot.diskUsedBytes, total: snapshot.diskTotalBytes)),
                        detail: usedTotalText(used: snapshot.diskUsedBytes, total: snapshot.diskTotalBytes),
                        secondary: "Startup volume",
                        accent: .blue,
                        fraction: fraction(used: snapshot.diskUsedBytes, total: snapshot.diskTotalBytes),
                        history: snapshot.diskHistory
                    )

                    StatsMetricCard(
                        title: "Battery",
                        symbol: "battery.75percent",
                        value: batteryText(snapshot),
                        detail: batteryDetail(snapshot),
                        secondary: "Uptime \(uptimeText(snapshot.uptimeSeconds))",
                        accent: .mint,
                        fraction: snapshot.batteryPercent,
                        history: batteryHistory(snapshot)
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
        .frame(width: 208, height: 76, alignment: .topLeading)
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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                chartPath(values: values, size: proxy.size)
                    .stroke(accent.opacity(0.86), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if !secondaryValues.isEmpty {
                    chartPath(values: secondaryValues, size: proxy.size)
                        .stroke(.white.opacity(0.42), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Timer", systemImage: "timer")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            TimerProgressRingView(
                progress: TimerProgressFormatting.progress(
                    remainingSeconds: timer.remainingSeconds,
                    totalSeconds: timer.totalSeconds
                ),
                remainingText: timer.displayText,
                isRunning: timer.isRunning
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Button("5m") { timer.start(minutes: 5) }
                Button("10m") { timer.start(minutes: 10) }
                Button("15m") { timer.start(minutes: 15) }

                Divider()
                    .frame(height: 24)
                    .overlay(.white.opacity(0.12))

                Button(timer.isRunning ? "Pause" : "Resume") {
                    timer.isRunning ? timer.pause() : timer.resume()
                }
                .disabled(timer.remainingSeconds <= 0)

                Button("Reset") { timer.reset() }
                    .disabled(timer.remainingSeconds <= 0)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .bold, design: .rounded))

            Spacer(minLength: 0)
        }
        .padding(.top, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TimerProgressRingView: View {
    let progress: Double
    let remainingText: String
    let isRunning: Bool
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

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.10), style: StrokeStyle(lineWidth: 13, lineCap: .round))

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(reduceMotion ? 0 : 0.32), radius: reduceMotion ? 0 : 10)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: clampedProgress)

            VStack(spacing: 3) {
                Text(remainingText)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
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
        .frame(width: 150, height: 150)
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
