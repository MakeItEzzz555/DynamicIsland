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
                "Spotify isn't configured in this build yet. Release users never need to enter a Client ID.",
                action: "Open Settings",
                perform: onOpenSettings
            )
        case .disconnected:
            setupMessage(
                controller.lastError ?? "Connect Spotify to use your queue, playlists and liked songs.",
                action: "Connect Spotify",
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
            .accessibilityLabel("Add (item.title) to queue")

            Button {
                Task { await controller.setSaved(item, saved: !isLikedTab) }
            } label: {
                Image(systemName: isLikedTab ? "heart.fill" : "heart")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isLikedTab ? .green : .white.opacity(0.55))
            .help(isLikedTab ? "Remove from Liked Songs" : "Save to Liked Songs")
            .accessibilityLabel(isLikedTab ? "Remove (item.title) from Liked Songs" : "Save (item.title) to Liked Songs")
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

struct CalendarSectionView: View {
    @ObservedObject var controller: CalendarEventsController
    let layoutStore: IslandLayoutStore?
    @Environment(\.rightWorkspacePageIsActive) private var isWorkspacePageActive

    var body: some View {
        Group {
            switch controller.accessState {
            case .fullAccess:
                if controller.events.isEmpty {
                    message(controller.statusText, action: nil)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(controller.events) { event in
                                CalendarEventRow(event: event) { controller.open(event) }
                            }
                        }
                    }
                    .modifier(WorkspaceScrollRegion(layoutStore: layoutStore))
                }
            case .notDetermined:
                message("Show your upcoming events here.", action: ("Allow Calendar Access", { Task { await controller.requestAccess() } }))
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red.opacity(0.75))
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if let action {
                Button(action: action.1) {
                    Text(action.0)
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                }
                .buttonStyle(WorkspaceTileButtonStyle(isOn: true, accent: .red, cornerRadius: 11))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CalendarEventRow: View {
    let event: CalendarEventDescriptor
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Text(timeText)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if event.meetingURL != nil {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .help("Open the event link")
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.9))
        .accessibilityLabel("\(event.title), \(timeText)")
    }

    private var color: Color {
        guard let rgb = event.calendarColor, rgb.count == 3 else { return .white.opacity(0.4) }
        return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
    }

    private var timeText: String {
        let day = event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let prefix = Calendar.current.isDateInToday(event.startDate) ? "Today"
            : Calendar.current.isDateInTomorrow(event.startDate) ? "Tomorrow" : day
        let calendarName = event.calendarTitle.isEmpty ? "" : " · \(event.calendarTitle)"
        if event.isAllDay { return "\(prefix) · All day\(calendarName)" }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(prefix) \(start)–\(end)\(calendarName)"
    }
}
