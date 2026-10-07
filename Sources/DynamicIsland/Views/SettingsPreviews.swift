import AppKit
import Combine
import SwiftUI

// MARK: - Sandbox environment

private struct SettingsPreviewEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SettingsPreviewReduceMotionKey: EnvironmentKey {
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
    /// The optional Settings simulation augments the OS-owned read-only
    /// accessibility preference. It has no effect outside the sandbox.
    var settingsPreviewReduceMotion: Bool {
        get { self[SettingsPreviewReduceMotionKey.self] }
        set { self[SettingsPreviewReduceMotionKey.self] = newValue }
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
    /// The live placement model is read only; previews never commit to it.
    var customization: WorkspaceCustomizationStore? = nil
}

/// Preview preferences stay in memory, including production AppStorage and
/// store persistence paths. They cannot fall back to the user's preferences.
final class SettingsPreviewDefaults: UserDefaults {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    init() { super.init(suiteName: "DynamicIsland.SettingsPreview.\(UUID().uuidString)")! }
    override func object(forKey key: String) -> Any? { lock.withLock { values[key] } }
    override func set(_ value: Any?, forKey key: String) { lock.withLock { values[key] = value } }
    override func set(_ value: Bool, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    override func set(_ value: Int, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    override func set(_ value: Float, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    override func set(_ value: Double, forKey key: String) { set(NSNumber(value: value), forKey: key) }
    override func set(_ value: URL?, forKey key: String) { set(value as Any?, forKey: key) }
    override func register(defaults registration: [String: Any]) {
        lock.withLock { values.merge(registration) { existing, _ in existing } }
    }
    override func removeObject(forKey key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
    override func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? false }
    override func integer(forKey key: String) -> Int { (object(forKey: key) as? NSNumber)?.intValue ?? 0 }
    override func double(forKey key: String) -> Double { (object(forKey: key) as? NSNumber)?.doubleValue ?? 0 }
    override func float(forKey key: String) -> Float { (object(forKey: key) as? NSNumber)?.floatValue ?? 0 }
    override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    override func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    override func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
    override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    override func url(forKey key: String) -> URL? { object(forKey: key) as? URL }
    override func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    override func dictionaryRepresentation() -> [String: Any] { lock.withLock { values } }
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
        let shelf = FileShelfStore(settings: settings, defaults: SettingsPreviewDefaults(),
                                   ownership: TemporaryFileOwnershipLedger(temporaryRoots: []))
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

    static func accountUsage() -> AgentUsage {
        AgentUsage(scopedSamples: Dictionary(uniqueKeysWithValues: [("5h", 32.0), ("Week", 58.0)].map { scope, value in
            (AgentUsageKey(metric: .quotaUsed, scope: scope),
             AgentUsageSample(value: value, limit: 100, unit: .fraction, scope: scope,
                              source: "Settings sample", observedAt: referenceDate))
        }))
    }
}

/// One deterministic display fixture; every sizing decision delegates to the
/// same geometry, header and grid resolvers used by the overlay.
@MainActor
struct SettingsPreviewPresentation {
    static let screen = ScreenSnapshot(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
        safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 635, height: 38),
        auxiliaryTopRightArea: CGRect(x: 877, y: 944, width: 635, height: 38))
    static let metrics = IslandDisplayMetricsResolver.resolve(IslandDisplaySnapshot(
        frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaInsets: screen.safeAreaInsets,
        auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea, auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
        backingScaleFactor: 2, displayID: nil, isBuiltIn: true, pixelSize: CGSize(width: 3024, height: 1964)))

    let geometry: IslandGeometry
    let header: ExpandedHeaderLayout
    let lane: WorkspaceNotchLane
    let chrome: ExpandedIslandLayoutMetrics
    let regions: [WorkspaceWidgetRegion]
    let projection: WorkspaceWidgetLayoutProjection

    static func mediaVisible(settings: AppSettings, media: MediaController) -> Bool {
        settings.mediaEnabled && media.hasActiveMediaSource && (settings.showMediaWhenPaused || media.isPlaying)
    }

    init(settings: AppSettings, page: ExpandedIslandPage = .island,
         configuration: WorkspaceConfiguration? = nil, mediaVisible: Bool = true) {
        let navigation = IslandNavigationStore()
        if let configuration { navigation.applyConfiguration(configuration, using: settings) }
        let count = navigation.availablePages(using: settings).count
        let integrated = Self.metrics.hasHardwareNotch && settings.respectHardwareNotch
        let headerWidth = ExpandedIslandHeaderMetrics.minimumContentWidth(pageCount: count,
            clipboardEnabled: settings.clipboardHistoryEnabled,
            hardwareNotchWidth: integrated ? Self.metrics.hardwareNotchWidth : 0)
        header = ExpandedPresentationProfile.headerLayout(page: page, configuration: configuration, editing: false,
            settings: settings, metrics: Self.metrics, pageCount: count)
        lane = header.mode != .winged ? .none : ExpandedIslandLayoutMetrics.workspaceNotchLane(
            settings: settings, metrics: Self.metrics, pageCount: count,
            hardwareNotchWidth: integrated ? Self.metrics.hardwareNotchWidth : 0)
        let size = ExpandedPresentationProfile.resolve(for: page).resolvedSize(from: settings.expandedSize,
            page: page, configuration: configuration, editing: false, settings: settings,
            metrics: Self.metrics, minimumHeaderWidth: headerWidth, lane: lane, header: header)
        geometry = NotchGeometryService().geometry(for: Self.screen, collapsedSize: settings.collapsedSize,
            expandedSize: size, collapsedActivityProfile: mediaVisible ? .media(showsArtwork: settings.showAlbumArtwork,
                showsVisualizer: settings.showVisualizer && settings.showCollapsedVisualizer) : nil,
            useAdaptiveNotchSizing: settings.useAdaptiveNotchSizing, respectHardwareNotch: settings.respectHardwareNotch)
        chrome = ExpandedIslandLayoutMetrics(containerSize: geometry.expandedFrame.size,
            horizontalPadding: IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: integrated),
            displayMetrics: Self.metrics, headerDrop: header.headerDrop, showHeader: header.mode != .hidden)
        let surface: WorkspaceSurface = page == .agents ? .agents : .media
        let allowed = WorkspaceWidgetAvailability.eligible(on: surface, settings: settings)
        regions = (configuration ?? .initial).regions(on: surface).compactMap { region in
            let widgets = region.widgets.filter { allowed.contains($0.kind) }
            return widgets.isEmpty ? nil : WorkspaceWidgetRegion(id: widgets.count > 1 ? region.id : widgets[0].id, widgets: widgets)
        }
        projection = WorkspaceWidgetLayoutProjection.make(regions: regions,
            availableSize: CGSize(width: chrome.innerWidth, height: chrome.pageHeight), metrics: Self.metrics, lane: lane)
    }

    static func fit(size: CGSize, in available: CGSize) -> CGFloat {
        max(0.01, min(1, max(available.width, 1) / max(size.width, 1), max(available.height, 1) / max(size.height, 1)))
    }

    static func placement(kind: IslandWidget, configuration: WorkspaceConfiguration?, surface: WorkspaceSurface = .media) -> WorkspaceWidgetPlacementContext {
        let region = configuration?.regions(on: surface).first { $0.widgets.contains { $0.kind == kind } }
        let presentation = region.map(WorkspaceWidgetLayoutProjection.presentationSize) ?? .standard
        let size = WidgetGridMetrics.make(surface: surface, metrics: metrics).size(for: presentation, kinds: region?.widgets.map(\.kind) ?? [kind])
        return WorkspaceWidgetPlacementContext(isSole: true, size: size, fillsRow: true, presentationSize: presentation)
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var defaults = SettingsPreviewDefaults()

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
            content(systemReduceMotion || reduceMotion)
                .environment(\.isSettingsPreview, true)
                .environment(\.settingsPreviewReduceMotion, systemReduceMotion || reduceMotion)
                .environment(\.nativeVisualSnapshotTime, systemReduceMotion || reduceMotion ? 0.6 : nil)
                .environment(\.colorScheme, .dark)
                .defaultAppStorage(defaults)
                .transformEnvironment(\.timerRulerInteractionRegistration) { $0.enabled = false }
                .disabled(true)
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
    var dependencies: SettingsPreviewDependencies? = nil
    @State private var expanded = true
    @StateObject private var navigation = IslandNavigationStore()
    @State private var configuration = WorkspaceConfiguration.initial

    var body: some View {
        SettingsPreviewSandbox(
            title: "Island Preview",
            usesSampleContent: dependencies != nil,
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
                    let presentation = SettingsPreviewPresentation(settings: settings,
                        page: navigation.selectedPage, configuration: configuration)
                    let rawSize = expanded ? presentation.geometry.expandedFrame.size : presentation.geometry.collapsedFrame.size
                    let scale = SettingsPreviewPresentation.fit(size: presentation.geometry.expandedFrame.size, in: proxy.size)
                    IslandSurface(
                        settings: settings,
                        isExpanded: expanded,
                        visualProgress: expanded ? 1 : 0
                    ) {
                        if expanded {
                            VStack(alignment: .leading, spacing: presentation.chrome.tabToPageSpacing) {
                                if presentation.chrome.showHeader {
                                    ExpandedIslandPageSwitcher(settings: settings, navigation: navigation)
                                        .fixedSize()
                                        .frame(height: presentation.chrome.tabSwitcherHeight)
                                }
                                if let dependencies {
                                    SettingsPreviewWidgetGrid(settings: settings, dependencies: dependencies, presentation: presentation)
                                        .frame(width: presentation.chrome.innerWidth, height: presentation.chrome.pageHeight)
                                } else { Spacer(minLength: 0) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, presentation.chrome.topPadding)
                            .padding(.bottom, presentation.chrome.bottomPadding)
                            .padding(.horizontal, presentation.chrome.horizontalPadding)
                            .transition(.opacity)
                        }
                    }
                    .notchIntegrated(presentation.geometry.hasHardwareNotch && settings.respectHardwareNotch)
                    .environment(\.islandDisplayMetrics, SettingsPreviewPresentation.metrics)
                    .environment(\.expandedHeaderLayout, presentation.header)
                    .environment(\.agentVisualPreferences, settings.agentVisualPreferences)
                    .frame(width: rawSize.width, height: rawSize.height)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: rawSize.width * scale, height: rawSize.height * scale, alignment: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .animation(IslandShellMotion.shellAnimation(settings: settings, reduceMotion: reduceMotion,
                        opening: expanded), value: expanded)
                    .animation(IslandShellMotion.shellAnimation(settings: settings, reduceMotion: reduceMotion), value: rawSize)
                }
            }
        )
        .onReceive(dependencies?.customization?.$configuration.eraseToAnyPublisher() ?? Just(.initial).eraseToAnyPublisher()) { value in
            configuration = value
            navigation.applyConfiguration(value, using: settings)
        }
        .onChange(of: settings.showAgentsTab) { _, _ in navigation.applyConfiguration(configuration, using: settings) }
    }
}

/// The shell's miniature uses the production grid frames and presentation
/// contexts. The content never mounts a PTY or an interactive provider.
private struct SettingsPreviewWidgetGrid: View {
    @ObservedObject var settings: AppSettings
    let dependencies: SettingsPreviewDependencies
    let presentation: SettingsPreviewPresentation
    @StateObject private var approvals = AgentApprovalController()
    @StateObject private var activities = LiveActivityStore()
    @StateObject private var navigation = IslandNavigationStore()
    @StateObject private var workspace = RightWorkspaceStore(defaults: SettingsPreviewDefaults())
    @StateObject private var samples = SettingsPreviewWorkspaceSamples()
    @StateObject private var feed = AgentWorkspaceFeedStore()
    @StateObject private var backgroundOperations = BackgroundOperationController(liveActivities: LiveActivityStore())
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(presentation.regions) { region in
                if let frame = presentation.projection.frames.first(where: { $0.id == region.id })?.frame {
                    widget(region, size: frame.size)
                        .environment(\.workspaceWidgetPlacement, WorkspaceWidgetPlacementContext(
                            isSole: presentation.regions.count == 1, size: frame.size, fillsRow: true,
                            presentationSize: WorkspaceWidgetLayoutProjection.presentationSize(of: region)))
                        .frame(width: frame.width, height: frame.height)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: WorkspaceEditorChrome.cornerRadius))
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(width: presentation.projection.contentSize.width, height: presentation.projection.contentSize.height, alignment: .topLeading)
        .environment(\.rightWorkspacePageIsActive, false)
        .clipped()
        .onAppear { syncActivities() }
        .onChange(of: LiveActivitySettingsSnapshot(settings: settings)) { _, _ in syncActivities() }
        .onReceive(dependencies.rightWorkspace.$configuration) { value in workspace.update { $0 = value } }
    }

