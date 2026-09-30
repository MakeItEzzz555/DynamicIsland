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
                    let scale = min(1, (proxy.size.width - 8) / max(expandedSize.width, 1), proxy.size.height / max(expandedSize.height, 1))
                    let size = expanded
                        ? CGSize(width: expandedSize.width * scale, height: expandedSize.height * scale)
                        : CGSize(width: settings.collapsedSize.width * scale, height: settings.collapsedSize.height * scale)
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
        previewStore.update { $0 = workspace.configuration }
        if !workspace.configuration.visiblePages.contains(page) {
            page = workspace.configuration.defaultPage
        }
        previewStore.show(page)
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
                        ),
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

    var body: some View {
        SettingsPreviewSandbox(title: "File Tray Preview", usesSampleContent: true, height: 150) { reduceMotion in
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(shelf.files, id: \.self) { url in
                        ShelfFileTile(
                            settings: settings,
                            url: url,
                            thumbnailCache: thumbnails,
                            isSelected: shelf.selection.contains(url),
                            onSelect: { _ in },
                            onRemove: {}
                        )
                    }
                }
                FileTrayQuickActionBar(
                    fileShelf: shelf,
                    backgroundRemoval: backgroundRemoval,
                    layoutStore: layoutStore,
                    reduceMotion: reduceMotion
                )
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

struct TimerSettingsPreview: View {
    let timer: TimerController

    var body: some View {
        SettingsPreviewSandbox(title: "Timer Preview", height: 170) { _ in
            TimerModuleView(timer: timer)
                .frame(width: 380)
                .frame(maxWidth: .infinity)
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
