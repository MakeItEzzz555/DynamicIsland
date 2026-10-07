import AppKit
import Foundation
import QuickLookUI

final class FileShelfQuickLookController: NSObject, QLPreviewPanelDataSource, @unchecked Sendable {
    static let shared = FileShelfQuickLookController()
    private let lock = NSLock()
    private var urls: [URL] = []

    @MainActor
    @discardableResult
    func preview(_ urls: [URL]) -> Bool {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty, let panel = QLPreviewPanel.shared() else { return false }
        lock.withLock { self.urls = existing }
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        lock.withLock { urls.count }
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        lock.withLock {
            guard urls.indices.contains(index) else { return nil }
            return urls[index] as NSURL
        }
    }
}

enum FileShelfDiskOperationError: LocalizedError, Equatable {
    case missingSource
    case invalidDestination
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSource: "The source file no longer exists."
        case .invalidDestination: "Choose a valid destination folder."
        case .operationFailed(let message): "The file operation failed: \(message)"
        }
    }
}

enum FileShelfDiskOperations {
    static func collisionSafeDestination(
        for source: URL,
        in directory: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let originalName = source.lastPathComponent.isEmpty ? "Item" : source.lastPathComponent
        let ext = source.pathExtension
        let base = ext.isEmpty ? originalName : source.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let name: String
            if index == 1 {
                name = originalName
            } else if ext.isEmpty {
                name = "\(base) \(index)"
            } else {
                name = "\(base) \(index).\(ext)"
            }
            let candidate = directory.appendingPathComponent(name).standardizedFileURL
            if !fileExists(candidate) { return candidate }
            index += 1
        }
    }

    static func copy(_ urls: [URL], to directory: URL) throws -> [URL] {
        try validateDirectory(directory)
        var outputs: [URL] = []
        do {
            for source in urls.map(\.standardizedFileURL) {
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw FileShelfDiskOperationError.missingSource
                }
                let destination = collisionSafeDestination(for: source, in: directory)
                try FileManager.default.copyItem(at: source, to: destination)
                outputs.append(destination)
            }
            return outputs
        } catch let error as FileShelfDiskOperationError {
            rollbackCopies(outputs)
            throw error
        } catch {
            rollbackCopies(outputs)
            throw FileShelfDiskOperationError.operationFailed(error.localizedDescription)
        }
    }

    static func move(_ urls: [URL], to directory: URL) throws -> [(from: URL, to: URL)] {
        try validateDirectory(directory)
        var moved: [(URL, URL)] = []
        do {
            for source in urls.map(\.standardizedFileURL) {
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw FileShelfDiskOperationError.missingSource
                }
                if source.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
                    continue
                }
                let destination = collisionSafeDestination(for: source, in: directory)
                try FileManager.default.moveItem(at: source, to: destination)
                moved.append((source, destination))
            }
            return moved
        } catch {
            // Best-effort rollback of only the moves completed by this call.
            for pair in moved.reversed() where FileManager.default.fileExists(atPath: pair.1.path) {
                try? FileManager.default.moveItem(at: pair.1, to: pair.0)
            }
            if let typed = error as? FileShelfDiskOperationError { throw typed }
            throw FileShelfDiskOperationError.operationFailed(error.localizedDescription)
        }
    }

    private static func validateDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard directory.isFileURL,
              FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileShelfDiskOperationError.invalidDestination
        }
    }

    private static func rollbackCopies(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
}

extension FileShelfActions {
    @discardableResult
    static func copyFiles(_ urls: [URL]) -> Bool {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects(existing.map { $0 as NSURL })
    }

    static func openWithApplications(for url: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: url)
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    @discardableResult
    static func open(_ url: URL, withApplication appURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        return true
    }

    @MainActor
    static func chooseDestination(title: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
