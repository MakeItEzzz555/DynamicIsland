import Foundation
import XCTest
@testable import DynamicIsland

private final class FakeTerminalProcessHandle: TerminalProcessHandle {
    var isRunning = true
    var terminateCount = 0
    var processID: Int32? { isRunning ? 41_002 : nil }
    private(set) var input: [UInt8] = []

    func send(data: [UInt8]) { input.append(contentsOf: data) }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }
}

private final class FakeTerminalProcessRunner: TerminalProcessRunning {
    var startCount = 0
    var receivedCommand: String?
    var receivedShell: String?
    var receivedWorkingDirectory: URL?
    var launchError: Error?
    let handle = FakeTerminalProcessHandle()
    var outputCallback: (@Sendable (String) -> Void)?
    var exitCallback: (@Sendable (Int32) -> Void)?

    func start(
        command: String,
        shellPath: String,
        workingDirectory: URL?,
        onOutput: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> TerminalProcessHandle {
        if let launchError { throw launchError }
        startCount += 1
        handle.isRunning = true
        receivedCommand = command
        receivedShell = shellPath
        receivedWorkingDirectory = workingDirectory
        outputCallback = onOutput
        exitCallback = onExit
        return handle
    }
}

@MainActor
final class TerminalSessionControllerTests: XCTestCase {
    func testCommandHistoryRequiresOptInAndCanBeCleared() throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        XCTAssertFalse(fixture.controller.persistCommandHistory)

        fixture.controller.persistCommandHistory = true
        try fixture.controller.run(command: "echo one")
        XCTAssertEqual(fixture.controller.commandHistory, ["echo one"])
        for index in 0..<140 { try fixture.controller.run(command: "echo \(index)") }
        XCTAssertEqual(fixture.controller.commandHistory.count, 128)
        XCTAssertEqual(fixture.controller.commandHistory.first, "echo 12")
        XCTAssertEqual(fixture.controller.commandHistory.last, "echo 139")
        XCTAssertEqual(runner.startCount, 1, "History recording cannot create additional shells")

        fixture.controller.clearCommandHistory()
        XCTAssertTrue(fixture.controller.commandHistory.isEmpty)

        fixture.controller.terminate()
        fixture.controller.persistCommandHistory = true
        XCTAssertTrue(fixture.controller.commandHistory.isEmpty)
    }

    func testDisablingHistoryOptInDiscardsHistory() throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        fixture.controller.persistCommandHistory = true
        try fixture.controller.run(command: "echo one")

        fixture.controller.persistCommandHistory = false

