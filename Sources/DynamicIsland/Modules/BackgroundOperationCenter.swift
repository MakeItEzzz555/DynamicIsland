import Combine
import Foundation

enum BackgroundOperationKind: String, Equatable, Sendable {
    case compression
}

enum BackgroundOperationState: String, Equatable, Sendable {
    case queued
    case preparing
    case running
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        case .queued, .preparing, .running: false
        }
    }

    var isActive: Bool { !isTerminal }
}

enum BackgroundOperationProgress: Equatable, Sendable {
    case indeterminate
    case determinate(Double)

    var fractionCompleted: Double? {
        switch self {
        case .indeterminate:
            nil
        case .determinate(let value):
            min(max(value, 0), 1)
        }
    }
}

enum BackgroundOperationFailureCode: String, Equatable, Sendable {
    case sourceUnavailable
    case destinationUnavailable
    case permissionDenied
    case collisionResolutionFailed
    case operationFailed
    case unsupported
}

struct BackgroundOperationFailure: Equatable, Sendable {
    let code: BackgroundOperationFailureCode
    let message: String
}

struct BackgroundOperationResult: Equatable, Sendable {
    let outputURL: URL
}

struct BackgroundOperation: Identifiable, Equatable, Sendable {
    let id: UUID
    let generation: UUID
    let kind: BackgroundOperationKind
    let title: String
    var subtitle: String?
    let sources: [URL]
    var destination: URL?
    var state: BackgroundOperationState
    var progress: BackgroundOperationProgress
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var failure: BackgroundOperationFailure?
    var result: BackgroundOperationResult?
    let supportsCancellation: Bool

    var statusText: String {
        switch state {
        case .queued: "Queued"
        case .preparing: "Preparing"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: failure?.message ?? "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

enum ZipCompressionError: LocalizedError, Equatable, Sendable {
    case noSources
    case missingSource(String)
    case destinationExists
    case launchFailed(String)
    case processFailed(String)
    case invalidArchive
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noSources:
            "Select at least one file or folder to compress."
        case .missingSource(let name):
            "The source item “\(name)” is no longer available."
        case .destinationExists:
            "The archive destination became unavailable."
        case .launchFailed(let message):
            "Compression could not start: \(message)"
        case .processFailed(let message):
            "Compression failed: \(message)"
        case .invalidArchive:
            "The generated archive could not be verified."
        case .cancelled:
            "Compression was cancelled."
        }
    }
}

/// Runs local macOS archive work outside the main actor. Progress is intentionally
/// indeterminate because ditto does not expose truthful byte-level progress.
final class ZipCompressionExecutor: @unchecked Sendable {
    static let executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    static let validatorURL = URL(fileURLWithPath: "/usr/bin/unzip")

    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]
    private var cancelled: Set<UUID> = []

