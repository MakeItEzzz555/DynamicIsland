import AppKit
import SwiftUI

/// Cross-process keyboard delivery against an inert production composer; never starts app services or transports.
@MainActor
enum IslandKeyboardNativeAcceptance {
    private static let eventTag: Int64 = 0x44494b4559

    static func run(directory: URL, peerMode: Bool) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if peerMode { await runPeer(directory: directory); return }
        var report: [String: Any] = ["liveServicesStarted": false, "typedContentRecorded": false,
            "cameraStarted": false, "crossProcessDeliveryVerified": false,
            "displayActive": CGDisplayIsActive(CGMainDisplayID()) != 0,
            "displayAsleep": CGDisplayIsAsleep(CGMainDisplayID()) != 0,
            "postEventsAuthorized": CGPreflightPostEventAccess()]
        defer { write(report, to: directory.appendingPathComponent("keyboard-acceptance.json")) }
        guard CGDisplayIsActive(CGMainDisplayID()) != 0, CGDisplayIsAsleep(CGMainDisplayID()) == 0 else {
            report["gate"] = "Keep the Mac awake and unlocked, then rerun this packaged acceptance mode."; return
        }
        guard CGPreflightPostEventAccess() else {
            report["gate"] = "Automated cross-app input lacks authorization; test immediate physical typing manually. No permission was requested."; return
        }
        guard let screen = NSScreen.main else { report["gate"] = "No display."; return }
        let previousApplication = NSWorkspace.shared.frontmostApplication
        var peerPID: pid_t?
        defer {
            let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if activePID == peerPID || activePID == ProcessInfo.processInfo.processIdentifier {
                previousApplication?.activate(options: [.activateIgnoringOtherApps])
            }
        }
        var submits = 0, deliveredKeys = 0
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let fixture = AgentSession(id: AgentSessionInstanceID(
            sessionID: AgentSessionID(provider: .codex, nativeID: "native-keyboard-fixture"),
            generation: AgentSessionGeneration(rawValue: 1)), source: .desktopApp, state: .idle,
            project: AgentProjectContext(displayName: "Keyboard acceptance"), capabilities: AgentCapabilities(),
            usage: AgentUsage(), tools: [:], commands: [:], approvals: [:], subagents: [:], recentActivity: [],
            startedAt: timestamp, endedAt: nil, lastUpdatedAt: timestamp)
        let root = AgentEmbeddedConsoleView(session: fixture,
            mode: .interactive(canInterrupt: true), interactionState: .ready, transcriptEntries: [],
            approvalControl: AgentApprovalController(), onSelectSession: { _ in },
            onSubmit: { _ in submits += 1; return true }, onInterrupt: {})
        let host = NSHostingView(rootView: root.frame(width: 520, height: 220))
        let panel = IslandOverlayPanel(contentRect: CGRect(x: screen.frame.midX - 260, y: screen.frame.midY - 110,
            width: 520, height: 220), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.contentView = host
        panel.orderFrontRegardless()
        defer { panel.contentView = nil; panel.close() }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == eventTag { deliveredKeys += 1 }
            return event
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        let peer = Process()
        peer.executableURL = Bundle.main.executableURL
        peer.arguments = ["--validate-keyboard-peer", directory.path]
        peer.standardOutput = FileHandle.nullDevice; peer.standardError = FileHandle.nullDevice
        do { try peer.run() } catch { report["gate"] = "Unable to launch isolated keyboard peer."; return }
        peerPID = peer.processIdentifier
        defer { if peer.isRunning { peer.terminate() } }
        await pause(400)
        let beatStarted = CACurrentMediaTime()
        var beatElapsed: Double?
        let beat = NormalCollapseDisplayBeat(view: host, isCurrent: { panel.isVisible }) {
            beatElapsed = (CACurrentMediaTime() - beatStarted) * 1_000
        }
        await pause(100)
        beat.cancel()
        report["normalBeatDisplayCallbacks"] = beat.deliveredFrameCount
        report["normalBeatMilliseconds"] = beatElapsed ?? -1
        report["normalBeatMeasurementScope"] = "Native callback delivery in the mounted fixture, not pixel-level production collapse timing."
        guard let editor = descendants(host).compactMap({ $0 as? AgentPromptTextView }).first else {
            report["gate"] = "Production composer did not mount."; return
        }
        let originalMouse = NSEvent.mouseLocation
        var lastInjectedPoint: CGPoint?
        defer {
            if let point = lastInjectedPoint, hypot(NSEvent.mouseLocation.x - point.x, NSEvent.mouseLocation.y - point.y) < 1 {
                postMouse(.mouseMoved, appKitPoint: originalMouse)
            }
        }
        var cycles: [[String: Any]] = []
        for cycle in 0..<3 {
            guard let application = NSRunningApplication(processIdentifier: peer.processIdentifier) else { break }
            application.activate(options: [.activateIgnoringOtherApps])
            await pause(180)
            let wasPeerActive = NSWorkspace.shared.frontmostApplication?.processIdentifier == peer.processIdentifier
            guard wasPeerActive, panel.isVisible, panel.occlusionState.contains(.visible) else {
                report["gate"] = "The isolated peer or composer window could not acquire visible ownership; no input was posted."; break
            }
            let point = panel.convertPoint(toScreen: editor.convert(CGPoint(x: 12, y: 12), to: nil))
            lastInjectedPoint = point
            postMouse(.mouseMoved, appKitPoint: point)
            postMouse(.leftMouseDown, appKitPoint: point)
            postMouse(.leftMouseUp, appKitPoint: point)
            // No focus-settle delay: keys enter WindowServer immediately behind the click.
            postKey(0)
            postKey(36, flags: .maskShift)
            postKey(51)
            postKey(36)
            await pause(180)
            let beforeEscape = panel.isKeyWindow && panel.firstResponder === editor
            postKey(53)
            await pause(100)
            cycles.append(["cycle": cycle, "peerWasActive": wasPeerActive, "exactComposerOwnedKeyboard": beforeEscape,
                "escapeReleased": !panel.isKeyWindow, "confirmedFixtureSubmissions": submits])
            panel.orderOut(nil); panel.orderFrontRegardless()
            await pause(50)
        }
        let peerKeys = (try? Data(contentsOf: directory.appendingPathComponent("peer-key-count.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Int] }?["keys"] ?? -1
        report["cycles"] = cycles; report["composerKeyEvents"] = deliveredKeys
        report["peerKeyEvents"] = peerKeys; report["fixtureSubmissions"] = submits
        report["crossProcessDeliveryVerified"] = cycles.count == 3 && cycles.allSatisfy {
            $0["peerWasActive"] as? Bool == true && $0["exactComposerOwnedKeyboard"] as? Bool == true &&
                $0["escapeReleased"] as? Bool == true
        } && deliveredKeys == 15 && peerKeys == 0 && submits == 3
        if report["gate"] == nil {
            report["gate"] = "Physical IME, paste, session switching and production collapse/reopen still require a user exercise."
        }
    }

    private static func runPeer(directory: URL) async {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: CGRect(x: 80, y: 120, width: 320, height: 160),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "DynamicIsland isolated keyboard peer"
        let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        window.contentView = editor
        var count = 0
        let output = directory.appendingPathComponent("peer-key-count.json")
        write(["keys": count], to: output)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == eventTag {
                count += 1; write(["keys": count], to: output)
            }
            return event
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) }; window.close() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(editor)
        await pause(10_000)
    }

    private static func postMouse(_ type: CGEventType, appKitPoint: CGPoint) {
        let point = CGPoint(x: appKitPoint.x, y: CGDisplayBounds(CGMainDisplayID()).height - appKitPoint.y)
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.setIntegerValueField(.eventSourceUserData, value: eventTag)
        event?.post(tap: .cghidEventTap)
    }
    private static func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.setIntegerValueField(.eventSourceUserData, value: eventTag)
            event?.post(tap: .cghidEventTap)
        }
    }
    private static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private static func pause(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }
    private static func write(_ report: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