        XCTAssertTrue(fixture.controller.commandHistory.isEmpty)
    }

    func testStartUsesConfiguredShellAndDirectoryWithoutFalseOngoingActivity() throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)

        try fixture.controller.run(command: "echo hello")

        XCTAssertEqual(runner.receivedCommand, "echo hello")
        XCTAssertEqual(runner.receivedShell, "/bin/zsh")
        XCTAssertEqual(runner.receivedWorkingDirectory?.path, "/tmp")
        XCTAssertTrue(fixture.controller.isRunning)
        XCTAssertTrue(fixture.controller.commandHistory.isEmpty, "History is off by default")

        XCTAssertEqual(String(decoding: runner.handle.input, as: UTF8.self), "echo hello\r")
        XCTAssertEqual(fixture.controller.processID, runner.handle.processID)
        XCTAssertTrue(fixture.activities.activities.isEmpty, "An idle interactive shell cannot imply an executing agent task")
        XCTAssertEqual(fixture.registry.snapshot(for: .terminal)?.isActive, true)
        try fixture.controller.startShell(initialDirectory: "/")
        XCTAssertEqual(runner.startCount, 1)
        XCTAssertEqual(fixture.controller.workingDirectoryPath, "/tmp", "Presentation changes cannot relocate a running shell")
    }

    func testStreamedOutputIsAppendedOnMainActor() async throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        try fixture.controller.run(command: "build")

        runner.outputCallback?("one\r\n")
        runner.outputCallback?("two\r\n")
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(fixture.controller.output.contains("one"))
        XCTAssertTrue(fixture.controller.output.contains("two"))
        XCTAssertFalse(fixture.controller.output.contains("$ build"), "The shell owns prompt/echo; controller must not manufacture command headers")
    }

    func testRepeatedCommandsPreserveEmulatorOwnedBoundedScrollback() async throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)

        try fixture.controller.run(command: "echo first")
        runner.outputCallback?("first\r\n")
        await Task.yield()
        await Task.yield()
        try fixture.controller.run(command: "echo second")
        runner.outputCallback?("second\r\n")
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(fixture.controller.output.contains("first"))
        XCTAssertTrue(fixture.controller.output.contains("second"))
        XCTAssertEqual(runner.startCount, 1)
        XCTAssertEqual(String(decoding: runner.handle.input, as: UTF8.self), "echo first\recho second\r")

        let lines = (0..<5_000).map { "bounded-line-\($0)" }.joined(separator: "\r\n") + "\r\n"
        runner.outputCallback?(lines)
        await Task.yield()
        await Task.yield()
        let output = fixture.controller.output
        XCTAssertTrue(output.contains("bounded-line-4999"))
        XCTAssertFalse(output.contains("bounded-line-0\n"), "Old scrollback must be evicted")
        let screenRows = fixture.controller.terminalView.getTerminal().rows
        XCTAssertLessThanOrEqual(output.split(separator: "\n", omittingEmptySubsequences: false).count,
                                 TerminalSessionController.maximumScrollbackLines + screenRows + 2)
        XCTAssertEqual(runner.startCount, 1)
    }

    func testExitTransitionsToFinishedAndActivityReflectsActualExitCode() async throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        try fixture.controller.run(command: "build")

        runner.exitCallback?(7)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(fixture.controller.state, .finished(command: "Shell", exitCode: 7))
        XCTAssertEqual(fixture.activities.activities.first?.subtitle, "Exited 7")
        XCTAssertEqual(fixture.registry.snapshot(for: .terminal)?.isActive, false)
    }

    func testTerminateDelegatesToActiveProcess() throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        try fixture.controller.run(command: "sleep 10")

        fixture.controller.terminate()

        XCTAssertEqual(runner.handle.terminateCount, 1)
    }

    func testOldLaunchCallbacksCannotClearOrWriteIntoRestartedTerminal() async throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        try fixture.controller.run(command: "first shell input")
        let oldOutput = try XCTUnwrap(runner.outputCallback)
        let oldExit = try XCTUnwrap(runner.exitCallback)

        // These callbacks have reached the controller, but their MainActor
        // Tasks have not run. Restart in the same actor turn before yielding.
        oldOutput("STALE_BEFORE_RESTART\r\n")
        oldExit(17)
        fixture.controller.terminate()
        try fixture.controller.startShell(initialDirectory: "/tmp")
        let currentPID = fixture.controller.processID
        let currentState = fixture.controller.state

        // Providers/read queues can also deliver late callbacks after restart.
        oldOutput("STALE_AFTER_RESTART\r\n")
        oldExit(23)
        runner.outputCallback?("CURRENT_SHELL_OUTPUT\r\n")
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(fixture.controller.isRunning)
        XCTAssertEqual(fixture.controller.state, currentState)
        XCTAssertEqual(fixture.controller.processID, currentPID)
        XCTAssertEqual(runner.startCount, 2, "A stale exit cannot start or orphan another terminal")
        XCTAssertEqual(runner.handle.terminateCount, 1)
        XCTAssertEqual(fixture.registry.snapshot(for: .terminal)?.isActive, true)
        XCTAssertTrue(fixture.activities.activities.isEmpty, "An old exit cannot publish a new shell completion")
        XCTAssertTrue(fixture.controller.output.contains("CURRENT_SHELL_OUTPUT"))
        XCTAssertFalse(fixture.controller.output.contains("STALE_BEFORE_RESTART"))
        XCTAssertFalse(fixture.controller.output.contains("STALE_AFTER_RESTART"))

        // The guard excludes stale launches, not the current provider truth.
        runner.exitCallback?(5)
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(fixture.controller.state, .finished(command: "Shell", exitCode: 5))
        XCTAssertNil(fixture.controller.processID)
    }

    func testSubsequentCommandsUseSameShellAndInputOwner() throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        try fixture.controller.run(command: "first")
        let processID = fixture.controller.processID
        try fixture.controller.run(command: "second")
        fixture.controller.sendInput([27, 91, 65])
        fixture.controller.interrupt()
        XCTAssertEqual(runner.startCount, 1)
        XCTAssertEqual(fixture.controller.processID, processID)
        XCTAssertEqual(String(decoding: runner.handle.input.prefix(13), as: UTF8.self), "first\rsecond\r")
        XCTAssertEqual(Array(runner.handle.input.suffix(4)), [27, 91, 65, 3],
            "Native history/control input must reach the existing PTY handle")
        XCTAssertTrue(fixture.controller.isRunning, "Ctrl-C must not close the interactive shell")
    }

    func testInvalidInputAndLaunchConfigurationAreRejectedBeforeShellStart() {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)

        XCTAssertThrowsError(try fixture.controller.run(command: "   ")) { error in
            XCTAssertEqual(error as? TerminalSessionError, .emptyCommand)
        }
        fixture.controller.shellPath = "/nonexistent/dynamicisland-shell"
        XCTAssertThrowsError(try fixture.controller.run(command: "pwd")) {
            XCTAssertEqual($0 as? TerminalSessionError, .invalidShell("/nonexistent/dynamicisland-shell"))
        }
        fixture.controller.shellPath = "/bin/zsh"
        fixture.controller.workingDirectoryPath = "/nonexistent/dynamicisland-cwd"
        XCTAssertThrowsError(try fixture.controller.run(command: "pwd")) {
            XCTAssertEqual($0 as? TerminalSessionError, .invalidWorkingDirectory("/nonexistent/dynamicisland-cwd"))
        }
        XCTAssertEqual(runner.startCount, 0)
    }

    func testLaunchFailurePublishesFailedHealthWithoutOptimisticActivity() {
        let runner = FakeTerminalProcessRunner()
        runner.launchError = TerminalSessionError.launchFailed("boom")
        let fixture = makeFixture(runner: runner)

        XCTAssertThrowsError(try fixture.controller.run(command: "bad"))
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        guard case .failed = fixture.registry.snapshot(for: .terminal)?.health else {
            return XCTFail("Expected terminal capability failure")
        }
    }

    func testDisablingActiveTerminalTerminatesProcessAndPreventsNewLaunches() throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        try fixture.controller.run(command: "work")

        fixture.controller.setEnabled(false)
        XCTAssertEqual(runner.handle.terminateCount, 1)
        XCTAssertEqual(fixture.registry.snapshot(for: .terminal)?.isEnabled, false)

        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertEqual(fixture.controller.state, .idle)
        let inputBefore = runner.handle.input
        try fixture.controller.run(command: "must not execute")
        XCTAssertEqual(runner.startCount, 1)
        XCTAssertEqual(runner.handle.input, inputBefore)
    }

    private func makeFixture(
        runner: FakeTerminalProcessRunner
    ) -> (
        controller: TerminalSessionController,
        activities: LiveActivityStore,
        registry: IslandCapabilityRegistry
    ) {
        let activities = LiveActivityStore()
        let registry = IslandCapabilityRegistry()
        let controller = TerminalSessionController(
            liveActivities: activities,
            capabilities: registry,
            runner: runner,
            shellPath: "/bin/zsh",
            workingDirectoryPath: "/tmp",
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        return (controller, activities, registry)
    }
}