    static func archiveDestination(
        for sources: [URL],
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) throws -> URL {
        guard let first = sources.first else { throw ZipCompressionError.noSources }
        let directory = first.standardizedFileURL.deletingLastPathComponent()
        let initialName = sources.count == 1
            ? "\(first.lastPathComponent.isEmpty ? "Archive" : first.lastPathComponent).zip"
            : "Archive.zip"
        let base = URL(fileURLWithPath: initialName).deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let name = index == 1 ? initialName : "\(base) \(index).zip"
            let candidate = directory.appendingPathComponent(name).standardizedFileURL
            if !fileExists(candidate) { return candidate }
            index += 1
        }
    }

    func compress(operationID: UUID, sources: [URL]) async throws -> URL {
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { [self] in
                try compressSynchronously(operationID: operationID, sources: sources)
            }.value
        } onCancel: { [self] in
            cancel(operationID: operationID)
        }
    }

    func cancel(operationID: UUID) {
        lock.lock()
        cancelled.insert(operationID)
        let process = processes[operationID]
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
        }
    }

    private func compressSynchronously(operationID: UUID, sources: [URL]) throws -> URL {
        let normalized = sources.map(\.standardizedFileURL)
        guard !normalized.isEmpty else { throw ZipCompressionError.noSources }
        for source in normalized {
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw ZipCompressionError.missingSource(source.lastPathComponent)
            }
        }

        let destination = try Self.archiveDestination(for: normalized)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("BackgroundOperations", isDirectory: true)
            .appendingPathComponent(operationID.uuidString, isDirectory: true)
        let temporaryArchive = root.appendingPathComponent("result.zip")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            clearExecutionState(operationID)
        }

        if normalized.count == 1 {
            try checkCancelled(operationID)
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: normalized[0].path, isDirectory: &isDirectory)
            var arguments = ["-c", "-k", "--sequesterRsrc"]
            if isDirectory.boolValue {
                arguments.append("--keepParent")
            }
            arguments.append(normalized[0].path)
            arguments.append(temporaryArchive.path)
            try run(
                operationID: operationID,
                executable: Self.executableURL,
                arguments: arguments
            )
        } else {
            let staging = root.appendingPathComponent("staging", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            for source in normalized {
                try checkCancelled(operationID)
                let stagedDestination = FileShelfDiskOperations.collisionSafeDestination(
                    for: source,
                    in: staging
                )
                try run(
                    operationID: operationID,
                    executable: Self.executableURL,
                    arguments: [source.path, stagedDestination.path]
                )
            }

            try checkCancelled(operationID)
            try run(
                operationID: operationID,
                executable: Self.executableURL,
                arguments: [
                    "-c", "-k", "--sequesterRsrc",
                    staging.path,
                    temporaryArchive.path
                ]
            )
        }

        try checkCancelled(operationID)
        try run(
            operationID: operationID,
            executable: Self.validatorURL,
            arguments: ["-tqq", temporaryArchive.path]
        )

        try checkCancelled(operationID)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ZipCompressionError.destinationExists
        }
        do {
            try FileManager.default.moveItem(at: temporaryArchive, to: destination)
        } catch {
            if (error as NSError).code == NSFileWriteFileExistsError {
                throw ZipCompressionError.destinationExists
            }
            throw ZipCompressionError.processFailed(error.localizedDescription)
        }
        return destination
    }

    private func run(operationID: UUID, executable: URL, arguments: [String]) throws {
        try checkCancelled(operationID)

        let process = Process()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardError = stderr

        lock.lock()
        if cancelled.contains(operationID) {
            lock.unlock()
            throw ZipCompressionError.cancelled
        }
        processes[operationID] = process
        lock.unlock()

        defer {
            lock.lock()
            if processes[operationID] === process {
                processes[operationID] = nil
            }
            lock.unlock()
        }

        do {
            try process.run()
        } catch {
            throw ZipCompressionError.launchFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        if isCancelled(operationID) {
            throw ZipCompressionError.cancelled
        }
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ZipCompressionError.processFailed(
                (message?.isEmpty == false ? message : nil) ?? "The archive process exited with status \(process.terminationStatus)."
            )
        }
    }

    private func checkCancelled(_ operationID: UUID) throws {
        if isCancelled(operationID) || Task.isCancelled {
            throw ZipCompressionError.cancelled
        }
    }

    private func isCancelled(_ operationID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled.contains(operationID)
    }

    private func clearExecutionState(_ operationID: UUID) {
        lock.lock()
        processes[operationID] = nil
        cancelled.remove(operationID)
        lock.unlock()
    }
}

@MainActor
final class BackgroundOperationController: ObservableObject {
    @Published private(set) var operations: [BackgroundOperation] = []

    private let executor: ZipCompressionExecutor
    private let liveActivities: LiveActivityStore
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let recentLimit = 12

    init(
        liveActivities: LiveActivityStore,
        executor: ZipCompressionExecutor = ZipCompressionExecutor(),
        initialOperations: [BackgroundOperation] = []
    ) {
        self.liveActivities = liveActivities
        self.executor = executor
        self.operations = initialOperations
    }

