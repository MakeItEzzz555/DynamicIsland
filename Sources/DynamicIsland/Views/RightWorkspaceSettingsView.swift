import SwiftUI

/// Personalization of the Island page's right workspace. Every change is
/// normalized by the store and immediately reflected in the live preview,
/// which renders the real workspace components.
struct RightWorkspaceSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var workspace: RightWorkspaceStore
    let dependencies: SettingsPreviewDependencies?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let dependencies {
                RightWorkspaceSettingsPreview(settings: settings, workspace: workspace, dependencies: dependencies)
            }

            SettingsGroup("Pages") {
                orderedList(
                    items: workspace.configuration.pageOrder,
                    hidden: workspace.configuration.hiddenPages,
                    title: \.title,
                    symbol: \.symbolName,
                    toggle: { page, visible in
                        workspace.update { $0.setVisibility(page, visible: visible, in: \.hiddenPages) }
                    },
                    move: { page, offset in workspace.update { $0.move(\.pageOrder, item: page, by: offset) } }
                )
                Picker("Default page", selection: Binding(
                    get: { workspace.configuration.defaultPage },
                    set: { page in workspace.update { $0.defaultPage = page } }
                )) {
                    ForEach(workspace.configuration.visiblePages) { page in
                        Text(page.title).tag(page)
                    }
                }
                Picker("Page indicator", selection: Binding(
                    get: { workspace.configuration.indicatorStyle },
                    set: { style in workspace.update { $0.indicatorStyle = style } }
                )) {
                    ForEach(RightWorkspaceIndicatorStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Toggle("Two-finger swipe changes pages", isOn: Binding(
                    get: { workspace.configuration.swipeEnabled },
                    set: { enabled in workspace.update { $0.swipeEnabled = enabled } }
                ))
                HelpText("Swipe left or right over the right half of the Island page. The page dots are always clickable, and VoiceOver can change pages with increment and decrement.")
            }

            SettingsGroup("Productivity Tools") {
                orderedList(
                    items: workspace.configuration.toolOrder,
                    hidden: workspace.configuration.hiddenTools,
                    title: \.title,
                    symbol: \.symbolName,
                    toggle: { tool, visible in
                        workspace.update { $0.setVisibility(tool, visible: visible, in: \.hiddenTools) }
                    },
                    move: { tool, offset in workspace.update { $0.move(\.toolOrder, item: tool, by: offset) } }
                )
            }

            SettingsGroup("Apps & Media Sections") {
                orderedList(
                    items: workspace.configuration.sectionOrder,
                    hidden: workspace.configuration.hiddenSections,
                    title: \.title,
                    symbol: \.symbolName,
                    toggle: { section, visible in
                        workspace.update { $0.setVisibility(section, visible: visible, in: \.hiddenSections) }
                    },
                    move: { section, offset in workspace.update { $0.move(\.sectionOrder, item: section, by: offset) } }
                )
            }

            if let spotify = dependencies?.workspaceServices.spotify {
                SpotifyConnectionSettingsView(controller: spotify)
            }

            Button("Reset Right Workspace to Defaults") {
                workspace.resetToDefaults()
            }
        }
    }

    private func orderedList<Item: Identifiable & Hashable>(
        items: [Item],
        hidden: Set<Item>,
        title: KeyPath<Item, String>,
        symbol: KeyPath<Item, String>,
        toggle: @escaping (Item, Bool) -> Void,
        move: @escaping (Item, Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { !hidden.contains(item) },
                        set: { toggle(item, $0) }
                    )) {
                        Label(item[keyPath: title], systemImage: item[keyPath: symbol])
                    }
                    Spacer()
                    Button {
                        move(item, -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(item[keyPath: title]) up")
                    Button {
                        move(item, 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == items.count - 1)
                    .accessibilityLabel("Move \(item[keyPath: title]) down")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// Spotify Web API setup: the user's own Spotify app Client ID, the exact
/// redirect URI to register, the exact scopes, and connect/disconnect.
struct SpotifyConnectionSettingsView: View {
    @ObservedObject var controller: SpotifyLibraryController
    @State private var clientIDDraft = ""

    var body: some View {
        SettingsGroup("Spotify Library (Web API)") {
            HelpText("Queue, playlists and liked songs come from the Spotify Web API. Create an app at developer.spotify.com, add the redirect URI below, and paste its Client ID. Playback of a chosen item uses the Spotify app.")
            LabeledContent("Redirect URI") {
                Text(SpotifyWebAPI.redirectURI).textSelection(.enabled).font(.system(.body, design: .monospaced))
            }
            LabeledContent("Scopes (read-only)") {
                Text(SpotifyWebAPI.scopes.joined(separator: ", ")).textSelection(.enabled)
            }
            HStack {
                TextField("Client ID", text: $clientIDDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { controller.setClientID(clientIDDraft) }
                    .disabled(clientIDDraft.trimmingCharacters(in: .whitespaces) == controller.clientID)
            }
            HStack {
                Text(statusText).foregroundStyle(.secondary)
                Spacer()
                switch controller.connectionState {
                case .connected:
                    Button("Disconnect", role: .destructive) { controller.disconnect() }
                case .disconnected:
                    Button("Connect Spotify") { Task { await controller.connect() } }
                case .connecting:
                    ProgressView().controlSize(.small)
                case .needsClientID:
                    EmptyView()
                }
            }
            if let error = controller.lastError {
                Text(error).foregroundStyle(.orange)
            }
        }
        .onAppear { clientIDDraft = controller.clientID }
    }

    private var statusText: String {
        switch controller.connectionState {
        case .needsClientID: "Not configured"
        case .disconnected: "Not connected"
        case .connecting: "Waiting for Spotify sign-in…"
        case .connected: "Connected"
        }
    }
}
