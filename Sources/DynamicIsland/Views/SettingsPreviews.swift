import AppKit
import SwiftUI

// MARK: - Sandbox environment

private struct SettingsPreviewEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a Settings preview sandbox. Production components use it
    /// to skip real side effects (e.g. the camera mirror never starts
    /// capture inside Settings).
    var isSettingsPreview: Bool {
        get { self[SettingsPreviewEnvironmentKey.self] }
        set { self[SettingsPreviewEnvironmentKey.self] = newValue }
    }
}

/// Dependencies the Settings previews render with: the app's own
/// production objects (read-only in the sandbox) plus explicitly labeled
/// preview-only objects that never escape Settings.
@MainActor
struct SettingsPreviewDependencies {
    let timer: TimerController
    let stats: SystemStatsController
    let clipboardHistory: ClipboardHistoryStore
    let shortcuts: ShortcutsStore
    let rightWorkspace: RightWorkspaceStore
    let workspaceServices: WorkspaceServices
    let agentManagedControl: AgentManagedSessionController?
    let productivity: ProductivityModules
    /// Preview-only: inert media controller with a labeled sample track.
    let previewMedia: MediaController
    /// Preview-only: shelf with sample system files for tray styling.
    let previewShelf: FileShelfStore
    /// Preview-only: background removal controller that never processes.
    let previewBackgroundRemoval: BackgroundRemovalController
}

/// Preview-only sample content. Referenced only from Settings files and the
/// composition root that builds `SettingsPreviewDependencies` (enforced by
/// a test).
@MainActor
enum SettingsPreviewFixtures {
    static let referenceDate = Date()

    static let sampleFileURLs: [URL] = [
        "/System/Applications/Calculator.app",
        "/System/Applications/TextEdit.app",
        "/System/Applications/Preview.app"
    ].map { URL(fileURLWithPath: $0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }

    static func previewShelf(settings: AppSettings) -> FileShelfStore {
        let suite = "com.local.dynamicisland.settings-preview.shelf"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let shelf = FileShelfStore(settings: settings, defaults: defaults)
        shelf.add(sampleFileURLs)
        if let first = shelf.files.first { shelf.select(first) }
        return shelf
    }

    static func agentSession(provider: AgentProvider) -> AgentSession {
        let now = referenceDate
        let correlation = AgentCorrelationID(rawValue: "preview-tool")
        return AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: provider, nativeID: "settings-preview"),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .desktopApp,
            state: .runningTool,
            project: AgentProjectContext(displayName: "Preview project", model: "Preview model"),
            capabilities: AgentCapabilities(),
            usage: AgentUsage(),
            tools: [correlation: AgentTool(
                correlationID: correlation,
                name: "Read",
                category: "file",
                summary: nil,
                status: .active,
                startedAt: now.addingTimeInterval(-4),
                completedAt: nil,
                success: nil
            )],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: now.addingTimeInterval(-120),
            endedAt: nil,
            lastUpdatedAt: now
        )
    }

    static func transcript(provider: AgentProvider) -> [AgentManagedTranscriptEntry] {
        [
            AgentManagedTranscriptEntry(id: "p1", nativeSessionID: "settings-preview", turnID: "t", role: .user,
                                        text: "Preview: summarize the project layout", timestamp: referenceDate.addingTimeInterval(-30)),
            AgentManagedTranscriptEntry(id: "p2", nativeSessionID: "settings-preview", turnID: "t", role: .tool,
                                        text: "Read", timestamp: referenceDate.addingTimeInterval(-20)),
            AgentManagedTranscriptEntry(id: "p3", nativeSessionID: "settings-preview", turnID: "t", role: .agent,
                                        text: "Sample reply shown for styling only.", timestamp: referenceDate.addingTimeInterval(-10))
        ]
    }
}

// MARK: - Sandbox container

/// Hosts production components in an isolated, non-interactive preview.
/// Sample content is labeled; interaction is disabled so previews can never
/// trigger real operations.
struct SettingsPreviewSandbox<Controls: View, Content: View>: View {
    let title: String
    var usesSampleContent = false
    var showsReduceMotionToggle = false
    var height: CGFloat = 200
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var content: (_ reduceMotion: Bool) -> Content

    @State private var reduceMotion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(title, systemImage: "eye")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if usesSampleContent {
                    Text("Sample content")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                        .help("This preview uses sample data. Production views never use it.")
                }
                Spacer()
                controls()
                if showsReduceMotionToggle {
                    Toggle("Reduce Motion", isOn: $reduceMotion)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }
            }
            content(reduceMotion)
                .environment(\.isSettingsPreview, true)
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .padding(10)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(title) live preview")
        }
    }
}

