import AppKit
import Darwin
import SwiftTerm

/// One retained native emulator. Its lifetime belongs to the terminal controller,
/// never to a SwiftUI presentation. SwiftTerm alone owns bounded scrollback.
@MainActor
final class InteractiveTerminalView: LocalProcessTerminalView {
    var onExit: (@Sendable (Int32) -> Void)?
    var onSend: (([UInt8]) -> Void)?
    private(set) var receivedByteCount = 0
    private(set) var lastInputByte: UInt8?
    /// Set by a click or typed input; cleared when focus leaves. Automatic
    /// focus (showing the Terminal page) never holds the island open.
    var userEngaged = false
    private var safeDelegate: InteractiveTerminalDelegate?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 640, height: 320),
                   font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                   options: TerminalOptions(cursorStyle: .steadyBlock,
                                            scrollback: TerminalSessionController.maximumScrollbackLines))
        nativeBackgroundColor = NSColor(calibratedWhite: 0.025, alpha: 1)
        nativeForegroundColor = NSColor(calibratedWhite: 0.9, alpha: 1)
        let delegate = InteractiveTerminalDelegate(view: self)
        safeDelegate = delegate
        terminalDelegate = delegate
        setAccessibilityElement(true)
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Interactive shell terminal")
        setAccessibilityHelp("Type directly into the shell. Control-C interrupts; Command-C copies selection and Command-V pastes.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func accessibilityValue() -> Any? {
        // Read only the displayed viewport on demand, never duplicate retained
        // scrollback or publish provider/SwiftUI state for terminal output.
        let terminal = getTerminal()
        return (0..<terminal.rows).compactMap { row in
            terminal.getLine(row: row)?.translateToString(trimRight: true,
                characterProvider: { terminal.getCharacter(for: $0) })
        }.joined(separator: "\n")
    }

    override func mouseDown(with event: NSEvent) {
        userEngaged = true
        super.mouseDown(with: event)
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        userEngaged = true
        lastInputByte = data.last
        if let onSend { onSend(Array(data)) } else { super.send(source: source, data: data) }
    }
    override func dataReceived(slice: ArraySlice<UInt8>) {
        receivedByteCount += slice.count
        super.dataReceived(slice: slice)
    }
    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        // SwiftTerm reports waitpid's encoded status, not the shell exit value.
        let status = exitCode ?? 0
        let result = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        onExit?(result)
    }

}

/// The sole production runner. The compatibility protocol is also used by
/// deterministic presentation fixtures; no command-runner process remains.
@MainActor
final class PTYTerminalProcessRunner: TerminalProcessRunning {
    private let view: InteractiveTerminalView
    init(view: InteractiveTerminalView) { self.view = view }

    func start(command: String, shellPath: String, workingDirectory: URL?,
               onOutput: @escaping @Sendable (String) -> Void,
               onExit: @escaping @Sendable (Int32) -> Void) throws -> TerminalProcessHandle {
        let configuration = try TerminalShellConfiguration(shell: shellPath)
        view.onExit = onExit
        view.startProcess(executable: shellPath, args: configuration.arguments,
                          environment: configuration.environment,
                          currentDirectory: workingDirectory?.path)
        guard view.process.running, view.process.shellPid > 0 else {
            throw TerminalSessionError.launchFailed("Unable to allocate the shell PTY")
        }
        return PTYTerminalProcessHandle(view: view, configuration: configuration)
    }
}

@MainActor
private final class PTYTerminalProcessHandle: TerminalProcessHandle {
    private let view: InteractiveTerminalView
    private let configuration: TerminalShellConfiguration
    private let pid: Int32
    private let lifetime: PTYShellLifetime
    @MainActor init(view: InteractiveTerminalView, configuration: TerminalShellConfiguration) {
        self.view = view
        self.configuration = configuration
        pid = view.process.shellPid
        lifetime = PTYShellLifetime(pid: view.process.shellPid)
    }
    var processID: Int32? { lifetime.closed ? nil : pid }
    var isRunning: Bool { !lifetime.closed }
    func send(data: [UInt8]) {
        if !lifetime.closed { view.process.send(data: data[...]) }
    }
    func terminate() {
        guard !lifetime.closed else { return }
        view.onExit = nil
        // The live process monitor is cancelled before our own reaper takes
        // ownership. Natural exits are already reaped and must not be signalled.
        if view.process.running { view.terminate() }
        lifetime.close()
    }
}

