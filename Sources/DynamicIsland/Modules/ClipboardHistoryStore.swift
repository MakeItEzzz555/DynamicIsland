import AppKit
import Combine
import Foundation

enum ClipboardHistoryPersistenceFinalizationResult: Equatable {
    case completed
    case failed
    case timedOut
}

private enum ClipboardHistoryFinalPersistenceOperation {
    case save(Data, count: Int)
    case delete
}

private final class ClipboardHistoryPersistenceFinalizationCompletion: @unchecked Sendable {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var result: ClipboardHistoryPersistenceFinalizationResult?

    init() {
        group.enter()
    }

    func finish(with result: ClipboardHistoryPersistenceFinalizationResult) {
        lock.withLock { self.result = result }
        group.leave()
    }

    func wait(timeout: TimeInterval) -> ClipboardHistoryPersistenceFinalizationResult {
        guard group.wait(timeout: .now() + max(0, timeout)) == .success else {
            return .timedOut
        }
        return lock.withLock { result ?? .failed }
    }
}

private final class ClipboardHistoryPersistenceWriter: @unchecked Sendable {
    private let persistence: ClipboardHistoryPersistence
    private let queue = DispatchQueue(
        label: "com.dynamicisland.clipboard-history.persistence",
        qos: .utility
    )
    private let lock = NSLock()
    private var generation = 0
    private var enabled: Bool
    private var isFinalizing = false
    private var finalizationCompletion: ClipboardHistoryPersistenceFinalizationCompletion?

    init(persistence: ClipboardHistoryPersistence, enabled: Bool) {
        self.persistence = persistence
        self.enabled = enabled
    }

    func scheduleSave(_ data: Data, count: Int) {
        guard let token = updateState(enabled: true) else { return }
        queue.async { [persistence, weak self] in
            guard let self, self.isCurrent(token, requiresEnabled: true) else { return }
            do {
                try persistence.saveDataAtomically(data)
                #if DEBUG
                print("[ClipboardHistory] persistence saved count=\(count)")
                #endif
            } catch {
                #if DEBUG
                print("[ClipboardHistory] persistence save failed")
                #endif
            }
        }
    }

    func disableAndDelete() {
        guard let token = updateState(enabled: false) else { return }
        queue.async { [persistence, weak self] in
            guard let self, self.isCurrent(token, requiresEnabled: false) else { return }
            do {
                try persistence.deleteArchive()
                #if DEBUG
                print("[ClipboardHistory] persistence deleted")
                #endif
            } catch {
                #if DEBUG
                print("[ClipboardHistory] persistence delete failed")
                #endif
            }
        }
    }

    func deleteWithoutDisabling() {
        guard let token = invalidate() else { return }
        queue.async { [persistence, weak self] in
            guard let self, self.isCurrent(token, requiresEnabled: nil) else { return }
            try? persistence.deleteArchive()
        }
    }

    func flush() {
        queue.sync {}
    }

    func finalize(
        with operation: ClipboardHistoryFinalPersistenceOperation,
        timeout: TimeInterval
    ) -> ClipboardHistoryPersistenceFinalizationResult {
        let (completion, token, shouldEnqueue) = lock.withLock {
            if let finalizationCompletion {
                return (finalizationCompletion, generation, false)
            }

            generation += 1
            isFinalizing = true
            enabled = switch operation {
            case .save: true
            case .delete: false
            }
            let completion = ClipboardHistoryPersistenceFinalizationCompletion()
            finalizationCompletion = completion
            return (completion, generation, true)
        }

        if shouldEnqueue {
            queue.async { [persistence, self] in
                guard isCurrent(token, requiresEnabled: nil) else {
                    completion.finish(with: .failed)
                    return
                }
                do {
                    switch operation {
                    case let .save(data, count):
                        try persistence.saveDataAtomically(data)
                        #if DEBUG
                        print("[ClipboardHistory] final persistence saved count=\(count)")
                        #endif
                    case .delete:
                        try persistence.deleteArchive()
                        #if DEBUG
                        print("[ClipboardHistory] final persistence deleted")
                        #endif
                    }
                    completion.finish(with: .completed)
                } catch {
                    #if DEBUG
                    print("[ClipboardHistory] final persistence failed")
                    #endif
                    completion.finish(with: .failed)
                }
            }
        }

        return completion.wait(timeout: timeout)
    }

