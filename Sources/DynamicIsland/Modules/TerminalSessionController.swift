import AppKit
import Foundation
import SwiftTerm

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

@MainActor
protocol TerminalProcessHandle: AnyObject {
    var isRunning: Bool { get }
    func terminate()
    func send(data: [UInt8])
    var processID: Int32? { get }
}

extension TerminalProcessHandle {
    var processID: Int32? { nil }
    func send(data: [UInt8]) {}
}

@MainActor
protocol TerminalProcessRunning {
    func start(
        command: String,
        shellPath: String,
        workingDirectory: URL?,
        onOutput: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> TerminalProcessHandle
}

@MainActor
final class TerminalSessionController: ObservableObject, IslandCapabilityAdapter {
    static let activityID = "terminalTask"
    static let defaultShell = "/bin/zsh"

    let capabilityID: IslandCapabilityID = .terminal

    @Published private(set) var state: TerminalSessionState = .idle
    /// The emulator is the only scrollback owner. Text is materialized only for explicit export/tests.
    var output: String { String(decoding: terminalView.getTerminal().getBufferAsData(), as: UTF8.self) }
    @Published private(set) var terminalView: InteractiveTerminalView
    var processID: Int32? { processHandle?.processID }
    static let maximumScrollbackLines = 2_000
    @Published private(set) var commandHistory: [String] = []
    @Published var shellPath: String
    @Published var workingDirectoryPath: String
    /// Opt-in, off by default. History is kept in memory for this app
    /// session only and is never written to disk.
    @Published var persistCommandHistory = false {
        didSet {
            if !persistCommandHistory {
                commandHistory = []
            }
        }
    }

    private var runner: TerminalProcessRunning
    private let usesNativePTY: Bool
    private var launchedBefore = false
    private var launchGeneration: UInt64 = 0
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
        runner: TerminalProcessRunning? = nil,
        shellPath: String = TerminalSessionController.configuredUserShell,
        workingDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        now: @escaping () -> Date = Date.init
    ) {
        self.liveActivities = liveActivities
        self.capabilities = capabilities
        let view = InteractiveTerminalView()
        self.terminalView = view
        self.runner = runner ?? PTYTerminalProcessRunner(view: view)
        usesNativePTY = runner == nil
        self.shellPath = shellPath
        self.workingDirectoryPath = workingDirectoryPath
        self.now = now
        view.onSend = { [weak self] data in self?.sendInput(data) }
        publishState()
    }

    static var configuredUserShell: String {
        let shell = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) }
        return shell.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? defaultShell
    }

    /// Starts once. Later selections never alter the shell-owned cwd.
    func startShell(initialDirectory: String? = nil) throws {
        guard !isRunning, isEnabled else { return }
        if let initialDirectory, !initialDirectory.isEmpty { workingDirectoryPath = initialDirectory }
        try launchShell(command: "")
    }

    func sendInput(_ data: [UInt8]) { processHandle?.send(data: data) }
    func interrupt() { sendInput([3]) }

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
        case .running(let shell): "Interactive \(shell) shell"
        case .finished(_, let code): "Exited \(code)"
        case .failed(_, let message): message
        }
    }

    /// Explicit user input only; every command goes to the same interactive PTY.
    func run(command rawCommand: String) throws {
        guard isEnabled else { return }
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { throw TerminalSessionError.emptyCommand }
        if !isRunning { try launchShell(command: command) }
        processHandle?.send(data: Array((command + "\r").utf8))
        if persistCommandHistory {
            commandHistory.append(command)
            if commandHistory.count > 128 { commandHistory.removeFirst(commandHistory.count - 128) }
        }
    }

    private func launchShell(command: String) throws {
        let shell = NSString(string: shellPath).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: shell) else { throw TerminalSessionError.invalidShell(shell) }
        let directory = NSString(string: workingDirectoryPath).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TerminalSessionError.invalidWorkingDirectory(directory)
        }
        lastError = nil
        completionDismissWorkItem?.cancel()
        launchGeneration &+= 1
        let generation = launchGeneration
        do {
            if usesNativePTY, launchedBefore {
                let view = InteractiveTerminalView()
                view.onSend = { [weak self] data in self?.sendInput(data) }
                terminalView = view
                runner = PTYTerminalProcessRunner(view: view)
            }
            let handle = try runner.start(
                command: command, shellPath: shell, workingDirectory: URL(fileURLWithPath: directory),
                onOutput: { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        guard let self, self.launchGeneration == generation, self.isRunning else { return }
                        self.terminalView.feed(text: chunk)
                    }
                },
                onExit: { [weak self] exitCode in
                    Task { @MainActor [weak self] in
                        guard let self, self.launchGeneration == generation, self.isRunning else { return }
                        self.handleExit(command: "Shell", exitCode: exitCode)
                    }
                }
            )
            processHandle = handle
            launchedBefore = true
            state = .running(command: URL(fileURLWithPath: shell).lastPathComponent)
            // An idle interactive shell is not an ongoing command or agent task.
            liveActivities.remove(id: Self.activityID)
            publishState()
        } catch {
            state = .failed(command: nil, message: error.localizedDescription)
            lastError = error.localizedDescription
            publishState(failed: true)
            throw error
        }
    }

    func terminate() {
        guard isRunning else { return }
        launchGeneration &+= 1
        processHandle?.terminate()
        processHandle = nil
        state = .idle
        liveActivities.remove(id: Self.activityID)
        publishState()
    }

    func clearCommandHistory() {
        commandHistory = []
    }

    func resetOutput() {
        terminalView.getTerminal().resetToInitialState()
        terminalView.needsDisplay = true
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
            Self.makeActivity(
                title: title,
                subtitle: subtitle,
                isActive: isActive,
                completionEvidence: completionEvidence,
                updatedAt: now()
            )
        )
    }

    /// Production activity shape; also used by Settings previews.
    static func makeActivity(
        title: String,
        subtitle: String,
        isActive: Bool,
        completionEvidence: String?,
        updatedAt: Date
    ) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: activityID,
            kind: .terminalTask,
            title: title,
            subtitle: subtitle,
            symbolName: "terminal.fill",
            priority: 88,
            isActive: isActive,
            progress: nil,
            updatedAt: updatedAt,
            lifecycle: LiveActivityLifecycleMetadata(
                authority: .process,
                startEvidence: "Interactive PTY shell successfully launched",
                progressEvidence: "PTY shell process lifecycle",
                completionEvidence: completionEvidence,
                dismissPolicy: isActive ? .untilSourceEnds : .automatic,
                supportsCancellation: true
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
