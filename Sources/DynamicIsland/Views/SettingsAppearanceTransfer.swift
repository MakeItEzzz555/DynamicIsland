import AppKit
import CryptoKit
import Darwin
import SwiftUI

enum SettingsDocumentFile {
    static func readJSON(_ url: URL) throws -> Data {
        guard url.isFileURL, url.pathExtension.lowercased() == "json" else { throw SettingsTransferError.invalid }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw SettingsTransferError.invalid }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size >= 0, metadata.st_size <= 65_536 else { throw SettingsTransferError.invalid }
        let data = try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).read(upToCount: 65_537) ?? Data()
        guard data.count <= 65_536 else { throw SettingsTransferError.invalid }
        return data
    }
}

/// Only scalar appearance preferences cross this boundary. Permissions, sources,
/// credentials, histories, file paths and integration identities are excluded.
enum SettingsTransferValue: Codable, Equatable {
    case boolean(Bool), number(Double), text(String)
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let bool = try? value.decode(Bool.self) { self = .boolean(bool) }
        else if let number = try? value.decode(Double.self), number.isFinite { self = .number(number) }
        else if let text = try? value.decode(String.self), text.count <= 64 { self = .text(text) }
        else { throw SettingsTransferError.invalid }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .boolean(let bool): try value.encode(bool)
        case .number(let number): try value.encode(number)
        case .text(let text): try value.encode(text)
        }
    }
    var object: Any {
        switch self { case .boolean(let value): value; case .number(let value): value; case .text(let value): value }
    }
    init?(object: Any) {
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .boolean(number.boolValue) }
            else if number.doubleValue.isFinite { self = .number(number.doubleValue) }
            else { return nil }
        } else if let text = object as? String, text.count <= 64 { self = .text(text) }
        else { return nil }
    }
}
struct SettingsTransferDocument: Codable {
    let version: Int
    let scope: String
    let values: [String: SettingsTransferValue]
    let sha256: String
    var workspace: Data? = nil
    static func checksum(_ values: [String: SettingsTransferValue]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(values)).map { String(format: "%02x", $0) }.joined()
    }
    static func checksum(_ values: [String: SettingsTransferValue], workspace: Data) throws -> String {
        struct Payload: Encodable { let values: [String: SettingsTransferValue]; let workspace: Data }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(Payload(values: values, workspace: workspace)))
            .map { String(format: "%02x", $0) }.joined()
    }
    func inspectedWorkspace() throws -> WorkspaceConfiguration? {
        guard let workspace else { return nil }
        guard workspace.count <= 32_768 else { throw SettingsTransferError.invalid }
        let configuration = try JSONDecoder().decode(WorkspaceConfiguration.self, from: workspace)
        guard configuration.schemaVersion == WorkspaceConfiguration.currentVersion,
              configuration.placements.count <= 64, configuration.groups.count <= 32,
              configuration.placements.allSatisfy({ $0.id.rawValue.count <= 128 && ($0.groupID?.rawValue.count ?? 0) <= 128 }),
              configuration.groups.allSatisfy({ $0.id.rawValue.count <= 128 && $0.members.count <= 64 }),
              configuration == configuration.normalized() else { throw SettingsTransferError.invalid }
        // The normal preference reader recovers corrupt legacy data. Imports instead reject loss or unknown fields.
        func canonical(_ data: Data) throws -> Data {
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var navigation = object["navigation"] as? [String: Any],
                  let hidden = navigation["hidden"] as? [String] else { throw SettingsTransferError.invalid }
            navigation["hidden"] = hidden.sorted(); object["navigation"] = navigation
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        guard try canonical(workspace) == canonical(JSONEncoder().encode(configuration)) else { throw SettingsTransferError.invalid }
        return configuration
    }
}
enum SettingsTransferError: LocalizedError {
    case invalid
    var errorDescription: String? { "Could not import settings. Check the version, checksum, supported preferences and workspace layout." }
}

struct SettingsAppearanceTransferView: View {
    @ObservedObject var settings: AppSettings
    var workspace: WorkspaceCustomizationStore? = nil
    @State private var pending: SettingsTransferDocument?
    @State private var changed: [String] = []
    @State private var message: String?
    @State private var showConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transfer settings")
                Spacer()
                Button("Export…", action: export)
                Button("Import…", action: chooseImport)
            }
            Text("Appearance, motion, display preferences and saved widget placement. Permissions, feature activation, credentials and personal content stay on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.caption) }
        }
        .sheet(isPresented: $showConfirmation, onDismiss: { pending = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review settings import").font(.title2.bold())
                Text("\(changed.count) stored preferences will change. Active sessions and private data are excluded.")
                if pending?.workspace != nil { Text("Saved widget placement and page order will also be replaced.").font(.callout) }
                ScrollView { VStack(alignment: .leading) { ForEach(changed, id: \.self) { Text($0).font(.caption.monospaced()) } } }
                HStack {
                    Spacer()
                    Button("Cancel") { pending = nil; showConfirmation = false }.keyboardShortcut(.cancelAction)
                    Button("Apply") {
                        guard let pending else { return }
                        do { try settings.applySettingsTransfer(pending, workspace: workspace); message = "Settings imported." }
                        catch { message = SettingsTransferError.invalid.localizedDescription }
                        self.pending = nil; showConfirmation = false
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 480, height: 380)
        }
    }
    private func export() {
        do {
            let data = try settings.exportAppearanceTransfer(workspace: workspace?.configuration)
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "DynamicIsland-settings.json"
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do { try data.write(to: url, options: .atomic); message = "Appearance settings exported." }
                catch { message = "Could not save the export. Check the destination and try again." }
            }
        } catch { message = "Could not prepare this appearance export." }
    }
    private func chooseImport() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let scope = url.startAccessingSecurityScopedResource()
            defer { if scope { url.stopAccessingSecurityScopedResource() } }
            do {
                let document = try settings.inspectAppearanceTransfer(SettingsDocumentFile.readJSON(url))
                changed = settings.appearanceTransferChanges(document)
                pending = document; showConfirmation = true
            } catch { message = SettingsTransferError.invalid.localizedDescription }
        }
    }
}

struct SettingsHardResetView: View {
    @ObservedObject var settings: AppSettings
    var workspace: WorkspaceCustomizationStore?
    @State private var reviewing = false
    @State private var confirmation = ""
    @State private var resetCompleted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Hard reset preferences…") { confirmation = ""; reviewing = true }
            if resetCompleted { Text("Preferences and widget placement reset.").font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $reviewing) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reset DynamicIsland preferences?").font(.title2.bold())
                Text("Restores app preferences and saved widget placement. Camera navigation will stop. Clipboard history and privacy preferences, files, shortcuts, credentials, permissions and Agent/Terminal sessions are preserved. Login and app visibility stay unchanged.")
                Text("Type RESET to confirm.").font(.callout)
                TextField("RESET", text: $confirmation).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Confirm reset by typing RESET")
                HStack {
                    Spacer()
                    Button("Cancel") { reviewing = false }.keyboardShortcut(.cancelAction)
                    Button("Reset", role: .destructive) {
                        settings.resetPreferencesPreservingAccess()
                        workspace?.reset(); resetCompleted = true; reviewing = false
                    }.disabled(confirmation != "RESET")
                }
            }.padding(24).frame(width: 480)
        }
    }
}

struct SettingsPanelSizeResetView: View {
    let reset: () -> Bool
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Reset panel size") {
                message = reset() ? "Settings window size restored." : "Exit Full Screen and close any sheet before resetting the window size."
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
