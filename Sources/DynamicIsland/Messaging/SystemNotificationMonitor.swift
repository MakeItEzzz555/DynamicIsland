import Foundation

/// One delivered macOS notification, normalized. Bodies stay in memory.
struct SystemNotificationRecord: Equatable, Sendable {
    let recordID: Int64
    let bundleIdentifier: String
    let title: String?
    let subtitle: String?
    let body: String?
    let deliveredAt: Date
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
}

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
        candidates.first { FileManager.default.fileExists(atPath: $0) || FileManager.default.fileExists(atPath: ($0 as NSString).deletingLastPathComponent) }
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
        let rows = try open().rows(
            """
            SELECT record.rec_id AS rec_id, record.data AS data, app.identifier AS identifier
            FROM record JOIN app ON app.app_id = record.app_id
            WHERE record.rec_id > ? ORDER BY record.rec_id ASC LIMIT ?
            """,
            [.integer(recordID), .integer(Int64(limit))]
        )
        return rows.compactMap { row in
            guard let id = row["rec_id"]?.int64,
                  let data = row["data"]?.data,
                  let parsed = NotificationPayloadParser.parse(data) else { return nil }
            let bundle = row["identifier"]?.string ?? parsed.bundleIdentifier ?? ""
            return SystemNotificationRecord(
                recordID: id,
                bundleIdentifier: bundle,
                title: parsed.title,
                subtitle: parsed.subtitle,
                body: parsed.body,
                deliveredAt: parsed.date ?? Date()
            )
        }
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

    private let makeSource: () -> SystemNotificationSource?
    private let fullDiskAccess: () -> FullDiskAccessState
    private let queue = DispatchQueue(label: "DynamicIsland.SystemNotificationMonitor")
    private var source: SystemNotificationSource?
    private var lastRecordID: Int64 = 0
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var pollTimer: Timer?
    private var fetching = false
    private var generation = 0

    init(
        makeSource: @escaping () -> SystemNotificationSource? = { NotificationCenterDatabaseSource.locate() },
        fullDiskAccess: @escaping () -> FullDiskAccessState = { FullDiskAccessProbe.state() }
    ) {
        self.makeSource = makeSource
        self.fullDiskAccess = fullDiskAccess
    }

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
            lastRecordID = try source.latestRecordID()
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
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fetch() }
        }
    }

    func stop() {
        generation += 1
        watchers.forEach { $0.cancel() }
        watchers = []
        pollTimer?.invalidate()
        pollTimer = nil
        source = nil
        fetching = false
        if state == .running { state = .stopped }
    }

    /// Fetches records newer than the last seen id. Exposed for tests.
    func fetch() {
        guard let source, !fetching, state == .running else { return }
        fetching = true
        let after = lastRecordID
        let token = generation
        let limit = Self.batchLimit
        queue.async { @Sendable [weak self] in
            let result = Result { try source.records(after: after, limit: limit) }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.fetching = false
                switch result {
                case .success(let records):
                    for record in records where record.recordID > self.lastRecordID {
                        self.lastRecordID = record.recordID
                        self.lastEventAt = record.deliveredAt
                        self.onRecord?(record)
                    }
                case .failure(ReadOnlySQLiteError.notPermitted):
                    self.stop()
                    self.state = .permissionRequired
                case .failure:
                    // Transient (locked database during a write): retry on next event.
                    break
                }
            }
        }
    }

    private func installWatchers(for paths: [String]) {
        for path in paths {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .rename, .delete],
                queue: queue
            )
            // Handlers run on `queue`; they must not inherit main-actor
            // isolation from this method (Swift 6 traps on that).
            watcher.setEventHandler { @Sendable [weak self] in
                Task { @MainActor [weak self] in self?.fetch() }
            }
            watcher.setCancelHandler { @Sendable in close(descriptor) }
            watcher.resume()
            watchers.append(watcher)
        }
    }
}
