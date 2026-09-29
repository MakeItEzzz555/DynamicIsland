import AppKit
import Foundation

enum TerminalSessionState: Equatable, Sendable {
    case idle
    case running(command: String)
    case finished(command: String, exitCode: Int32)
    case failed(command: String?, message: String)
}

enum TerminalSessionError: LocalizedError, Equatable {
    case emptyCommand
    case invalidShell(String)
    case invalidWorkingDirectory(String)
    case alreadyRunning
    case launchFailed(String)
    case unsupportedAction(IslandCapabilityAction)

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            "Enter a command before starting a terminal task."
        case .invalidShell(let shell):
            "Configured shell does not exist or is not executable: \(shell)"
        case .invalidWorkingDirectory(let path):
            "Working directory does not exist or is not a directory: \(path)"
        case .alreadyRunning:
            "A terminal task is already running."
        case .launchFailed(let message):
            "Terminal task could not start: \(message)"
        case .unsupportedAction(let action):
            "Terminal does not support \(action.rawValue) without additional context."
        }
    }
}

protocol TerminalProcessHandle: AnyObject {
    var isRunning: Bool { get }
    func terminate()
}

protocol TerminalProcessRunning {
    func start(
        command: String,
        shellPath: String,
        workingDirectory: URL?,
        onOutput: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> TerminalProcessHandle
}

private final class FoundationTerminalProcessHandle: TerminalProcessHandle {
    private let process: Process
    private let outputPipe: Pipe

    init(process: Process, outputPipe: Pipe) {
        self.process = process
        self.outputPipe = outputPipe
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    deinit {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }
}

struct FoundationTerminalProcessRunner: TerminalProcessRunning {
    func start(
        command: String,
        shellPath: String,
        workingDirectory: URL?,
        onOutput: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> TerminalProcessHandle {
        let shellURL = URL(fileURLWithPath: shellPath)
        guard FileManager.default.isExecutableFile(atPath: shellURL.path) else {
            throw TerminalSessionError.invalidShell(shellPath)
        }

        if let workingDirectory {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: workingDirectory.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw TerminalSessionError.invalidWorkingDirectory(workingDirectory.path)
            }
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = shellURL
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            onOutput(output)
        }

        process.terminationHandler = { process in
            pipe.fileHandleForReading.readabilityHandler = nil
            let trailing = pipe.fileHandleForReading.readDataToEndOfFile()
            if !trailing.isEmpty, let output = String(data: trailing, encoding: .utf8), !output.isEmpty {
                onOutput(output)
            }
            onExit(process.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw TerminalSessionError.launchFailed(error.localizedDescription)
        }

        return FoundationTerminalProcessHandle(process: process, outputPipe: pipe)
    }
}

@MainActor
final class TerminalSessionController: ObservableObject, IslandCapabilityAdapter {
    static let activityID = "terminalTask"
    static let defaultShell = "/bin/zsh"

    let capabilityID: IslandCapabilityID = .terminal

    @Published private(set) var state: TerminalSessionState = .idle
    @Published private(set) var output = ""
    @Published private(set) var commandHistory: [String] = []
    @Published var shellPath: String
    @Published var workingDirectoryPath: String
    @Published var persistCommandHistory = false

    private let runner: TerminalProcessRunning
    private let liveActivities: LiveActivityStore
    private let capabilities: IslandCapabilityRegistry
    private let now: () -> Date
    private var processHandle: TerminalProcessHandle?
    private var completionDismissWorkItem: DispatchWorkItem?
    private var isEnabled = true
    private var lastError: String?

    init(
        liveActivities: LiveActivityStore,
        capabilities: IslandCapabilityRegistry,
        runner: TerminalProcessRunning = FoundationTerminalProcessRunner(),
        shellPath: String = TerminalSessionController.defaultShell,
        workingDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        now: @escaping () -> Date = Date.init
    ) {
        self.liveActivities = liveActivities
        self.capabilities = capabilities
        self.runner = runner
        self.shellPath = shellPath
        self.workingDirectoryPath = workingDirectoryPath
        self.now = now
        publishState()
    }

