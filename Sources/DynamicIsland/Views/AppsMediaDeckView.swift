import AppKit
import SwiftUI

/// Right-workspace Apps & Media page: real installed apps, Spotify library
/// data from the Web API when connected, and EventKit calendar events.
/// Nothing here is sample data; missing access is shown as such.
struct AppsMediaDeckView: View {
    let services: WorkspaceServices
    let media: MediaController?
    let sections: [RightWorkspaceSection]
    let layoutStore: IslandLayoutStore?
    var onOpenSettings: () -> Void = {}

    @State private var selected: RightWorkspaceSection?

    var body: some View {
        let current = selected.flatMap { sections.contains($0) ? $0 : nil } ?? sections.first
        VStack(alignment: .leading, spacing: 6) {
            if sections.count > 1 {
                HStack(spacing: 5) {
                    ForEach(sections) { section in
                        Button {
                            selected = section
                        } label: {
                            Label(section.title, systemImage: section.symbolName)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(section == current ? 0.92 : 0.55))
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                        }
                        .buttonStyle(WorkspaceTileButtonStyle(isOn: section == current, accent: .white, cornerRadius: 11))
                        .accessibilityAddTraits(section == current ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
            }
            Group {
                switch current {
                case .appLibrary:
                    AppLibrarySectionView(store: services.appLibrary, layoutStore: layoutStore)
                case .spotify:
                    SpotifySectionView(controller: services.spotify, media: media, layoutStore: layoutStore, onOpenSettings: onOpenSettings)
                case .calendar:
                    CalendarSectionView(controller: services.calendar, layoutStore: layoutStore)
                case nil:
                    Text("No Apps & Media sections are enabled")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Registers the scrollable list as the expanded content scroll region so
/// vertical scrolling scrolls it instead of triggering island gestures.
private struct WorkspaceScrollRegion: ViewModifier {
    let layoutStore: IslandLayoutStore?

    func body(content: Content) -> some View {
        if let layoutStore {
            content
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: WorkspaceScrollRegionKey.self,
                            value: proxy.frame(in: .named(IslandCanvasCoordinateSpace.name))
                        )
                    }
                }
                .onPreferenceChange(WorkspaceScrollRegionKey.self) { frame in
                    layoutStore.setExpandedContentScrollRegion(IslandCanvasCoordinateSpace.appKitLocalRect(
                        fromSwiftUI: frame,
                        canvasHeight: layoutStore.canvasSize.height
                    ))
                }
                .onDisappear { layoutStore.setExpandedContentScrollRegion(.zero) }
        } else {
            content
        }
    }
}

private struct WorkspaceScrollRegionKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

// MARK: - App Library

struct AppLibrarySectionView: View {
    @ObservedObject var store: AppLibraryStore
    let layoutStore: IslandLayoutStore?
    @State private var query = ""
    @Environment(\.rightWorkspacePageIsActive) private var isWorkspacePageActive

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search apps", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .onSubmit(launchFirstMatch)
                if let error = store.lastLaunchError {
                    Text(error)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            content
        }
        .onAppear {
            if isWorkspacePageActive { store.refreshIfNeeded() }
        }
        .onChange(of: isWorkspacePageActive) { _, active in
            if active { store.refreshIfNeeded() }
        }
    }

    @ViewBuilder
    private var content: some View {
        let results = store.filtered(query)
        if store.state == .loading || (store.state == .idle && store.apps.isEmpty) {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            Text(query.isEmpty ? "No applications found" : "No apps match “\(query)”")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    if query.isEmpty {
                        let pinned = uniqueApps(store.favorites + store.recents)
                        if !pinned.isEmpty {
                            iconGrid(Array(pinned.prefix(6)))
                            Divider().overlay(.white.opacity(0.08))
                        }
                    }
                    iconGrid(results)
                }
                .padding(.vertical, 2)
            }
            .modifier(WorkspaceScrollRegion(layoutStore: layoutStore))
        }
    }

    private func iconGrid(_ apps: [InstalledApp]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 76), spacing: 4)], spacing: 4) {
            ForEach(apps) { app in
                AppLibraryIcon(app: app, store: store)
            }
        }
    }

    private func uniqueApps(_ apps: [InstalledApp]) -> [InstalledApp] {
        var seen = Set<String>()
        return apps.filter { seen.insert($0.id).inserted }
    }

    private func launchFirstMatch() {
        guard !query.isEmpty, let first = store.filtered(query).first else { return }
        Task { await store.launch(first) }
    }
}

