import AppKit
import ApplicationServices
import CryptoKit

/// Only structural AX metadata leaves the probe. Titles, descriptions, values and caller text are never read.
struct FaceTimeAXNode: Codable, Equatable, Sendable {
    let depth: Int
    let role: String
    let subrole: String?
    let identifierSHA256: String?
    let actions: [String]
    let enabled: Bool
}

struct FaceTimeAXSnapshot: Codable, Equatable, Sendable {
    let nodes: [FaceTimeAXNode]
    let readStatus: Int32
    let truncated: Bool

    // shortcut: no active-call AX identity has been verified; add a versioned mapping only after live call evidence.
    var hasVerifiedCall: Bool { false }
    var verifiedControls: [String] { [] }
}

@MainActor
final class FaceTimeAccessibilityProvider: ObservableObject {
    static let bundleIdentifier = "com.apple.FaceTime"
    static let enabledKey = "faceTimeAccessibilityIntegrationEnabled"
    static let notificationActivityID = "facetime.notification"

    enum State: String {
        case disabled = "Not enabled"
        case permissionRequired = "Accessibility not granted"
        case processAbsent = "FaceTime not running"
        case available = "Available · no call verified"
        case unsupported = "This FaceTime interface could not be read"
    }

    @Published private(set) var enabled = false
    @Published private(set) var state: State = .disabled
    @Published private(set) var snapshot: FaceTimeAXSnapshot?
    @Published private(set) var supportedEvents: [String] = []
    @Published private(set) var notificationObservedAt: Date?
    var onEnabledChanged: (Bool) -> Void = { _ in }

    private let liveActivities: LiveActivityStore
    let notifications: SystemNotificationMonitor
    private let trusted: () -> Bool
    private let running: () -> NSRunningApplication?
    private var application: AXUIElement?
    private var observer: AXObserver?
    private var processID: pid_t?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var rescan: Task<Void, Never>?
    private var expiration: Task<Void, Never>?
    private let scanQueue = DispatchQueue(label: "DynamicIsland.FaceTimeAX")
    private var generation = 0
    private var scanning = false
    private var scanAgain = false

    init(liveActivities: LiveActivityStore, notifications: SystemNotificationMonitor = SystemNotificationMonitor(),
         trusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         running: @escaping () -> NSRunningApplication? = {
             NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
         }) {
        self.liveActivities = liveActivities
        self.notifications = notifications
        self.trusted = trusted
        self.running = running
        notifications.onRecord = { [weak self] in self?.receive($0) }
    }

