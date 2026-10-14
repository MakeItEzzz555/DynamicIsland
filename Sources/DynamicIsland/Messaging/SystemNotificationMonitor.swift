import Foundation

/// Undocumented bulletin name is only a wake-up hint; records still come from SQLite.
@MainActor
private enum NotificationDatabaseDarwinHint {
    static let name = Notification.Name("DynamicIsland.NotificationDatabaseHint")
    static let observer = NSObject()
    static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(observer).toOpaque(), { _, _, _, _, _ in
                NotificationCenter.default.post(name: Notification.Name("DynamicIsland.NotificationDatabaseHint"), object: nil)
            }, "com.apple.notificationcenterui.bulletin_added" as CFString, nil, .deliverImmediately)
    }
}

/// One delivered macOS notification, normalized. Bodies stay in memory.
struct SystemNotificationRecord: Equatable, Sendable {
    let recordID: Int64
    let bundleIdentifier: String
    let title: String?
    let subtitle: String?
    let body: String?
    let deliveredAt: Date?
    let observedAt: Date
    let stableID: Data?
    var epoch: Int = 0

    init(recordID: Int64, bundleIdentifier: String, title: String?, subtitle: String?, body: String?,
         deliveredAt: Date?, observedAt: Date = Date(), stableID: Data? = nil) {
        self.recordID = recordID
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.deliveredAt = deliveredAt
        self.observedAt = observedAt
        self.stableID = stableID.flatMap { !$0.isEmpty && $0.count <= 128 ? $0 : nil }
    }
}

/// Parses Notification Center record payloads (binary property lists).
/// Content may be flat or nested under `req` depending on macOS version.
enum NotificationPayloadParser {
    struct Parsed: Equatable {
        let bundleIdentifier: String?
        let title: String?
        let subtitle: String?
        let body: String?
        let date: Date?
    }

    static func parse(_ data: Data) -> Parsed? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any] else { return nil }
        let request = root["req"] as? [String: Any] ?? [:]
        func string(_ keys: [String]) -> String? {
            for key in keys {
                if let value = request[key] as? String ?? root[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }
        let date: Date?
        if let seconds = (root["date"] as? Double) ?? (request["date"] as? Double) {
            date = Date(timeIntervalSinceReferenceDate: seconds)
        } else {
            date = (root["date"] as? Date) ?? (request["date"] as? Date)
        }
        return Parsed(
            bundleIdentifier: string(["app"]),
            title: string(["titl", "title"]),
            subtitle: string(["subt", "subtitle"]),
            body: string(["body"]),
            date: date
        )
    }
}

protocol SystemNotificationSource: AnyObject, Sendable {
    /// Highest record id currently present (used as the starting point so
    /// historical notifications are never replayed).
    func latestRecordID() throws -> Int64
    func records(after recordID: Int64, limit: Int) throws -> [SystemNotificationRecord]
    /// Files to watch for changes.
    var watchedPaths: [String] { get }
    func snapshot(after: Int64, limit: Int) throws -> NotificationStoreSnapshot
}

struct NotificationFileIdentity: Equatable, Sendable {
    let device: Int32
    let inode: UInt64

    static func read(_ path: String) -> Self? {
        var value = stat()
        guard stat(path, &value) == 0 else { return nil }
        return Self(device: value.st_dev, inode: value.st_ino)
    }

    static func read(descriptor: Int32) -> Self? {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { return nil }
        return Self(device: value.st_dev, inode: value.st_ino)
    }
}

struct NotificationStoreSnapshot: Sendable {
    let fileIdentity: NotificationFileIdentity?
    let maxRecordID: Int64
    let records: [SystemNotificationRecord]
    var cursorStableID: Data? = nil
    var scannedThroughRecordID: Int64? = nil
    var scannedRecordCount: Int? = nil
}

