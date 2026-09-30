import Foundation

/// Claude account usage windows, as percentages used (0...100).
struct ClaudeUsageWindows: Equatable, Sendable {
    var fiveHourUsedPercent: Double?
    var weekUsedPercent: Double?
    var fiveHourResetsAt: Date?
    var weekResetsAt: Date?

    var isEmpty: Bool { fiveHourUsedPercent == nil && weekUsedPercent == nil }

    /// Samples in the shared AgentUsage vocabulary. Scopes match the Codex
    /// window scopes so the same indicator logic applies; `limit` is 100.
    func usage(source: String, observedAt: Date) -> AgentUsage {
        var samples: [AgentUsageKey: AgentUsageSample] = [:]
        if let five = fiveHourUsedPercent {
            samples[AgentUsageKey(metric: .quotaUsed, scope: "5h")] = AgentUsageSample(
                value: min(max(five, 0), 100), limit: 100, unit: .fraction,
                scope: "5h", source: source, observedAt: observedAt
            )
        }
        if let week = weekUsedPercent {
            samples[AgentUsageKey(metric: .quotaUsed, scope: "weekly")] = AgentUsageSample(
                value: min(max(week, 0), 100), limit: 100, unit: .fraction,
                scope: "weekly", source: source, observedAt: observedAt
            )
        }
        return AgentUsage(scopedSamples: samples)
    }
}

enum ClaudeUsageSource {
    /// `rate_limit_event.rate_limit_info.unifiedWindows` in stream-json.
    static let rateLimitEvent = "claude-rate-limit-event"
    /// Built-in `/usage` command output (local, no model request).
    static let usageCommand = "claude-usage-command"
}

/// Parses `rate_limit_info` from a stream-json `rate_limit_event`.
/// `utilization` is a 0...1 used fraction per window.
enum ClaudeRateLimitParser {
    static func parse(_ info: CodexJSONValue?) -> ClaudeUsageWindows? {
        guard let windows = info?["unifiedWindows"] else { return nil }
        func window(_ key: String) -> (Double?, Date?) {
            guard let entry = windows[key],
                  let utilization = entry["utilization"]?.doubleValue,
                  utilization.isFinite, utilization >= 0, utilization <= 1.0001 else { return (nil, nil) }
            let resets = entry["resetsAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) }
            return (utilization * 100, resets)
        }
        let five = window("five_hour")
        let week = window("seven_day")
        let result = ClaudeUsageWindows(
            fiveHourUsedPercent: five.0,
            weekUsedPercent: week.0,
            fiveHourResetsAt: five.1,
            weekResetsAt: week.1
        )
        return result.isEmpty ? nil : result
    }
}

/// Parses the built-in `/usage` text. Verified against Claude Code 2.1.285:
///   "Current session: 17% used · resets …"
///   "Current week (all models): 16% used · resets …"
/// Anything unrecognized yields nil values (shown as unavailable), never a guess.
enum ClaudeUsageTextParser {
    static func parse(_ text: String) -> ClaudeUsageWindows? {
        var result = ClaudeUsageWindows()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Current session:") {
                result.fiveHourUsedPercent = percentUsed(in: line)
            } else if line.hasPrefix("Current week (all models):") {
                result.weekUsedPercent = percentUsed(in: line)
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func percentUsed(in line: String) -> Double? {
        guard let range = line.range(of: #"(\d{1,3}(?:\.\d+)?)% used"#, options: .regularExpression) else { return nil }
        let number = line[range].replacingOccurrences(of: "% used", with: "")
        guard let value = Double(number), value >= 0, value <= 100 else { return nil }
        return value
    }
}

/// What a `/usage` probe learned. Agents and the default model come from
/// the probe's `system/init` message (the list Claude Code itself exposes).
struct ClaudeUsageProbeResult: Equatable, Sendable {
    let windows: ClaudeUsageWindows?
    let availableAgents: [String]
    let defaultModel: String?
    let cliVersion: String?
}

protocol ClaudeUsageProbing: Sendable {
    func probe() async throws -> ClaudeUsageProbeResult
}

/// Runs the built-in `/usage` command through supported print mode with no
/// session persistence. It is handled locally by Claude Code (no model
/// request, no cost) and never touches credentials.
struct ClaudeUsageCommandProbe: ClaudeUsageProbing {
    let executableURL: URL
    let workingDirectory: URL
    var timeout: TimeInterval = 30

    static func makeDefault() -> ClaudeUsageCommandProbe? {
        guard let executable = ClaudeCodeStreamingClient.resolveExecutable() else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("ClaudeUsageProbe", isDirectory: true)
        return ClaudeUsageCommandProbe(executableURL: executable, workingDirectory: directory)
    }

    static let arguments = [
        "--print",
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--verbose",
        "--permission-prompts", "none",
        "--no-session-persistence"
    ]

    func probe() async throws -> ClaudeUsageProbeResult {
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = Self.arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = ClaudeCodeStreamingClient.environment()
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let input = CodexJSONValue.object([
            "type": .string("user"),
            "message": .object(["role": .string("user"), "content": .string("/usage")]),
            "parent_tool_use_id": .null
        ])
        var line = try JSONEncoder().encode(input)
        line.append(0x0A)
        try stdin.fileHandleForWriting.write(contentsOf: line)
        try stdin.fileHandleForWriting.close()

        let deadline = timeout
        let output: Data = try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask {
                stdout.fileHandleForReading.readDataToEndOfFile()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            if process.isRunning { process.terminate() }
            guard let first else { throw ClaudeCodeStreamingError.launchFailed }
            return first
        }
        return Self.parse(output)
    }

    static func parse(_ output: Data) -> ClaudeUsageProbeResult {
        var windows: ClaudeUsageWindows?
        var agents: [String] = []
        var model: String?
        var version: String?
        for rawLine in output.split(separator: 0x0A) {
            guard let message = try? JSONDecoder().decode(CodexJSONValue.self, from: Data(rawLine)) else { continue }
            switch message["type"]?.stringValue {
            case "system" where message["subtype"]?.stringValue == "init":
                agents = message["agents"]?.arrayValue?.compactMap(\.stringValue) ?? []
                model = message["model"]?.stringValue
                version = message["claude_code_version"]?.stringValue
            case "assistant":
                let text = message["message"]?["content"]?.arrayValue?
                    .compactMap { $0["text"]?.stringValue }
                    .joined(separator: "\n") ?? ""
                if let parsed = ClaudeUsageTextParser.parse(text) { windows = parsed }
            case "rate_limit_event":
                if let parsed = ClaudeRateLimitParser.parse(message["rate_limit_info"]) { windows = parsed }
            default:
                continue
            }
        }
        return ClaudeUsageProbeResult(windows: windows, availableAgents: agents, defaultModel: model, cliVersion: version)
    }
}
