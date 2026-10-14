import AppKit
import SwiftUI

struct SettingsHiddenAppsView: View {
    @ObservedObject var settings: AppSettings
    @State private var apps: [InstalledApp] = []
    @State private var choosing = false
    @State private var query = ""
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hide the island and let clicks through while one of these apps is in front. Protected approvals, replies, menus and file interactions finish first. DynamicIsland itself is never excluded.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(settings.hiddenInAppBundleIDs.enumerated()), id: \.element) { index, id in
                HStack {
                    Image(systemName: "app").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(apps.first { $0.bundleIdentifier.caseInsensitiveCompare(id) == .orderedSame }?.name ?? id)
                        Text(id).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).accessibilityLabel("Move app up")
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == settings.hiddenInAppBundleIDs.count - 1).accessibilityLabel("Move app down")
                    Button("Remove") { settings.hiddenInAppBundleIDs.removeAll { $0 == id } }
                }
            }
            Button("Add app…") { query = ""; choosing = true }.disabled(settings.hiddenInAppBundleIDs.count >= 64)
        }
        .task { await loadApps() }
        .sheet(isPresented: $choosing) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose an app").font(.title2.bold())
                TextField("Search apps", text: $query).textFieldStyle(.roundedBorder)
                if loading { ProgressView("Finding installed apps…") }
                List(apps.filter { app in
                    app.bundleIdentifier != Bundle.main.bundleIdentifier && !settings.hiddenInAppBundleIDs.contains { $0.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame } &&
                    (query.isEmpty || app.name.localizedCaseInsensitiveContains(query) || app.bundleIdentifier.localizedCaseInsensitiveContains(query))
                }) { app in
                    Button {
                        settings.hiddenInAppBundleIDs.append(app.bundleIdentifier); choosing = false
                    } label: {
                        HStack {
                            Image(systemName: "app.fill").foregroundStyle(.tint)
                            VStack(alignment: .leading) { Text(app.name); Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Hide island in \(app.name)")
                }
                HStack { Spacer(); Button("Cancel") { choosing = false }.keyboardShortcut(.cancelAction) }
            }.padding(20).frame(width: 460, height: 420)
        }
    }
    private func move(_ index: Int, by delta: Int) {
        let next = index + delta
        guard settings.hiddenInAppBundleIDs.indices.contains(index), settings.hiddenInAppBundleIDs.indices.contains(next) else { return }
        settings.hiddenInAppBundleIDs.swapAt(index, next)
    }
    private func loadApps() async {
        guard apps.isEmpty, !loading else { return }
        loading = true
        let found = await Task.detached(priority: .utility) { InstalledAppScanner.scan() }.value
        guard !Task.isCancelled else { loading = false; return }
        apps = found; loading = false
    }
}
