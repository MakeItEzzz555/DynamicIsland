import AppKit
import Foundation

/// One normalized agent activity, as persisted by Record Activities.
///
/// Built only from structured fields of an already-normalized `AgentEvent`
/// and the session it produced. Free-form provider text (summaries, plan
/// text, prompts, transcripts, command arguments, paths, environment) is
/// never copied, so a record cannot carry secrets or conversation content.
struct AgentActivityRecord: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    struct UsageSample: Codable, Equatable, Sendable {
        let metric: String
        let scope: String
        let value: Double
        let limit: Double?
        let unit: String
    }

    var version = AgentActivityRecord.schemaVersion
    let occurredAt: Date
    let provider: String
    /// Provider-native session id (an opaque identifier) and generation.
    let session: String
    let generation: UInt64
    let event: String
    /// Session state after the event was applied.
    let state: String
    let source: String
    /// Opaque operation/request id (tool call, command or approval).
    let correlation: String?
    /// Tool name only (e.g. "Edit"), never its input.
    var tool: String?
    /// Executable name only (e.g. "git"), never arguments.
    var executable: String?
    var success: Bool?
    var exitCode: Int?
    var approval: String?
    /// Project folder name only, never the full path.
    var project: String?
    var model: String?
    var usage: [UsageSample]?
}

enum AgentActivityRecordProjection {
    /// Events that are bookkeeping, not activity.
    private static let ignored: Set<String> = ["heartbeat", "capabilitiesUpdated"]
    private static let identifierCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "_-.:@"))

    /// The leading identifier only: "Bash(rm -rf x)" -> "Bash". Producers are
    /// not trusted to keep arguments out of name fields.
    static func identifier(_ value: String?, limit: Int = 64) -> String? {
        guard let value else { return nil }
        let scalars = value.unicodeScalars.prefix { identifierCharacters.contains($0) }
        let token = String(String.UnicodeScalarView(scalars).prefix(limit))
        return token.isEmpty ? nil : token
    }

    /// A folder name, never a path.
    static func projectName(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let name = URL(fileURLWithPath: value).lastPathComponent
        return name.isEmpty || name == "/" ? nil : String(name.prefix(64))
    }

    static func record(for event: AgentEvent, session: AgentSession) -> AgentActivityRecord? {
        if case .unsupported = event.type { return nil }
        let type = event.type.stableName
        guard !ignored.contains(type) else { return nil }
        var record = AgentActivityRecord(
            occurredAt: event.effectiveTimestamp,
            provider: event.sessionID.provider.stableName,
            session: identifier(event.sessionID.nativeID, limit: 128) ?? "unknown",
            generation: event.generation.rawValue,
            event: type,
            state: session.state.rawValue,
            source: session.source.rawValue,
            correlation: identifier(event.correlationID?.rawValue, limit: 128)
        )
        switch event.payload {
        case .tool(let tool):
            record.tool = identifier(tool.name)
            record.success = tool.success
        case .command(let command):
            record.executable = command.executable.flatMap {
                identifier(AgentPrivacyProjection.commandSummary(executable: $0))
            }
            record.success = command.success
            record.exitCode = command.exitCode
        case .approvalResolution(let resolution):
            record.approval = resolution.state.rawValue
        case .approvalRequest:
            record.approval = AgentApprovalState.pending.rawValue
        case .usage(let usage):
            record.usage = usage.scopedEntries
                .sorted { ($0.key.metric.rawValue, $0.key.scope) < ($1.key.metric.rawValue, $1.key.scope) }
                .prefix(8)
                .map {
                    AgentActivityRecord.UsageSample(
                        metric: $0.key.metric.rawValue,
                        scope: String($0.key.scope.prefix(32)),
                        value: $0.value.value,
                        limit: $0.value.limit,
                        unit: $0.value.unit.rawValue
                    )
                }
        case .sessionMetadata, .projectContext:
            record.project = projectName(session.project.displayName)
            record.model = identifier(session.project.model)
        default:
            break
        }
        if event.type == .sessionStarted || event.type == .sessionResumed {
            record.project = record.project ?? projectName(session.project.displayName)
            record.model = record.model ?? identifier(session.project.model)
        }
        return record
    }
}

/// Bounded local retention for recorded activity.
struct AgentActivityRetention: Equatable, Sendable {
    var maximumAge: TimeInterval = 14 * 24 * 60 * 60
    var maximumTotalBytes = 20 * 1024 * 1024
    var maximumFileBytes = 2 * 1024 * 1024

    static let standard = AgentActivityRetention()
}

struct AgentActivityStorageSummary: Equatable, Sendable {
    var fileCount = 0
    var totalBytes = 0
    var oldest: Date?
}

