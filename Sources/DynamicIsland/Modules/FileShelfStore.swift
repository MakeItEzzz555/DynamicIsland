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
    /// Temp-file cleanup authority shared with Floating Baskets, so a file
    /// that moved between surfaces is never deleted while another owns it.
    private let ownership: TemporaryFileOwnershipLedger
    private var cancellables: Set<AnyCancellable> = []
    private static let persistedBookmarksKey = "fileShelfPersistedBookmarks"
    private static let persistedDatesKey = "fileShelfRetentionDates"
    private let now: () -> Date
    private var addedAt: [String: TimeInterval] = [:]
    private var retentionTask: Task<Void, Never>?
    private var monitorsRetention = false
    var retentionMonitoringActive: Bool { retentionTask != nil }
    deinit { retentionTask?.cancel() }

    @Published private(set) var files: [URL] = [] {
        didSet {
            let paths = Set(files.map(\.path))
            addedAt = addedAt.filter { paths.contains($0.key) }
            for file in files where addedAt[file.path] == nil { addedAt[file.path] = now().timeIntervalSince1970 }
            selection.formIntersection(files)
            if let selectionAnchor, !files.contains(selectionAnchor) {
                self.selectionAnchor = nil
            }
        }
    }
    /// Explicit Tray selection used as the quick-action target.
    @Published private(set) var selection: Set<URL> = []
    @Published private(set) var fileActionRequest: FileTrayActionRequest?
    /// The one visible result of a File Tray operation (menu or drop zone).
    @Published private(set) var operationStatus: FileTrayOperationStatus?
    private var operationStatusGeneration = 0

    /// Publishes a status; finished states clear themselves after `clearAfter`.
    func setOperationStatus(_ status: FileTrayOperationStatus?, clearAfter: Duration? = nil) {
        operationStatusGeneration += 1
        operationStatus = status
        guard let clearAfter else { return }
        let generation = operationStatusGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: clearAfter)
            guard let self, self.operationStatusGeneration == generation else { return }
            self.operationStatus = nil
        }
    }

    func requestFileActions(for urls: [URL], openShelfAfterDrop: Bool = false) {
        let accepted = files.filter { urls.map(\.standardizedFileURL).contains($0) }
        guard !accepted.isEmpty else { return }
        fileActionRequest = FileTrayActionRequest(id: UUID(), urls: accepted, openShelfAfterDrop: openShelfAfterDrop)
    }

    func consumeAutoOpenRequest(_ id: UUID) {
        guard fileActionRequest?.id == id else { return }
        fileActionRequest?.openShelfAfterDrop = false
    }

    func discardUnacceptedDrop(_ urls: [URL]) { ownership.discardIfUnowned(urls) }

    func dismissFileActions(_ id: UUID?) {
        if fileActionRequest?.id == id { fileActionRequest = nil }
    }
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

    /// Selects exactly the given Tray items (e.g. new operation outputs).
    func select(only urls: [URL]) {
        let wanted = urls.map(\.standardizedFileURL).filter(files.contains)
        selection = Set(wanted)
        selectionAnchor = wanted.first
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

    init(
        settings: AppSettings,
        defaults: UserDefaults = .standard,
        ownership: TemporaryFileOwnershipLedger = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.defaults = defaults
        self.ownership = ownership
        self.now = now
        loadPersistedFiles()
        installSettingsObservers()
    }

    func startRetentionMonitoring() {
        guard !monitorsRetention else { return }
        monitorsRetention = true
        updateRetentionMonitoring()
    }
    func stopRetentionMonitoring() {
        monitorsRetention = false
        retentionTask?.cancel(); retentionTask = nil
    }
    private func updateRetentionMonitoring() {
        retentionTask?.cancel(); retentionTask = nil
        guard monitorsRetention, settings.shelfFileRetention.seconds != nil else { return }
        pruneExpiredReferences()
        retentionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
                guard !Task.isCancelled else { break }
                self?.pruneExpiredReferences()
            }
        }
    }
    func pruneExpiredReferences() {
        guard let lifetime = settings.shelfFileRetention.seconds else { return }
        let cutoff = now().timeIntervalSince1970 - lifetime
        let protected = selection.union(fileActionRequest?.urls ?? [])
        let expired = files.filter { !protected.contains($0) && (addedAt[$0.path] ?? .infinity) <= cutoff }
        guard !expired.isEmpty else { return }
        let targets = Set(expired)
        files.removeAll(where: targets.contains)
        ownership.release(expired, by: .shelf)
        persistFilesIfNeeded()
    }

    func add(_ urls: [URL]) {
        guard settings.fileShelfEnabled else {
            ownership.discardIfUnowned(urls)
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
        ownership.retain(newFiles.filter(files.contains), by: .shelf)
        rejectedOwnedURLs.append(contentsOf: combinedFiles.dropFirst(settings.maxShelfFiles))
        ownership.discardIfUnowned(rejectedOwnedURLs)
        persistFilesIfNeeded()
    }

    /// Accepts files handed over by another app surface (Basket → Shelf).
    /// Unlike `add`, rejected files are left untouched: the caller still owns
    /// them. Returns exactly the standardized URLs the Shelf accepted.
    @discardableResult
    func adopt(_ urls: [URL]) -> [URL] {
        guard settings.fileShelfEnabled else { return [] }
        var seen = Set(files)
        var accepted: [URL] = []
        for url in urls.map(\.standardizedFileURL) where url.isFileURL {
            guard files.count + accepted.count < settings.maxShelfFiles else { break }
            guard !seen.contains(url), FileManager.default.fileExists(atPath: url.path) else { continue }
            seen.insert(url)
            accepted.append(url)
        }
        guard !accepted.isEmpty else { return [] }
        ownership.retain(accepted, by: .shelf)
        files += accepted
        persistFilesIfNeeded()
        return accepted
    }

    /// Removes files that are being handed to another surface (Shelf →
    /// Basket). Ownership is NOT released here; the caller transfers it.
    @discardableResult
    func removeForTransfer(_ urls: [URL]) -> [URL] {
        let targets = Set(urls.map(\.standardizedFileURL))
        let removed = files.filter(targets.contains)
        guard !removed.isEmpty else { return [] }
        files.removeAll(where: targets.contains)
        persistFilesIfNeeded()
        return removed
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
        let age = addedAt[source.path]
        files[index] = destination
        if let age { addedAt[destination.path] = age }
        // The file already moved on disk, so releasing the old path deletes nothing.
        ownership.release([source], by: .shelf)
        ownership.retain([destination], by: .shelf)
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
        let age = addedAt[old.path]
        files[index] = new
        if let age { addedAt[new.path] = age }
        ownership.release([old], by: .shelf)
        ownership.retain([new], by: .shelf)
        if wasSelected { selection.insert(new) }
        if wasAnchor { selectionAnchor = new }
        persistFilesIfNeeded()
    }

    func remove(_ url: URL) {
        let target = url.standardizedFileURL
        guard files.contains(target) else { return }
        files.removeAll { $0 == target }
        ownership.release([target], by: .shelf)
        persistFilesIfNeeded()
    }

    func clear() {
        let removed = files
        files.removeAll()
        ownership.release(removed, by: .shelf)
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

        addedAt = (defaults.dictionary(forKey: Self.persistedDatesKey) as? [String: Double] ?? [:])
            .filter { $0.value.isFinite && $0.value >= 0 && $0.value <= now().timeIntervalSince1970 }
        files = Array(restoredFiles.prefix(settings.maxShelfFiles))
        ownership.retain(files, by: .shelf)
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
        defaults.set(addedAt, forKey: Self.persistedDatesKey)
    }

    func clearPersistedFiles() {
        defaults.removeObject(forKey: Self.persistedBookmarksKey)
        defaults.removeObject(forKey: Self.persistedDatesKey)
    }

    private func installSettingsObservers() {
        settings.$shelfFileRetention.dropFirst().removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateRetentionMonitoring() }.store(in: &cancellables)
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
                    self.ownership.release(removedFiles, by: .shelf)
                    self.persistFilesIfNeeded()
                }
            }
            .store(in: &cancellables)
    }
}