    var primaryOperation: BackgroundOperation? {
        Self.presentationOrder(operations).first
    }

    var activeCount: Int {
        operations.filter { $0.state.isActive }.count
    }

    var completedCount: Int {
        operations.filter { $0.state == .completed }.count
    }

    @discardableResult
    func startCompression(sources: [URL]) -> UUID? {
        let normalized = sources.map(\.standardizedFileURL)
        guard !normalized.isEmpty else { return nil }

        let id = UUID()
        let destination = try? ZipCompressionExecutor.archiveDestination(for: normalized)
        let count = normalized.count
        let operation = BackgroundOperation(
            id: id,
            generation: UUID(),
            kind: .compression,
            title: count == 1 ? "Compressing \(normalized[0].lastPathComponent)" : "Compressing \(count) items",
            subtitle: destination?.lastPathComponent,
            sources: normalized,
            destination: destination,
            state: .queued,
            progress: .indeterminate,
            createdAt: Date(),
            startedAt: nil,
            completedAt: nil,
            failure: nil,
            result: nil,
            supportsCancellation: true
        )
        operations.append(operation)
        trimRecentOperations()
        publish(operationID: id)

        let task = Task { [weak self] in
            guard let self else { return }
            update(id) {
                $0.state = .preparing
                $0.startedAt = Date()
            }
            update(id) { $0.state = .running }

            do {
                let output = try await executor.compress(operationID: id, sources: normalized)
                guard !Task.isCancelled else {
                    finishCancelled(id)
                    return
                }
                update(id) {
                    $0.state = .completed
                    $0.progress = .determinate(1)
                    $0.destination = output
                    $0.result = BackgroundOperationResult(outputURL: output)
                    $0.completedAt = Date()
                    $0.subtitle = output.lastPathComponent
                }
            } catch is CancellationError {
                finishCancelled(id)
            } catch let error as ZipCompressionError {
                if error == .cancelled {
                    finishCancelled(id)
                } else {
                    finishFailed(id, error: error)
                }
            } catch {
                finishFailed(id, error: error)
            }
            tasks[id] = nil
        }
        tasks[id] = task
        return id
    }

    func cancel(_ id: UUID) {
        guard let operation = operation(id), operation.state.isActive, operation.supportsCancellation else { return }
        executor.cancel(operationID: id)
        tasks[id]?.cancel()
        finishCancelled(id)
    }

    func clearFinished() {
        let removedIDs = operations.filter(\.state.isTerminal).map(\.id)
        operations.removeAll { $0.state.isTerminal }
        for id in removedIDs {
            liveActivities.remove(id: liveActivityID(for: id))
        }
    }

    func operation(_ id: UUID) -> BackgroundOperation? {
        operations.first { $0.id == id }
    }

    /// Generation-scoped progress updates let future executors stream truthful
    /// progress without allowing stale callbacks to mutate a newer execution.
    @discardableResult
    func updateProgress(
        operationID: UUID,
        generation: UUID,
        progress: BackgroundOperationProgress
    ) -> Bool {
        guard let index = operations.firstIndex(where: { $0.id == operationID }),
              operations[index].generation == generation,
              operations[index].state.isActive else { return false }

        if case .determinate(let proposed) = progress,
           case .determinate(let current) = operations[index].progress,
           proposed < current {
            return false
        }
        operations[index].progress = progress
        publish(operationID: operationID)
        return true
    }