/// JSON Lines files under Application Support, written on a private serial
/// queue so recording never blocks the main thread. Directory 0700, files
/// 0600. Nothing here touches the network.
final class AgentActivityLog: @unchecked Sendable {
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("AgentActivity", isDirectory: true)
    }

    let directory: URL
    private let retention: AgentActivityRetention
    private let now: @Sendable () -> Date
    private let queue = DispatchQueue(label: "DynamicIsland.AgentActivityLog", qos: .utility)
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    init(
        directory: URL = AgentActivityLog.defaultDirectory,
        retention: AgentActivityRetention = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directory = directory
        self.retention = retention
        self.now = now
    }

    func append(_ records: [AgentActivityRecord], completion: (@Sendable () -> Void)? = nil) {
        guard !records.isEmpty else { completion?(); return }
        queue.async { [self] in
            write(records)
            completion?()
        }
    }

    /// Blocks until queued writes and `records` are on disk (termination).
    func appendSynchronously(_ records: [AgentActivityRecord]) {
        queue.sync { write(records) }
    }

    func clear(completion: (@Sendable () -> Void)? = nil) {
        queue.async { [self] in
            for file in files() { try? FileManager.default.removeItem(at: file) }
            completion?()
        }
    }

    func summary() -> AgentActivityStorageSummary {
        queue.sync { summaryOnQueue() }
    }

    func readAll() -> [AgentActivityRecord] {
        queue.sync {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return files().sorted { $0.lastPathComponent < $1.lastPathComponent }.flatMap { file -> [AgentActivityRecord] in
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
                return text.split(separator: "\n").compactMap {
                    try? decoder.decode(AgentActivityRecord.self, from: Data($0.utf8))
                }
            }
        }
    }

    // MARK: Queue-confined

    private func write(_ records: [AgentActivityRecord]) {
        guard !records.isEmpty, prepareDirectory() else { return }
        var payload = Data()
        for record in records {
            guard let line = try? encoder.encode(record) else { continue }
            payload.append(line)
            payload.append(0x0A)
        }
        let file = currentFile(adding: payload.count)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        }
        prune()
    }

    private func prepareDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return true
        } catch {
            return false
        }
    }

    private func files() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []
        return contents.filter { $0.lastPathComponent.hasPrefix("activity-") && $0.pathExtension == "jsonl" }
    }

    /// `activity-YYYY-MM-DD.N.jsonl`, rolling to the next part at the size cap.
    private func currentFile(adding bytes: Int) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: now())
        var part = 1
        while true {
            let file = directory.appendingPathComponent("activity-\(day).\(part).jsonl")
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size == 0 || size + bytes <= retention.maximumFileBytes { return file }
            part += 1
        }
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-retention.maximumAge)
        var entries = files().compactMap { file -> (URL, Int, Date)? in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (file, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }
        for entry in entries where entry.2 < cutoff {
            try? FileManager.default.removeItem(at: entry.0)
        }
        entries.removeAll { $0.2 < cutoff }
        // Oldest first by name (date + part), then size cap.
        entries.sort { $0.0.lastPathComponent.localizedStandardCompare($1.0.lastPathComponent) == .orderedAscending }
        var total = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where total > retention.maximumTotalBytes && entries.count > 1 {
            guard entry.0 != entries.last?.0 else { break }
            try? FileManager.default.removeItem(at: entry.0)
            total -= entry.1
        }
    }

    private func summaryOnQueue() -> AgentActivityStorageSummary {
        var summary = AgentActivityStorageSummary()
        for file in files() {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            summary.fileCount += 1
            summary.totalBytes += values?.fileSize ?? 0
            if let created = values?.contentModificationDate {
                summary.oldest = min(summary.oldest ?? created, created)
            }
        }
        return summary
    }
}

/// Record Activities: explicit opt-in, local-only recording of normalized
/// agent activity. Observes the normalized event store (the single source
/// of truth for every producer), buffers records on the main actor and
/// writes them in batches off the main thread.
@MainActor
final class AgentActivityRecorder: ObservableObject {
    static let batchSize = 64
    static let flushDelay: TimeInterval = 1

    @Published private(set) var isRecording = false
    @Published private(set) var summary = AgentActivityStorageSummary()

    let log: AgentActivityLog
    private var pending: [AgentActivityRecord] = []
    private var flushScheduled = false

    init(log: AgentActivityLog = AgentActivityLog()) {
        self.log = log
    }

    var storageDirectory: URL { log.directory }

    func setRecording(_ enabled: Bool) {
        guard enabled != isRecording else { return }
        if !enabled { flush() }
        isRecording = enabled
        refreshSummary()
    }

    /// Called by the event store for every applied normalized event.
    func handleApplied(_ event: AgentEvent, session: AgentSession) {
        guard isRecording,
              let record = AgentActivityRecordProjection.record(for: event, session: session) else { return }
        pending.append(record)
        if pending.count >= Self.batchSize {
            flush()
        } else if !flushScheduled {
            flushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.flushDelay) { [weak self] in
                MainActor.assumeIsolated {
                    self?.flushScheduled = false
                    self?.flush()
                }
            }
        }
    }

    func flush() {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        log.append(batch) { [weak self] in
            Task { @MainActor in self?.refreshSummary() }
        }
    }

    func flushForTermination() {
        let batch = pending
        pending.removeAll()
        log.appendSynchronously(batch)
    }

    func clear() {
        pending.removeAll()
        log.clear { [weak self] in
            Task { @MainActor in self?.refreshSummary() }
        }
    }

    func revealStorage() {
        let directory = log.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func refreshSummary() {
        let value = log.summary()
        if value != summary { summary = value }
    }
}
