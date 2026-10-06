import SwiftUI
import XCTest
@testable import DynamicIsland

/// Chat <-> Terminal is a presentation switch inside one region. Regression
/// (2026-10-06): the embedded Terminal button added a Terminal widget below
/// the Chat (`configuration.add(.terminal)` + commit) on every switch.
@MainActor
final class AgentConsoleSwitchTests: XCTestCase {
    private func agentsConfig(_ kinds: [IslandWidget]) -> WorkspaceConfiguration {
        var config = WorkspaceConfiguration.initial
        for widget in config.widgets(on: .agents) { config.remove(widget.id) }
        for kind in kinds { config.add(kind, on: .agents) }
        return config
    }

    func testTerminalFromChatSwitchesTheSameRegionWithoutTouchingTheLayout() throws {
        let config = agentsConfig([.chat])
        let before = config
        let chat = try XCTUnwrap(config.regions(on: .agents).first)
        let presentation = AgentWorkspacePresentation()
        XCTAssertEqual(presentation.consoleMode(for: chat), .chat)
        presentation.switchConsole(to: .terminal, in: chat)
        XCTAssertEqual(presentation.consoleMode(for: chat), .terminal, "same region now shows Terminal")
        XCTAssertEqual(config, before, "configuration stays [Chat], never [Chat, Terminal]")
        XCTAssertEqual(config.regions(on: .agents).map(\.id), [chat.id])
        presentation.switchConsole(to: .chat, in: chat)
        XCTAssertEqual(presentation.consoleMode(for: chat), .chat)
        XCTAssertEqual(config, before)
    }

    func testSeparateChatAndTerminalWidgetsKeepIndependentPresentations() throws {
        let config = agentsConfig([.chat, .terminal])
        let regions = config.regions(on: .agents)
        let chat = try XCTUnwrap(regions.first { $0.widgets.first?.kind == .chat })
        let terminal = try XCTUnwrap(regions.first { $0.widgets.first?.kind == .terminal })
        let presentation = AgentWorkspacePresentation()
        XCTAssertEqual(presentation.consoleMode(for: terminal), .terminal, "a Terminal region defaults to Terminal")
        // Live finding (2026-10-06): showing Terminal in the Chat region while
        // the Terminal widget also showed it mounted the one PTY host twice
        // (one pane blank). Each surface is presented once: the regions swap.
        presentation.switchConsole(to: .terminal, in: chat, among: regions)
        XCTAssertEqual(presentation.consoleMode(for: chat), .terminal)
        XCTAssertEqual(presentation.consoleMode(for: terminal), .chat, "the other region takes the other surface")
        presentation.switchConsole(to: .terminal, in: terminal, among: regions)
        XCTAssertEqual(presentation.consoleMode(for: terminal), .terminal)
        XCTAssertEqual(presentation.consoleMode(for: chat), .chat)
        let shown = regions.map { presentation.consoleMode(for: $0) }
        XCTAssertEqual(Set(shown).count, shown.count, "never the same surface twice")
        XCTAssertEqual(config.regions(on: .agents).count, 2, "both widgets remain")
    }

    func testStackUsesItsPagesAndOtherWidgetsAreNotConsoles() throws {
        var config = agentsConfig([.chat, .terminal])
        config.combineTerminalWithChat(on: .agents)
        let stack = try XCTUnwrap(config.regions(on: .agents).first(where: \.isStack))
        XCTAssertEqual(AgentConsoleSwitchTarget.resolve(stack), .stack)
        let presentation = AgentWorkspacePresentation()
        presentation.switchConsole(to: .terminal, in: stack)
        XCTAssertEqual(presentation.stackPage, .terminal)
        XCTAssertTrue(presentation.consoleModes.isEmpty)
        let feed = WorkspaceWidgetRegion(id: WidgetID(rawValue: "agents.feed"),
            widgets: [WidgetPlacement(kind: .feed, surface: .agents, order: 0)])
        XCTAssertEqual(AgentConsoleSwitchTarget.resolve(feed), .none)
    }

    /// Source guard: the embedded switch must never commit a configuration.
    func testAgentViewsNeverAddATerminalWidgetFromTheModeSwitch() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/DynamicIsland/Views/AgentActivityViews.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(source.contains("add(.terminal"), "mode controls must not create widgets")
        // Compact Terminal is a real terminal pane on the shared controller,
        // never the agent summary with its conversation removed.
        XCTAssertFalse(source.contains("role: .terminal"), "Compact Terminal must not use AgentCompactSessionSummary")
        XCTAssertTrue(source.contains("AgentConsoleTerminalPane(controller: terminal, onSelectInteraction: consoleSwitch(region), compact: true)"))
    }

    func testTerminalPaneShowsOnlyTheLastPathComponent() {
        XCTAssertEqual(AgentConsoleTerminalPane<EmptyView>.directoryLabel("/Users/someone/Projects/DynamicIsland"), "DynamicIsland")
        XCTAssertEqual(AgentConsoleTerminalPane<EmptyView>.directoryLabel(FileManager.default.homeDirectoryForCurrentUser.path), "~")
    }
}
