import Combine
import Foundation

@MainActor
final class FileShelfStore: ObservableObject {
    private let settings: AppSettings
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private static let persistedBookmarksKey = "fileShelfPersistedBookmarks"

    @Published private(set) var files: [URL] = []

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        loadPersistedFiles()
        installSettingsObservers()
    }

    func add(_ urls: [URL]) {
        guard settings.fileShelfEnabled else { return }
        var seen = Set(files.map(\.standardizedFileURL))
        let newFiles = urls.compactMap { incoming -> URL? in
            guard incoming.isFileURL else { return nil }
            let standardizedURL = incoming.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardizedURL.path) else { return nil }
            guard !seen.contains(standardizedURL) else { return nil }
            seen.insert(standardizedURL)
            return standardizedURL
        }
        files = Array((files + newFiles).prefix(settings.maxShelfFiles))
        persistFilesIfNeeded()
    }

    func remove(_ url: URL) {
        files.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        persistFilesIfNeeded()
    }

    func clear() {
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
                    self.persistFilesIfNeeded()
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
                    self.files = Array(self.files.prefix(maxFiles))
                    self.persistFilesIfNeeded()
                }
            }
            .store(in: &cancellables)
    }
}
