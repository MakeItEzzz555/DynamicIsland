import AppKit
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
                HelpText("Shown when DynamicIsland starts. Choosing a default page also switches to it now.")
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

/// Normal-user Spotify setup. The release app owns its OAuth Client ID;
/// implementation details and developer overrides are hidden from release UX.
struct SpotifyConnectionSettingsView: View {
    @ObservedObject var controller: SpotifyLibraryController
    #if DEBUG
    @State private var clientIDDraft = ""
    #endif

    var body: some View {
        SettingsGroup("Spotify") {
            HStack(spacing: 10) {
                spotifyIcon
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spotify")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Queue, playlists, liked songs and supported playback actions.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            switch controller.connectionState {
            case .connected:
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Library and queue access are ready.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disconnect Spotify", role: .destructive) {
                        controller.disconnect()
                    }
                }
            case .disconnected, .reconnectRequired:
                HStack {
                    Text(controller.lastError ?? "Connect your Spotify account to enable the library workspace.")
                        .font(.caption)
                        .foregroundStyle(controller.lastError == nil ? Color.secondary : Color.orange)
                    Spacer()
                    Button(controller.connectionState == .reconnectRequired ? "Reconnect Spotify" : "Connect Spotify") {
                        Task { await controller.connect() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .connecting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Spotify sign-in…")
                        .foregroundStyle(.secondary)
                }
            case .needsClientID:
                Text(SpotifySectionCopy.settingsNotConfigured)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            #if DEBUG
            DisclosureGroup("Developer OAuth Override") {
                VStack(alignment: .leading, spacing: 8) {
                    HelpText("Debug only. Release users never see or enter a Client ID.")
                    HStack {
                        TextField("Client ID", text: $clientIDDraft)
                            .textFieldStyle(.roundedBorder)
                        Button("Apply") {
                            controller.setDeveloperClientID(clientIDDraft)
                            clientIDDraft = controller.clientID
                        }
                        .disabled(
                            SpotifyAuthConfiguration.normalizedClientID(clientIDDraft) == nil
                            || clientIDDraft.trimmingCharacters(in: .whitespacesAndNewlines) == controller.clientID
                        )
                        Button("Clear") {
                            clientIDDraft = ""
                            controller.setDeveloperClientID("")
                            clientIDDraft = controller.clientID
                        }
                    }
                    LabeledContent("Redirect URI") {
                        Text(SpotifyWebAPI.redirectURI)
                            .textSelection(.enabled)
                            .font(.system(.caption, design: .monospaced))
                    }
                    LabeledContent("Scopes") {
                        Text(SpotifyWebAPI.scopes.joined(separator: ", "))
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 6)
            }
            .onAppear { clientIDDraft = controller.clientID }
            #endif

            if let error = controller.lastError, controller.connectionState == .connected {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var spotifyIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.18))
                Image(systemName: "music.note")
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch controller.connectionState {
        case .connected:
            Text("Connected").foregroundStyle(.green)
        case .connecting:
            Text("Connecting…").foregroundStyle(.secondary)
        case .disconnected:
            Text("Disconnected").foregroundStyle(.secondary)
        case .reconnectRequired:
            Text("Reconnect required").foregroundStyle(.orange)
        case .needsClientID:
            Text("Not configured").foregroundStyle(.orange)
        }
    }
}