    var snapshot: IslandCapabilitySnapshot {
        IslandCapabilitySnapshot(
            id: .terminal,
            isEnabled: isEnabled,
            permission: .notRequired,
            availability: .available,
            health: lastError.map { .degraded(message: $0) } ?? .healthy,
            supportedActions: [.start, .stop, .test, .openSettings, .configureShortcut],
            isActive: isRunning,
            statusText: statusText
        )
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var statusText: String {
        switch state {
        case .idle: "Ready"
        case .running(let command): command
        case .finished(_, let code): "Exited \(code)"
        case .failed(_, let message): message
        }
    }

    func run(command rawCommand: String) throws {
        guard isEnabled else { return }
        guard !isRunning else { throw TerminalSessionError.alreadyRunning }

        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { throw TerminalSessionError.emptyCommand }

        let workingDirectory: URL?
        let trimmedDirectory = workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDirectory.isEmpty {
            workingDirectory = nil
        } else {
            workingDirectory = URL(fileURLWithPath: NSString(string: trimmedDirectory).expandingTildeInPath)
        }

        output = ""
        lastError = nil
        completionDismissWorkItem?.cancel()

        do {
            let handle = try runner.start(
                command: command,
                shellPath: NSString(string: shellPath).expandingTildeInPath,
                workingDirectory: workingDirectory,
                onOutput: { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        self?.appendOutput(chunk)
                    }
                },
                onExit: { [weak self] exitCode in
                    Task { @MainActor [weak self] in
                        self?.handleExit(command: command, exitCode: exitCode)
                    }
                }
            )
            processHandle = handle
            commandHistory.append(command)
            state = .running(command: command)
            publishActivity(
                title: terminalTitle(for: command),
                subtitle: "Running",
                isActive: true,
                completionEvidence: nil
            )
            publishState()
        } catch {
            state = .failed(command: command, message: error.localizedDescription)
            lastError = error.localizedDescription
            publishState(failed: true)
            throw error
        }
    }

    func terminate() {
        guard isRunning else { return }
        processHandle?.terminate()
    }

    func resetOutput() {
        output = ""
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            terminate()
        }
        publishState()
    }

    func openExternalTerminal(bundleIdentifier: String = "com.apple.Terminal") -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }

    func refresh() async {
        publishState()
    }

    func perform(_ action: IslandCapabilityAction) async throws {
        switch action {
        case .stop:
            terminate()
        case .test:
            try run(command: "printf 'DynamicIsland terminal OK'")
        case .openSettings:
            _ = openExternalTerminal()
        case .start, .configureShortcut:
            throw TerminalSessionError.unsupportedAction(action)
        }
    }

    private func appendOutput(_ chunk: String) {
        output.append(chunk)
    }

    private func handleExit(command: String, exitCode: Int32) {
        processHandle = nil
        state = .finished(command: command, exitCode: exitCode)
        lastError = exitCode == 0 ? nil : "Command exited with status \(exitCode)"

        publishActivity(
            title: terminalTitle(for: command),
            subtitle: exitCode == 0 ? "Complete" : "Exited \(exitCode)",
            isActive: false,
            completionEvidence: "process exited with status \(exitCode)"
        )
        publishState()

        completionDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.liveActivities.remove(id: Self.activityID)
            }
        }
        completionDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func publishActivity(
        title: String,
        subtitle: String,
        isActive: Bool,
        completionEvidence: String?
    ) {
        liveActivities.update(
            DynamicIslandLiveActivity(
                id: Self.activityID,
                kind: .terminalTask,
                title: title,
                subtitle: subtitle,
                symbolName: "terminal.fill",
                priority: 88,
                isActive: isActive,
                progress: nil,
                updatedAt: now(),
                lifecycle: LiveActivityLifecycleMetadata(
                    authority: .process,
                    startEvidence: "Foundation Process successfully launched",
                    progressEvidence: "stdout/stderr stream and Process.isRunning",
                    completionEvidence: completionEvidence,
                    dismissPolicy: isActive ? .untilSourceEnds : .automatic,
                    supportsCancellation: true
                )
            )
        )
    }

    private func publishState(failed: Bool = false) {
        var value = snapshot
        if failed, let lastError {
            value.health = .failed(message: lastError)
        }
        capabilities.update(value)
    }

    private func terminalTitle(for command: String) -> String {
        let first = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        return first?.isEmpty == false ? first! : "Terminal"
    }
}