extension SystemNotificationSource {
    func snapshot(after: Int64, limit: Int) throws -> NotificationStoreSnapshot {
        let maximum = try latestRecordID()
        let rows = limit > 0 ? try records(after: after, limit: limit) : []
        // Legacy sources expose no atomic epoch evidence; only snapshot implementations can prove regression.
        return NotificationStoreSnapshot(fileIdentity: nil,
            maxRecordID: limit > 0 ? max(maximum, after, rows.last?.recordID ?? 0) : maximum, records: rows)
    }
}

private enum NotificationSnapshotError: Error { case replacedDuringRead }


/// Reads the Notification Center database read-only. Table and column
/// names are validated against the live schema before any query.
final class NotificationCenterDatabaseSource: SystemNotificationSource, @unchecked Sendable {
    static let requiredSchema: [String: Set<String>] = [
        "record": ["rec_id", "app_id", "data"],
        "app": ["app_id", "identifier"]
    ]

    let path: String

    init(path: String) {
        self.path = path
    }

    static func locate(candidates: [String] = NotificationCenterDatabaseLocation.candidates) -> NotificationCenterDatabaseSource? {
        let existing = candidates.first { FileManager.default.fileExists(atPath: $0) }
        // Keep the parent fallback to distinguish denied access, after checking actual database files.
        return (existing ?? candidates.first { FileManager.default.fileExists(atPath: ($0 as NSString).deletingLastPathComponent) })
            .map(NotificationCenterDatabaseSource.init(path:))
    }

    var watchedPaths: [String] { [path, path + "-wal"] }

    private func open() throws -> ReadOnlySQLiteDatabase {
        let database = try ReadOnlySQLiteDatabase(path: path)
        try database.require(Self.requiredSchema)
        return database
    }

    func latestRecordID() throws -> Int64 {
        try open().rows("SELECT MAX(rec_id) AS max_id FROM record").first?["max_id"]?.int64 ?? 0
    }

    func records(after recordID: Int64, limit: Int) throws -> [SystemNotificationRecord] {
        try snapshot(after: recordID, limit: limit).records
    }

    func snapshot(after: Int64, limit: Int) throws -> NotificationStoreSnapshot {
        let identity = NotificationFileIdentity.read(path)
        let database = try open()
        // One SQLite read transaction also prevents a writer changing MAX between queries.
        _ = try database.rows("BEGIN")
        defer { _ = try? database.rows("ROLLBACK") }
        let hasUUID = try database.columns(of: "record").contains("uuid")
        let maximum = try database.rows("SELECT MAX(rec_id) AS max_id FROM record").first?["max_id"]?.int64 ?? 0
        let uuidColumn = hasUUID ? "record.uuid" : "NULL"
        let cursorUUID = (hasUUID
            ? try database.rows("SELECT uuid FROM record WHERE rec_id = ?", [.integer(limit == 0 ? maximum : after)]).first?["uuid"]?.data
            : nil).flatMap { !$0.isEmpty && $0.count <= 128 ? $0 : nil }
        let rows = try database.rows(
            """
            SELECT record.rec_id AS rec_id, record.data AS data, app.identifier AS identifier, \(uuidColumn) AS uuid
            FROM record JOIN app ON app.app_id = record.app_id
            WHERE record.rec_id > ? ORDER BY record.rec_id ASC LIMIT ?
            """, [.integer(after), .integer(Int64(max(0, min(limit, 50))))])
        let observedAt = Date()
        let records = rows.compactMap { row -> SystemNotificationRecord? in
            guard let id = row["rec_id"]?.int64, let data = row["data"]?.data,
                  let parsed = NotificationPayloadParser.parse(data) else { return nil }
            return SystemNotificationRecord(recordID: id,
                bundleIdentifier: row["identifier"]?.string ?? parsed.bundleIdentifier ?? "",
                title: parsed.title, subtitle: parsed.subtitle, body: parsed.body,
                deliveredAt: parsed.date, observedAt: observedAt, stableID: row["uuid"]?.data)
        }
        guard identity == NotificationFileIdentity.read(path) else { throw NotificationSnapshotError.replacedDuringRead }
        return NotificationStoreSnapshot(fileIdentity: identity, maxRecordID: maximum,
            records: records, cursorStableID: cursorUUID,
            scannedThroughRecordID: rows.last?["rec_id"]?.int64, scannedRecordCount: rows.count)
    }

}

