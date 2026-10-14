import AppKit
@preconcurrency import AVFoundation
import QuartzCore
import ScreenCaptureKit
import ImageIO
import SwiftUI

/// Runs the production Settings host in a packaged app, with isolated preferences
/// and offline content. Normal app services and the user's sessions are never started.
@MainActor
enum SettingsNativeAcceptance {
    private struct OfflineSpotifyCredentials: SpotifyCredentialStoring {
        func credentials() -> SpotifyStoredCredentials { .init() }
        func store(accessToken: String, expiresAt: Date, refreshToken: String?, authorizationDate: Date?) {}
        func clear() {}
    }
    static func run(directory: URL) async {
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Native Settings validation")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        var report: [String: Any] = ["bundle": Bundle.main.bundleURL.path, "headlessFixture": false,
            "preferences": "isolated in-memory", "capture": "mounted native window content renders; no desktop or camera capture",
            "liveServices": "not started", "workspaceVideoFidelity": "not verified: missing supplemental recording"]
        report["mainDisplayActive"] = CGDisplayIsActive(CGMainDisplayID()) != 0
        report["mainDisplayAsleep"] = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let defaults = SettingsPreviewDefaults()
            let settings = AppSettings(defaults: defaults)
            let navigation = SettingsNavigationStore(defaults: defaults)
            let activities = LiveActivityStore(), capabilities = IslandCapabilityRegistry()
            let recording = ScreenRecordingController(liveActivities: activities, capabilities: capabilities,
                requestLedger: .init(defaults: defaults, buildIdentity: "settings-acceptance"))
            let background = BackgroundRemovalController(liveActivities: activities, capabilities: capabilities, addToShelf: { _ in })
            let productivity = ProductivityModules(capabilities: capabilities,
                keepAwake: KeepAwakeController(liveActivities: activities, capabilities: capabilities),
                windowSnap: WindowSnapController(liveActivities: activities, capabilities: capabilities),
                terminal: TerminalSessionController(liveActivities: activities, capabilities: capabilities),
                reminders: RemindersController(liveActivities: activities, capabilities: capabilities),
                voice: VoiceTranscriptionController(liveActivities: activities, capabilities: capabilities, addToShelf: { _ in }),
                camera: CameraPreviewController(liveActivities: activities, capabilities: capabilities),
                backgroundRemoval: background, screenRecording: recording,
                screenRecordingSetup: .production(controller: recording))
            let shortcuts = ShortcutsStore(defaults: defaults)
            shortcuts.shortcuts = [
                .init(title: "Preview browser", target: "https://example.invalid", symbolName: "safari"),
                .init(title: "Preview folder", target: "/tmp", symbolName: "folder"),
                .init(title: "Preview settings", target: "https://example.invalid/settings", symbolName: "gearshape"),
                .init(title: "Preview notes", target: "https://example.invalid/notes", symbolName: "note.text")]
            let preview = SettingsPreviewDependencies(timer: TimerController(), stats: SystemStatsController(),
                clipboardHistory: ClipboardHistoryStore(settings: settings,
                    persistence: FileClipboardHistoryPersistence(archiveURL: directory.appendingPathComponent("fixture-history.json")),
                    automaticallySchedulesTimer: false),
                shortcuts: shortcuts, rightWorkspace: RightWorkspaceStore(defaults: defaults),
                workspaceServices: WorkspaceServices(appLibrary: AppLibraryStore(defaults: defaults), calendar: CalendarEventsController(),
                    spotify: SpotifyLibraryController(defaults: defaults, tokens: OfflineSpotifyCredentials())),
                agentManagedControl: nil, productivity: productivity, previewMedia: MediaController.settingsPreview(),
                previewShelf: SettingsPreviewFixtures.previewShelf(settings: settings), previewBackgroundRemoval: background, customization: WorkspaceCustomizationStore(defaults: defaults))
            let events = AgentEventStore()
            let frameName = "DynamicIsland.Settings.Acceptance.\(UUID().uuidString)"
            defer { UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(frameName)") }
            let controller = SettingsWindowController(settings: settings, shortcuts: shortcuts,
                agentIngestion: AgentIngestionCoordinator(eventStore: events), agentEvents: events,
                productivity: productivity, previews: preview, navigation: navigation, frameAutosaveName: frameName)
            let window = controller.window
            window.appearance = NSAppearance(named: .darkAqua)
            controller.show()
            await settle()
            let firstNumber = window.windowNumber
            controller.show(); report["singletonReopen"] = window.windowNumber == firstNumber
            let minimizeKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: "m", charactersIgnoringModifiers: "m", isARepeat: false, keyCode: 46)
            report["nativeMinimizeKeyHandled"] = minimizeKey.map { NSApp.mainMenu?.performKeyEquivalent(with: $0) == true } ?? false
            report["minimize"] = await waitUntil { window.isMiniaturized }
            controller.show(); await settle(); report["restoreFromMinimize"] = !window.isMiniaturized && window.isVisible
            window.setContentSize(NSSize(width: 720, height: 700)); await settle()
            let displaySample = SettingsDisplaySampling()
            let displayLink = window.displayLink(target: displaySample, selector: #selector(SettingsDisplaySampling.tick(_:)))
            displayLink.add(to: .main, forMode: .common)
            for page in [SettingsPage.general, .shelf, .liveActivities, .clipboard, .lockScreen, .shelf, .general] {
                navigation.navigate(.page(page)); await settle(milliseconds: 180)
            }
            displayLink.invalidate()
            report["displayCallbackSampling"] = displaySample.report
            let regularFrame = window.frame
            var renders: [String] = [], timings: [Double] = [], scrollChecks: [String: Any] = [:]
            var accessibility: [String: [String]] = [:]
            for page in SettingsPage.allCases {
                let start = CACurrentMediaTime()
                navigation.navigate(.page(page)); await settle()
                timings.append((CACurrentMediaTime() - start) * 1000)
                try render(window, name: "compact-\(page.id)", directory: directory)
                renders.append("compact-\(page.id)")
                if page == .general { report["windowServerCapture"] = await captureOwnWindow(window, directory: directory) }
                accessibility[page.id] = accessibilityLabels(window.contentView)
                if let scroll = detailScroll(window) {
                    let sidebar = nativeScrolls(window.contentView).first { $0 !== scroll }
                    let sidebarOrigin = sidebar?.contentView.bounds.origin
                    let maximum = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
                    scrollTo(maximum / 2, scroll: scroll); await settle()
                    try render(window, name: "middle-\(page.id)", directory: directory)
                    scrollTo(maximum, scroll: scroll); await settle()
                    try render(window, name: "bottom-\(page.id)", directory: directory)
                    scrollChecks[page.id] = ["contentHeight": scroll.documentView?.bounds.height ?? 0,
                        "viewportHeight": scroll.contentView.bounds.height, "maximumScroll": maximum,
                        "sidebarUnaffected": sidebar?.contentView.bounds.origin == sidebarOrigin]
                    scrollTo(0, scroll: scroll); await settle()
                }

            }
            navigation.navigate(.page(.general)); await settle()
            report["obsoleteNotchChoicesAbsent"] = navigation.nativeControls.object(forKey: "settings.notch.hide") == nil &&
                navigation.nativeControls.object(forKey: "settings.notch.openSettings") == nil
            navigation.navigate(.page(.clipboard)); await settle()
            let back = click("settings.back", in: window, navigation: navigation)
            _ = await waitUntil { navigation.route == .page(.general) }
            back?.shutdown()
            report["nativeBackAction"] = back != nil && navigation.route == .page(.general)
            let forward = click("settings.forward", in: window, navigation: navigation)
            _ = await waitUntil { navigation.route == .page(.clipboard) }
            forward?.shutdown()
            report["nativeForwardAction"] = forward != nil && navigation.route == .page(.clipboard)
            navigation.navigate(.page(.liveActivities)); await settle()
            if let scroll = detailScroll(window) {
                let maximum = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
                scrollTo(maximum, scroll: scroll); await settle()
            }
            let externalChoice = click("settings.external-display.whenActive", in: window, navigation: navigation)
            _ = await waitUntil { settings.externalDisplayVisibility == .whenActive }
            externalChoice?.shutdown()
            report["nativeExternalDisplayChoicePersistence"] = externalChoice != nil && settings.externalDisplayVisibility == .whenActive &&
                AppSettings(defaults: defaults).externalDisplayVisibility == .whenActive
            try render(window, name: "external-display-selected", directory: directory)
            settings.externalDisplayVisibility = .always
            navigation.navigate(.page(.shelf)); await settle()
            let originalPlacement = preview.customization?.configuration
            report["nativeControlFrames"] = ["measurement": "AppKit view-to-window conversion"]
            if let editorClick = click("settings.workspace-editor", in: window, navigation: navigation) {
                _ = await waitUntil { window.attachedSheet != nil }
                editorClick.shutdown()
                report["workspaceEditorSheetOpened"] = window.attachedSheet != nil
                if let sheet = window.attachedSheet {
                    try render(sheet, name: "workspace-editor-sheet", directory: directory)
                    sheet.makeKey(); sheet.makeFirstResponder(sheet.contentView)
                    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber, context: nil,
                        characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)
                    if let escape { NSApp.postEvent(escape, atStart: false) }
                    report["workspaceEditorCancelAction"] = escape != nil
                    await settle()
                    report["workspaceEditorCancelPreservesLayout"] = preview.customization?.configuration == originalPlacement && window.attachedSheet == nil
                }
            } else { report["workspaceEditorSheetOpened"] = false }
            window.setContentSize(NSSize(width: 1100, height: 800)); await settle()
            for page in [SettingsPage.shelf, .lockScreen, .liveActivities] {
                navigation.navigate(.page(page)); await settle()
                try render(window, name: "wide-\(page.id)", directory: directory)
            }
            let warm = SettingsDisplaySampling()
            let warmLink = window.displayLink(target: warm, selector: #selector(SettingsDisplaySampling.tick(_:)))
            warmLink.add(to: .main, forMode: .common)
            for page in [SettingsPage.general, .shelf, .liveActivities, .clipboard, .lockScreen, .shelf, .general] {
                navigation.navigate(.page(page)); await settle(milliseconds: 180)
            }
            warmLink.invalidate(); report["warmDisplayCallbackSampling"] = warm.report
            window.appearance = NSAppearance(named: .aqua)
            for page in [SettingsPage.general, .shelf, .clipboard, .about] {
                navigation.navigate(.page(page)); await settle()
                try render(window, name: "light-\(page.id)", directory: directory)
            }
            window.appearance = NSAppearance(named: .darkAqua)
            settings.reduceExtraMotion = true
            navigation.navigate(.page(.liveActivities)); await settle()
            try render(window, name: "reduced-motion-liveActivities", directory: directory)
            settings.reduceExtraMotion = false
            let syntheticAudio = directory.appendingPathComponent("accepted-file-fixture.wav")
            let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 480)!
            audioBuffer.frameLength = 480
            audioBuffer.floatChannelData?.pointee.initialize(repeating: 0, count: 480)
            try AVAudioFile(forWriting: syntheticAudio, settings: audioFormat.settings).write(from: audioBuffer)
            preview.previewShelf.add([syntheticAudio]); preview.previewShelf.requestFileActions(for: [syntheticAudio])
            let fileLayout = IslandLayoutStore()
            let filePresenter = FileActionPresenter(shelf: preview.previewShelf,
                operations: BackgroundOperationController(liveActivities: LiveActivityStore()), layout: fileLayout)
            if let request = preview.previewShelf.fileActionRequest, let content = window.contentView {
                report["filePopupCompactAnchor"] = filePresenter.present(request,
                    relativeTo: NSRect(x: content.bounds.midX - 95, y: content.bounds.maxY - 44, width: 190, height: 38),
                    of: content, permitted: true, reduceMotion: true)
                await settle()
                report["filePopupOwnsInteraction"] = fileLayout.isTransientInteractionActive
                if let popup = filePresenter.presentationWindow {
                    try render(popup, name: "accepted-file-popup", directory: directory)
                }
                filePresenter.close(); await settle()
                report["filePopupCleanup"] = !filePresenter.isShown && !fileLayout.isTransientInteractionActive && preview.previewShelf.fileActionRequest == nil
            }
            report["nativePanelSizeReset"] = SettingsWindowController.resetPanelSize(window)
            report["nativePanelSizeResetDimensions"] = window.contentView.map { abs($0.bounds.width - 720) <= 1 && abs($0.bounds.height - 700) <= 1 } ?? false
            navigation.navigate(.page(.general)); await settle()
            let beforeFullscreen = window.frame
            checkpoint("fullscreen-request", window: window, directory: directory)
            window.makeKey()
            let fullscreenRouter = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
            if let green = window.standardWindowButton(.zoomButton) {
                let point = green.convert(CGPoint(x: green.bounds.midX, y: green.bounds.midY), to: nil)
                fullscreenRouter.press(at: point); fullscreenRouter.release(at: point)
            }
            let entered = await waitUntil { window.styleMask.contains(.fullScreen) }
            fullscreenRouter.shutdown()
            report["nativeFullscreenEnter"] = entered
            report["nativeGreenButtonFullscreenEnter"] = entered
            if entered {
                await settle(milliseconds: 1200)
                try render(window, name: "fullscreen-general", directory: directory)
                checkpoint("fullscreen-exit-request", window: window, directory: directory)
                let fullscreenKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .control],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)
                report["nativeFullscreenKeyHandled"] = fullscreenKey.map { NSApp.mainMenu?.performKeyEquivalent(with: $0) == true } ?? false
                report["nativeFullscreenExit"] = await waitUntil { !window.styleMask.contains(.fullScreen) }
                await settle(milliseconds: 1200)
            }
            checkpoint("fullscreen-exited", window: window, directory: directory)
            report["fullscreenRestoredRegularFrame"] = abs(window.frame.width - beforeFullscreen.width) <= 1 && abs(window.frame.height - beforeFullscreen.height) <= 1
            report["restoredRegularContentSize"] = [window.contentView?.bounds.width ?? 0, window.contentView?.bounds.height ?? 0]
            report["regularFrameBeforeWideResize"] = [regularFrame.width, regularFrame.height]
            checkpoint("close-request", window: window, directory: directory)
            navigation.navigate(.page(.shelf)); window.makeKey()
            let closeKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)
            report["nativeCloseKeyHandled"] = closeKey.map { NSApp.mainMenu?.performKeyEquivalent(with: $0) == true } ?? false
            await settle()
            report["close"] = !window.isVisible
            checkpoint("reopen-request", window: window, directory: directory)
            controller.show()
            checkpoint("reopened", window: window, directory: directory)
            await settle()
            report["reopenRetainsRoute"] = window.isVisible && navigation.route == .page(.shelf)
            report["screenshots"] = renders
            report["scrollChecks"] = scrollChecks
            report["accessibilityLabels"] = accessibility
            report["accessibilityInspection"] = accessibility.values.contains(where: { !$0.isEmpty }) ? "Partial AppKit labels inspected; full SwiftUI/VoiceOver acceptance remains unverified" : "Not verified: this in-process accessibility traversal did not expose SwiftUI labels. VoiceOver/Accessibility Inspector acceptance remains required."
            report["pageSwitchTestIntervalMs"] = timings
            report["performanceLimit"] = "Intervals include deliberate 250 ms UI settling; not display frame pacing or input latency."
            report["noCaptureOwner"] = !productivity.camera.isRunning
            report["v3Status"] = "navigation milestone only; feature/visual matrix remains incomplete"
            window.orderOut(nil)
        } catch { report["error"] = String(describing: error) }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("settings-acceptance.json"), options: .atomic)
        }
    }
    private static func checkpoint(_ phase: String, window: NSWindow, directory: URL) {
        let data: [String: Any] = ["phase": phase, "fullscreen": window.styleMask.contains(.fullScreen),
            "visible": window.isVisible, "activationPolicy": NSApp.activationPolicy().rawValue]
        if let json = try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys) {
            try? json.write(to: directory.appendingPathComponent("native-checkpoint.json"), options: .atomic)
        }
    }
    private static func nativeScrolls(_ view: NSView?) -> [NSScrollView] {
        guard let view else { return [] }
        return (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { nativeScrolls($0) }
    }
    private static func detailScroll(_ window: NSWindow) -> NSScrollView? {
        nativeScrolls(window.contentView).filter { scroll in
            guard let content = window.contentView else { return false }
            return scroll.convert(scroll.bounds, to: content).minX > 150
        }.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }
    private static func scrollTo(_ y: CGFloat, scroll: NSScrollView) {
        let clip = scroll.contentView
        let next = clip.constrainBoundsRect(CGRect(origin: CGPoint(x: clip.bounds.minX, y: y), size: clip.bounds.size))
        clip.scroll(to: next.origin); scroll.reflectScrolledClipView(clip)
    }
    private static func accessibilityElements(_ view: NSView?) -> [any NSAccessibilityProtocol] {
        guard let view else { return [] }
        var result: [any NSAccessibilityProtocol] = [], visited = Set<ObjectIdentifier>(), pending: [AnyObject] = [view]
        while let item = pending.popLast(), visited.count < 2_000 {
            guard visited.insert(ObjectIdentifier(item)).inserted, let element = item as? any NSAccessibilityProtocol else { continue }
            result.append(element)
            if let view = item as? NSView { pending.append(contentsOf: view.subviews) }
            pending.append(contentsOf: (element.accessibilityChildren() ?? []).map { $0 as AnyObject })
        }
        return result
    }
    private static func accessibilityLabels(_ view: NSView?) -> [String] {
        Array(Set(accessibilityElements(view).flatMap { [$0.accessibilityLabel(), $0.accessibilityTitle()].compactMap { $0 }.filter { !$0.isEmpty } })).sorted()
    }
    private static func click(_ identifier: String, in window: NSWindow, navigation: SettingsNavigationStore) -> CameraInteractionRouter? {
        guard let anchor = navigation.nativeControls.object(forKey: identifier as NSString), anchor.window === window,
              !anchor.bounds.isEmpty else { return nil }
        let point = anchor.convert(CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
        let router = CameraInteractionRouter(window: window, monitorsPhysicalInput: false)
        router.press(at: point); router.release(at: point)
        // The caller keeps the router alive until the native action is observed.
        return router
    }
    private static func captureOwnWindow(_ window: NSWindow, directory: URL) async -> String {
        guard CGPreflightScreenCaptureAccess() else { return "Not captured: Screen Recording permission is not granted to this build; no prompt requested." }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let own = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }) else {
                return "Not captured: this validation window was not enumerated."
            }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * window.backingScaleFactor)
            configuration.height = Int(window.frame.height * window.backingScaleFactor)
            configuration.showsCursor = false; configuration.capturesAudio = false; configuration.ignoreShadowsSingleWindow = true
            let picture = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration)
            let bytes = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) else { return "Capture encoding unavailable." }
            CGImageDestinationAddImage(destination, picture, nil)
            guard CGImageDestinationFinalize(destination) else { return "Capture encoding failed." }
            try (bytes as Data).write(to: directory.appendingPathComponent("window-server-general.png"), options: .atomic)
            return "Captured only this process's Settings window with public ScreenCaptureKit."
        } catch { return "ScreenCaptureKit access failed; no permission request or TCC change made." }
    }
    private static func settle(milliseconds: Int = 250) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }
    private static func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<80 { if predicate() { return true }; await settle(milliseconds: 100) }
        return false
    }
    private static func render(_ window: NSWindow, name: String, directory: URL) throws {
        guard let view = window.contentView else { throw ScreenRecordingError.invalidOutput }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw ScreenRecordingError.invalidOutput }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw ScreenRecordingError.invalidOutput }
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }
}

@MainActor
private final class SettingsDisplaySampling: NSObject {
    private var previous: CFTimeInterval?
    private var intervals: [Double] = []
    @objc func tick(_ sender: CADisplayLink) {
        let time = CACurrentMediaTime()
        if let previous { intervals.append((time - previous) * 1000) }
        previous = time
    }
    var report: [String: Any] {
        let sorted = intervals.sorted()
        let maximum: Double = sorted.last ?? 0
        return ["samples": intervals.count, "meanMs": intervals.reduce(0, +) / Double(max(1, intervals.count)),
            "p95Ms": sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
            "maximumMs": maximum,
            "scope": "Actual native display-link callback delivery during page navigation; not pixel presentation or physical input latency."]
    }
}
