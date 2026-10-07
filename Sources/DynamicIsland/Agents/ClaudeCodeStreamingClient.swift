import Foundation

enum ClaudeCodeStreamingError: Error, Equatable, Sendable {
    case executableNotFound
    case launchFailed
    case turnAlreadyRunning
    case sessionNotRunning
    case malformedMessage
    case unsupported
}

struct ClaudeCodeStreamEnvelope: Equatable, Sendable {
    let nativeSessionID: String
    let turnID: String
    let message: CodexJSONValue
}

enum ClaudeCodeStreamEvent: Equatable, Sendable {
    case message(ClaudeCodeStreamEnvelope)
    /// The process ended during a turn (no terminal `result`).
    case transportFailed(nativeSessionID: String, turnID: String)
    /// The process ended while idle (normal after stdin closes or stop).
    case sessionExited(nativeSessionID: String)
}

/// How a managed Claude Code process is launched. Verified against Claude
/// Code 2.1.285: `--print` + stream-json in/out, partial messages, host
/// permission prompts answered over stdio (`control_request` /
/// `control_response`), `--session-id` for a new exact session id,
/// `--resume` for an existing one, optional `--model` and `--agent`.
struct ClaudeLaunchSpec: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case new
        case resume
    }

    let nativeSessionID: String
    let mode: Mode
    let cwd: String?
    let model: String?
    let agent: String?

    var arguments: [String] {
        var arguments = [
            "--print",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-prompts", "host",
            "--permission-prompt-tool", "stdio"
        ]
        switch mode {
        case .new: arguments += ["--session-id", nativeSessionID]
        case .resume: arguments += ["--resume", nativeSessionID]
        }
        if let model, !model.isEmpty { arguments += ["--model", model] }
        if let agent, !agent.isEmpty { arguments += ["--agent", agent] }
        return arguments
    }
}

