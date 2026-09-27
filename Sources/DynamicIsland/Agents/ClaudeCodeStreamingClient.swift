import Foundation

enum ClaudeCodeStreamingError: Error, Equatable, Sendable {
    case executableNotFound
    case launchFailed
    case turnAlreadyRunning
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
    case transportFailed(nativeSessionID: String, turnID: String)
}

actor ClaudeCodeStreamingClient {
    private struct Run {
        let turnID: String
        let process: Process
        let stdout: Pipe
        let stderr: Pipe
        var stdoutBuffer = Data()
        var stderrBytes = 0
        var sawTerminalMessage = false
        var stdoutTask: Task<Void, Never>?
        var stderrTask: Task<Void, Never>?
    }

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

    func events() -> AsyncStream<ClaudeCodeStreamEvent> {
        stream
    }

    func submit(prompt: String, nativeSessionID: String) throws -> AgentManagedTurnDescriptor {
        guard runs[nativeSessionID] == nil else {
            throw ClaudeCodeStreamingError.turnAlreadyRunning
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--print",
            "--resume", nativeSessionID,
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--permission-prompts", "none"
        ]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let turnID = UUID().uuidString.lowercased()
        var run = Run(
            turnID: turnID,
            process: process,
            stdout: stdout,
            stderr: stderr
        )
        installReaders(
            stdout: stdout,
            stderr: stderr,
            nativeSessionID: nativeSessionID,
            run: &run
        )
        runs[nativeSessionID] = run

        do {
            try process.run()
            let input = CodexJSONValue.object([
                "type": .string("user"),
                "message": .object([
                    "role": .string("user"),
                    "content": .string(prompt)
                ]),
                "parent_tool_use_id": .null
            ])
            var data = try JSONEncoder().encode(input)
            data.append(0x0A)
            try stdin.fileHandleForWriting.write(contentsOf: data)
            try stdin.fileHandleForWriting.close()
        } catch {
            stopRun(nativeSessionID)
            throw ClaudeCodeStreamingError.launchFailed
        }

        return AgentManagedTurnDescriptor(nativeSessionID: nativeSessionID, turnID: turnID)
    }

    func stop() {
        for nativeSessionID in Array(runs.keys) {
            stopRun(nativeSessionID)
        }
    }

    private func installReaders(
        stdout: Pipe,
        stderr: Pipe,
        nativeSessionID: String,
        run: inout Run
    ) {
        let stdoutStream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(32)) { continuation in
            stdout.fileHandleForReading.readabilityHandler = { handle in
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

        let stderrStream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(8)) { continuation in
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
        run.stderrTask = Task { [weak self] in
            for await data in stderrStream {
                await self?.consumeStderr(data, nativeSessionID: nativeSessionID)
            }
        }
    }

    private func consumeStdout(_ data: Data, nativeSessionID: String) {
        guard var run = runs[nativeSessionID] else { return }
        run.stdoutBuffer.append(data)
        while let newline = run.stdoutBuffer.firstIndex(of: 0x0A) {
            let line = Data(run.stdoutBuffer[..<newline])
            run.stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard let message = try? JSONDecoder().decode(CodexJSONValue.self, from: line) else {
                continuation.yield(.transportFailed(
                    nativeSessionID: nativeSessionID,
                    turnID: run.turnID
                ))
                stopRun(nativeSessionID)
                return
            }
            if message["type"]?.stringValue == "result" {
                run.sawTerminalMessage = true
            }
            continuation.yield(.message(ClaudeCodeStreamEnvelope(
                nativeSessionID: nativeSessionID,
                turnID: run.turnID,
                message: message
            )))
        }
        runs[nativeSessionID] = run
    }

    private func consumeStderr(_ data: Data, nativeSessionID: String) {
        guard var run = runs[nativeSessionID] else { return }
        // Count and discard stderr. Provider diagnostics are never presentation data.
        run.stderrBytes = min(run.stderrBytes + data.count, 8_192)
        runs[nativeSessionID] = run
    }

    private func readerClosed(nativeSessionID: String) {
        if let run = runs[nativeSessionID], !run.sawTerminalMessage {
            continuation.yield(.transportFailed(
                nativeSessionID: nativeSessionID,
                turnID: run.turnID
            ))
        }
        stopRun(nativeSessionID)
    }

    private func stopRun(_ nativeSessionID: String) {
        guard let run = runs.removeValue(forKey: nativeSessionID) else { return }
        run.stdoutTask?.cancel()
        run.stderrTask?.cancel()
        run.stdout.fileHandleForReading.readabilityHandler = nil
        run.stderr.fileHandleForReading.readabilityHandler = nil
        if run.process.isRunning { run.process.terminate() }
    }

    private nonisolated static func resolveExecutable() -> URL? {
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
