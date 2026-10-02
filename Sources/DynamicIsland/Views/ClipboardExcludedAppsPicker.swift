import SwiftUI

struct ClipboardExcludedAppsPicker: View {
    @ObservedObject var settings: AppSettings
    @State private var apps: [InstalledApp] = []
    @State private var search = ""
    @State private var isLoading = false

    private var visibleApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Find an app", text: $search)
                    .textFieldStyle(.roundedBorder)
                if isLoading { ProgressView().controlSize(.small) }
            }

            if apps.isEmpty, !isLoading {
                Text("No launchable applications found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(visibleApps) { app in
                            Toggle(isOn: binding(for: app.bundleIdentifier)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                        .font(.system(size: 11, weight: .medium))
                                    Text(app.bundleIdentifier)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 170)
            }

            Text("Excluded apps are blocked at capture time; their clipboard contents are never added to history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await loadAppsIfNeeded() }
    }

    private func binding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: {
                settings.clipboardHistoryExcludedAppBundleIDs.contains {
                    $0.caseInsensitiveCompare(bundleID) == .orderedSame
                }
            },
            set: { excluded in
                var ids = settings.clipboardHistoryExcludedAppBundleIDs
                ids.removeAll { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
                if excluded { ids.append(bundleID) }
                settings.clipboardHistoryExcludedAppBundleIDs = ids.sorted()
            }
        )
    }

    private func loadAppsIfNeeded() async {
        guard apps.isEmpty, !isLoading else { return }
        isLoading = true
        let result = await Task.detached(priority: .utility) {
            InstalledAppScanner.scan()
        }.value
        apps = result
        isLoading = false
    }
}