    static func presentationOrder(_ operations: [BackgroundOperation]) -> [BackgroundOperation] {
        operations.sorted { lhs, rhs in
            let lhsRank = presentationRank(lhs.state)
            let rhsRank = presentationRank(rhs.state)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            let lhsDate = lhs.completedAt ?? lhs.startedAt ?? lhs.createdAt
            let rhsDate = rhs.completedAt ?? rhs.startedAt ?? rhs.createdAt
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func presentationRank(_ state: BackgroundOperationState) -> Int {
        switch state {
        case .failed: 5
        case .running: 4
        case .preparing: 3
        case .queued: 2
        case .completed: 1
        case .cancelled: 0
        }
    }

    private func update(_ id: UUID, mutate: (inout BackgroundOperation) -> Void) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        if operations[index].state.isTerminal { return }
        mutate(&operations[index])
        publish(operationID: id)
    }

    private func finishCancelled(_ id: UUID) {
        guard let index = operations.firstIndex(where: { $0.id == id }),
              !operations[index].state.isTerminal else { return }
        operations[index].state = .cancelled
        operations[index].completedAt = Date()
        operations[index].failure = nil
        operations[index].result = nil
        publish(operationID: id)
    }

    private func finishFailed(_ id: UUID, error: Error) {
        guard let index = operations.firstIndex(where: { $0.id == id }),
              !operations[index].state.isTerminal else { return }
        operations[index].state = .failed
        operations[index].completedAt = Date()
        operations[index].failure = Self.failure(from: error)
        operations[index].result = nil
        publish(operationID: id)
    }

    private static func failure(from error: Error) -> BackgroundOperationFailure {
        if let zip = error as? ZipCompressionError {
            let code: BackgroundOperationFailureCode = switch zip {
            case .noSources: .unsupported
            case .missingSource: .sourceUnavailable
            case .destinationExists: .collisionResolutionFailed
            case .launchFailed, .processFailed, .invalidArchive: .operationFailed
            case .cancelled: .operationFailed
            }
            return BackgroundOperationFailure(
                code: code,
                message: zip.localizedDescription
            )
        }
        let nsError = error as NSError
        let code: BackgroundOperationFailureCode = nsError.code == NSFileWriteNoPermissionError
            ? .permissionDenied
            : .operationFailed
        return BackgroundOperationFailure(code: code, message: error.localizedDescription)
    }

    private func trimRecentOperations() {
        let activeIDs = Set(operations.filter { $0.state.isActive }.map(\.id))
        let terminal = Self.presentationOrder(operations.filter { $0.state.isTerminal })
        guard terminal.count > recentLimit else { return }
        let recentTerminalIDs = Set(terminal.prefix(recentLimit).map(\.id))
        let keep = activeIDs.union(recentTerminalIDs)
        let removed = operations.filter { !keep.contains($0.id) }
        operations.removeAll { !keep.contains($0.id) }
        for operation in removed {
            liveActivities.remove(id: liveActivityID(for: operation.id))
        }
    }

    private func publish(operationID: UUID) {
        guard let operation = operation(operationID) else { return }
        let progress = operation.progress.fractionCompleted
        let subtitle: String = {
            if operation.state == .failed {
                return operation.failure?.message ?? "Failed"
            }
            if operation.state == .completed {
                return operation.result?.outputURL.lastPathComponent ?? "Completed"
            }
            return operation.statusText
        }()

        liveActivities.update(
            DynamicIslandLiveActivity(
                id: liveActivityID(for: operation.id),
                kind: .backgroundOperation,
                title: operation.title,
                subtitle: subtitle,
                symbolName: operation.state == .completed ? "archivebox.fill" : "archivebox",
                priority: operation.state.isActive ? 95 : 64,
                isActive: operation.state.isActive,
                progress: LiveActivityStore.clampedProgress(progress),
                updatedAt: Date(),
                lifecycle: LiveActivityLifecycleMetadata(
                    authority: .process,
                    startEvidence: "Background operation queued",
                    progressEvidence: progress == nil ? "Indeterminate process state" : "Executor progress",
                    completionEvidence: operation.state.isTerminal ? operation.statusText : nil,
                    dismissPolicy: operation.state.isTerminal ? .automatic : .untilSourceEnds,
                    supportsCancellation: operation.state.isActive && operation.supportsCancellation
                )
            )
        )
    }

    private func liveActivityID(for id: UUID) -> String {
        "backgroundOperation.\(id.uuidString)"
    }
}