enum SystemNotificationMonitorState: Equatable, Sendable {
    case stopped
    case running
    case permissionRequired
    case unavailable(reason: String)
    case failed(reason: String)
}

/// Watches the Notification Center database (file-system events on the
/// database and its WAL, plus a restrained backup poll) and delivers new
/// records. Starts from the newest record so history is never replayed.
@MainActor
final class SystemNotificationMonitor: ObservableObject {
    static let pollInterval: TimeInterval = 4
    static let batchLimit = 50

    @Published private(set) var state: SystemNotificationMonitorState = .stopped
    @Published private(set) var lastEventAt: Date?

    var onRecord: ((SystemNotificationRecord) -> Void)?
    private var recordObservers: [UUID: (SystemNotificationRecord) -> Void] = [:]
    private var observationOwners: Set<UUID> = []

    func observeRecords(owner: UUID, receive: @escaping (SystemNotificationRecord) -> Void) {
        recordObservers[owner] = receive
    }

    func setObservationEnabled(_ enabled: Bool, owner: UUID) {
        if enabled {
            observationOwners.insert(owner)
            if state != .running { start() }
        } else {
            observationOwners.remove(owner)
            if observationOwners.isEmpty { stop() }
        }
    }

    func removeObserver(owner: UUID) {
        setObservationEnabled(false, owner: owner)
        recordObservers.removeValue(forKey: owner)
    }

    var observationOwnerCount: Int { observationOwners.count }

    private let makeSource: () -> SystemNotificationSource?
    private let fullDiskAccess: () -> FullDiskAccessState
    private let queue = DispatchQueue(label: "DynamicIsland.SystemNotificationMonitor")
    private var source: SystemNotificationSource?
    private var lastRecordID: Int64 = 0
    private final class Watch: @unchecked Sendable {
        let source: DispatchSourceFileSystemObject
        let identity: NotificationFileIdentity?
        init(source: DispatchSourceFileSystemObject, identity: NotificationFileIdentity?) {
            self.source = source; self.identity = identity
        }
    }
    struct Diagnostics: Equatable {
        var cursorRebases = 0
        var watcherRearms = 0
        var transientFailures = 0
        var unknownTimestampCount = 0
        var installedWatchPaths: Set<String> = []
        var watchersOpened = 0
        var watchersClosed = 0
        var epoch = 0
        var deduplicationCount = 0
    }
    private(set) var diagnostics = Diagnostics()
    private var watchers: [String: Watch] = [:]
    private(set) var armToken = 0
    private var rearmPending = false
    private var epochIdentity: NotificationFileIdentity?
    private var lastStableID: Data?
    private var openFailures = 0
    private struct RecordKey: Hashable { let epoch: Int; let id: Int64 }
    private var deliveredKeys: [RecordKey] = []
    private var deliveredStableIDs: [Data] = []
    private var pollTimer: Timer?
    private var fetching = false
    private var fetchAgain = false
    private var hintObserver: NSObjectProtocol?
    private let useDarwinHints: Bool
    private var generation = 0

    init(
        makeSource: @escaping () -> SystemNotificationSource? = { NotificationCenterDatabaseSource.locate() },
        fullDiskAccess: @escaping () -> FullDiskAccessState = { FullDiskAccessProbe.state() },
        useDarwinHints: Bool = true
    ) {
        self.makeSource = makeSource
        self.fullDiskAccess = fullDiskAccess
        self.useDarwinHints = useDarwinHints
    }

    deinit { watchers.values.forEach { $0.source.cancel() } }