extension SettingsPreviewSandbox where Controls == EmptyView {
    init(
        title: String,
        usesSampleContent: Bool = false,
        showsReduceMotionToggle: Bool = false,
        height: CGFloat = 200,
        @ViewBuilder content: @escaping (_ reduceMotion: Bool) -> Content
    ) {
        self.title = title
        self.usesSampleContent = usesSampleContent
        self.showsReduceMotionToggle = showsReduceMotionToggle
        self.height = height
        self.controls = { EmptyView() }
        self.content = content
    }
}

// MARK: - Island shell, tabs, motion

/// The production IslandSurface and page switcher, driven by the live
/// settings: dimensions, notch integration, theme, opacity, stroke, tabs
/// and shell animation.
struct IslandShellSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    @State private var expanded = true
    @StateObject private var navigation = IslandNavigationStore()

    var body: some View {
        SettingsPreviewSandbox(
            title: "Island Preview",
            showsReduceMotionToggle: true,
            height: 190,
            controls: {
                Picker("State", selection: $expanded) {
                    Text("Collapsed").tag(false)
                    Text("Expanded").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
                Button("Replay") { expanded.toggle() }
                    .controlSize(.small)
            },
            content: { reduceMotion in
                GeometryReader { proxy in
                    let expandedSize = settings.expandedSize
                    // Use the production geometry resolver against a deterministic
                    // notched-screen fixture so adaptive notch sizing has a real,
                    // immediately visible Settings preview without touching hardware.
                    let previewScreen = ScreenSnapshot(
                        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
                        safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
                        auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 635, height: 38),
                        auxiliaryTopRightArea: CGRect(x: 877, y: 944, width: 635, height: 38)
                    )
                    let resolved = NotchGeometryService().geometry(
                        for: previewScreen,
                        collapsedSize: settings.collapsedSize,
                        expandedSize: expandedSize,
                        useAdaptiveNotchSizing: settings.useAdaptiveNotchSizing,
                        respectHardwareNotch: settings.respectHardwareNotch
                    )
                    let rawSize = expanded ? expandedSize : resolved.collapsedFrame.size
                    let scale = min(
                        1,
                        (proxy.size.width - 8) / max(expandedSize.width, 1),
                        proxy.size.height / max(expandedSize.height, 1)
                    )
                    let size = CGSize(width: rawSize.width * scale, height: rawSize.height * scale)
                    IslandSurface(
                        settings: settings,
                        isExpanded: expanded,
                        visualProgress: expanded ? 1 : 0
                    ) {
                        if expanded {
                            VStack(alignment: .leading) {
                                ExpandedIslandPageSwitcher(settings: settings, navigation: navigation)
                                    .fixedSize()
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                            .padding(.horizontal, 22)
                            .transition(.opacity)
                        }
                    }
                    .notchIntegrated(settings.respectHardwareNotch)
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .animation(IslandShellMotion.shellAnimation(settings: settings, reduceMotion: reduceMotion), value: expanded)
                    .animation(IslandShellMotion.shellAnimation(settings: settings, reduceMotion: reduceMotion), value: size)
                }
            }
        )
    }
}


// MARK: - Content motion

/// Replays the exact production staged-content modifier used by expanded pages,
/// so blur/scale/stagger settings can be evaluated without operating the shell.
struct ContentMotionSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    @State private var visible = true
    @State private var generation = 0

    var body: some View {
        SettingsPreviewSandbox(
            title: "Content Motion Preview",
            showsReduceMotionToggle: true,
            height: 116,
            controls: {
                Button("Replay") { replay() }
                    .controlSize(.small)
            },
            content: { reduceMotion in
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.11))
                            .overlay(alignment: .leading) {
                                HStack(spacing: 7) {
                                    Image(systemName: ["waveform", "folder", "sparkles"][index])
                                        .foregroundStyle(.white.opacity(0.82))
                                    Text(["Media", "Files", "Tools"][index])
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.84))
                                }
                                .padding(.horizontal, 10)
                            }
                            .frame(height: 50)
                            .innerBlurScaleClean(
                                settings: settings,
                                isVisible: visible,
                                isRemoval: !visible,
                                index: index,
                                reduceMotion: reduceMotion
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
    }

    private func replay() {
        generation += 1
        let token = generation
        visible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            guard token == generation else { return }
            visible = true
        }
    }
}

// MARK: - Collapsed media + hover preview