/// One long-lived Claude Code process per managed session; turns are
/// written to stdin as stream-json user messages. Never parses terminal
/// text and never forwards stderr.
actor ClaudeCodeStreamingClient {
    private struct Run {
        let spec: ClaudeLaunchSpec
        let process: Process
        let stdin: FileHandle
        let stdout: Pipe
        let stderr: Pipe
        var stdoutBuffer = Data()
        var activeTurnID: String?
        var stdoutTask: Task<Void, Never>?
        var stderrTask: Task<Void, Never>?
    }

    static let maximumLineBytes = 2 * 1_024 * 1_024

    private let executableURL: URL
    private var runs: [String: Run] = [:]
    private let stream: AsyncStream<ClaudeCodeStreamEvent>
    private let continuation: AsyncStream<ClaudeCodeStreamEvent>.Continuation

    init(executableURL: URL? = nil) throws {
        guard let executableURL = executableURL ?? Self.resolveExecutable() else {
            throw ClaudeCodeStreamingError.executableNotFound
        }
        self.executableURL = executableURL
        var continuation: AsyncStream<ClaudeCodeStreamEvent>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    nonisolated var executablePath: String { executableURL.path }

    func events() -> AsyncStream<ClaudeCodeStreamEvent> {
        stream
    }

    func isRunning(_ nativeSessionID: String) -> Bool {
        runs[nativeSessionID] != nil
    }

    func activeTurn(_ nativeSessionID: String) -> String? {
        runs[nativeSessionID]?.activeTurnID
    }

    /// Writes a user turn, launching (or relaunching with `--resume`) the
    /// session process when needed.
    func submit(prompt: String, spec: ClaudeLaunchSpec) throws -> AgentManagedTurnDescriptor {
        if runs[spec.nativeSessionID] == nil {
            try launch(spec)
        }
        guard var run = runs[spec.nativeSessionID] else { throw ClaudeCodeStreamingError.launchFailed }
        guard run.activeTurnID == nil else { throw ClaudeCodeStreamingError.turnAlreadyRunning }
        let turnID = UUID().uuidString.lowercased()
        let message = CodexJSONValue.object([
            "type": .string("user"),
            "message": .object([
                "role": .string("user"),
                "content": .string(prompt)
            ]),
            "parent_tool_use_id": .null
        ])
        do {
            try write(message, to: run.stdin)
        } catch {
            stopRun(spec.nativeSessionID)
            throw ClaudeCodeStreamingError.launchFailed
        }
        run.activeTurnID = turnID
        runs[spec.nativeSessionID] = run
        return AgentManagedTurnDescriptor(nativeSessionID: spec.nativeSessionID, turnID: turnID)
    }

    func interrupt(nativeSessionID: String) throws {
        guard let run = runs[nativeSessionID] else { throw ClaudeCodeStreamingError.sessionNotRunning }
        try write(.object([
            "type": .string("control_request"),
            "request_id": .string("interrupt-\(UUID().uuidString.lowercased())"),
            "request": .object(["subtype": .string("interrupt")])
        ]), to: run.stdin)
    }

    /// Answers one exact `can_use_tool` control request.
    func respondToPermission(
        nativeSessionID: String,
        requestID: String,
        allow: Bool,
        input: CodexJSONValue
    ) throws {
        guard let run = runs[nativeSessionID] else { throw ClaudeCodeStreamingError.sessionNotRunning }
        let decision: CodexJSONValue = allow
            ? .object(["behavior": .string("allow"), "updatedInput": input])
            : .object(["behavior": .string("deny"), "message": .string("Denied in DynamicIsland")])
        try write(.object([
            "type": .string("control_response"),
            "response": .object([
                "subtype": .string("success"),
                "request_id": .string(requestID),
                "response": decision
            ])
        ]), to: run.stdin)
    }

    func terminate(nativeSessionID: String) {
        stopRun(nativeSessionID)
    }

    func stop() {
        for nativeSessionID in Array(runs.keys) {
            stopRun(nativeSessionID)
        }
    }

    // MARK: Process

    private func launch(_ spec: ClaudeLaunchSpec) throws {
        let process = Process()
        process.executableURL = executableURL
        if let cwd = spec.cwd, !cwd.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }
        process.arguments = spec.arguments
        process.environment = Self.environment()

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        var run = Run(
            spec: spec,
            process: process,
            stdin: stdin.fileHandleForWriting,
            stdout: stdout,
            stderr: stderr
        )
        installReaders(stdout: stdout, stderr: stderr, nativeSessionID: spec.nativeSessionID, run: &run)
        runs[spec.nativeSessionID] = run
        do {
            try process.run()
        } catch {
            stopRun(spec.nativeSessionID)
            throw ClaudeCodeStreamingError.launchFailed
        }
    }

    private func write(_ value: CodexJSONValue, to handle: FileHandle) throws {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private func installReaders(
        stdout: Pipe,
        stderr: Pipe,
        nativeSessionID: String,
        run: inout Run
    ) {
        let stdoutStream = AsyncStream<Data>(bufferingPolicy: .unbounded) { continuation in
            stdout.fileHandleForReading.readabilityHandler = { @Sendable handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
        run.stdoutTask = Task { [weak self] in
            for await data in stdoutStream {
                await self?.consumeStdout(data, nativeSessionID: nativeSessionID)
            }
            await self?.readerClosed(nativeSessionID: nativeSessionID)
        }

        // Stderr is drained and discarded: provider diagnostics are never
        // presentation data.
        let stderrStream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(4)) { continuation in
            stderr.fileHandleForReading.readabilityHandler = { @Sendable handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
        run.stderrTask = Task {
            for await _ in stderrStream {}
        }
    }

    private func consumeStdout(_ data: Data, nativeSessionID: String) {
        guard var run = runs[nativeSessionID] else { return }
        run.stdoutBuffer.append(data)
        guard run.stdoutBuffer.count <= Self.maximumLineBytes else {
            failTurn(nativeSessionID, run: run)
            return
        }
        while let newline = run.stdoutBuffer.firstIndex(of: 0x0A) {
            let line = Data(run.stdoutBuffer[..<newline])
            run.stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard let message = try? JSONDecoder().decode(CodexJSONValue.self, from: line) else {
                // Non-JSON lines are ignored rather than trusted.
                continue
            }
            let turnID = run.activeTurnID ?? "idle"
            if message["type"]?.stringValue == "result" {
                run.activeTurnID = nil
            }
            continuation.yield(.message(ClaudeCodeStreamEnvelope(
                nativeSessionID: nativeSessionID,
                turnID: turnID,
                message: message
            )))
        }
        runs[nativeSessionID] = run
    }

    private func failTurn(_ nativeSessionID: String, run: Run) {
        if let turnID = run.activeTurnID {
            continuation.yield(.transportFailed(nativeSessionID: nativeSessionID, turnID: turnID))
        } else {
            continuation.yield(.sessionExited(nativeSessionID: nativeSessionID))
        }
        stopRun(nativeSessionID)
    }

    private func readerClosed(nativeSessionID: String) {
        guard let run = runs[nativeSessionID] else { return }
        failTurn(nativeSessionID, run: run)
    }

    private func stopRun(_ nativeSessionID: String) {
        guard let run = runs.removeValue(forKey: nativeSessionID) else { return }
        run.stdoutTask?.cancel()
        run.stderrTask?.cancel()
        run.stdout.fileHandleForReading.readabilityHandler = nil
        run.stderr.fileHandleForReading.readabilityHandler = nil
        try? run.stdin.close()
        if run.process.isRunning { run.process.terminate() }
    }

    // MARK: Environment

    /// GUI apps get a minimal PATH; Claude Code hooks and tools expect the
    /// user's usual locations.
    nonisolated static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let current = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var merged: [String] = []
        for path in current + extra where !merged.contains(path) {
            merged.append(path)
        }
        environment["PATH"] = merged.joined(separator: ":")
        return environment
    }

    nonisolated static func resolveExecutable() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