    func start() {
        stop()
        generation += 1
        guard fullDiskAccess() != .denied else {
            state = .permissionRequired
            return
        }
        guard let source = makeSource() else {
            state = .unavailable(reason: "Notification Center database not found on this macOS version")
            return
        }
        do {
            let snapshot = try queue.sync { try source.snapshot(after: Int64.max, limit: 0) }
            lastRecordID = snapshot.maxRecordID
            epochIdentity = snapshot.fileIdentity
            lastStableID = snapshot.cursorStableID
            diagnostics.epoch += 1
            deliveredKeys = []
            deliveredStableIDs = []
            openFailures = 0
        } catch ReadOnlySQLiteError.notPermitted {
            state = .permissionRequired
            return
        } catch ReadOnlySQLiteError.unsupportedSchema(let detail) {
            state = .unavailable(reason: "Unsupported Notification Center database: \(detail)")
            return
        } catch {
            state = .failed(reason: "Could not read Notification Center")
            return
        }
        self.source = source
        state = .running
        installWatchers(for: source.watchedPaths)
        if useDarwinHints {
            NotificationDatabaseDarwinHint.install()
            let token = generation
            hintObserver = NotificationCenter.default.addObserver(forName: NotificationDatabaseDarwinHint.name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.fetch()
                }
            }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollTick() }
        }
    }

    func stop() {
        generation += 1
        if let hintObserver { NotificationCenter.default.removeObserver(hintObserver) }
        hintObserver = nil
        fetchAgain = false
        armToken += 1
        rearmPending = false
        watchers.values.forEach { $0.source.cancel() }
        watchers = [:]
        diagnostics.installedWatchPaths = []
        pollTimer?.invalidate()
        pollTimer = nil
        source = nil
        fetching = false
        if state == .running { state = .stopped }
    }

    /// Existing backup poll also discovers a late WAL or replaced vnode.
    func pollTick() {
        guard let source, state == .running else { return }
        let token = generation
        queue.async { @Sendable [weak self] in
            let identities = Dictionary(uniqueKeysWithValues: Set(source.watchedPaths).compactMap { path in
                NotificationFileIdentity.read(path).map { (path, $0) }
            })
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.state == .running else { return }
                if Set(identities.keys) != Set(self.watchers.keys) || identities.contains(where: { self.watchers[$0.key]?.identity != $0.value }) {
                    self.rearmWatchers()
                }
                self.fetch()
            }
        }
    }

    func rearmWatchers() {
        guard let source, state == .running else { return }
        rearmPending = false
        armToken += 1
        watchers.values.forEach { $0.source.cancel() }
        watchers = [:]
        diagnostics.installedWatchPaths = []
        diagnostics.watcherRearms += 1
        installWatchers(for: source.watchedPaths)
    }

    func watcherEvent(token: Int, replaced: Bool) {
        guard token == armToken, state == .running else { return }
        if replaced {
            guard !rearmPending else { return }
            rearmPending = true
            let generation = generation
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation, self.armToken == token else { return }
                self.rearmPending = false
                self.rearmWatchers()
                self.fetch()
            }
        } else { fetch() }
    }

    /// Reads on the serial queue; all cursor, epoch and delivery authority stays on MainActor.
    func fetch() {
        guard let source, state == .running else { return }
        guard !fetching else { fetchAgain = true; return }
        fetching = true
        let after = lastRecordID
        let token = generation
        let epoch = diagnostics.epoch
        let limit = Self.batchLimit
        queue.async { @Sendable [weak self] in
            let result = Result { try source.snapshot(after: after, limit: limit) }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.diagnostics.epoch == epoch else { return }
                self.fetching = false
                let pending = self.fetchAgain
                self.fetchAgain = false
                switch result {
                case .success(let snapshot):
                    self.openFailures = 0
                    let changed = self.epochIdentity != nil && self.epochIdentity != snapshot.fileIdentity
                    let continuous = self.lastStableID != nil && self.lastStableID == snapshot.cursorStableID
                    if snapshot.maxRecordID < self.lastRecordID || (changed && !continuous) {
                        self.diagnostics.epoch += 1
                        self.diagnostics.cursorRebases += 1
                        self.epochIdentity = snapshot.fileIdentity
                        self.lastRecordID = snapshot.maxRecordID
                        self.lastStableID = nil
                        self.rearmWatchers()
                        if pending { self.fetch() }
                        return
                    }
                    self.epochIdentity = snapshot.fileIdentity
                    if changed { self.rearmWatchers() }
                    for record in snapshot.records where record.recordID > self.lastRecordID {
                        guard self.generation == token, self.state == .running else { return }
                        self.lastRecordID = record.recordID
                        self.lastStableID = record.stableID
                        let key = RecordKey(epoch: self.diagnostics.epoch, id: record.recordID)
                        guard !self.deliveredKeys.contains(key),
                              record.stableID.map({ !self.deliveredStableIDs.contains($0) }) ?? true else { continue }
                        self.deliveredKeys.append(key)
                        if self.deliveredKeys.count > 512 { self.deliveredKeys.removeFirst() }
                        if let stable = record.stableID {
                            self.deliveredStableIDs.append(stable)
                            if self.deliveredStableIDs.count > 512 { self.deliveredStableIDs.removeFirst() }
                        }
                        self.diagnostics.deduplicationCount = self.deliveredKeys.count
                        if record.deliveredAt == nil { self.diagnostics.unknownTimestampCount += 1 }
                        self.lastEventAt = record.deliveredAt ?? record.observedAt
                        var event = record
                        event.epoch = self.diagnostics.epoch
                        self.onRecord?(event)
                        for (owner, receive) in Array(self.recordObservers) {
                            guard self.generation == token, self.state == .running else { return }
                            if self.observationOwners.contains(owner) { receive(event) }
                        }
                    }
                    self.lastRecordID = max(self.lastRecordID, snapshot.scannedThroughRecordID ?? self.lastRecordID)
                    if pending || (snapshot.scannedRecordCount ?? snapshot.records.count) == Self.batchLimit { self.fetch() }
                case .failure(ReadOnlySQLiteError.notPermitted):
                    self.stop(); self.state = .permissionRequired
                case .failure(ReadOnlySQLiteError.unsupportedSchema(let reason)):
                    self.stop(); self.state = .unavailable(reason: "Unsupported Notification Center database: \(reason)")
                case .failure(ReadOnlySQLiteError.cannotOpen):
                    self.diagnostics.transientFailures += 1
                    self.openFailures += 1
                    if self.openFailures >= 2 {
                        // Re-location seeds the newest cursor; it never replays a replacement's history.
                        self.start()
                        if case .failed = self.state {
                            self.state = .unavailable(reason: "Notification Center database could not be opened")
                        }
                    }
                case .failure:
                    self.openFailures = 0
                    self.diagnostics.transientFailures += 1
                }
            }
        }
    }

    private func installWatchers(for paths: [String]) {
        armToken += 1
        let token = armToken
        for path in Set(paths) {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                eventMask: [.write, .extend, .rename, .delete], queue: queue)
            let identity = queue.sync { NotificationFileIdentity.read(descriptor: descriptor) }
            let watch = Watch(source: source, identity: identity)
            source.setEventHandler { @Sendable [weak self, weak watch] in
                guard let watch else { return }
                let replaced = !watch.source.data.intersection([.rename, .delete]).isEmpty
                Task { @MainActor [weak self] in self?.watcherEvent(token: token, replaced: replaced) }
            }
            source.setCancelHandler { @Sendable [weak self] in
                close(descriptor)
                Task { @MainActor [weak self] in self?.diagnostics.watchersClosed += 1 }
            }
            watchers[path] = watch
            diagnostics.watchersOpened += 1
            source.resume()
        }
        diagnostics.installedWatchPaths = Set(watchers.keys)
    }
}
