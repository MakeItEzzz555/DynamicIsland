import AppKit
import Darwin
import SwiftTerm
import XCTest
@testable import DynamicIsland

/// Integration: an actual forkpty shell + the production native emulator.
/// Conditions are polled with deadlines; no mocked command processes and no
/// assumed fixed command/animation completion delays.
@MainActor
final class InteractiveTerminalIntegrationTests: XCTestCase {
    private func terminal() -> TerminalSessionController {
        _ = NSApplication.shared
        return TerminalSessionController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry(),
                                         shellPath: "/bin/zsh", workingDirectoryPath: "/tmp")
    }
    private func wait(_ description: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), description)
    }
    private func hasLine(_ line: String, in terminal: TerminalSessionController) -> Bool {
        terminal.output.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == line }
    }
    private func command(_ value: String, marker: String, terminal: TerminalSessionController) async throws {
        try terminal.run(command: value + "; printf '\\n" + marker + "\\n'")
        try await wait(marker) { self.hasLine(marker, in: terminal) }
    }

    func testOnePersistentShellPreservesCWDEnvironmentAndRealPrompt() async throws {
        let terminal = terminal()
        defer { terminal.terminate() }
        try terminal.startShell()
        let pid = try XCTUnwrap(terminal.processID)
        try await command("pwd", marker: "DI_READY_1", terminal: terminal)
        XCTAssertTrue(hasLine("/private/tmp", in: terminal) || hasLine("/tmp", in: terminal))
        try await command("cd /; export DYNAMIC_TEST=abc", marker: "DI_READY_2", terminal: terminal)
        try await command("printf 'ENV=%s\\n' \"$DYNAMIC_TEST\"; pwd", marker: "DI_READY_3", terminal: terminal)
        XCTAssertTrue(hasLine("ENV=abc", in: terminal))
        XCTAssertTrue(hasLine("/", in: terminal))
        try await wait("Prompt tracks actual / cwd") { terminal.output.contains("/ %") || terminal.output.contains("/ #") }
        XCTAssertEqual(terminal.processID, pid)
        try terminal.startShell(initialDirectory: NSHomeDirectory())
        XCTAssertEqual(terminal.processID, pid, "Presentation changes cannot start or cd a live shell")
        try await command("pwd", marker: "DI_READY_4", terminal: terminal)
        XCTAssertTrue(hasLine("/", in: terminal))
    }

    func testNativeReturnHistoryTabControlKeysAndInterruptReachPTY() async throws {
        let terminal = terminal()
        defer { terminal.terminate() }
        try terminal.startShell()
        try await command("printf 'DI_HISTORY\\n'", marker: "DI_HISTORY_READY", terminal: terminal)
        let view = terminal.terminalView
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                  timestamp: 0, windowNumber: 0, context: nil,
                                                  characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        view.insertText("printf 'DI_NATIVE_RETURN\\n'", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.keyDown(with: event)
        try await wait("Native Return executes in PTY") { self.hasLine("DI_NATIVE_RETURN", in: terminal) }
        XCTAssertEqual(view.lastInputByte, 13)
        terminal.sendInput(Array("\u{001B}[A".utf8))
        try await wait("Up recalls previous command") {
            terminal.output.components(separatedBy: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?.contains("DI_NATIVE_RETURN") == true
        }
        terminal.sendInput([21]) // Ctrl-U: clear recalled input, not the transcript.
        terminal.sendInput(Array("echo /tm\t".utf8))
        try await wait("Native shell Tab completes /tmp") { terminal.output.contains("echo /tmp/") }
        terminal.sendInput([21])
        terminal.sendInput(Array("sleep 30\r".utf8))
        let fd = view.process.childfd
        let shellPID = try XCTUnwrap(terminal.processID)
        try await wait("Foreground job starts") { tcgetpgrp(fd) > 0 && tcgetpgrp(fd) != shellPID }
        terminal.interrupt()
        try await wait("Ctrl-C returns control to shell") { tcgetpgrp(fd) == shellPID }
        XCTAssertEqual(terminal.processID, shellPID)
        try await command("printf 'DI_AFTER_INTERRUPT\\n'", marker: "DI_INTERRUPT_READY", terminal: terminal)
        XCTAssertTrue(hasLine("DI_AFTER_INTERRUPT", in: terminal))
        terminal.sendInput([12]) // Ctrl-L redraw/clear visible shell, remains alive.
        try await command("printf 'DI_AFTER_CLEAR\\n'", marker: "DI_CLEAR_READY", terminal: terminal)
        XCTAssertTrue(hasLine("DI_AFTER_CLEAR", in: terminal))
    }

    func testPTYResizeAndANSIEmulation() async throws {
        let terminal = terminal()
        defer { terminal.terminate() }
        try terminal.startShell()
        let view = terminal.terminalView
        view.getTerminal().resize(cols: 72, rows: 18)
        view.sizeChanged(source: view, newCols: 72, newRows: 18)
        var dimensions = winsize()
        XCTAssertEqual(ioctl(view.process.childfd, TIOCGWINSZ, &dimensions), 0)
        XCTAssertEqual(dimensions.ws_col, 72)
        XCTAssertEqual(dimensions.ws_row, 18)
        try await command("printf '\\033[31mRED\\033[0m\\nold\\rNEW\\033[K\\n'", marker: "DI_ANSI_READY", terminal: terminal)
        XCTAssertTrue(hasLine("RED", in: terminal))
        XCTAssertTrue(hasLine("NEW", in: terminal))
        XCTAssertFalse(terminal.output.contains("\u{001B}[31m"), "ANSI is parsed, not rendered as garbage")
        XCTAssertNil(view.terminalDelegate?.clipboardRead(source: view), "Shell output cannot read the system clipboard")
        XCTAssertEqual(view.accessibilityRole(), .textArea)
        XCTAssertTrue((view.accessibilityValue() as? String)?.contains("RED") == true)
    }

    func testBoundedEmulatorScrollbackAndNoOutputPublicationStorm() async throws {
        let terminal = terminal()
        defer { terminal.terminate() }
        var publications = 0
        let observer = terminal.objectWillChange.sink { publications += 1 }
        defer { observer.cancel() }
        try terminal.startShell()
        let initial = publications
        try await command("for i in {1..5000}; do printf 'line-%s\\n' $i; done", marker: "DI_FLOOD_READY", terminal: terminal)
        XCTAssertTrue(hasLine("line-5000", in: terminal))
        XCTAssertFalse(hasLine("line-1", in: terminal))
        XCTAssertGreaterThan(terminal.terminalView.getTerminal().buffer.totalLinesTrimmed, 0)
        XCTAssertLessThanOrEqual(terminal.output.components(separatedBy: "\n").count,
                                 TerminalSessionController.maximumScrollbackLines + terminal.terminalView.getTerminal().rows + 1)
        XCTAssertEqual(publications, initial, "PTY output never republishes Agents SwiftUI state")
    }

    func testFullScreenPagerExitPreservesShell() async throws {
        let terminal = terminal()
        defer { terminal.terminate() }
        try terminal.startShell()
        let pid = terminal.processID
        terminal.sendInput(Array("/usr/bin/less /etc/shells\r".utf8))
        try await wait("less enters alternate screen") { terminal.terminalView.getTerminal().isCurrentBufferAlternate }
        terminal.sendInput(Array("q".utf8))
        try await wait("less exits alternate screen") { !terminal.terminalView.getTerminal().isCurrentBufferAlternate }
        try await command("printf 'DI_PAGER_DONE\\n'", marker: "DI_PAGER_READY", terminal: terminal)
        XCTAssertEqual(terminal.processID, pid)
    }

    func testControllerTeardownIntentionallyClosesAndReapsOwnedPTY() async throws {
        var terminal: TerminalSessionController? = terminal()
        try terminal?.startShell()
        let pid = try XCTUnwrap(terminal?.processID)
        weak var weakController = terminal
        terminal = nil
        try await wait("Controller released") { weakController == nil }
        try await wait("Owned shell reaped") { kill(pid, 0) == -1 && errno == ESRCH }
    }

    func testExplicitRestartCreatesOneFreshProcessWithoutOldExitChangingNewState() async throws {
        let terminal = terminal()
        defer { terminal.terminate() }
        try terminal.startShell()
        let old = terminal.processID
        let oldView = terminal.terminalView
        let retiredHost = TerminalMountView()
        retiredHost.mount(oldView)
        terminal.terminate()
        try terminal.startShell()
        XCTAssertNil(oldView.superview, "Restart detaches even a hidden/retiring host's dead renderer")
        XCTAssertNil(oldView.onSend, "The retired renderer cannot send into the new shell")
        XCTAssertTrue(retiredHost.subviews.isEmpty)
        XCTAssertNotEqual(terminal.processID, old)
        XCTAssertFalse(terminal.terminalView === oldView)
        try await command("printf 'DI_RESTART_OK\\n'", marker: "DI_RESTART_READY", terminal: terminal)
        XCTAssertTrue(terminal.isRunning)
        if let old { try await wait("Old shell gone") { kill(old, 0) == -1 && errno == ESRCH } }
    }

    func testPTYSurvivesNativeHostRemountWithCWDEnvironmentAndScrollback() async throws {
        let terminal = terminal()
        defer { terminal.terminate() }
        try terminal.startShell()
        let pid = terminal.processID
        let emulator = terminal.terminalView
        try await command("cd /; export DYNAMIC_TEST=retained", marker: "DI_MOUNT_BEFORE", terminal: terminal)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.orderOut(nil) }
        for _ in 0..<24 {
            let host = TerminalMountView()
            host.wasVisible = true
            window.contentView = host
            host.mount(emulator)
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(window.makeFirstResponder(emulator))
            host.releaseFocus()
            host.detach()
            window.contentView = NSView()
            await Task.yield()
            XCTAssertEqual(terminal.processID, pid)
            XCTAssertTrue(terminal.isRunning)
        }
        try await command("printf 'RETAINED=%s\\n' \"$DYNAMIC_TEST\"; pwd", marker: "DI_MOUNT_AFTER", terminal: terminal)
        XCTAssertTrue(hasLine("RETAINED=retained", in: terminal))
        XCTAssertTrue(hasLine("/", in: terminal))
        XCTAssertTrue(hasLine("DI_MOUNT_BEFORE", in: terminal))
        XCTAssertTrue(terminal.terminalView === emulator)
    }

    func testNaturalShellExitReportsRealStatusAndAllowsCleanRestart() async throws {
        let terminal = terminal()
        defer { terminal.terminate() }
        try terminal.startShell()
        terminal.sendInput(Array("exit 23\r".utf8))
        try await wait("Shell exits") { !terminal.isRunning }
        XCTAssertEqual(terminal.state, .finished(command: "Shell", exitCode: 23))
        try terminal.startShell()
        try await command("printf 'DI_AFTER_EXIT\\n'", marker: "DI_EXIT_READY", terminal: terminal)
        XCTAssertTrue(terminal.isRunning)
    }
}
