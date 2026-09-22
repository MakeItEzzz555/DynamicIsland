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
                    let removedFiles = Array(self.files.dropFirst(maxFiles))
                    self.files = Array(self.files.prefix(maxFiles))
                    FileShelfTemporaryStorage.shared.removeIfOwned(removedFiles)
                    self.persistFilesIfNeeded()
                }
            }
            .store(in: &cancellables)
    }
}