    func setEnabled(_ value: Bool) {
        stop()
        enabled = value
        onEnabledChanged(value)
        guard value else { state = .disabled; return }
        notifications.start()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.bundleIdentifier else { return }
                Task { @MainActor [weak self] in self?.checkAgain() }
            })
        }
        checkAgain()
    }

    func stop() {
        enabled = false
        state = .disabled
        rescan?.cancel(); rescan = nil
        expiration?.cancel(); expiration = nil
        notifications.stop()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers = []
        detachObserver()
        snapshot = nil
        notificationObservedAt = nil
        liveActivities.remove(id: Self.notificationActivityID)
    }

    func checkAgain() {
        guard enabled else { return }
        guard trusted() else {
            detachObserver(); snapshot = nil; state = .permissionRequired
            return
        }
        guard let app = running(), app.bundleIdentifier == Self.bundleIdentifier, !app.isTerminated else {
            detachObserver(); snapshot = nil; state = .processAbsent
            return
        }
        if processID != app.processIdentifier {
            detachObserver()
            processID = app.processIdentifier
            let element = AXUIElementCreateApplication(app.processIdentifier)
            application = element
            AXUIElementSetMessagingTimeout(element, 0.05)
            var next: AXObserver?
            if AXObserverCreate(app.processIdentifier, { _, _, _, context in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<FaceTimeAccessibilityProvider>.fromOpaque(context).takeUnretainedValue().scheduleRescan()
                }
            }, &next) == .success, let next {
                observer = next
                for event in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                              kAXUIElementDestroyedNotification, kAXLayoutChangedNotification] {
                    if AXObserverAddNotification(next, element, event as CFString,
                        Unmanaged.passUnretained(self).toOpaque()) == .success {
                        supportedEvents.append(event)
                    }
                }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
            }
        }
        guard application != nil else { return }
        guard !scanning else { scanAgain = true; return }
        scanning = true
        let token = generation
        let pid = app.processIdentifier
        scanQueue.async { @Sendable [weak self] in
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.05)
            let snapshot = Self.inspect(element)
            Task { @MainActor [weak self] in
                guard let self, self.enabled, self.generation == token, self.processID == pid else { return }
                self.scanning = false
                guard self.trusted(), let app = self.running(), app.processIdentifier == pid,
                      app.bundleIdentifier == Self.bundleIdentifier, !app.isTerminated else {
                    self.checkAgain(); return
                }
                self.snapshot = snapshot
                self.state = snapshot.readStatus == AXError.success.rawValue ? .available : .unsupported
                if self.scanAgain { self.scanAgain = false; self.scheduleRescan() }
            }
        }
    }

    /// Notification evidence never establishes a connected, held or ended call.
    func receive(_ record: SystemNotificationRecord) {
        guard enabled, record.bundleIdentifier.lowercased() == Self.bundleIdentifier.lowercased() else { return }
        notificationObservedAt = record.deliveredAt
        liveActivities.update(DynamicIslandLiveActivity(id: Self.notificationActivityID, kind: .call,
            title: "FaceTime notification", subtitle: "Notification observed · open FaceTime", symbolName: "phone.fill",
            priority: 75, isActive: false, progress: nil, updatedAt: record.deliveredAt,
            lifecycle: .init(authority: .integrationAdapter, startEvidence: "FaceTime Notification Center record",
                progressEvidence: nil, completionEvidence: "Notification preview expired, not call end",
                dismissPolicy: .automatic, supportsCancellation: false)))
        scheduleRescan()
        expiration?.cancel()
        expiration = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.liveActivities.remove(id: Self.notificationActivityID)
        }
    }

    func refreshNotificationAccess() {
        if enabled { notifications.start() }
        checkAgain()
    }

    static func openFaceTime() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.open(url)
    }

    private func scheduleRescan() {
        guard enabled, rescan == nil else { return }
        rescan = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            self.rescan = nil
            self.checkAgain()
        }
    }

    private func detachObserver() {
        generation += 1
        scanning = false; scanAgain = false
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            if let application {
                for event in supportedEvents { AXObserverRemoveNotification(observer, application, event as CFString) }
            }
        }
        observer = nil; application = nil; processID = nil; supportedEvents = []
    }

    nonisolated static func inspect(_ application: AXUIElement) -> FaceTimeAXSnapshot {
        var expectedPID: pid_t = 0
        guard AXUIElementGetPid(application, &expectedPID) == .success else {
            return .init(nodes: [], readStatus: AXError.invalidUIElement.rawValue, truncated: false)
        }
        var windowCount: CFIndex = 0
        let countStatus = AXUIElementGetAttributeValueCount(application, kAXWindowsAttribute as CFString, &windowCount)
        guard countStatus == .success else { return .init(nodes: [], readStatus: countStatus.rawValue, truncated: false) }
        var windows: CFArray?
        let status = windowCount == 0 ? AXError.success
            : AXUIElementCopyAttributeValues(application, kAXWindowsAttribute as CFString, 0, min(windowCount, 8), &windows)
        var nodes: [FaceTimeAXNode] = []
        var truncated = windowCount > 8
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var output: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &output) == .success ? output : nil
        }
        func walk(_ element: AXUIElement, depth: Int) {
            guard nodes.count < 128, depth < 12, ProcessInfo.processInfo.systemUptime < deadline else {
                truncated = true; return
            }
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success, pid == expectedPID else { return }
            let role = value(element, kAXRoleAttribute) as? String ?? "unknown"
            let subrole = value(element, kAXSubroleAttribute) as? String
            let safeRoles = [kAXWindowRole, kAXSheetRole, kAXGroupRole, kAXButtonRole, kAXCheckBoxRole,
                kAXRadioButtonRole, kAXStaticTextRole, kAXTextFieldRole, kAXImageRole, kAXScrollAreaRole,
                kAXToolbarRole, kAXTableRole, kAXRowRole, kAXMenuButtonRole, kAXPopUpButtonRole]
            let safeSubroles = [kAXStandardWindowSubrole, kAXDialogSubrole, kAXSystemDialogSubrole,
                kAXCloseButtonSubrole, kAXMinimizeButtonSubrole, kAXZoomButtonSubrole]
            let identifier = (value(element, kAXIdentifierAttribute) as? String).map {
                SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined()
            }
            var actions: CFArray?
            _ = AXUIElementCopyActionNames(element, &actions)
            nodes.append(.init(depth: depth, role: safeRoles.contains(role) ? role : "other",
                subrole: subrole.map { safeSubroles.contains($0) ? $0 : "other" }, identifierSHA256: identifier,
                actions: (actions as? [String] ?? []).filter { [kAXPressAction, kAXRaiseAction, kAXCancelAction,
                    kAXConfirmAction, kAXShowMenuAction].contains($0) }, enabled: value(element, kAXEnabledAttribute) as? Bool ?? false))
            var children: CFArray?
            var childCount: CFIndex = 0
            if AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &childCount) == .success {
                let limit = min(childCount, 128 - nodes.count)
                if childCount > limit { truncated = true }
                if limit > 0, AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, limit, &children) == .success {
                    for child in children as? [AXUIElement] ?? [] { walk(child, depth: depth + 1) }
                }
            }
        }
        var windowElements = windows as? [AXUIElement] ?? []
        // FaceTime 36 exposes its Catalyst window in AXChildren while AXWindows is empty.
        if windowCount == 0 {
            var count: CFIndex = 0
            var children: CFArray?
            if AXUIElementGetAttributeValueCount(application, kAXChildrenAttribute as CFString, &count) == .success,
               count > 0, AXUIElementCopyAttributeValues(application, kAXChildrenAttribute as CFString, 0, min(count, 8), &children) == .success {
                windowElements = (children as? [AXUIElement] ?? []).filter { value($0, kAXRoleAttribute) as? String == kAXWindowRole }
                if count > 8 { truncated = true }
            }
        }
        for window in windowElements { walk(window, depth: 0) }
        return .init(nodes: nodes, readStatus: status.rawValue, truncated: truncated)
    }
}