struct CollapsedMediaSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    let media: MediaController

    var body: some View {
        SettingsPreviewSandbox(title: "Collapsed Media Preview", usesSampleContent: true, height: 86) { _ in
            HStack(spacing: 0) {
                if settings.showAlbumArtwork {
                    CompactMediaView(media: media)
                }
                Spacer(minLength: 16)
                if settings.showVisualizer && settings.showCollapsedVisualizer {
                    AudioVisualizerView(
                        isPlaying: media.isPlaying,
                        isActive: media.hasActiveMediaSource,
                        accentColor: .orange,
                        variant: .compact,
                        barCount: 7,
                        pauseDuringShellMorph: settings.disableVisualizerDuringMorph
                    )
                }
            }
            .padding(.horizontal, 10)
            .frame(width: max(CGFloat(settings.collapsedWidth), 190), height: max(CGFloat(settings.collapsedHeight), 44))
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct CollapsedHoverSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    let media: MediaController
    @State private var revealed = true
    @State private var replayGeneration = 0

    var body: some View {
        SettingsPreviewSandbox(
            title: "Collapsed Hover Preview",
            usesSampleContent: true,
            height: 126,
            controls: {
                Button("Replay Delay") { replay() }
                    .controlSize(.small)
            },
            content: { _ in
                let base = settings.collapsedSize
                let content = previewContent
                let rowCount = content.rows.count
                let liveHeight = base.height + CGFloat(max(rowCount, 1) * 20) + 8
                let previewHeight = settings.collapsedHoverPreviewEnabled && revealed
                    ? max(base.height, CGFloat(settings.collapsedHoverPreviewHeight), liveHeight)
                    : base.height

                IslandSurface(settings: settings, isExpanded: false, visualProgress: 0) {
                    VStack(spacing: 0) {
                        Spacer(minLength: max(base.height - 3, 0))
                        if settings.collapsedHoverPreviewEnabled && revealed {
                            CollapsedPreviewRow(content: content)
                                .transition(.opacity)
                        }
                    }
                }
                .notchIntegrated(settings.respectHardwareNotch)
                .frame(width: base.width, height: previewHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(.easeOut(duration: 0.16), value: revealed)
            }
        )
    }

    private var previewContent: CollapsedPreviewContent {
        let title = settings.collapsedHoverPreviewShowTitle && settings.showMediaTitle
            ? media.title
            : "Media"
        let subtitle: String? = if settings.collapsedHoverPreviewShowsArtist {
            if !media.artist.isEmpty {
                media.artist
            } else if settings.collapsedHoverPreviewShowsSource {
                media.sourceName
            } else {
                nil
            }
        } else {
            nil
        }
        return CollapsedPreviewContent(rows: [
            CollapsedPreviewRowContent(
                id: "settings-preview-media",
                title: title,
                subtitle: settings.collapsedHoverPreviewMediaEnabled ? subtitle : nil,
                trailingText: "2:41",
                symbolName: settings.collapsedHoverPreviewTitleIconName,
                fallbackSymbolName: "music.note",
                kind: .media,
                isPrimary: true
            )
        ])
    }

    private func replay() {
        replayGeneration += 1
        let token = replayGeneration
        revealed = false
        let delay = settings.collapsedHoverPreviewEnabled
            ? max(settings.collapsedHoverPreviewDelay, 0)
            : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token == replayGeneration else { return }
            revealed = true
        }
    }
}

// MARK: - Media

struct MediaSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    let media: MediaController

    var body: some View {
        SettingsPreviewSandbox(title: "Media Player Preview", usesSampleContent: true, height: 160) { _ in
            MediaModuleView(
                settings: settings,
                media: media,
                availableHeight: 150,
                onLauncherActivated: {},
                onMediaSourceOpened: {}
            )
            .frame(width: 380)
            .frame(maxWidth: .infinity)
        }
    }
}


