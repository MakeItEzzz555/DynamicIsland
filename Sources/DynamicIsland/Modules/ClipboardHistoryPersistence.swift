import Foundation

protocol ClipboardHistoryPersistence: AnyObject, Sendable {
    var archiveURL: URL { get }
    func loadData() -> Data?
    func saveDataAtomically(_ data: Data) throws
    func deleteArchive() throws
}

final class FileClipboardHistoryPersistence: ClipboardHistoryPersistence, @unchecked Sendable {
    let archiveURL: URL
    private let fileManager: FileManager

    init(
        archiveURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let archiveURL {
            self.archiveURL = archiveURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.archiveURL = applicationSupport
                .appendingPathComponent("DynamicIsland", isDirectory: true)
                .appendingPathComponent("clipboard-history.json")
        }
    }

    func loadData() -> Data? {
        try? Data(contentsOf: archiveURL)
    }

    func saveDataAtomically(_ data: Data) throws {
        if let existing = try? Data(contentsOf: archiveURL), existing == data {
            return
        }
        try fileManager.createDirectory(
            at: archiveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: archiveURL, options: .atomic)
    }

    func deleteArchive() throws {
        guard fileManager.fileExists(atPath: archiveURL.path) else { return }
        try fileManager.removeItem(at: archiveURL)
    }
}