    private func syncActivities() {
        activities.removeAll()
        LiveActivityLayoutSettingsPreview.publishedActivities(LiveActivityPreviewCatalog.activities(for: .mediaTimer),
            settings: LiveActivitySettingsSnapshot(settings: settings)).forEach(activities.update)
    }

    @ViewBuilder
    private func widget(_ region: WorkspaceWidgetRegion, size: CGSize) -> some View {
        switch region.widgets.first?.kind {
        case .media:
            MediaModuleView(settings: settings, media: dependencies.previewMedia, availableHeight: size.height,
                            onLauncherActivated: {}, onMediaSourceOpened: {})
        case .timer:
            FocusTimerView(timer: dependencies.timer, settings: settings, showsPanel: false)
        case .shortcuts:
            ShortcutsModuleView(shortcuts: dependencies.shortcuts, availableHeight: size.height, onShortcutLaunched: {})
        case .calendar:
            CalendarSectionView(controller: samples.services.calendar, layoutStore: nil)
        case .clipboard:
            ClipboardHistoryView(store: dependencies.clipboardHistory, onClose: {})
        case .activities:
            LiveActivitiesModuleView(liveActivities: activities, navigation: navigation, rightWorkspace: workspace,
                                     settings: settings, availableHeight: size.height)
        case .workspace:
            RightWorkspaceView(store: workspace, layoutStore: nil, reduceMotion: reduceMotion,
                overview: {
                    VStack(spacing: 8) {
                        if settings.liveActivitiesEnabled && settings.showExpandedLiveActivitiesSection {
                            LiveActivitiesModuleView(liveActivities: activities, navigation: navigation,
                                rightWorkspace: workspace, settings: settings, availableHeight: size.height / 2)
                        }
                        if settings.shortcutsEnabled {
                            ShortcutsModuleView(shortcuts: dependencies.shortcuts,
                                availableHeight: size.height / 2, onShortcutLaunched: {})
                        }
                    }
                }, productivity: {
                    ProductivityDeckView(productivity: dependencies.productivity, fileShelf: dependencies.previewShelf,
                        tools: workspace.configuration.visibleTools, reduceMotion: reduceMotion)
                }, appsMedia: {
                    AppsMediaDeckView(services: samples.services, media: nil,
                        sections: workspace.configuration.visibleSections, layoutStore: nil)
                        .environment(\.rightWorkspacePageIsActive, false)
                })
        case .chat:
            let session = SettingsPreviewFixtures.agentSession(provider: .claude)
            let console = AgentEmbeddedConsoleView(session: session,
                    mode: .interactive(canInterrupt: false), interactionState: .ready,
                    transcriptEntries: SettingsPreviewFixtures.transcript(provider: .claude),
                    approvalControl: approvals, onSelectSession: { _ in }, onSubmit: { _ in false }, onInterrupt: {})
            if WorkspaceWidgetLayoutProjection.presentationSize(of: region) == .compact {
                AgentCompactSessionSummary(session: session, role: region.isStack ? .stack : .chat,
                    isVisible: true, attention: AnyView(EmptyView()), conversation: AnyView(console))
            } else { console }
        case .terminal:
            AgentConsoleTerminalPane(controller: samples.terminal, onSelectInteraction: { _ in },
                                    compact: WorkspaceWidgetLayoutProjection.presentationSize(of: region) == .compact) {
                Text("Sample terminal output")
                    .font(.system(size: SettingsPreviewPresentation.metrics.transcriptFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            }
        case .agentUsage, .codexUsage, .claudeUsage:
            let providers: [AgentProvider] = region.widgets.first?.kind == .agentUsage ? [.codex, .claude]
                : region.widgets.first?.kind == .codexUsage ? [.codex] : [.claude]
            let size = WorkspaceWidgetLayoutProjection.presentationSize(of: region)
            AgentUsageComposition(groups: providers.map { provider in
                (provider, AgentUsageIndicatorPresentation.make(provider: provider,
                    accountUsage: SettingsPreviewFixtures.accountUsage(), selectedSession: nil,
                    now: SettingsPreviewFixtures.referenceDate).filter { $0.kind != .context })
            }, compact: size == .compact, large: size == .large)
        case .feed:
            AgentWorkspaceFeedView(feed: feed, approvals: approvals, sessions: [], onSelect: { _ in }, isVisible: false)
        case .files, .none:
            FileShelfModuleView(settings: settings, fileShelf: dependencies.previewShelf,
                                backgroundOperations: backgroundOperations)
        }
    }
}

@MainActor
private final class SettingsPreviewCalendarProvider: CalendarEventsProviding {
    let accessState = CalendarAccessState.fullAccess
    var changeNotificationName: Notification.Name? { nil }
    func requestFullAccess() async throws -> CalendarAccessState { accessState }
    func upcomingEvents(from start: Date, through end: Date) -> [CalendarEventDescriptor] {
        [CalendarEventDescriptor(id: "settings-preview-calendar", title: "Sample planning session",
            startDate: start.addingTimeInterval(3600), endDate: start.addingTimeInterval(5400),
            isAllDay: false, calendarTitle: "Preview calendar", calendarColor: [0.9, 0.3, 0.3], meetingURL: nil)]
    }
}

private struct SettingsPreviewSpotifyCredentials: SpotifyCredentialStoring {
    func credentials() -> SpotifyStoredCredentials {
        SpotifyStoredCredentials(accessToken: nil, accessTokenExpiry: nil, refreshToken: nil)
    }
    func store(accessToken: String, expiresAt: Date, refreshToken: String?, authorizationDate: Date?) {}
    func clear() {}
}

@MainActor
private struct SettingsPreviewTerminalRunner: TerminalProcessRunning {
    func start(command: String, shellPath: String, workingDirectory: URL?,
               onOutput: @escaping @Sendable (String) -> Void,
               onExit: @escaping @Sendable (Int32) -> Void) throws -> TerminalProcessHandle {
        throw TerminalSessionError.launchFailed("Settings previews do not run commands")
    }
}

@MainActor
final class SettingsPreviewWorkspaceSamples: ObservableObject {
    let services: WorkspaceServices
    let terminal: TerminalSessionController

    init() {
        let calendar = CalendarEventsController(provider: SettingsPreviewCalendarProvider(),
            now: { SettingsPreviewFixtures.referenceDate })
        calendar.refresh()
        services = WorkspaceServices(
            appLibrary: AppLibraryStore(defaults: SettingsPreviewDefaults(), scan: { [] }), calendar: calendar,
            spotify: SpotifyLibraryController(defaults: SettingsPreviewDefaults(),
                configuration: SpotifyAuthConfiguration(clientID: nil, source: .unavailable),
                tokens: SettingsPreviewSpotifyCredentials()))
        terminal = TerminalSessionController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry(),
            runner: SettingsPreviewTerminalRunner(), shellPath: "/bin/zsh", workingDirectoryPath: "/DynamicIslandPreview")
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
    @ObservedObject var media: MediaController

    var body: some View {
        SettingsPreviewSandbox(title: "Collapsed Media Preview", usesSampleContent: true, height: 86) { _ in
            GeometryReader { proxy in
                let presentation = SettingsPreviewPresentation(settings: settings,
                    mediaVisible: SettingsPreviewPresentation.mediaVisible(settings: settings, media: media))
                let size = presentation.geometry.collapsedFrame.size
                let scale = SettingsPreviewPresentation.fit(size: size, in: proxy.size)
                IslandSurface(settings: settings, isExpanded: false, visualProgress: 0) {
                    SettingsPreviewCollapsedMediaRow(settings: settings, media: media, geometry: presentation.geometry)
                }
                .notchIntegrated(presentation.geometry.hasHardwareNotch && settings.respectHardwareNotch)
                .environment(\.islandDisplayMetrics, SettingsPreviewPresentation.metrics)
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct SettingsPreviewCollapsedMediaRow: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var media: MediaController
    let geometry: IslandGeometry
    @ObservedObject private var accentCache = ArtworkAccentColorCache.shared

    private var accent: Color {
        switch settings.visualizerAccentMode {
        case .white: .white
        case .system: .accentColor
        case .artwork:
            settings.useArtworkAccentColor ? accentCache.color(
                for: media.artworkPresentation.displayedSnapshot?.fingerprint,
                image: media.artworkPresentation.displayedSnapshot?.image) : .white
        }
    }

    var body: some View {
        CompactCollapsedSideSlotLayout(geometry: CompactCollapsedSideSlotGeometry(
            isNotchIntegrated: geometry.hasHardwareNotch && settings.respectHardwareNotch,
            leftRegionWidth: geometry.collapsedLeftRegionWidth, notchCoreWidth: geometry.collapsedNotchCoreWidth,
            rightRegionWidth: geometry.collapsedRightRegionWidth)) {
                if SettingsPreviewPresentation.mediaVisible(settings: settings, media: media) && settings.showAlbumArtwork {
                    CompactMediaView(media: media)
                }
            } right: {
                if SettingsPreviewPresentation.mediaVisible(settings: settings, media: media)
                    && settings.showVisualizer && settings.showCollapsedVisualizer {
                    AudioVisualizerView(isPlaying: media.isPlaying, isActive: media.hasActiveMediaSource,
                        accentColor: accent, variant: .compact, barCount: 7, cadence: .ambient,
                        pauseDuringShellMorph: settings.disableVisualizerDuringMorph)
                }
            }
            .frame(height: 16)
    }
}

struct CollapsedHoverSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var media: MediaController
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
            content: { reduceMotion in
                let presentation = SettingsPreviewPresentation(settings: settings,
                    mediaVisible: SettingsPreviewPresentation.mediaVisible(settings: settings, media: media))
                let base = presentation.geometry.collapsedFrame.size
                let content = previewContent
                let rowCount = content.rows.count
                let liveHeight = base.height + CGFloat(max(rowCount, 1) * 20) + 8
                let active = settings.collapsedHoverPreviewEnabled && settings.collapsedHoverPreviewMediaEnabled
                    && SettingsPreviewPresentation.mediaVisible(settings: settings, media: media) && revealed
                let previewHeight = active
                    ? max(base.height, CGFloat(settings.collapsedHoverPreviewHeight), liveHeight)
                    : base.height

                IslandSurface(settings: settings, isExpanded: false, visualProgress: 0) {
                    VStack(spacing: 0) {
                        SettingsPreviewCollapsedMediaRow(settings: settings, media: media, geometry: presentation.geometry)
                            .frame(height: 16)
                            .padding(.top, active ? 2 : max(0, (base.height - 16) / 2))
                        Spacer(minLength: 0)
                        if active {
                            CollapsedPreviewRow(content: content)
                                .transition(.opacity)
                        }
                    }
                }
                .notchIntegrated(presentation.geometry.hasHardwareNotch && settings.respectHardwareNotch)
                .environment(\.islandDisplayMetrics, SettingsPreviewPresentation.metrics)
                .frame(width: base.width, height: previewHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(IslandShellMotion.shellAnimation(settings: settings, reduceMotion: reduceMotion, opening: revealed), value: previewHeight)
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
    var customization: WorkspaceCustomizationStore? = nil
    @State private var configuration: WorkspaceConfiguration? = nil

    var body: some View {
        SettingsPreviewSandbox(title: "Media Player Preview", usesSampleContent: true, height: 160) { _ in
            GeometryReader { proxy in
                let placement = SettingsPreviewPresentation.placement(kind: .media, configuration: configuration)
                let scale = SettingsPreviewPresentation.fit(size: placement.size, in: proxy.size)
                MediaModuleView(settings: settings, media: media, availableHeight: placement.size.height,
                    onLauncherActivated: {}, onMediaSourceOpened: {})
                    .environment(\.workspaceWidgetPlacement, placement)
                    .environment(\.islandDisplayMetrics, SettingsPreviewPresentation.metrics)
                    .frame(width: placement.size.width, height: placement.size.height)
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(settings.mediaEnabled ? 1 : 0.35)
            }
        }
        .onReceive(customization?.$configuration.map(Optional.some).eraseToAnyPublisher() ?? Just(nil).eraseToAnyPublisher()) { configuration = $0 }
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
        defaults: SettingsPreviewDefaults()
    )
    @StateObject private var previewActivities = LiveActivityStore()
    @StateObject private var previewNavigation = IslandNavigationStore()
    @State private var page: RightWorkspacePage = .overview
    @StateObject private var samples = SettingsPreviewWorkspaceSamples()

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
                            if settings.liveActivitiesEnabled && settings.showExpandedLiveActivitiesSection {
                              LiveActivitiesModuleView(
                                liveActivities: previewActivities,
                                navigation: previewNavigation,
                                rightWorkspace: previewStore,
                                settings: settings,
                                availableHeight: 84,
                                compactScale: 0.9
                            )
                            .frame(height: 84, alignment: .topLeading)
                            }
                            if settings.shortcutsEnabled {
                            ShortcutsModuleView(
                                shortcuts: dependencies.shortcuts,
                                availableHeight: 84,
                                compactScale: 0.9,
                                onShortcutLaunched: {}
                            )
                            .frame(height: 84, alignment: .topLeading)
                            }
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
                            services: samples.services,
                            media: nil,
                            sections: previewStore.configuration.visibleSections,
                            layoutStore: nil
                        )
                        .environment(\.rightWorkspacePageIsActive, false)
                    }
                )
                .frame(width: 430)
                .frame(maxWidth: .infinity)
            }
        )
        .onAppear {
            sync()
            syncActivities()
        }
        .onChange(of: workspace.configuration) { _, _ in sync() }
        .onChange(of: page) { _, newPage in previewStore.show(newPage) }
        .onChange(of: LiveActivitySettingsSnapshot(settings: settings)) { _, _ in syncActivities() }
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

    private func syncActivities() {
        previewActivities.removeAll()
        LiveActivityLayoutSettingsPreview.publishedActivities(LiveActivityPreviewCatalog.activities(for: .mediaTimer),
            settings: LiveActivitySettingsSnapshot(settings: settings)).forEach(previewActivities.update)
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
    var settings: AppSettings? = nil
    var dependencies: SettingsPreviewDependencies? = nil
    @State private var configuration = WorkspaceConfiguration.initial
    @StateObject private var approvals = AgentApprovalController()

    var body: some View {
        SettingsPreviewSandbox(title: "Agents Preview", usesSampleContent: true, height: 230) { _ in
            let provider = managedControl.managedProvider ?? .claude
            if let settings, let dependencies {
                GeometryReader { proxy in
                    let presentation = SettingsPreviewPresentation(settings: settings, page: .agents, configuration: configuration)
                    let size = CGSize(width: presentation.chrome.innerWidth, height: presentation.chrome.pageHeight)
                    let scale = SettingsPreviewPresentation.fit(size: size, in: proxy.size)
                    SettingsPreviewWidgetGrid(settings: settings, dependencies: dependencies, presentation: presentation)
                        .environment(\.islandDisplayMetrics, SettingsPreviewPresentation.metrics)
                        .environment(\.agentVisualPreferences, settings.agentVisualPreferences)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(settings.agentActivityEnabled ? 1 : 0.35)
                }
            } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AgentProviderButtons(managedControl: managedControl)
                    Spacer()
                    AgentUsageIndicatorRow(
                        indicators: AgentUsageIndicatorPresentation.make(
                            provider: provider,
                            accountUsage: SettingsPreviewFixtures.accountUsage(),
                            selectedSession: nil,
                            now: SettingsPreviewFixtures.referenceDate
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
            .environment(\.agentVisualPreferences, settings?.agentVisualPreferences ?? .init())
            .environment(\.rightWorkspacePageIsActive, false)
            .opacity(settings?.agentActivityEnabled == false ? 0.35 : 1)
            }
        }
        .onReceive(dependencies?.customization?.$configuration.eraseToAnyPublisher() ?? Just(.initial).eraseToAnyPublisher()) {
            configuration = $0
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
    var customization: WorkspaceCustomizationStore? = nil
    @State private var configuration: WorkspaceConfiguration? = nil

    var body: some View {
        SettingsPreviewSandbox(title: "Timer Page Preview (live timer)", height: 190) { _ in
            GeometryReader { proxy in
                let placement = SettingsPreviewPresentation.placement(kind: .timer, configuration: configuration)
                let scale = SettingsPreviewPresentation.fit(size: placement.size, in: proxy.size)
                FocusTimerView(timer: timer, settings: settings, showsPanel: false)
                    .environment(\.workspaceWidgetPlacement, placement)
                    .environment(\.islandDisplayMetrics, SettingsPreviewPresentation.metrics)
                    .frame(width: placement.size.width, height: placement.size.height)
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(settings.timerEnabled ? 1 : 0.35)
            }
        }
        .onReceive(customization?.$configuration.map(Optional.some).eraseToAnyPublisher() ?? Just(nil).eraseToAnyPublisher()) { configuration = $0 }
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

// MARK: - Live Activity layout

struct LiveActivityLayoutSettingsPreview: View {
    @ObservedObject var settings: AppSettings
    var dependencies: SettingsPreviewDependencies? = nil
    @State private var scenario: LiveActivityLayoutPreviewScenario = .mediaTimer
    @StateObject private var media = MediaController.settingsPreview()

    struct Presentation {
        let geometry: IslandGeometry
        let canvasSize: CGSize
        let resolution: LiveActivityLayoutResolution
        let composite: LiveActivityCompositeGeometry
    }

    /// Only the available canvas differs for the constrained scenario. Shell
    /// and sidecar dimensions remain those of the production resolvers.
    static func presentation(settings: AppSettings, scenario: LiveActivityLayoutPreviewScenario) -> Presentation {
        let activities = publishedActivities(LiveActivityPreviewCatalog.activities(for: scenario),
            settings: LiveActivitySettingsSnapshot(settings: settings))
        func resolve(_ geometry: IslandGeometry, width: CGFloat) -> LiveActivityLayoutResolution {
            LiveActivityLayoutResolver.resolve(activities: activities, context: LiveActivityLayoutContext(
                availableWidth: width, hasHardwareNotch: geometry.hasHardwareNotch,
                hardwareNotchWidth: geometry.hardwareNotchWidth,
                primaryMinimumWidth: max(geometry.collapsedFrame.width, 172),
                primaryIdealWidth: max(geometry.collapsedFrame.width, 226),
                sidecarDiameter: LiveActivitySidecarMetrics.diameter, sidecarGap: LiveActivitySidecarMetrics.gap,
                allowSimultaneousSidecars: settings.allowSimultaneousLiveActivitySidecars,
                timerSidePreference: settings.timerSidecarPreference))
        }
        func geometry(profile: CollapsedActivityLayoutProfile?, presentation: CollapsedPresentationProfile = .normal) -> IslandGeometry {
            NotchGeometryService().geometry(for: SettingsPreviewPresentation.screen,
                collapsedSize: settings.collapsedSize, expandedSize: settings.expandedSize,
                collapsedActivityProfile: profile, collapsedPresentationProfile: presentation,
                useAdaptiveNotchSizing: settings.useAdaptiveNotchSizing,
                respectHardwareNotch: settings.respectHardwareNotch)
        }
        let initial = geometry(profile: nil)
        let preliminary = resolve(initial, width: SettingsPreviewPresentation.screen.frame.width)
        let profile: CollapsedActivityLayoutProfile?
        switch preliminary.primary?.activity.kind {
        case .media: profile = .media(showsArtwork: settings.showAlbumArtwork,
            showsVisualizer: settings.showVisualizer && settings.showCollapsedVisualizer)
        case .timer: profile = .timer
        case .fileTray: profile = .file
        case .battery: profile = .battery
        case .none: profile = nil
        default: profile = .genericActivity
        }
        let overlay = preliminary.overlayTransient?.activity
        let shell = overlay.map { activity in
            geometry(profile: .systemHUD, presentation:
                activity.systemHUDKind == .volume || activity.systemHUDKind == .brightness
                ? .systemHUD(value: activity.progress ?? 0) : .normal)
        } ?? geometry(profile: profile, presentation: preliminary.primary?.activity.kind == .agent
            ? AgentCollapsedShellPresentation.routine(sessions: [SettingsPreviewFixtures.agentSession(provider: .codex)],
                enabled: settings.agentActivityEnabled) ?? .normal : .normal)
        let sideSpace = LiveActivitySidecarMetrics.diameter + LiveActivitySidecarMetrics.gap
        let width = max(shell.collapsedFrame.width, 172) + sideSpace * (scenario == .constrained ? 1 : 2)
        let canvas = CGSize(width: width, height: max(shell.collapsedFrame.height, LiveActivitySidecarMetrics.diameter) + 16)
        let resolution = resolve(shell, width: width)
        let primaryX = scenario == .constrained && resolution.hasSidecars
            ? (resolution.leadingSidecar != nil ? sideSpace : 0)
            : (width - shell.collapsedFrame.width) / 2
        let primary = CGRect(x: primaryX,
            y: canvas.height - shell.collapsedFrame.height - 8,
            width: shell.collapsedFrame.width, height: shell.collapsedFrame.height)
        return Presentation(geometry: shell, canvasSize: canvas, resolution: resolution,
            composite: LiveActivityCompositeGeometry.resolve(primaryFrame: primary, canvasSize: canvas,
                resolution: resolution, sidecarDiameter: LiveActivitySidecarMetrics.diameter,
                sidecarGap: LiveActivitySidecarMetrics.gap))
    }

    var body: some View {
        SettingsPreviewSandbox(title: "Layout Preview", usesSampleContent: true,
            showsReduceMotionToggle: true, height: 100, controls: {
                Picker("Scenario", selection: $scenario) {
                    ForEach(LiveActivityLayoutPreviewScenario.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 215)
            }, content: { reduceMotion in
                GeometryReader { proxy in
                    let display = Self.presentation(settings: settings, scenario: scenario)
                    let frame = display.composite.primaryFrame
                    let scale = SettingsPreviewPresentation.fit(size: display.canvasSize, in: proxy.size)
                    ZStack(alignment: .topLeading) {
                        IslandSurface(settings: settings, isExpanded: false, visualProgress: 0,
                            collapsedPresentationProfile: display.geometry.collapsedPresentationProfile,
                            systemHUDActivity: display.resolution.overlayTransient?.activity) {
                            primaryContent(display)
                        }
                        .notchIntegrated(display.geometry.hasHardwareNotch && settings.respectHardwareNotch)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: display.canvasSize.height - frame.midY)
                        LiveActivitySidecarLayer(resolution: display.resolution, compositeGeometry: display.composite,
                            canvasHeight: display.canvasSize.height, reduceMotion: reduceMotion, onActivate: { _ in })
                    }
                    .frame(width: display.canvasSize.width, height: display.canvasSize.height)
                    .environment(\.islandDisplayMetrics, SettingsPreviewPresentation.metrics)
                    .environment(\.agentVisualPreferences, settings.agentVisualPreferences)
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(IslandShellMotion.shellAnimation(settings: settings, reduceMotion: reduceMotion), value: display.canvasSize)
                    .animation(IslandShellMotion.shellAnimation(settings: settings, reduceMotion: reduceMotion), value: display.resolution)
                }
            })
    }

    @ViewBuilder
    private func primaryContent(_ display: Presentation) -> some View {
        let geometry = display.geometry
        let layout = CompactCollapsedSideSlotGeometry(
            isNotchIntegrated: geometry.hasHardwareNotch && settings.respectHardwareNotch,
            leftRegionWidth: geometry.collapsedLeftRegionWidth, notchCoreWidth: geometry.collapsedNotchCoreWidth,
            rightRegionWidth: geometry.collapsedRightRegionWidth)
        if let overlay = display.resolution.overlayTransient?.activity {
            CollapsedSystemHUDCompactView(activity: overlay, layout: layout)
        } else if let primary = display.resolution.primary?.activity {
            switch primary.kind {
            case .media:
                SettingsPreviewCollapsedMediaRow(settings: settings, media: media, geometry: geometry)
            case .timer:
                CollapsedTimerActivityCompactView(activity: primary, layout: layout)
            case .fileTray:
                CollapsedFileActivityCompactView(activity: primary, layout: layout)
            case .battery:
                CollapsedBatteryActivityCompactView(activity: primary, layout: layout)
            case .agent:
                let session = SettingsPreviewFixtures.agentSession(provider: .codex)
                CompactCollapsedSideSlotLayout(geometry: layout) {
                    AgentCompactRoutineLeadingView(session: session)
                } right: {
                    AgentCompactRoutineTrailingView(session: session)
                }
            case .voiceRecording, .voiceTranscription:
                if let dependencies {
                    CollapsedVoiceBeamCompactView(controller: dependencies.productivity.voice, activity: primary)
                } else {
                    CollapsedGenericActivityCompactView(activity: primary, layout: layout)
                }
            default:
                CollapsedGenericActivityCompactView(activity: primary, layout: layout)
            }
        }
    }

    /// Applies the same per-source switches the composition root applies
    /// before publishing media, timer, file tray and battery activities, so
    /// toggling them updates this preview immediately.
    static func publishedActivities(
        _ activities: [DynamicIslandLiveActivity],
        settings: LiveActivitySettingsSnapshot
    ) -> [DynamicIslandLiveActivity] {
        activities.filter { activity in
            switch activity.kind {
            case .media:
                settings.liveActivitiesEnabled && settings.showMusicLiveActivity
            case .timer:
                settings.liveActivitiesEnabled && settings.showTimerLiveActivity
            case .fileTray:
                settings.liveActivitiesEnabled && settings.showFileDropLiveActivity
            case .battery:
                settings.liveActivitiesEnabled && settings.showBatteryLiveActivity
            default:
                true
            }
        }
    }
}