/// Process cleanup contains no AppKit calls and is safe on any release thread.
/// Using isolated deinit here triggers the macOS 15 Swift runtime's task-local
/// back-deployment abort under repeated SwiftUI/AppKit teardown.
private final class PTYShellLifetime: @unchecked Sendable {
    let pid: Int32
    private(set) var closed = false
    init(pid: Int32) { self.pid = pid }
    func close() {
        guard !closed else { return }
        closed = true
        var status: Int32 = 0
        // A provider or unrelated process can never be targeted after the child
        // has been reaped (and its PID might have been reused).
        guard waitpid(pid, &status, WNOHANG) == 0 else { return }
        kill(-pid, SIGHUP)
        kill(pid, SIGHUP)
        let childPID = pid
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            while waitpid(childPID, &status, 0) == -1 && errno == EINTR {}
        }
    }
    deinit { close() }

}

/// Child-local startup files give a truthful cwd prompt without touching the
/// user's shell configuration. Normal aliases/functions are sourced first.
private final class TerminalShellConfiguration {
    let arguments: [String]
    let environment: [String]
    private let directory: URL
    init(shell: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dynamicisland-shell-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "DynamicIsland"
        env["HISTFILE"] = "/dev/null"
        env.removeValue(forKey: "DYNAMIC_ISLAND_AGENT_PERF")
        let name = URL(fileURLWithPath: shell).lastPathComponent
        switch name {
        case "zsh":
            let original = env["ZDOTDIR"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            env["DI_ORIGINAL_ZDOTDIR"] = original
            env["ZDOTDIR"] = directory.path
            env["DI_TERMINAL_ZDOTDIR"] = directory.path
            try "[[ -r $DI_ORIGINAL_ZDOTDIR/.zshenv ]] && source $DI_ORIGINAL_ZDOTDIR/.zshenv\nZDOTDIR=$DI_TERMINAL_ZDOTDIR\n".write(to: directory.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
            let rc = #"""
            [[ -r $DI_ORIGINAL_ZDOTDIR/.zshrc ]] && source $DI_ORIGINAL_ZDOTDIR/.zshrc
            HISTFILE=/dev/null
            SAVEHIST=0
            HISTSIZE=1000
            PROMPT='%~ %# '
            RPROMPT=''
            function di_terminal_cwd { PROMPT='%~ %# '; RPROMPT=''; printf '\033]7;file://%s%s\007' "$HOST" "$PWD"; }
            precmd_functions+=(di_terminal_cwd)
            """#
            try rc.write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            arguments = ["-i"]
        case "bash":
            let rc = #"""
            [[ -r $HOME/.bashrc ]] && source "$HOME/.bashrc"
            HISTFILE=/dev/null
            HISTFILESIZE=0
            HISTSIZE=1000
            PS1='\w \$ '
            PROMPT_COMMAND='printf "\033]7;file://%s%s\007" "$HOSTNAME" "$PWD"'
            """#
            let file = directory.appendingPathComponent("bashrc")
            try rc.write(to: file, atomically: true, encoding: .utf8)
            arguments = ["--rcfile", file.path, "-i"]
        case "fish":
            arguments = ["--private", "-i", "-C", "function fish_prompt; printf '%s > ' (prompt_pwd); end"]
        default:
            env["PS1"] = "${PWD} $ "
            arguments = ["-i"]
        }
        environment = env.map { "\($0.key)=\($0.value)" }
    }
    deinit { try? FileManager.default.removeItem(at: directory) } // Only our generated startup directory.
}

/// Explicit copy/paste remains in SwiftTerm's native keyboard handlers. Shell
/// output cannot silently query or overwrite the user's system clipboard.
@MainActor
private final class InteractiveTerminalDelegate: @preconcurrency TerminalViewDelegate {
    weak var view: InteractiveTerminalView?
    init(view: InteractiveTerminalView) { self.view = view }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        view?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }
    func setTerminalTitle(source: TerminalView, title: String) { view?.setTerminalTitle(source: source, title: title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { view?.hostCurrentDirectoryUpdate(source: source, directory: directory) }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { view?.send(source: source, data: data) }
    func scrolled(source: TerminalView, position: Double) { view?.scrolled(source: source, position: position) }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) { view?.rangeChanged(source: source, startY: startY, endY: endY) }
    func clipboardRead(source: TerminalView) -> Data? { nil }
    func clipboardCopy(source: TerminalView, content: Data) {}
}