private struct AppLibraryIcon: View {
    let app: InstalledApp
    @ObservedObject var store: AppLibraryStore

    var body: some View {
        Button {
            Task { await store.launch(app) }
        } label: {
            VStack(spacing: 3) {
                Image(nsImage: store.icon(for: app))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                Text(app.name)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(WorkspaceTileButtonStyle(isOn: store.isFavorite(app), accent: .yellow, cornerRadius: 9))
        .help("Open \(app.name)")
        .contextMenu {
            Button(store.isFavorite(app) ? "Remove from Favorites" : "Add to Favorites") {
                store.toggleFavorite(app)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
        }
        .accessibilityLabel("Open \(app.name)")
    }
}

// MARK: - Spotify

/// User-facing copy for the Spotify section. The Web API library (queue,
/// playlists, liked songs) needs an app Client ID shipped with the build;
/// local Spotify playback controls use the Spotify app directly and never
/// depend on it, so the unconfigured message must not imply otherwise.
enum SpotifySectionCopy {
    static let notConfigured =
        "Spotify library (queue, playlists, liked songs) is not available in this build. Now Playing controls for the Spotify app still work."
    static let settingsNotConfigured =
        "Spotify library access is not configured in this build (no Spotify app Client ID is packaged). Now Playing detection and playback controls for the Spotify app work without it."
}

struct SpotifySectionView: View {
    @ObservedObject var controller: SpotifyLibraryController
    let media: MediaController?
    let layoutStore: IslandLayoutStore?
    let onOpenSettings: () -> Void
    @Environment(\.rightWorkspacePageIsActive) private var isWorkspacePageActive

    enum Tab: String, CaseIterable, Identifiable {
        case queue = "Queue"
        case playlists = "Playlists"
        case liked = "Liked"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .queue

    var body: some View {
        switch controller.connectionState {
        case .needsClientID:
            setupMessage(
                SpotifySectionCopy.notConfigured,
                action: "Open Settings",
                perform: onOpenSettings
            )
        case .disconnected:
            setupMessage(
                controller.lastError ?? "Connect Spotify to use your queue, playlists and liked songs.",
                action: "Connect Spotify",
                perform: { Task { await controller.connect() } }
            )
        case .reconnectRequired:
            setupMessage(
                controller.lastError ?? "Spotify needs to be reconnected.",
                action: "Reconnect Spotify",
                perform: { Task { await controller.connect() } }
            )
        case .connecting:
            ProgressView("Waiting for Spotify sign-in…")
                .controlSize(.small)
                .font(.system(size: 9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .connected:
            connected
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 5) {
            toolbar
            if tab == .playlists, controller.selectedPlaylist != nil {
                playlistDetail
            } else {
                libraryList
            }
        }
        .task {
            if isWorkspacePageActive, controller.snapshot == nil {
                await controller.refresh()
            }
        }
        .onChange(of: isWorkspacePageActive) { _, active in
            if active, controller.snapshot == nil {
                Task { await controller.refresh() }
            }
        }
        .onChange(of: tab) { _, _ in
            if tab != .playlists { controller.closePlaylist() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { option in
                Button(option.rawValue) {
                    tab = option
                    if option != .playlists { controller.closePlaylist() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(option == tab ? 0.9 : 0.45))
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(.white.opacity(option == tab ? 0.1 : 0), in: Capsule())
            }
            Spacer(minLength: 0)
            if let error = controller.lastError {
                Text(error)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.85))
                    .lineLimit(1)
            }
            Button {
                Task { await controller.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .disabled(controller.isLoading)
            .accessibilityLabel("Refresh Spotify")
        }
    }

    @ViewBuilder
    private var libraryList: some View {
        let items = items(for: tab)
        if controller.snapshot == nil {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            Text(emptyText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        spotifyRow(item, tab: tab)
                            .onAppear {
                                if item.id == items.last?.id {
                                    loadMoreIfNeeded(for: tab)
                                }
                            }
                    }
                    if isLoadingMore(for: tab) {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                }
            }
            .modifier(WorkspaceScrollRegion(layoutStore: layoutStore))
        }
    }

    @ViewBuilder
    private var playlistDetail: some View {
        if let playlist = controller.selectedPlaylist {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Button {
                        controller.closePlaylist()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to playlists")
                    Text(playlist.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        _ = media?.playSpotifyURI(playlist.uri)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Play playlist in Spotify")
                }
                if controller.isLoadingPlaylist, controller.playlistItems.isEmpty {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if controller.playlistItems.isEmpty {
                    Text("No playable items in this playlist")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(controller.playlistItems) { item in
                                spotifyTrackRow(item)
                                    .onAppear {
                                        if item.id == controller.playlistItems.last?.id {
                                            Task { await controller.loadMorePlaylistItems() }
                                        }
                                    }
                            }
                            if controller.isLoadingPlaylist {
                                ProgressView().controlSize(.mini).frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .modifier(WorkspaceScrollRegion(layoutStore: layoutStore))
                }
            }
        }
    }

    private func spotifyRow(_ item: SpotifyMediaItem, tab: Tab) -> some View {
        HStack(spacing: 5) {
            Button {
                if tab == .playlists {
                    Task { await controller.loadPlaylist(item) }
                } else {
                    _ = media?.playSpotifyURI(item.uri)
                }
            } label: {
                rowLabel(item, symbol: tab == .playlists ? "music.note.list" : "music.note")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
            .help(tab == .playlists ? "Browse playlist" : "Play in Spotify")

            if tab == .playlists {
                Button {
                    _ = media?.playSpotifyURI(item.uri)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.plain)
                .help("Play playlist in Spotify")
            } else {
                itemActions(item, isLikedTab: tab == .liked)
            }
        }
        .frame(height: 28)
    }

    private func spotifyTrackRow(_ item: SpotifyMediaItem) -> some View {
        HStack(spacing: 5) {
            Button {
                _ = media?.playSpotifyURI(item.uri)
            } label: {
                rowLabel(item, symbol: "music.note")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
            itemActions(item, isLikedTab: isLiked(item))
        }
        .frame(height: 28)
    }

    private func rowLabel(_ item: SpotifyMediaItem, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(.green.opacity(0.8))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func itemActions(_ item: SpotifyMediaItem, isLikedTab: Bool) -> some View {
        let pending = controller.pendingItemURIs.contains(item.uri)
        if pending {
            ProgressView().controlSize(.mini).frame(width: 18)
        } else {
            Button {
                Task { await controller.addToQueue(item) }
            } label: {
                Image(systemName: "text.badge.plus")
            }
            .buttonStyle(.plain)
            .help("Add to queue")
            .accessibilityLabel("Add \(item.title) to queue")

            Button {
                Task { await controller.setSaved(item, saved: !isLikedTab) }
            } label: {
                Image(systemName: isLikedTab ? "heart.fill" : "heart")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isLikedTab ? .green : .white.opacity(0.55))
            .help(isLikedTab ? "Remove from Liked Songs" : "Save to Liked Songs")
            .accessibilityLabel(isLikedTab ? "Remove \(item.title) from Liked Songs" : "Save \(item.title) to Liked Songs")
        }
    }

    private func isLiked(_ item: SpotifyMediaItem) -> Bool {
        controller.snapshot?.likedSongs.contains(where: { $0.id == item.id }) ?? false
    }

    private func items(for tab: Tab) -> [SpotifyMediaItem] {
        guard let snapshot = controller.snapshot else { return [] }
        switch tab {
        case .queue: return snapshot.queue
        case .playlists: return snapshot.playlists
        case .liked: return snapshot.likedSongs
        }
    }

    private func loadMoreIfNeeded(for tab: Tab) {
        switch tab {
        case .queue:
            break
        case .playlists:
            guard controller.hasMorePlaylists else { return }
            Task { await controller.loadMorePlaylists() }
        case .liked:
            guard controller.hasMoreLikedSongs else { return }
            Task { await controller.loadMoreLikedSongs() }
        }
    }

    private func isLoadingMore(for tab: Tab) -> Bool {
        switch tab {
        case .queue: false
        case .playlists: controller.isLoadingMorePlaylists
        case .liked: controller.isLoadingMoreLikedSongs
        }
    }

    private var emptyText: String {
        switch tab {
        case .queue: "Nothing queued (Spotify reports no active playback)"
        case .playlists: "No playlists"
        case .liked: "No liked songs"
        }
    }

    private func setupMessage(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 7) {
            spotifySourceIcon
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(action: perform) {
                Text(action)
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 22)
            }
            .buttonStyle(WorkspaceTileButtonStyle(isOn: true, accent: .green, cornerRadius: 11))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var spotifySourceIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green.opacity(0.75))
        }
    }
}

// MARK: - Calendar

/// Right Workspace Calendar: a day navigator (Droppy ToDo due-date stepper
/// metrics) whose date opens a native graphical DatePicker in a popover,
/// followed by the real EventKit events of the selected local day.
struct CalendarSectionView: View {
    @ObservedObject var controller: CalendarEventsController
    let layoutStore: IslandLayoutStore?
    @Environment(\.rightWorkspacePageIsActive) private var isWorkspacePageActive
    @Environment(\.islandDisplayMetrics) private var displayMetrics

    var body: some View {
        Group {
            switch controller.accessState {
            case .fullAccess:
                VStack(alignment: .leading, spacing: displayMetrics.spacing(6, minimum: 4, maximum: 8)) {
                    CalendarDayNavigator(controller: controller, layoutStore: layoutStore)
                    if controller.dayEvents.isEmpty {
                        message(controller.dayStatusText, action: nil)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(controller.dayEvents) { event in
                                    CalendarEventRow(event: event, selectedDay: controller.selectedDay) { controller.open(event) }
                                }
                            }
                        }
                        .modifier(WorkspaceScrollRegion(layoutStore: layoutStore))
                    }
                }
            case .notDetermined:
                message("Show your calendar events here.", action: ("Allow Calendar Access", { Task { await controller.requestAccess() } }))
            case .denied, .restricted, .writeOnly:
                message(controller.statusText, action: ("Open Privacy Settings", {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }))
            }
        }
        .onAppear {
            guard isWorkspacePageActive else { return }
            controller.refresh()
            controller.startObserving()
        }
        .onChange(of: isWorkspacePageActive) { _, active in
            if active {
                controller.refresh()
                controller.startObserving()
            } else {
                controller.stopObserving()
            }
        }
        .onDisappear { controller.stopObserving() }
    }

    private func message(_ text: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 7) {
            Image(systemName: "calendar")
                .font(.system(size: displayMetrics.icon(16, minimum: 13, maximum: 19), weight: .semibold))
                .foregroundStyle(.red.opacity(0.75))
            Text(text)
                .font(.system(size: displayMetrics.font(9.5, minimum: 8.6, maximum: 11.4), weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if let action {
                Button(action: action.1) {
                    Text(action.0)
                        .font(.system(size: displayMetrics.font(9.5, minimum: 8.6, maximum: 11.4), weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 22 * displayMetrics.compactControlScale)
                }
                .buttonStyle(WorkspaceTileButtonStyle(isOn: true, accent: .red, cornerRadius: 11))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// ‹ [calendar · date] › plus Today. Metrics follow Droppy's due-date
/// stepper row (30 pt row, 10 pt radius, 1 pt 0.12 stroke, 20 pt step
/// circles, 12 pt semibold monospaced date), scaled by display metrics.
struct CalendarDayNavigator: View {
    @ObservedObject var controller: CalendarEventsController
    let layoutStore: IslandLayoutStore?
    @Environment(\.islandDisplayMetrics) private var displayMetrics
    @State private var isPickerPresented = false

    var body: some View {
        let control = displayMetrics.compactControlScale
        HStack(spacing: displayMetrics.spacing(6, minimum: 4, maximum: 8)) {
            HStack(spacing: 6) {
                stepButton("chevron.left", label: "Previous day") { controller.shiftSelectedDay(by: -1) }
                Button {
                    isPickerPresented.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: displayMetrics.icon(10.5, minimum: 9, maximum: 13), weight: .semibold))
                            .foregroundStyle(.red)
                        Text(Self.dateLabel(controller.selectedDay))
                            .font(.system(size: displayMetrics.font(11, minimum: 9.8, maximum: 12.8), weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 24 * control)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.92))
                .help("Choose a date")
                .accessibilityLabel("Selected date, \(controller.selectedDay.formatted(date: .complete, time: .omitted))")
                .accessibilityHint("Opens a date picker")
                .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
                    CalendarDatePickerPopover(controller: controller, isPresented: $isPickerPresented)
                }
                stepButton("chevron.right", label: "Next day") { controller.shiftSelectedDay(by: 1) }
            }
            .padding(.horizontal, 6)
            .frame(height: 30 * control)
            .background(
                RoundedRectangle(cornerRadius: 10 * displayMetrics.cornerRadiusScale, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10 * displayMetrics.cornerRadiusScale, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )

            if !controller.isSelectedDayToday {
                Button { controller.selectToday() } label: {
                    Text("Today")
                        .font(.system(size: displayMetrics.font(10, minimum: 9, maximum: 11.6), weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 26 * control)
                }
                .buttonStyle(WorkspaceTileButtonStyle(isOn: true, accent: .red, cornerRadius: 13))
                .fixedSize()
                .accessibilityHint("Show today's events")
            }
        }
        // The popover is a separate native window; while it is open the
        // island must stay expanded even with the pointer inside it.
        .onChange(of: isPickerPresented) { _, open in
            layoutStore?.setTransientInteraction(open, owner: .calendarDatePicker)
        }
        .onDisappear {
            isPickerPresented = false
            layoutStore?.setTransientInteraction(false, owner: .calendarDatePicker)
        }
    }

    static func dateLabel(_ day: Date) -> String {
        day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: displayMetrics.icon(10, minimum: 9, maximum: 12), weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20 * displayMetrics.compactControlScale, height: 20 * displayMetrics.compactControlScale)
                .background(Circle().fill(.white.opacity(0.08)))
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Native graphical DatePicker, red tint (ExploreSwiftUI "DatePicker
/// colors" + "Graphical" techniques). Selection drives the controller, which
/// queries EventKit once per chosen day.
struct CalendarDatePickerPopover: View {
    @ObservedObject var controller: CalendarEventsController
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(
                "Select Date",
                selection: Binding(
                    get: { controller.selectedDay },
                    set: { controller.selectDay(containing: $0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(.red)
            .accessibilityLabel("Select date")

            HStack {
                Button("Today") { controller.selectToday() }
                    .disabled(controller.isSelectedDayToday)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        // SwiftUI-drawn controls take the Calendar red; the AppKit-drawn
        // graphical grid follows the system accent colour on macOS.
        .tint(.red)
        .padding(12)
        .frame(width: 236)
    }
}

private struct CalendarEventRow: View {
    let event: CalendarEventDescriptor
    let selectedDay: Date
    let onOpen: () -> Void
    @Environment(\.islandDisplayMetrics) private var displayMetrics

    var body: some View {
        let isOngoing = !event.isAllDay && event.startDate <= Date() && Date() < event.endDate
        Button(action: onOpen) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: 24 * displayMetrics.compactControlScale)
                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title)
                        .font(.system(size: displayMetrics.font(10, minimum: 9, maximum: 11.8), weight: .semibold))
                        .lineLimit(1)
                    Text(CalendarEventPresentation.timeText(event, selectedDay: selectedDay))
                        .font(.system(size: displayMetrics.font(8.5, minimum: 7.8, maximum: 10), weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isOngoing {
                    Text("Now")
                        .font(.system(size: displayMetrics.font(8, minimum: 7.4, maximum: 9.4), weight: .bold))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
                if event.meetingURL != nil {
                    Image(systemName: "video.fill")
                        .font(.system(size: displayMetrics.icon(9, minimum: 8, maximum: 11)))
                        .foregroundStyle(.white.opacity(0.6))
                        .help("Open the event link")
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 30 * displayMetrics.compactControlScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.9))
        .accessibilityLabel(CalendarEventPresentation.accessibilityText(event, selectedDay: selectedDay, isOngoing: isOngoing))
        .accessibilityHint(event.meetingURL != nil ? "Opens the event link" : "Opens Calendar")
    }

    private var color: Color {
        guard let rgb = event.calendarColor, rgb.count == 3 else { return .white.opacity(0.4) }
        return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
    }
}

/// Row text, relative to the selected day.
enum CalendarEventPresentation {
    /// Times relative to the selected day; a day prefix appears only for an
    /// end or start that falls on another day (events crossing midnight).
    static func timeText(_ event: CalendarEventDescriptor, selectedDay: Date, calendar: Calendar = .current) -> String {
        let calendarName = event.calendarTitle.isEmpty ? "" : " · \(event.calendarTitle)"
        if event.isAllDay { return "All day\(calendarName)" }
        func stamp(_ date: Date) -> String {
            let time = date.formatted(date: .omitted, time: .shortened)
            guard !calendar.isDate(date, inSameDayAs: selectedDay) else { return time }
            return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }
        return "\(stamp(event.startDate))–\(stamp(event.endDate))\(calendarName)"
    }

    static func accessibilityText(_ event: CalendarEventDescriptor, selectedDay: Date, isOngoing: Bool) -> String {
        var parts = [event.title, timeText(event, selectedDay: selectedDay)]
        if isOngoing { parts.append("in progress") }
        if event.meetingURL != nil { parts.append("has a meeting link") }
        return parts.joined(separator: ", ")
    }
}
