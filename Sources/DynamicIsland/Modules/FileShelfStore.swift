import Combine
import Foundation

enum FileShelfMutationError: LocalizedError, Equatable {
    case invalidName
    case destinationExists
    case missingSource
    case moveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a valid file name."
        case .destinationExists: "A file with that name already exists."
        case .missingSource: "The original file no longer exists."
        case .moveFailed(let message): "The file could not be renamed: \(message)"
        }
    }
}

@MainActor
final class FileShelfStore: ObservableObject {
    private let settings: AppSettings
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private static let persistedBookmarksKey = "fileShelfPersistedBookmarks"

    @Published private(set) var files: [URL] = [] {
        didSet {
            selection.formIntersection(files)
            if let selectionAnchor, !files.contains(selectionAnchor) {
                self.selectionAnchor = nil
            }
        }
    }
    /// Explicit Tray selection used as the quick-action target.
    @Published private(set) var selection: Set<URL> = []
    private var selectionAnchor: URL?

    /// Plain click selects one file; Command toggles; Shift selects a stable
    /// contiguous range using Shelf order rather than Set iteration order.
    func select(_ url: URL, extend: Bool = false, range: Bool = false) {
        let url = url.standardizedFileURL
        guard let index = files.firstIndex(of: url) else { return }

        if range, let anchor = selectionAnchor, let anchorIndex = files.firstIndex(of: anchor) {
            let bounds = min(anchorIndex, index)...max(anchorIndex, index)
            let rangeSelection = Set(bounds.map { files[$0] })
            selection = extend ? selection.union(rangeSelection) : rangeSelection
            return
        }

        if extend {
            if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
            selectionAnchor = url
        } else {
            selection = selection == [url] ? [] : [url]
            selectionAnchor = url
        }
    }

    func selectAll() {
        selection = Set(files)
        selectionAnchor = files.first
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
    }

    var quickActionTargets: FileTrayActionTargets {
        FileTrayActionTargets.resolve(files: files, selection: selection)
    }

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        loadPersistedFiles()
        installSettingsObservers()
    }

    func add(_ urls: [URL]) {
        guard settings.fileShelfEnabled else {
            FileShelfTemporaryStorage.shared.removeIfOwned(urls)
            return
        }
        var seen = Set(files.map(\.standardizedFileURL))
        var rejectedOwnedURLs: [URL] = []
        let newFiles = urls.compactMap { incoming -> URL? in
            guard incoming.isFileURL else {
                rejectedOwnedURLs.append(incoming)
                return nil
            }
            let standardizedURL = incoming.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
                rejectedOwnedURLs.append(standardizedURL)
                return nil
            }
            guard !seen.contains(standardizedURL) else { return nil }
            seen.insert(standardizedURL)
            return standardizedURL
        }
        let combinedFiles = files + newFiles
        files = Array(combinedFiles.prefix(settings.maxShelfFiles))
        rejectedOwnedURLs.append(contentsOf: combinedFiles.dropFirst(settings.maxShelfFiles))
        FileShelfTemporaryStorage.shared.removeIfOwned(rejectedOwnedURLs)
        persistFilesIfNeeded()
    }

    @discardableResult
    func rename(_ url: URL, to requestedName: String) throws -> URL {
        let source = url.standardizedFileURL
        guard let index = files.firstIndex(of: source), FileManager.default.fileExists(atPath: source.path) else {
            throw FileShelfMutationError.missingSource
        }
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":"), name != ".", name != ".." else {
            throw FileShelfMutationError.invalidName
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
        if destination == source { return source }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileShelfMutationError.destinationExists
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw FileShelfMutationError.moveFailed(error.localizedDescription)
        }
        let wasSelected = selection.contains(source)
        let wasAnchor = selectionAnchor == source
        files[index] = destination
        if wasSelected { selection.insert(destination) }
        if wasAnchor { selectionAnchor = destination }
        persistFilesIfNeeded()
        return destination
    }

    /// Updates the Shelf's reference after a user-requested move performed by
    /// FileShelfDiskOperations. This never moves files by itself.
    func recordMove(from oldURL: URL, to newURL: URL) {
        let old = oldURL.standardizedFileURL
        let new = newURL.standardizedFileURL
        guard let index = files.firstIndex(of: old), FileManager.default.fileExists(atPath: new.path) else { return }
        let wasSelected = selection.contains(old)
        let wasAnchor = selectionAnchor == old
        files[index] = new
        if wasSelected { selection.insert(new) }
        if wasAnchor { selectionAnchor = new }
        persistFilesIfNeeded()
    }

    func remove(_ url: URL) {
        files.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        FileShelfTemporaryStorage.shared.removeIfOwned(url)
        persistFilesIfNeeded()
    }

    func clear() {
        FileShelfTemporaryStorage.shared.removeIfOwned(files)
        files.removeAll()
        persistFilesIfNeeded()
    }

    func removeMissingFiles() {
        let existingFiles = files.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard existingFiles != files else { return }
        files = existingFiles
        persistFilesIfNeeded()
    }

    func loadPersistedFiles() {
        guard settings.persistFileShelfAcrossLaunches else {
            return
        }
        guard let bookmarkDataItems = defaults.array(forKey: Self.persistedBookmarksKey) as? [Data] else {
            files = []
            return
        }

        var restoredFiles: [URL] = []
        for bookmarkData in bookmarkDataItems {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }
            let standardizedURL = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
                continue
            }
            guard !restoredFiles.contains(standardizedURL) else {
                continue
            }
            restoredFiles.append(standardizedURL)
        }

        files = Array(restoredFiles.prefix(settings.maxShelfFiles))
        persistFilesIfNeeded()
    }

    func persistFilesIfNeeded() {
        guard settings.persistFileShelfAcrossLaunches else {
            return
        }
        persistFiles()
    }

    private func persistFiles() {
        let bookmarks = files.compactMap { url in
            try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        defaults.set(bookmarks, forKey: Self.persistedBookmarksKey)
    }

    func clearPersistedFiles() {
        defaults.removeObject(forKey: Self.persistedBookmarksKey)
    }

    private func installSettingsObservers() {
        settings.$persistFileShelfAcrossLaunches
            .removeDuplicates()
            .sink { [weak self] shouldPersist in
                guard let self else { return }
                if shouldPersist {
                    self.removeMissingFiles()
                    self.persistFiles()
                } else {
                    self.clearPersistedFiles()
                }
            }
            .store(in: &cancellables)

        settings.$maxShelfFiles
            .removeDuplicates()
            .sink { [weak self] maxFiles in
                guard let self else { return }
                if self.files.count > maxFiles {
                    let removedFiles = Array(self.files.dropFirst(maxFiles))
                    self.files = Array(self.files.prefix(maxFiles))
                    FileShelfTemporaryStorage.shared.removeIfOwned(removedFiles)
                    self.persistFilesIfNeeded()
                }
            }
            .store(in: &cancellables)
    }
}
