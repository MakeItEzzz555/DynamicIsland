import AppKit
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsLocalModule: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let id: String
    let title: String
    let summary: String
    /// A local module is a declarative shortcut to an existing Settings feature.
    let destination: String
    let capabilities: [String]

    static func validate(_ data: Data) throws -> Self {
        guard data.count <= 65_536,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schemaVersion", "id", "title", "summary", "destination", "capabilities"],
              let module = try? JSONDecoder().decode(Self.self, from: data),
              module.schemaVersion == 1,
              module.id.range(of: "^[a-z][a-z0-9.-]{0,63}$", options: .regularExpression) != nil,
              !module.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              module.title.count <= 80, module.summary.count <= 300,
              !module.title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              module.capabilities == ["settings-navigation"],
              SettingsSection.allCases.contains(where: { $0.rawValue == module.destination }) else {
            throw ValidationError.invalid
        }
        return module
    }
    enum ValidationError: LocalizedError {
        case invalid, unsupportedFile
        var errorDescription: String? {
            switch self {
            case .invalid: "Invalid module. Use schema version 1 and a supported Settings destination. Code and additional capabilities are not accepted."
            case .unsupportedFile: "Choose a local JSON module file. Folders, symbolic links, archives and executable plugins are not supported."
            }
        }
    }
    static func read(_ url: URL) throws -> (Self, String) {
        guard url.isFileURL, url.pathExtension.lowercased() == "json" else { throw ValidationError.unsupportedFile }
        let data: Data
        do { data = try SettingsDocumentFile.readJSON(url) }
        catch { throw ValidationError.unsupportedFile }
        return (try validate(data), SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
}

struct SettingsModuleReceipt: Codable, Equatable, Identifiable {
    let module: SettingsLocalModule
    let sha256: String
    var id: String { module.id }
}

@MainActor
final class SettingsModuleImportStore: ObservableObject {
    @Published private(set) var receipts: [SettingsModuleReceipt]
    @Published private(set) var candidate: SettingsModuleReceipt?
    @Published private(set) var isValidating = false
    @Published private(set) var message: String?
    private let defaults: UserDefaults
    private var generation = UUID()
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: "settings.localModules")
            .flatMap { try? JSONDecoder().decode([SettingsModuleReceipt].self, from: $0) } ?? []
        var ids = Set<String>()
        receipts = stored.filter {
            guard let data = try? JSONEncoder().encode($0.module),
                  (try? SettingsLocalModule.validate(data)) != nil else { return false }
            return ids.insert($0.id).inserted
        }
    }
    func inspect(_ url: URL) async {
        let token = UUID(); generation = token
        candidate = nil; message = nil; isValidating = true
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let result = await Task.detached(priority: .userInitiated) { Result { try SettingsLocalModule.read(url) } }.value
        guard generation == token else { return }
        isValidating = false
        switch result {
        case .success(let (module, hash)):
            guard !receipts.contains(where: { $0.id == module.id }) else {
                message = "A module with this identifier is already added."; return
            }
            candidate = SettingsModuleReceipt(module: module, sha256: hash)
        case .failure(let error):
            message = error is SettingsLocalModule.ValidationError ? error.localizedDescription : "Unable to read this module file. Check access and try again."
        }
    }
    func accept() {
        guard let candidate, !receipts.contains(where: { $0.id == candidate.id }) else { return }
        receipts.append(candidate); persist(); self.candidate = nil
        message = "Module added. It can open its declared Settings page; it cannot run code."
    }
    func cancel() { generation = UUID(); candidate = nil; isValidating = false }
    func remove(_ id: String) { receipts.removeAll { $0.id == id }; persist() }
    private func persist() {
        if let data = try? JSONEncoder().encode(receipts) { defaults.set(data, forKey: "settings.localModules") }
    }
}

