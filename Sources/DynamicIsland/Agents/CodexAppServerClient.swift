import Foundation

enum CodexJSONValue: Codable, Equatable, Sendable {
    case object([String: CodexJSONValue])
    case array([CodexJSONValue])
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CodexJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: CodexJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: CodexJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [CodexJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        switch self {
        case .integer(let value): return Int(exactly: value)
        case .number(let value) where value.isFinite: return Int(exactly: value)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .number(let value): return value
        default: return nil
        }
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    subscript(key: String) -> CodexJSONValue? {
        objectValue?[key]
    }
}

enum CodexAppServerError: Error, Equatable, Sendable {
    case executableNotFound
    case launchFailed(String)
    case notRunning
    case requestTimedOut(String)
    case transportClosed(String?)
    case malformedMessage
    case rpcError(code: Int?, message: String)
    case invalidResponse(String)
}

struct CodexManagedThread: Equatable, Sendable {
    let id: String
    let cwd: String?
    let model: String?
    let canAcceptDirectInput: Bool
}

struct CodexManagedTurn: Equatable, Sendable {
    let id: String
    let status: String?
}

struct CodexListedThread: Equatable, Sendable {
    let id: String
    let cwd: String?
    let model: String?
    let status: AgentDiscoveredSessionRuntimeState
    let updatedAt: Date
    let rolloutPath: String?
    let canAcceptDirectInput: Bool
}

struct CodexThreadItemEntry: Equatable, Sendable {
    let turnID: String
    let item: CodexJSONValue
    let timestamp: Date
}


struct CodexAvailableModel: Equatable, Sendable {
    let id: String
    let model: String
    let displayName: String
    let description: String?
    let hidden: Bool
    let isDefault: Bool
}

enum CodexAppServerEvent: Equatable, Sendable {
    case notification(method: String, params: CodexJSONValue)
    case serverRequest(id: CodexJSONValue, method: String, params: CodexJSONValue)
    case transportClosed(String?)
}

actor CodexAppServerClient {
    private struct PendingRequest {
        let continuation: CheckedContinuation<CodexJSONValue, Error>
        let timeoutTask: Task<Void, Never>
    }

    private let executableURL: URL
    private let requestTimeout: Duration
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var startTask: Task<Void, Error>?
    private var pending: [String: PendingRequest] = [:]
    private var stdoutBuffer = Data()
    private var recentStderr = ""
    private var initialized = false
    private var transportGeneration: UInt64 = 0

    private let eventsStream: AsyncStream<CodexAppServerEvent>
    private let eventsContinuation: AsyncStream<CodexAppServerEvent>.Continuation

    init(
        executableURL: URL? = nil,
        requestTimeout: Duration = .seconds(20)
    ) throws {
        guard let resolved = executableURL ?? Self.resolveExecutable() else {
            throw CodexAppServerError.executableNotFound
        }
        self.executableURL = resolved
        self.requestTimeout = requestTimeout
        var continuation: AsyncStream<CodexAppServerEvent>.Continuation!
        self.eventsStream = AsyncStream { continuation = $0 }
        self.eventsContinuation = continuation
    }

    deinit {
        stdoutTask?.cancel()
        stderrTask?.cancel()
        eventsContinuation.finish()
    }

    func events() -> AsyncStream<CodexAppServerEvent> {
        eventsStream
    }

    func start() async throws {
        if process?.isRunning == true, initialized { return }
        if let startTask {
            try await startTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { throw CodexAppServerError.notRunning }
            try await self.launchAndInitialize()
        }
        startTask = task
        do {
            try await task.value
            startTask = nil
        } catch {
            startTask = nil
            throw error
        }
    }

    private func launchAndInitialize() async throws {
        failAllPending(CodexAppServerError.transportClosed(nil))
        stopProcessOnly()
        transportGeneration = transportGeneration == UInt64.max ? 1 : transportGeneration + 1
        let generation = transportGeneration

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        self.process = process
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        recentStderr = ""
        stdoutBuffer = Data()
        initialized = false

        installReaders(stdout: stdout, stderr: stderr, generation: generation)

        do {
            try process.run()
        } catch {
            stopProcessOnly()
            throw CodexAppServerError.launchFailed(error.localizedDescription)
        }

        let initialize = CodexJSONValue.object([
            "clientInfo": .object([
                "name": .string("dynamic-island"),
                "title": .string("DynamicIsland"),
                "version": .string("1")
            ]),
            "capabilities": .object([
                // Required for typed thread control capability fields such as
                // canAcceptDirectInput in the current v2 app-server schema.
                "experimentalApi": .bool(true)
            ])
        ])
        do {
            _ = try await request(method: "initialize", params: initialize)
            try sendNotification(method: "initialized")
            initialized = true
        } catch {
            if generation == transportGeneration {
                initialized = false
                transportGeneration = transportGeneration == UInt64.max ? 1 : transportGeneration + 1
                stopProcessOnly()
            }
            throw error
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        failAllPending(CodexAppServerError.transportClosed(nil))
        initialized = false
        transportGeneration = transportGeneration == UInt64.max ? 1 : transportGeneration + 1
        stopProcessOnly()
    }

    func startThread(cwd: String?, model: String? = nil) async throws -> CodexManagedThread {
        try await start()
        var params: [String: CodexJSONValue] = [:]
        if let cwd, !cwd.isEmpty { params["cwd"] = .string(cwd) }
        if let model, !model.isEmpty { params["model"] = .string(model) }
        let result = try await request(method: "thread/start", params: .object(params))
        return try decodeThreadResponse(result, method: "thread/start")
    }

    func listThreads(limit: Int = 500) async throws -> [CodexListedThread] {
        try await start()
        let totalLimit = min(max(limit, 1), 500)
        var cursor: String?
        var result: [CodexListedThread] = []
        var seen = Set<String>()

        while result.count < totalLimit {
            let pageLimit = min(100, totalLimit - result.count)
            var params: [String: CodexJSONValue] = [
                "archived": .bool(false),
                "limit": .integer(Int64(pageLimit)),
                "sortKey": .string("recency_at"),
                "sortDirection": .string("desc"),
                "useStateDbOnly": .bool(false)
            ]
            if let cursor { params["cursor"] = .string(cursor) }

            let response = try await request(
                method: "thread/list",
                params: .object(params)
            )
            guard let values = response["data"]?.arrayValue else {
                throw CodexAppServerError.invalidResponse("thread/list")
            }
            for value in values {
                guard let thread = Self.decodeListedThread(value),
                      seen.insert(thread.id).inserted else { continue }
                result.append(thread)
                if result.count == totalLimit { break }
            }

            guard let next = response["nextCursor"]?.stringValue,
                  !next.isEmpty,
                  next != cursor,
                  !values.isEmpty else { break }
            cursor = next
        }
        return result
    }

    func readThread(threadID: String) async throws -> CodexManagedThread {
        try await start()
        let result = try await request(
            method: "thread/read",
            params: .object([
                "threadId": .string(threadID),
                "includeTurns": .bool(false)
            ])
        )
        return try decodeThreadResponse(result, method: "thread/read")
    }

    func listModels(limit: Int = 100) async throws -> [CodexAvailableModel] {
        try await start()
        let boundedLimit = min(max(limit, 1), 200)
        let result = try await request(
            method: "model/list",
            params: .object([
                "limit": .integer(Int64(boundedLimit)),
                "includeHidden": .bool(false)
            ])
        )
        guard let values = result["data"]?.arrayValue else {
            throw CodexAppServerError.invalidResponse("model/list")
        }
        return values.compactMap { value in
            guard let id = value["id"]?.stringValue,
                  let model = value["model"]?.stringValue,
                  let displayName = value["displayName"]?.stringValue else {
                return nil
            }
            return CodexAvailableModel(
                id: id,
                model: model,
                displayName: displayName,
                description: value["description"]?.stringValue,
                hidden: value["hidden"]?.boolValue ?? false,
                isDefault: value["isDefault"]?.boolValue ?? false
            )
        }
    }

    func readAccountRateLimits() async throws -> CodexJSONValue {
        try await start()
        return try await request(
            method: "account/rateLimits/read",
            params: .object([
                "excludeResetCreditDetails": .bool(true),
                "supportsLunaReserve": .bool(false)
            ])
        )
    }

    func listThreadItems(threadID: String, limit: Int = 80) async throws -> [CodexThreadItemEntry] {
        try await start()
        let boundedLimit = min(max(limit, 1), 100)
        let result = try await request(
            method: "thread/items/list",
            params: .object([
                "threadId": .string(threadID),
                "limit": .integer(Int64(boundedLimit)),
                "sortDirection": .string("desc")
            ])
        )
        guard let values = result["data"]?.arrayValue else {
            throw CodexAppServerError.invalidResponse("thread/items/list")
        }
        return values.compactMap(Self.decodeThreadItemEntry).sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            let lhsID = $0.item["id"]?.stringValue ?? ""
            let rhsID = $1.item["id"]?.stringValue ?? ""
            return lhsID < rhsID
        }
    }

    func resumeThread(threadID: String) async throws -> CodexManagedThread {
        try await start()
        let result = try await request(
            method: "thread/resume",
            params: .object([
                "threadId": .string(threadID),
                "excludeTurns": .bool(true)
            ])
        )
        return try decodeThreadResponse(result, method: "thread/resume")
    }

    func startTurn(
        threadID: String,
        prompt: String,
        model: String? = nil
    ) async throws -> CodexManagedTurn {
        try await start()
        let input: CodexJSONValue = .array([
            .object([
                "type": .string("text"),
                "text": .string(prompt),
                "text_elements": .array([])
            ])
        ])
        var params: [String: CodexJSONValue] = [
            "threadId": .string(threadID),
            "input": input,
            "turnTrigger": .string("dynamic-island")
        ]
        if let model, !model.isEmpty {
            params["model"] = .string(model)
        }
        let result = try await request(
            method: "turn/start",
            params: .object(params)
        )
        guard let turn = result["turn"],
              let id = turn["id"]?.stringValue else {
            throw CodexAppServerError.invalidResponse("turn/start")
        }
        return CodexManagedTurn(id: id, status: turn["status"]?.stringValue)
    }

    func interrupt(threadID: String, turnID: String) async throws {
        try await start()
        _ = try await request(
            method: "turn/interrupt",
            params: .object([
                "threadId": .string(threadID),
                "turnId": .string(turnID)
            ])
        )
    }

    func respondToApproval(requestToken: AgentInteractiveRequestToken, allow: Bool) throws {
        guard process?.isRunning == true else { throw CodexAppServerError.notRunning }
        try writeMessage(.object([
            "id": Self.codexRequestID(requestToken),
            "result": .object([
                "decision": .string(allow ? "accept" : "decline")
            ])
        ]))
    }

    private nonisolated static func codexRequestID(
        _ token: AgentInteractiveRequestToken
    ) -> CodexJSONValue {
        switch token {
        case .string(let value): .string(value)
        case .integer(let value): .integer(value)
        }
    }

    func respondUnsupportedRequest(
        requestID: CodexJSONValue,
        method: String
    ) throws {
        guard process?.isRunning == true else { throw CodexAppServerError.notRunning }
        try writeMessage(.object([
            "id": requestID,
            "error": .object([
                "code": .integer(-32_601),
                "message": .string("Unsupported app-server request: \(method.prefix(80))")
            ])
        ]))
    }

    private nonisolated static func decodeThreadItemEntry(_ value: CodexJSONValue) -> CodexThreadItemEntry? {
        guard let turnID = value["turnId"]?.stringValue,
              let item = value["item"] else { return nil }
        let milliseconds = value["completedAtMs"]?.doubleValue
            ?? value["startedAtMs"]?.doubleValue
            ?? 0
        return CodexThreadItemEntry(
            turnID: turnID,
            item: item,
            timestamp: Date(timeIntervalSince1970: max(milliseconds, 0) / 1_000)
        )
    }

    private nonisolated static func decodeListedThread(_ value: CodexJSONValue) -> CodexListedThread? {
        guard let id = value["id"]?.stringValue else { return nil }
        let statusType = value["status"]?["type"]?.stringValue ?? "notLoaded"
        let status = AgentDiscoveredSessionRuntimeState(rawValue: statusType) ?? .notLoaded
        let updatedAtSeconds = value["updatedAt"]?.doubleValue ?? 0
        return CodexListedThread(
            id: id,
            cwd: value["cwd"]?.stringValue,
            model: value["model"]?.stringValue,
            status: status,
            updatedAt: Date(timeIntervalSince1970: max(updatedAtSeconds, 0)),
            rolloutPath: value["path"]?.stringValue,
            canAcceptDirectInput: value["canAcceptDirectInput"]?.boolValue ?? false
        )
    }

    private func decodeThreadResponse(
        _ result: CodexJSONValue,
        method: String
    ) throws -> CodexManagedThread {
        guard let thread = result["thread"],
              let id = thread["id"]?.stringValue else {
            throw CodexAppServerError.invalidResponse(method)
        }
        return CodexManagedThread(
            id: id,
            cwd: result["cwd"]?.stringValue ?? thread["cwd"]?.stringValue,
            model: result["model"]?.stringValue ?? thread["model"]?.stringValue,
            canAcceptDirectInput: thread["canAcceptDirectInput"]?.boolValue ?? false
        )
    }

    private func request(
        method: String,
        params: CodexJSONValue
    ) async throws -> CodexJSONValue {
        guard process?.isRunning == true else { throw CodexAppServerError.notRunning }
        let requestID = UUID().uuidString.lowercased()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(for: self.requestTimeout)
                    guard !Task.isCancelled else { return }
                    await self.timeoutRequest(requestID, method: method)
                }
                pending[requestID] = PendingRequest(
                    continuation: continuation,
                    timeoutTask: timeout
                )
                do {
                    try writeMessage(.object([
                        "id": .string(requestID),
                        "method": .string(method),
                        "params": params
                    ]))
                } catch {
                    if let pending = pending.removeValue(forKey: requestID) {
                        pending.timeoutTask.cancel()
                        pending.continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { [weak self] in
            Task {
                await self?.cancelRequest(requestID)
            }
        }
    }

    private func sendNotification(method: String) throws {
        try writeMessage(.object(["method": .string(method)]))
    }

    private func writeMessage(_ message: CodexJSONValue) throws {
        guard let stdinPipe, process?.isRunning == true else {
            throw CodexAppServerError.notRunning
        }
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func installReaders(stdout: Pipe, stderr: Pipe, generation: UInt64) {
        let stdoutStream = AsyncStream<Data> { continuation in
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
        stdoutTask = Task { [weak self] in
            for await data in stdoutStream {
                await self?.consumeStdout(data, generation: generation)
            }
            await self?.readerClosed(generation: generation)
        }

        let stderrStream = AsyncStream<Data> { continuation in
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
        stderrTask = Task { [weak self] in
            for await data in stderrStream {
                await self?.consumeStderr(data, generation: generation)
            }
        }
    }

    private func consumeStdout(_ data: Data, generation: UInt64) {
        guard generation == transportGeneration else { return }
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            guard !lineData.isEmpty else { continue }
            handleLine(Data(lineData))
        }
    }

    private func consumeStderr(_ data: Data, generation: UInt64) {
        guard generation == transportGeneration else { return }
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else { return }
        recentStderr.append(value)
        if recentStderr.utf8.count > 8_192 {
            recentStderr = String(recentStderr.suffix(8_192))
        }
    }

    private func handleLine(_ data: Data) {
        guard let message = try? JSONDecoder().decode(CodexJSONValue.self, from: data),
              let object = message.objectValue else {
            failAllPending(CodexAppServerError.malformedMessage)
            initialized = false
            transportGeneration = transportGeneration == UInt64.max ? 1 : transportGeneration + 1
            eventsContinuation.yield(.transportClosed(nil))
            stopProcessOnly()
            return
        }

        if let id = object["id"] {
            if let method = object["method"]?.stringValue {
                eventsContinuation.yield(.serverRequest(
                    id: id,
                    method: method,
                    params: object["params"] ?? .object([:])
                ))
                return
            }

            let requestID: String?
            switch id {
            case .string(let value): requestID = value
            case .integer(let value): requestID = String(value)
            default: requestID = nil
            }
            guard let requestID, let pending = pending.removeValue(forKey: requestID) else { return }
            pending.timeoutTask.cancel()
            if let error = object["error"] {
                let code = error["code"]?.intValue
                let message = error["message"]?.stringValue ?? "Codex app-server RPC error"
                pending.continuation.resume(
                    throwing: CodexAppServerError.rpcError(code: code, message: message)
                )
            } else {
                pending.continuation.resume(returning: object["result"] ?? .null)
            }
            return
        }

        if let method = object["method"]?.stringValue {
            eventsContinuation.yield(.notification(
                method: method,
                params: object["params"] ?? .object([:])
            ))
        }
    }

    private func timeoutRequest(_ id: String, method: String) {
        guard let pending = pending.removeValue(forKey: id) else { return }
        pending.timeoutTask.cancel()
        pending.continuation.resume(
            throwing: CodexAppServerError.requestTimedOut(method)
        )
    }

    private func cancelRequest(_ id: String) {
        guard let pending = pending.removeValue(forKey: id) else { return }
        pending.timeoutTask.cancel()
        pending.continuation.resume(throwing: CancellationError())
    }

    private func readerClosed(generation: UInt64) {
        guard generation == transportGeneration else { return }
        failAllPending(CodexAppServerError.transportClosed(nil))
        initialized = false
        transportGeneration = transportGeneration == UInt64.max ? 1 : transportGeneration + 1
        eventsContinuation.yield(.transportClosed(nil))
        stopProcessOnly()
    }

    private func failAllPending(_ error: Error) {
        let values = pending.values
        pending.removeAll()
        for value in values {
            value.timeoutTask.cancel()
            value.continuation.resume(throwing: error)
        }
    }

    private func stopProcessOnly() {
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe?.fileHandleForWriting.close()

        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    nonisolated private static func resolveExecutable() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
