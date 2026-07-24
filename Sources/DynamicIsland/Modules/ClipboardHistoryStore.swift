import Combine
import Foundation

private final class ClipboardHistoryPersistenceWriter: @unchecked Sendable {
    private let persistence: ClipboardHistoryPersistence
    private let queue = DispatchQueue(
        label: "com.dynamicisland.clipboard-history.persistence",
        qos: .utility
    )
    private let lock = NSLock()
    private var generation = 0
    private var enabled: Bool

    init(persistence: ClipboardHistoryPersistence, enabled: Bool) {
        self.persistence = persistence
        self.enabled = enabled
    }

    func scheduleSave(_ data: Data, count: Int) {
        let token = updateState(enabled: true)
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
        let token = updateState(enabled: false)
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
        let token = invalidate()
        queue.async { [persistence, weak self] in
            guard let self, self.isCurrent(token, requiresEnabled: nil) else { return }
            try? persistence.deleteArchive()
        }
    }

    func flush() {
        queue.sync {}
    }

    private func updateState(enabled: Bool) -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        self.enabled = enabled
        return generation
    }

    private func invalidate() -> Int {
        lock.lock()
        defer { lock.unlock() }
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
    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    @Published private(set) var isMonitoring = false

    private let settings: AppSettings
    private let pasteboard: ClipboardPasteboardClient
    private let persistence: ClipboardHistoryPersistence
    private let limits: ClipboardHistoryLimits
    private let now: () -> Date
    private let automaticallySchedulesTimer: Bool
    private let persistenceWriter: ClipboardHistoryPersistenceWriter

    private nonisolated(unsafe) var timer: Timer?
    private var lastObservedChangeCount = 0
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings,
        pasteboard: ClipboardPasteboardClient = SystemClipboardPasteboardClient(),
        persistence: ClipboardHistoryPersistence = FileClipboardHistoryPersistence(),
        limits: ClipboardHistoryLimits = .standard,
        now: @escaping () -> Date = Date.init,
        automaticallySchedulesTimer: Bool = true
    ) {
        self.settings = settings
        self.pasteboard = pasteboard
        self.persistence = persistence
        self.limits = limits
        self.now = now
        self.automaticallySchedulesTimer = automaticallySchedulesTimer
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
    }

    func startMonitoring() {
        startMonitoring(assumingEnabled: settings.clipboardHistoryEnabled)
    }

    private func startMonitoring(assumingEnabled: Bool) {
        guard assumingEnabled, !isMonitoring else { return }
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
        guard isMonitoring || timer != nil else { return }
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        #if DEBUG
        print("[ClipboardHistory] monitoring stopped")
        #endif
    }

    func pollNow() {
        guard isMonitoring, settings.clipboardHistoryEnabled else { return }
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastObservedChangeCount else { return }
        lastObservedChangeCount = currentChangeCount

        let result = pasteboard.readSupportedPayload(
            limits: limits,
            capturesImages: settings.clipboardHistoryCaptureImagesEnabled
        )
        guard case let .payload(payload) = result else { return }
        capture(payload)
    }

    func clearHistory() {
        entries.removeAll()
        persistenceWriter.deleteWithoutDisabling()
    }

    func removeEntry(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
        persistHistoryIfNeeded()
    }

    func waitForPendingPersistenceForTesting() {
        persistenceWriter.flush()
    }

    @discardableResult
    func copyEntryToPasteboard(id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        let entry = entries[index]
        let result = pasteboard.write(entry.payload)
        guard result.succeeded else { return false }

        lastObservedChangeCount = result.resultingChangeCount
        entries.remove(at: index)
        entries.insert(
            ClipboardHistoryEntry(
                id: entry.id,
                createdAt: now(),
                payload: entry.payload,
                fingerprint: entry.fingerprint
            ),
            at: 0
        )
        persistHistoryIfNeeded()
        #if DEBUG
        print("[ClipboardHistory] restored kind=\(entry.payload.kind.rawValue)")
        #endif
        return true
    }

    private func capture(_ payload: ClipboardHistoryPayload) {
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
                payload: payload,
                fingerprint: fingerprint
            )
            wasDuplicate = true
        } else {
            entry = ClipboardHistoryEntry(
                id: UUID(),
                createdAt: captureDate,
                payload: payload,
                fingerprint: fingerprint
            )
            wasDuplicate = false
        }

        entries.insert(entry, at: 0)
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

    private func pruneToCurrentLimits(maximumItems: Int? = nil) {
        let maximumItems = maximumItems ?? settings.clipboardHistoryMaximumItems
        if entries.count > maximumItems {
            entries.removeLast(entries.count - maximumItems)
        }
        var total = entries.reduce(into: 0) { $0 += $1.payload.byteCount }
        while total > limits.maximumTotalHistoryPayloadBytes, let removed = entries.popLast() {
            total -= removed.payload.byteCount
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
                    payload: payload,
                    fingerprint: canonicalFingerprint
                )
            )
        }
        return result
    }

    private func loadPersistedHistory() {
        guard let data = persistence.loadData() else { return }
        do {
            let archive = try JSONDecoder().decode(ClipboardHistoryArchive.self, from: data)
            guard archive.schemaVersion == ClipboardHistoryArchive.currentSchemaVersion else {
                #if DEBUG
                print("[ClipboardHistory] unknown archive schema ignored")
                #endif
                return
            }
            entries = validatedLoadedEntries(archive.entries)
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
        guard assumingEnabled ?? settings.clipboardHistoryPersistenceEnabled else { return }
        let archive = ClipboardHistoryArchive(
            schemaVersion: ClipboardHistoryArchive.currentSchemaVersion,
            entries: entries
        )
        guard let data = try? JSONEncoder().encode(archive) else { return }
        persistenceWriter.scheduleSave(data, count: archive.entries.count)
    }
}
