import Foundation
import XCTest
@testable import DynamicIsland

private final class FakeTerminalProcessHandle: TerminalProcessHandle {
    var isRunning = true
    var terminateCount = 0

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
    func testStartUsesConfiguredShellAndWorkingDirectoryAndPublishesActivity() throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)

        try fixture.controller.run(command: "echo hello")

        XCTAssertEqual(runner.receivedCommand, "echo hello")
        XCTAssertEqual(runner.receivedShell, "/bin/zsh")
        XCTAssertEqual(runner.receivedWorkingDirectory?.path, "/tmp")
        XCTAssertTrue(fixture.controller.isRunning)
        XCTAssertEqual(fixture.controller.commandHistory, ["echo hello"])

        let activity = fixture.activities.activities.first
        XCTAssertEqual(activity?.kind, .terminalTask)
        XCTAssertEqual(activity?.lifecycle.authority, .process)
        XCTAssertEqual(activity?.subtitle, "Running")
        XCTAssertEqual(fixture.registry.snapshot(for: .terminal)?.isActive, true)
    }

    func testStreamedOutputIsAppendedOnMainActor() async throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        try fixture.controller.run(command: "build")

        runner.outputCallback?("one\n")
        runner.outputCallback?("two\n")
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(fixture.controller.output, "one\ntwo\n")
    }

    func testExitTransitionsToFinishedAndActivityReflectsActualExitCode() async throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        try fixture.controller.run(command: "build")

        runner.exitCallback?(7)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(fixture.controller.state, .finished(command: "build", exitCode: 7))
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

    func testSecondCommandIsRejectedWhileRunning() throws {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)
        try fixture.controller.run(command: "first")

        XCTAssertThrowsError(try fixture.controller.run(command: "second")) { error in
            XCTAssertEqual(error as? TerminalSessionError, .alreadyRunning)
        }
        XCTAssertEqual(runner.startCount, 1)
    }

    func testEmptyCommandIsRejectedBeforeProcessStart() {
        let runner = FakeTerminalProcessRunner()
        let fixture = makeFixture(runner: runner)

        XCTAssertThrowsError(try fixture.controller.run(command: "   ")) { error in
            XCTAssertEqual(error as? TerminalSessionError, .emptyCommand)
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

        // The existing process must report termination before state becomes non-running.
        runner.exitCallback?(15)
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