struct MediaLauncherSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    let media: MediaController

    var body: some View {
        SettingsPreviewSandbox(title: "No-source Launcher Preview", usesSampleContent: true, height: 142) { _ in
            if settings.showMediaWhenNoSource && settings.mediaLauncherEnabled {
                EmptyMediaLauncherView(settings: settings, media: media, onLauncherActivated: {})
                    .scaleEffect(0.80)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Launcher disabled by current settings")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.52))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Right workspace

/// A miniature of the real right workspace, bound to the live
/// configuration: order, visibility, default page, indicator style.
struct RightWorkspaceSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var workspace: RightWorkspaceStore
    let dependencies: SettingsPreviewDependencies
    @StateObject private var previewStore = RightWorkspaceStore(
        defaults: UserDefaults(suiteName: "com.local.dynamicisland.settings-preview.workspace") ?? .standard
    )
    @StateObject private var previewActivities = LiveActivityStore()
    @StateObject private var previewNavigation = IslandNavigationStore()
    @State private var page: RightWorkspacePage = .overview

    var body: some View {
        SettingsPreviewSandbox(
            title: "Right Workspace Preview",
            usesSampleContent: true,
            showsReduceMotionToggle: true,
            height: 206,
            controls: {
                Picker("Page", selection: $page) {
                    ForEach(workspace.configuration.visiblePages) { page in
                        Text(page.title).tag(page)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            },
            content: { reduceMotion in
                RightWorkspaceView(
                    store: previewStore,
                    layoutStore: nil,
                    reduceMotion: reduceMotion,
                    overview: {
                        VStack(spacing: 8) {
                            LiveActivitiesModuleView(
                                liveActivities: previewActivities,
                                navigation: previewNavigation,
                                rightWorkspace: previewStore,
                                settings: settings,
                                availableHeight: 84,
                                compactScale: 0.9
                            )
                            .frame(height: 84, alignment: .topLeading)
                            ShortcutsModuleView(
                                shortcuts: dependencies.shortcuts,
                                availableHeight: 84,
                                compactScale: 0.9,
                                onShortcutLaunched: {}
                            )
                            .frame(height: 84, alignment: .topLeading)
                        }
                    },
                    productivity: {
                        ProductivityDeckView(
                            productivity: dependencies.productivity,
                            fileShelf: dependencies.previewShelf,
                            tools: previewStore.configuration.visibleTools,
                            reduceMotion: reduceMotion
                        )
                    },
                    appsMedia: {
                        AppsMediaDeckView(
                            services: dependencies.workspaceServices,
                            media: nil,
                            sections: previewStore.configuration.visibleSections,
                            layoutStore: nil
                        )
                    }
                )
                .frame(width: 430)
                .frame(maxWidth: .infinity)
            }
        )
        .onAppear {
            sync()
            LiveActivityPreviewCatalog.activities(for: .mediaTimer).forEach(previewActivities.update)
        }
        .onChange(of: workspace.configuration) { _, _ in sync() }
        .onChange(of: page) { _, newPage in previewStore.show(newPage) }
    }

    private func sync() {
        let previousDefault = previewStore.configuration.defaultPage
        previewStore.update { $0 = workspace.configuration }
        page = Self.previewPage(
            current: page,
            previousDefault: previousDefault,
            configuration: workspace.configuration
        )
        previewStore.show(page)
    }

    /// The page the preview shows after a settings change: a newly chosen
    /// default page is shown immediately; a hidden page falls back to the
    /// default; otherwise the page picked in the preview stays.
    static func previewPage(
        current: RightWorkspacePage,
        previousDefault: RightWorkspacePage,
        configuration: RightWorkspaceConfiguration
    ) -> RightWorkspacePage {
        if configuration.defaultPage != previousDefault || !configuration.visiblePages.contains(current) {
            return configuration.defaultPage
        }
        return current
    }
}

// MARK: - Agents

struct AgentsSettingsPreview: View {
    @ObservedObject var managedControl: AgentManagedSessionController
    @StateObject private var approvals = AgentApprovalController()

    var body: some View {
        SettingsPreviewSandbox(title: "Agents Preview", usesSampleContent: true, height: 230) { _ in
            let provider = managedControl.managedProvider ?? .claude
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AgentProviderButtons(managedControl: managedControl)
                    Spacer()
                    AgentUsageIndicatorRow(
                        indicators: AgentUsageIndicatorPresentation.make(
                            provider: provider,
                            accountUsage: managedControl.accountUsage,
                            selectedSession: nil
                        ).filter { $0.kind != .context },
                        spacing: 10
                    )
                }
                AgentEmbeddedConsoleView(
                    session: SettingsPreviewFixtures.agentSession(provider: provider),
                    mode: .interactive(canInterrupt: true),
                    interactionState: .ready,
                    maximumActivityEntries: 4,
                    transcriptEntries: SettingsPreviewFixtures.transcript(provider: provider),
                    approvalControl: approvals,
                    onSelectSession: { _ in },
                    onSubmit: { _ in false },
                    onInterrupt: {}
                )
            }
        }
    }
}

// MARK: - File Tray

struct FileTraySettingsPreview: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shelf: FileShelfStore
    let backgroundRemoval: BackgroundRemovalController
    @StateObject private var thumbnails = FileThumbnailCache()
    @StateObject private var layoutStore = IslandLayoutStore()
    @StateObject private var backgroundOperations = BackgroundOperationController(liveActivities: LiveActivityStore())

    var body: some View {
        SettingsPreviewSandbox(title: "File Tray Preview", usesSampleContent: true, height: 170) { reduceMotion in
            HStack(spacing: 10) {
                if settings.airDropZoneEnabled {
                    AirDropDropZoneView(
                        settings: settings,
                        isTargeted: false,
                        reduceMotion: reduceMotion
                    )
                    .frame(width: 116)
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(shelf.files, id: \.self) { url in
                            ShelfFileTile(
                                settings: settings,
                                fileShelf: shelf,
                                url: url,
                                thumbnailCache: thumbnails,
                                isSelected: shelf.selection.contains(url),
                                onRemove: {}
                            )
                        }
                    }
                    FileTrayQuickActionBar(
                        fileShelf: shelf,
                        backgroundOperations: backgroundOperations,
                        backgroundRemoval: backgroundRemoval,
                        layoutStore: layoutStore,
                        reduceMotion: reduceMotion
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Clipboard, timer, stats, productivity

struct ClipboardSettingsPreview: View {
    @ObservedObject var store: ClipboardHistoryStore

    var body: some View {
        SettingsPreviewSandbox(title: "Clipboard Preview (your current history)", height: 240) { _ in
            ClipboardHistoryView(store: store, onClose: {})
        }
    }
}

struct StatsSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    let stats: SystemStatsController

    var body: some View {
        SettingsPreviewSandbox(title: "Stats Preview (live values)", height: 190) { _ in
            GeometryReader { proxy in
                StatsPageView(
                    settings: settings,
                    stats: stats,
                    metrics: ExpandedIslandLayoutMetrics(containerSize: proxy.size, horizontalPadding: 0)
                )
            }
        }
    }
}

struct ProductivityDeckSettingsPreview: View {
    @ObservedObject var workspace: RightWorkspaceStore
    let productivity: ProductivityModules
    let shelf: FileShelfStore

    var body: some View {
        SettingsPreviewSandbox(title: "Productivity Page Preview (live status)", height: 196) { reduceMotion in
            ProductivityDeckView(
                productivity: productivity,
                fileShelf: shelf,
                tools: workspace.configuration.visibleTools,
                reduceMotion: reduceMotion
            )
            .frame(width: 430)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Timer page

/// The production Timer page with the app's real timer, read-only.
struct TimerPageSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    let timer: TimerController

    var body: some View {
        SettingsPreviewSandbox(title: "Timer Page Preview (live timer)", height: 190) { _ in
            DedicatedTimerPageView(
                settings: settings,
                timer: timer,
                ringSize: 110,
                pageHeight: 180,
                onTimerStarted: {}
            )
            .frame(width: 420)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Production FloatingBasketView with in-memory sample baskets. Inert by
/// construction: `.inert` actions, no BasketManager, no window, no drop
/// targets, no drag-out, no sharing and no file reads beyond icon lookup.
struct FloatingBasketSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var samples = FloatingBasketPreviewSamples()

    var body: some View {
        SettingsPreviewSandbox(title: SettingsPreviewID.floatingBasket.rawValue, usesSampleContent: true, height: 230) { _ in
            HStack(alignment: .top, spacing: 18) {
                basket(samples.empty, accent: false)
                basket(samples.stack, accent: settings.basketMultipleEnabled)
                if settings.basketMultipleEnabled {
                    basket(samples.second, accent: true)
                }
            }
            .opacity(settings.floatingBasketEnabled ? 1 : 0.35)
            .frame(maxWidth: .infinity)
        }
    }

    private func basket(_ state: BasketState, accent: Bool) -> some View {
        let metrics = BasketMetrics(scale: 0.9)
        let size = metrics.windowSize(surface: metrics.collapsedSize)
        return FloatingBasketView(state: state, showsAccent: accent, metrics: metrics, actions: .inert,
                                  multiBasketMode: settings.basketMultipleEnabled)
            .frame(width: size.width, height: size.height)
            .scaleEffect(0.62, anchor: .top)
            .frame(width: size.width * 0.62, height: size.height * 0.62, alignment: .top)
    }
}

@MainActor
final class FloatingBasketPreviewSamples: ObservableObject {
    let empty = BasketState(accent: .teal)
    let stack = BasketState(accent: .teal)
    let second = BasketState(accent: .coral)

    init() {
        let base = URL(fileURLWithPath: "/DynamicIslandPreview", isDirectory: true)
        stack.appendItems(["Brief.pdf", "Moodboard.png", "Notes.txt"].map { BasketItem(url: base.appendingPathComponent($0)) })
        second.appendItems(["Archive.zip"].map { BasketItem(url: base.appendingPathComponent($0)) })
        [empty, stack, second].forEach { $0.setVisible(true) }
    }
}