struct SettingsModuleCatalogView: View {
    let navigate: (SettingsRoute) -> Void
    @ObservedObject var settings: AppSettings
    @StateObject private var imports: SettingsModuleImportStore
    @State private var search = ""
    @State private var filter = 0
    @State private var targeted = false
    static let builtIns: [SettingsSection] = [.agents, .media, .tray, .basket, .clipboard, .timer,
        .stats, .productivity, .rightWorkspace, .messaging, .liveActivities, .gestures]
    init(settings: AppSettings, defaults: UserDefaults = .standard, navigate: @escaping (SettingsRoute) -> Void) {
        self.navigate = navigate
        self.settings = settings
        _imports = StateObject(wrappedValue: SettingsModuleImportStore(defaults: defaults))
    }
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 46)).foregroundStyle(.tint)
            VStack(spacing: 5) {
                Text("Module Store").font(.title2.bold())
                Text("Configure built-in features and add local Settings modules.").foregroundStyle(.secondary)
            }
            Picker("Module source", selection: $filter) {
                Text("All \(Self.builtIns.count + imports.receipts.count)").tag(0)
                Text("Built-in \(Self.builtIns.count)").tag(1)
                Text("Local \(imports.receipts.count)").tag(2)
            }.pickerStyle(.segmented)
            TextField("Search modules", text: $search).textFieldStyle(.roundedBorder)
            if filter != 2 {
                VStack(spacing: 0) {
                ForEach(Self.builtIns.filter { search.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(search) }) { module in
                    HStack(spacing: 12) {
                        SettingsNavigationRow(title: module.rawValue, subtitle: subtitle(module),
                            symbol: module.symbol) { navigate(.section(module)) }
                        if let enabled = enabledBinding(module) {
                            Toggle("Enable \(module.rawValue)", isOn: enabled).labelsHidden().toggleStyle(.switch)
                                .help("Enable or disable \(module.rawValue). Configuration stays available independently.")
                        } else if [.productivity, .messaging].contains(module) {
                            Button("Set up") { navigate(.section(module)) }.controlSize(.small)
                                .accessibilityHint("Review requirements; opening setup does not enable a module")
                        } else {
                            Image(systemName: "gearshape").foregroundStyle(.secondary).accessibilityLabel("Configuration")
                        }
                    }.padding(.vertical, 3)
                    Divider()
                }
                }
            }
            if filter != 1 {
                ForEach(imports.receipts.filter { search.isEmpty || $0.module.title.localizedCaseInsensitiveContains(search) }) { receipt in
                    HStack {
                        SettingsNavigationRow(title: receipt.module.title, subtitle: receipt.module.summary, symbol: "doc.text") {
                            if let section = SettingsSection(rawValue: receipt.module.destination) { navigate(.section(section)) }
                        }
                        Button { imports.remove(receipt.id) } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Remove \(receipt.module.title)")
                    }
                }
            }
            SettingsGroup("Local modules") {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus").font(.title)
                    Text("Drop a DynamicIsland JSON module here").font(.headline)
                    Text("Declarative Settings shortcuts only. Executable plugins are not supported.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Choose…", action: choose).disabled(imports.isValidating)
                }
                .padding(20).frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? Color.accentColor : .secondary,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .dropDestination(for: URL.self) { urls, _ in
                    guard urls.count == 1 else { return false }
                    Task { await imports.inspect(urls[0]) }; return true
                } isTargeted: { targeted = $0 }
                if imports.isValidating { ProgressView("Inspecting module…") }
                if let candidate = imports.candidate {
                    Text(candidate.module.title).font(.headline)
                    Text("Opens \(candidate.module.destination). Requested capability: Settings navigation.")
                    Text("SHA-256: \(candidate.sha256)").font(.caption.monospaced()).textSelection(.enabled)
                    HStack {
                        Button("Cancel", action: imports.cancel)
                        Button("Add Module", action: imports.accept).buttonStyle(.borderedProminent)
                    }
                }
                if let message = imports.message { Text(message).font(.caption).fixedSize(horizontal: false, vertical: true) }
            }
        }.onDisappear { imports.cancel() }
    }
    private func enabledBinding(_ module: SettingsSection) -> Binding<Bool>? {
        switch module {
        case .agents: $settings.agentActivityEnabled
        case .media: $settings.mediaEnabled
        case .tray: $settings.trayEnabled
        case .basket: $settings.floatingBasketEnabled
        case .clipboard: $settings.clipboardHistoryEnabled
        case .timer: $settings.timerEnabled
        case .stats: $settings.statsEnabled
        case .liveActivities: $settings.liveActivitiesEnabled
        case .gestures: $settings.gesturesEnabled
        default: nil
        }
    }
    private func subtitle(_ module: SettingsSection) -> String {
        if let enabled = enabledBinding(module) { return "Built-in · " + (enabled.wrappedValue ? "Enabled" : "Off") }
        return [.messaging, .productivity].contains(module) ? "Built-in · Review permissions and setup" : "Built-in · Configure layout"
    }
    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await imports.inspect(url) }
        }
    }
}
