import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Production editors, Media view, existing Timer view and stack header.
/// Chat/Terminal bodies are explicitly labelled proxies; these are native
/// offscreen layout fixtures, never packaged/live acceptance evidence.
@MainActor
final class WorkspaceCustomizationSnapshotTests: XCTestCase {
    func testRenderNativeCustomizationReviewFixtures() async throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_CUSTOMIZATION_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_CUSTOMIZATION_SNAPSHOT_DIR for native customization layout fixtures")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "DynamicIsland.CustomizationSnapshots.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.reduceExtraMotion = true
        let media = MediaController.settingsPreview()
        let timer = TimerController(refreshInterval: nil)
        let store = WorkspaceCustomizationStore(defaults: defaults)
        var mediaLayout = WorkspaceConfiguration.initial
        mediaLayout.resetWidgets(on: .media)
        for placement in mediaLayout.widgets(on: .media) where placement.kind != .media { mediaLayout.remove(placement.id) }
        mediaLayout.add(.timer, on: .media)
        store.commit(mediaLayout)
        let mediaContent: (WorkspaceWidgetRegion, CGFloat) -> AnyView = { region, height in
            switch region.widgets.first?.kind {
            case .media: return AnyView(MediaModuleView(settings: settings, media: media, availableHeight: height))
            case .timer: return AnyView(FocusTimerView(timer: timer, settings: settings))
            default: return AnyView(Self.proxy("Unavailable fixture"))
            }
        }
        for (name, width, editing, reduced) in [
            ("media-normal", CGFloat(900), false, false),
            ("media-edit", CGFloat(900), true, false),
            ("media-narrow-edit", CGFloat(420), true, false),
            ("media-reduce-motion", CGFloat(900), true, true)
        ] {
            let editor = IslandWidgetEditor(store: store, surface: .media, editing: .constant(editing),
                eligibleWidgets: [.media, .timer], extraMotion: false, content: mediaContent)
            try await render(editor, size: CGSize(width: width, height: 300), reduced: reduced,
                to: directory.appendingPathComponent(name + ".png"))
        }
        var stacked = store.configuration
        stacked.add(.terminal, on: .agents)
        stacked.add(.timer, on: .agents)
        stacked.combineTerminalWithChat()
        stacked.markCustomized(.agents)
        store.commit(stacked)
        let presentation = AgentWorkspacePresentation()
        for (name, page, editing, width) in [
            ("agents-stack-chat", AgentStackPage.chat, false, CGFloat(900)),
            ("agents-stack-terminal", AgentStackPage.terminal, false, CGFloat(900)),
            ("agents-stack-edit", AgentStackPage.chat, true, CGFloat(900)),
            ("agents-narrow-edit", AgentStackPage.chat, true, CGFloat(420))
        ] {
            presentation.showStack(page)
            let editor = IslandWidgetEditor(store: store, surface: .agents, editing: .constant(editing),
                eligibleWidgets: [.chat, .terminal, .feed, .timer], extraMotion: false) { region, _ in
                if region.isStack {
                    return AnyView(AgentChatTerminalStack(presentation: presentation, isVisible: true,
                        reduceMotion: true, layoutStore: nil,
                        chat: { AnyView(Self.proxy("Chat fixture — selected-session content proxy")) },
                        terminal: { AnyView(Self.proxy("Terminal fixture — renderer proxy, no PTY")) }))
                }
                if region.widgets.first?.kind == .timer {
                    return AnyView(FocusTimerView(timer: timer, settings: settings))
                }
                return AnyView(Self.proxy("\(region.widgets.first?.kind.title ?? "Widget") fixture"))
            }
            try await render(editor, size: CGSize(width: width, height: 320), reduced: true,
                to: directory.appendingPathComponent(name + ".png"))
        }
        var navigation = store.configuration
        navigation.navigation.setVisible(.timer, visible: false)
        navigation.navigation.setVisible(.stats, visible: false)
        navigation.navigation.setVisible(.tools, visible: false)
        store.commit(navigation)
        let editor = WorkspaceNavigationEditor(store: store, eligiblePages: ExpandedIslandPage.allCases.filter { $0 != .messages },
            editing: .constant(true), extraMotion: false)
        try await render(editor, size: CGSize(width: 900, height: 90), reduced: true,
            to: directory.appendingPathComponent("navigation-edit.png"))
        try "Native fixture evidence only. Media uses inert Settings Preview controller; Timer uses existing production view/controller. Chat/Terminal bodies are labelled renderer proxies with production stack header. No provider/session/PTY or packaged-live evidence.\n".write(
            to: directory.appendingPathComponent("EVIDENCE.txt"), atomically: true, encoding: .utf8)
    }

    private static func proxy(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.system(size: 12, weight: .semibold))
            Text("Native layout fixture").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    private func render<Content: View>(_ content: Content, size: CGSize, reduced: Bool, to url: URL) async throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .padding(12).background(Color.black)
            .environment(\.colorScheme, .dark)
            )
        let canvas = CGSize(width: size.width + 24, height: size.height + 24)
        host.frame = CGRect(origin: .zero, size: canvas)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<12 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(3))
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url)
        XCTAssertGreaterThan(data.count, 1000)
    }
}