    private func updateState(enabled: Bool) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinalizing else { return nil }
        generation += 1
        self.enabled = enabled
        return generation
    }

    private func invalidate() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinalizing else { return nil }
        generation += 1
        return generation
    }

    private func isCurrent(_ token: Int, requiresEnabled: Bool?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard token == generation else { return false }
        guard let requiresEnabled else { return true }
        return enabled == requiresEnabled
    }
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    /// A short lifecycle-only grace period for ordinary local archive writes/deletes.
    static let terminationPersistenceWaitSeconds: TimeInterval = 0.5

    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    @Published private(set) var tags: [ClipboardTag] = []
    @Published private(set) var isMonitoring = false

    var autoFocusSearchEnabled: Bool { settings.clipboardHistoryAutoFocusSearch }
    var tagsEnabled: Bool { settings.clipboardHistoryTagsEnabled }

    private let settings: AppSettings
    private let pasteboard: ClipboardPasteboardClient
    private let persistence: ClipboardHistoryPersistence
    private let limits: ClipboardHistoryLimits
    private let now: () -> Date
    private let automaticallySchedulesTimer: Bool
    private let persistenceWriter: ClipboardHistoryPersistenceWriter

    private nonisolated(unsafe) var timer: Timer?
    private var imageCaptureTask: Task<Void, Never>?
    private var imageCaptureGeneration = 0
    private let processImage: @Sendable (ClipboardImageCapture) async -> ClipboardPasteboardReadResult
    private let sourceApplicationProvider: () -> ClipboardSourceApplication?
    private var lastObservedChangeCount = 0
    private var cancellables: Set<AnyCancellable> = []
    private var isFinalizing = false

    init(
        settings: AppSettings,
        pasteboard: ClipboardPasteboardClient = SystemClipboardPasteboardClient(),
        persistence: ClipboardHistoryPersistence = FileClipboardHistoryPersistence(),
        limits: ClipboardHistoryLimits = .standard,
        now: @escaping () -> Date = Date.init,
        automaticallySchedulesTimer: Bool = true,
        processImage: @escaping @Sendable (ClipboardImageCapture) async -> ClipboardPasteboardReadResult = { capture in
            await Task.detached(priority: .utility) { capture.resolve() }.value
        },
        sourceApplicationProvider: @escaping () -> ClipboardSourceApplication? = {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return nil }
            return ClipboardSourceApplication(
                name: app.localizedName ?? bundleID,
                bundleIdentifier: bundleID
            )
        }
    ) {
        self.settings = settings
        self.pasteboard = pasteboard
        self.persistence = persistence
        self.limits = limits
        self.now = now
        self.automaticallySchedulesTimer = automaticallySchedulesTimer
        self.processImage = processImage
        self.sourceApplicationProvider = sourceApplicationProvider
        persistenceWriter = ClipboardHistoryPersistenceWriter(
            persistence: persistence,
            enabled: settings.clipboardHistoryPersistenceEnabled
        )

        if settings.clipboardHistoryPersistenceEnabled {
            loadPersistedHistory()
        }
        installSettingsObservers()
        if settings.clipboardHistoryEnabled {
            startMonitoring()
        }
    }

    deinit {
        timer?.invalidate()
        imageCaptureTask?.cancel()
    }

    func startMonitoring() {
        startMonitoring(assumingEnabled: settings.clipboardHistoryEnabled)
    }

    private func startMonitoring(assumingEnabled: Bool) {
        guard !isFinalizing, assumingEnabled, !isMonitoring else { return }
        lastObservedChangeCount = pasteboard.changeCount
        isMonitoring = true
        if automaticallySchedulesTimer {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pollNow()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        #if DEBUG
        print("[ClipboardHistory] monitoring started")
        #endif
    }

    func stopMonitoring() {
        imageCaptureGeneration += 1
        guard isMonitoring || timer != nil else { return }
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        #if DEBUG
        print("[ClipboardHistory] monitoring stopped")
        #endif
    }

    func pollNow() {
        // Keep at most one image job in flight. Subsequent polls observe the latest
        // change when it finishes rather than queueing decoded images without bound.
        guard !isFinalizing,
              isMonitoring, settings.clipboardHistoryEnabled,
              imageCaptureTask == nil else { return }
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastObservedChangeCount else { return }
        lastObservedChangeCount = currentChangeCount
        let sourceApplication = sourceApplicationProvider()
        if let bundleID = sourceApplication?.bundleIdentifier,
           settings.clipboardHistoryExcludedAppBundleIDs.contains(where: {
               $0.caseInsensitiveCompare(bundleID) == .orderedSame
           }) {
            return
        }

        let prepared = pasteboard.prepareCapture(
            limits: limits,
            capturesImages: settings.clipboardHistoryCaptureImagesEnabled
        )
        switch prepared {
        case let .ready(result):
            if case let .payload(payload) = result { capture(payload, sourceApplication: sourceApplication) }
        case let .image(image):
            let generation = imageCaptureGeneration
            let processImage = self.processImage
            imageCaptureTask = Task { @MainActor [weak self] in
                let result = await processImage(image)
                guard let self else { return }
                self.imageCaptureTask = nil
                if generation == self.imageCaptureGeneration,
                   self.isMonitoring, self.settings.clipboardHistoryEnabled,
                   self.settings.clipboardHistoryCaptureImagesEnabled,
                   self.pasteboard.changeCount == currentChangeCount,
                   case let .payload(payload) = result {
                    self.capture(payload, sourceApplication: sourceApplication)
                }
                self.pollNow()
            }
        }
    }

    func waitForPendingImageCaptureForTesting() async {
        await imageCaptureTask?.value
    }

    func clearHistory() {
        imageCaptureGeneration += 1
        entries.removeAll()
        if settings.clipboardHistoryPersistenceEnabled, !tags.isEmpty {
            persistHistoryIfNeeded()
        } else {
            persistenceWriter.deleteWithoutDisabling()
        }
    }

    func removeEntry(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
        persistHistoryIfNeeded()
    }

    func toggleFavorite(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        entries[index] = ClipboardHistoryEntry(
            id: entry.id,
            createdAt: entry.createdAt,
            lastUsedAt: entry.lastUsedAt,
            payload: entry.payload,
            fingerprint: entry.fingerprint,
            sourceApplication: entry.sourceApplication,
            isFavorite: !entry.isFavorite,
            customTitle: entry.customTitle,
            tagIDs: entry.tagIDs
        )
        sortPinnedFirst()
        pruneToCurrentLimits()
        persistHistoryIfNeeded()
    }

    func renameEntry(id: UUID, title: String?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        let normalized = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index] = ClipboardHistoryEntry(
            id: entry.id,
            createdAt: entry.createdAt,
            lastUsedAt: entry.lastUsedAt,
            payload: entry.payload,
            fingerprint: entry.fingerprint,
            sourceApplication: entry.sourceApplication,
            isFavorite: entry.isFavorite,
            customTitle: normalized?.isEmpty == false ? normalized : nil,
            tagIDs: entry.tagIDs
        )
        persistHistoryIfNeeded()
    }

    @discardableResult
    func addTag(name: String, color: ClipboardTagColor) -> ClipboardTag? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 48 else { return nil }
        guard !tags.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        let tag = ClipboardTag(name: name, color: color, sortOrder: tags.count)
        tags.append(tag)
        persistHistoryIfNeeded()
        return tag
    }

    func updateTag(id: UUID, name: String, color: ClipboardTagColor) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 48 else { return }
        guard !tags.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        tags[index].name = name
        tags[index].color = color
        persistHistoryIfNeeded()
    }

    func deleteTag(id: UUID) {
        guard tags.contains(where: { $0.id == id }) else { return }
        tags.removeAll { $0.id == id }
        for index in entries.indices where entries[index].tagIDs.contains(id) {
            let entry = entries[index]
            entries[index] = ClipboardHistoryEntry(
                id: entry.id,
                createdAt: entry.createdAt,
                lastUsedAt: entry.lastUsedAt,
                payload: entry.payload,
                fingerprint: entry.fingerprint,
                sourceApplication: entry.sourceApplication,
                isFavorite: entry.isFavorite,
                customTitle: entry.customTitle,
                tagIDs: entry.tagIDs.filter { $0 != id }
            )
        }
        persistHistoryIfNeeded()
    }

    func setTag(_ tagID: UUID, on entryID: UUID, enabled: Bool) {
        guard tags.contains(where: { $0.id == tagID }),
              let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let entry = entries[index]
        var tagIDs = entry.tagIDs
        if enabled {
            if !tagIDs.contains(tagID) { tagIDs.append(tagID) }
        } else {
            tagIDs.removeAll { $0 == tagID }
        }
        entries[index] = ClipboardHistoryEntry(
            id: entry.id,
            createdAt: entry.createdAt,
            lastUsedAt: entry.lastUsedAt,
            payload: entry.payload,
            fingerprint: entry.fingerprint,
            sourceApplication: entry.sourceApplication,
            isFavorite: entry.isFavorite,
            customTitle: entry.customTitle,
            tagIDs: tagIDs
        )
        persistHistoryIfNeeded()
    }

    func waitForPendingPersistenceForTesting() {
        persistenceWriter.flush()
    }

    @discardableResult
    func finalizePersistenceForTermination(
        timeout: TimeInterval = ClipboardHistoryStore.terminationPersistenceWaitSeconds
    ) -> ClipboardHistoryPersistenceFinalizationResult {
        if !isFinalizing {
            isFinalizing = true
            stopMonitoring()
            imageCaptureTask?.cancel()
            cancellables.removeAll()
        }

        let operation: ClipboardHistoryFinalPersistenceOperation
        if settings.clipboardHistoryPersistenceEnabled, (!entries.isEmpty || !tags.isEmpty) {
            let archive = ClipboardHistoryArchive(
                schemaVersion: ClipboardHistoryArchive.currentSchemaVersion,
                entries: entries,
                tags: tags
            )
            guard let data = try? JSONEncoder().encode(archive) else { return .failed }
            operation = .save(data, count: archive.entries.count)
        } else {
            operation = .delete
        }

        return persistenceWriter.finalize(with: operation, timeout: timeout)
    }

    @discardableResult
    func copyEntryToPasteboard(id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        let entry = entries[index]
        let result = pasteboard.write(entry.payload)
        guard result.succeeded else { return false }

        imageCaptureGeneration += 1
        lastObservedChangeCount = result.resultingChangeCount
        entries.remove(at: index)
        entries.insert(
            ClipboardHistoryEntry(
                id: entry.id,
                createdAt: entry.createdAt,
                lastUsedAt: now(),
                payload: entry.payload,
                fingerprint: entry.fingerprint,
                sourceApplication: entry.sourceApplication,
                isFavorite: entry.isFavorite,
                customTitle: entry.customTitle,
                tagIDs: entry.tagIDs
            ),
            at: 0
        )
        sortPinnedFirst()
        persistHistoryIfNeeded()
        #if DEBUG
        print("[ClipboardHistory] restored kind=\(entry.payload.kind.rawValue)")
        #endif
        return true
    }

    private func capture(
        _ payload: ClipboardHistoryPayload,
        sourceApplication: ClipboardSourceApplication?
    ) {
        guard !isFinalizing else { return }
        guard let payload = sanitized(payload) else { return }
        let fingerprint = ClipboardHistoryFingerprint.make(for: payload)
        let captureDate = now()
        let wasDuplicate: Bool
        let entry: ClipboardHistoryEntry

        if let existingIndex = entries.firstIndex(where: { $0.fingerprint == fingerprint }) {
            let existing = entries.remove(at: existingIndex)
            entry = ClipboardHistoryEntry(
                id: existing.id,
                createdAt: captureDate,
                lastUsedAt: existing.lastUsedAt,
                payload: payload,
                fingerprint: fingerprint,
                sourceApplication: sourceApplication ?? existing.sourceApplication,
                isFavorite: existing.isFavorite,
                customTitle: existing.customTitle,
                tagIDs: existing.tagIDs
            )
            wasDuplicate = true
        } else {
            entry = ClipboardHistoryEntry(
                id: UUID(),
                createdAt: captureDate,
                payload: payload,
                fingerprint: fingerprint,
                sourceApplication: sourceApplication
            )
            wasDuplicate = false
        }

        entries.insert(entry, at: 0)
        sortPinnedFirst()
        pruneToCurrentLimits()
        persistHistoryIfNeeded()
        #if DEBUG
        let action = wasDuplicate ? "promoted" : "captured"
        print("[ClipboardHistory] \(action) kind=\(payload.kind.rawValue) count=\(entries.count)")
        #endif
    }

    private func installSettingsObservers() {
        settings.$clipboardHistoryEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.startMonitoring(assumingEnabled: true)
                } else {
                    self.stopMonitoring()
                }
            }
            .store(in: &cancellables)

        settings.$clipboardHistoryCaptureImagesEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.imageCaptureGeneration += 1 }
            .store(in: &cancellables)

        settings.$clipboardHistoryMaximumItems
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] maximumItems in
                guard let self else { return }
                self.pruneToCurrentLimits(maximumItems: maximumItems)
                self.persistHistoryIfNeeded()
            }
            .store(in: &cancellables)

        settings.$clipboardHistoryPersistenceEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.persistHistoryIfNeeded(assumingEnabled: true)
                } else {
                    self.persistenceWriter.disableAndDelete()
                }
            }
            .store(in: &cancellables)
    }

    private func sortPinnedFirst() {
        entries.sort {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
            let lhs = $0.lastUsedAt ?? $0.createdAt
            let rhs = $1.lastUsedAt ?? $1.createdAt
            if lhs != rhs { return lhs > rhs }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func pruneToCurrentLimits(maximumItems: Int? = nil) {
        let maximumOrdinary = maximumItems ?? settings.clipboardHistoryMaximumItems
        let maximumFavorites = 50
        var ordinarySeen = 0
        var favoritesSeen = 0
        entries = entries.filter { entry in
            if entry.isFavorite {
                favoritesSeen += 1
                return favoritesSeen <= maximumFavorites
            }
            ordinarySeen += 1
            return ordinarySeen <= maximumOrdinary
        }

        var total = entries.reduce(into: 0) { $0 += $1.payload.byteCount }
        while total > limits.maximumTotalHistoryPayloadBytes {
            if let ordinaryIndex = entries.lastIndex(where: { !$0.isFavorite }) {
                total -= entries.remove(at: ordinaryIndex).payload.byteCount
            } else if let removed = entries.popLast() {
                total -= removed.payload.byteCount
            } else {
                break
            }
        }
    }

    private func sanitized(_ payload: ClipboardHistoryPayload) -> ClipboardHistoryPayload? {
        switch payload {
        case let .text(text):
            guard !text.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.plainText.utf8.count <= limits.maximumPlainTextBytes else {
                return nil
            }
            return .text(
                ClipboardTextPayload(
                    plainText: text.plainText,
                    rtfData: boundedRichRepresentation(text.rtfData),
                    htmlData: boundedRichRepresentation(text.htmlData)
                )
            )
        case let .url(url):
            guard !url.isFileURL,
                  url.scheme?.isEmpty == false,
                  !url.absoluteString.isEmpty,
                  url.absoluteString.utf8.count <= limits.maximumURLStringBytes else {
                return nil
            }
            return .url(url)
        case let .files(urls):
            guard urls.allSatisfy(\.isFileURL) else { return nil }
            var seen = Set<String>()
            let sanitizedURLs = urls.compactMap { url -> URL? in
                guard url.isFileURL else { return nil }
                let standardized = url.standardizedFileURL
                return seen.insert(standardized.absoluteString).inserted ? standardized : nil
            }
            guard !sanitizedURLs.isEmpty,
                  sanitizedURLs.count <= limits.maximumFilesPerEntry else {
                return nil
            }
            return .files(sanitizedURLs)
        case let .imagePNG(data):
            guard !data.isEmpty, data.count <= limits.maximumImageBytes else { return nil }
            return .imagePNG(data)
        }
    }

    private func boundedRichRepresentation(_ data: Data?) -> Data? {
        guard let data, data.count <= limits.maximumRichTextBytesPerRepresentation else {
            return nil
        }
        return data
    }

    private func validatedLoadedEntries(_ loaded: [ClipboardHistoryEntry]) -> [ClipboardHistoryEntry] {
        var seen = Set<String>()
        var result: [ClipboardHistoryEntry] = []
        for entry in loaded.sorted(by: { $0.createdAt > $1.createdAt }) {
            guard let payload = sanitized(entry.payload) else { continue }
            let canonicalFingerprint = ClipboardHistoryFingerprint.make(for: payload)
            guard seen.insert(canonicalFingerprint).inserted else { continue }
            result.append(
                ClipboardHistoryEntry(
                    id: entry.id,
                    createdAt: entry.createdAt,
                    lastUsedAt: entry.lastUsedAt,
                    payload: payload,
                    fingerprint: canonicalFingerprint,
                    sourceApplication: entry.sourceApplication,
                    isFavorite: entry.isFavorite,
                    customTitle: entry.customTitle,
                    tagIDs: entry.tagIDs.filter { id in tags.contains(where: { $0.id == id }) }
                )
            )
        }
        return result
    }

    private func loadPersistedHistory() {
        guard let data = persistence.loadData() else { return }
        do {
            let archive = try JSONDecoder().decode(ClipboardHistoryArchive.self, from: data)
            guard (1...ClipboardHistoryArchive.currentSchemaVersion).contains(archive.schemaVersion) else {
                #if DEBUG
                print("[ClipboardHistory] unknown archive schema ignored")
                #endif
                return
            }
            tags = archive.tags.sorted { $0.sortOrder < $1.sortOrder }
            entries = validatedLoadedEntries(archive.entries)
            sortPinnedFirst()
            pruneToCurrentLimits()
            #if DEBUG
            print("[ClipboardHistory] persistence loaded count=\(entries.count)")
            #endif
        } catch {
            entries = []
            #if DEBUG
            print("[ClipboardHistory] corrupt archive ignored")
            #endif
        }
    }

    private func persistHistoryIfNeeded(assumingEnabled: Bool? = nil) {
        guard !isFinalizing else { return }
        guard assumingEnabled ?? settings.clipboardHistoryPersistenceEnabled else { return }
        let archive = ClipboardHistoryArchive(
            schemaVersion: ClipboardHistoryArchive.currentSchemaVersion,
            entries: entries,
            tags: tags
        )
        guard let data = try? JSONEncoder().encode(archive) else { return }
        persistenceWriter.scheduleSave(data, count: archive.entries.count)
    }
}
