import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let settings: AppSettings
    private let islandState: IslandStateStore
    private let modules: IslandModules
    private let geometryService: NotchGeometryService
    private let layoutStore = IslandLayoutStore()
    private let panel: IslandOverlayPanel
    private let collapsedHitPanel: IslandOverlayPanel
    private let expandedPanel: IslandOverlayPanel
    private var cancellables: Set<AnyCancellable> = []
    private var mouseContainmentTimer: Timer?
    private var localMouseDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var localMouseMovedMonitor: Any?
    private var globalMouseMovedMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var targetCollapsedFrame: NSRect?
    private var targetExpandedFrame: NSRect?
    private var expandedAt: CFTimeInterval = 0
    #if DEBUG
    private var lastCollapseDebugLogAt: CFTimeInterval = 0
    #endif
    private weak var hostingView: IslandHostingView<IslandRootView>?

    init(
        settings: AppSettings,
        islandState: IslandStateStore,
        modules: IslandModules,
        geometryService: NotchGeometryService
    ) {
        self.settings = settings
        self.islandState = islandState
        self.modules = modules
        self.geometryService = geometryService
        #if DEBUG
        debugPrint(
            "DynamicIsland OverlayWindowController init",
            "mediaInstance=\(ObjectIdentifier(modules.media))"
        )
        #endif

        panel = IslandOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        collapsedHitPanel = IslandOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        expandedPanel = IslandOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        Self.configure(panel)
        Self.configure(collapsedHitPanel)
        Self.configure(expandedPanel)
        panel.ignoresMouseEvents = true

        let rootView = IslandRootView(
            settings: settings,
            islandState: islandState,
            layoutStore: layoutStore,
            modules: modules
        )
        let hostingView = IslandHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.onMouseExited = { [weak self] in
            self?.collapseIfExpandedMouseOutsideAfterGrace()
        }
        panel.contentView = hostingView
        self.hostingView = hostingView

        let collapsedHitView = CollapsedHitView()
        collapsedHitView.onMouseDown = { [weak islandState] in
            guard islandState?.state == .collapsed else { return }
            islandState?.toggleExpanded()
        }
        collapsedHitView.onFileDragEntered = { [weak islandState, weak navigation = modules.navigation] in
            guard islandState?.state == .collapsed else { return }
            navigation?.showTrayForFileDrag()
            islandState?.expand()
        }
        collapsedHitView.onFileDragExited = { [weak islandState, weak navigation = modules.navigation] in
            // If entering the collapsed pill expanded the island, AppKit can send a synthetic
            // exit/end to the collapsed drag view as it is ordered out. Do not clear the Tray
            // highlight in that handoff; the expanded SwiftUI drop destination now owns the
            // target state until the drag leaves, drops, or cancels.
            guard islandState?.state == .collapsed else { return }
            navigation?.setFileDropTargeted(false)
        }
        collapsedHitView.onFileDrop = { [weak fileShelf = modules.fileShelf, weak navigation = modules.navigation] urls in
            fileShelf?.add(urls)
            navigation?.setFileDropTargeted(false)
        }
        collapsedHitPanel.contentView = collapsedHitView

        let expandedHostingView = IslandHostingView(
            rootView: ExpandedIslandPanelView(modules: modules, islandState: islandState)
        )
        expandedHostingView.autoresizingMask = [.width, .height]
        expandedHostingView.wantsLayer = true
        expandedHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        expandedHostingView.onMouseExited = { [weak self] in
            self?.collapseIfExpandedMouseOutsideAfterGrace()
        }
        expandedPanel.contentView = expandedHostingView

        islandState.$state
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let state = self.islandState.state
                    self.debugLog("state committed as \(state)")
                    self.debugLog("state changed to \(state)")
                    if state == .expanded {
                        self.expandedAt = CACurrentMediaTime()
                        self.debugLog("expandedAt set to \(self.expandedAt)")
                        self.startMouseContainmentTimer()
                    } else {
                        self.stopMouseContainmentTimer()
                    }
                    self.reposition(animated: true)
                    self.updateWindowVisibility()
                }
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setVisible(self.settings.overlayEnabled)
                    self.reposition(animated: false)
                }
            }
            .store(in: &cancellables)

        modules.media.$hasActiveMediaSource
            .removeDuplicates()
            .sink { [weak self] hasActiveMediaSource in
                DispatchQueue.main.async {
                    #if DEBUG
                    debugPrint(
                        "DynamicIsland Overlay media active changed",
                        "hasActiveMediaSource=\(hasActiveMediaSource)",
                        "mediaInstance=\(ObjectIdentifier(modules.media))"
                    )
                    #endif
                    self?.reposition(animated: true)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.reposition(animated: false)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.reposition(animated: false)
            }
            .store(in: &cancellables)

        installMouseDownMonitors()
    }

    func show() {
        islandState.collapse()
        reposition(animated: false)
        updateWindowVisibility()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else {
            panel.orderOut(nil)
            collapsedHitPanel.orderOut(nil)
            expandedPanel.orderOut(nil)
        }
        if !visible {
            stopMouseContainmentTimer()
        }
    }

    func reposition(animated: Bool = false) {
        let geometry = geometryService.geometry(
            collapsedSize: settings.collapsedSize,
            expandedSize: settings.expandedSize,
            collapsedMediaActive: modules.media.hasActiveMediaSource
        )
        layoutStore.update(canvas: geometry.canvas)
        targetCollapsedFrame = geometry.collapsedFrame
        targetExpandedFrame = geometry.expandedFrame
        applyFrame(geometry.canvas.frame, to: panel)
        applyFrame(geometry.collapsedFrame, to: collapsedHitPanel)
        applyFrame(geometry.expandedFrame, to: expandedPanel)
        hostingView?.needsLayout = true
        updateWindowVisibility()

        updateMouseContainmentTimer()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let correctedGeometry = self.geometryService.geometry(
                collapsedSize: self.settings.collapsedSize,
                expandedSize: self.settings.expandedSize,
                collapsedMediaActive: self.modules.media.hasActiveMediaSource
            )
            if !animated {
                self.layoutStore.update(canvas: correctedGeometry.canvas)
                self.targetCollapsedFrame = correctedGeometry.collapsedFrame
                self.targetExpandedFrame = correctedGeometry.expandedFrame
                self.applyFrame(correctedGeometry.canvas.frame, to: self.panel)
                self.applyFrame(correctedGeometry.collapsedFrame, to: self.collapsedHitPanel)
                self.applyFrame(correctedGeometry.expandedFrame, to: self.expandedPanel)
                self.hostingView?.needsLayout = true
                self.updateWindowVisibility()
            }
        }
    }

    private static func configure(_ panel: IslandOverlayPanel) {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.sharingType = .readOnly
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
    }

    private func applyFrame(_ frame: NSRect, to panel: IslandOverlayPanel) {
        guard frame != .zero else { return }
        panel.animations.removeAll()
        panel.disableScreenUpdatesUntilFlush()
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func updateWindowVisibility() {
        panel.ignoresMouseEvents = true

        switch islandState.state {
        case .collapsed:
            debugLog("updateWindowVisibility received collapsed")
            expandedPanel.orderOut(nil)
            collapsedHitPanel.ignoresMouseEvents = false
            collapsedHitPanel.orderFrontRegardless()
            panel.orderFrontRegardless()
            collapsedHitPanel.orderFrontRegardless()
            stopMouseContainmentTimer()
        case .expanded:
            collapsedHitPanel.orderOut(nil)
            panel.orderOut(nil)
            expandedPanel.ignoresMouseEvents = false
            expandedPanel.makeKeyAndOrderFront(nil)
            startMouseContainmentTimer()
        }
    }

    private func updateMouseContainmentTimer() {
        switch islandState.state {
        case .collapsed:
            stopMouseContainmentTimer()
        case .expanded:
            startMouseContainmentTimer()
        }
    }

    private func startMouseContainmentTimer() {
        guard mouseContainmentTimer == nil else {
            debugLog("timer start skipped; already running")
            return
        }
        debugLog("timer started")
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.debugLog("timer fired state=\(self?.islandState.state.rawValue ?? "nil") mouse=\(String(describing: self?.currentMouseScreenLocation()))")
                self?.collapseIfExpandedMouseOutsideAfterGrace(source: "timer")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseContainmentTimer = timer
    }

    private func stopMouseContainmentTimer() {
        if mouseContainmentTimer != nil {
            debugLog("timer stopped")
        }
        mouseContainmentTimer?.invalidate()
        mouseContainmentTimer = nil
    }

    private func installMouseDownMonitors() {
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.expandIfCollapsedClick(at: NSEvent.mouseLocation) ? nil : event
        }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                _ = self?.expandIfCollapsedClick(at: NSEvent.mouseLocation)
            }
        }

        localMouseMovedMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.collapseIfExpandedMouseOutsideAfterGrace(source: "localMouseMonitor")
            return event
        }

        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.collapseIfExpandedMouseOutsideAfterGrace(source: "globalMouseMonitor")
            }
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == 53, self.islandState.state == .expanded else {
                return event
            }
            self.debugLog("Escape pressed while expanded; calling collapse")
            self.stopMouseContainmentTimer()
            self.islandState.collapse()
            return nil
        }
    }

    private func expandIfCollapsedClick(at screenPoint: NSPoint) -> Bool {
        guard islandState.state == .collapsed,
              let targetCollapsedFrame,
              targetCollapsedFrame.insetBy(dx: -4, dy: -4).contains(screenPoint) else {
            return false
        }
        islandState.toggleExpanded()
        return true
    }

    private func currentMouseScreenLocation() -> NSPoint {
        NSEvent.mouseLocation
    }

    private func collapseIfExpandedMouseOutsideAfterGrace(source: String = "event") {
        debugLog("collapse check entered source=\(source) state=\(islandState.state)")
        guard islandState.state == .expanded else {
            debugLog("collapse check ignored; state is not expanded")
            return
        }
        let elapsedSinceExpansion = CACurrentMediaTime() - expandedAt
        guard elapsedSinceExpansion >= 0.18 else {
            debugLog("collapse check grace failed elapsed=\(elapsedSinceExpansion)")
            return
        }
        debugLog("collapse check grace passed elapsed=\(elapsedSinceExpansion)")

        let mouseLocation = currentMouseScreenLocation()
        let canonicalFrame = targetExpandedFrame ?? expandedPanel.frame
        let paddedExpandedFrame = canonicalFrame.insetBy(dx: -10, dy: -10)
        let containsMouse = paddedExpandedFrame.contains(mouseLocation)
        logCollapseBoundaryCheck(
            source: source,
            mouseLocation: mouseLocation,
            canonicalFrame: canonicalFrame,
            paddedFrame: paddedExpandedFrame,
            containsMouse: containsMouse
        )
        debugLog("collapse hover contains=\(containsMouse)")

        if source == "timer", isMouseFarBelowTop(mouseLocation) {
            debugLog("timer hard test triggered; mouse is more than 350px below screen top; calling collapse")
            stopMouseContainmentTimer()
            islandState.collapse()
            return
        }

        if !containsMouse {
            debugLog("mouse outside padded hover rect; calling collapse")
            stopMouseContainmentTimer()
            islandState.collapse()
        }
    }

    private func isMouseFarBelowTop(_ mouseLocation: NSPoint) -> Bool {
        let screenTop = targetExpandedFrame?.maxY ?? expandedPanel.frame.maxY
        return screenTop - mouseLocation.y > 350
    }

    private func logCollapseBoundaryCheck(
        source: String,
        mouseLocation: NSPoint,
        canonicalFrame: NSRect,
        paddedFrame: NSRect,
        containsMouse: Bool
    ) {
        #if DEBUG
        let now = CACurrentMediaTime()
        guard !containsMouse || now - lastCollapseDebugLogAt >= 0.35 else {
            return
        }
        lastCollapseDebugLogAt = now
        debugPrint(
            "DynamicIsland collapse check",
            "source=\(source)",
            "state=\(islandState.state)",
            "mouseLocation=\(mouseLocation)",
            "expandedPanel.frame=\(expandedPanel.frame)",
            "targetExpandedFrame=\(String(describing: targetExpandedFrame))",
            "canonicalFrame=\(canonicalFrame)",
            "paddedFrame=\(paddedFrame)",
            "contains=\(containsMouse)"
        )
        #endif
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        let line = "DynamicIsland DEBUG \(Date()) \(message)"
        debugPrint(line)
        guard let data = "\(line)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/dynamicisland-debug.log")
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
            _ = try? handle.close()
        } else {
            try? data.write(to: url)
        }
        #endif
    }
}

private final class IslandOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onMouseExited: (() -> Void)?
    private var trackingAreaReference: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
        super.mouseExited(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class CollapsedHitView: NSView {
    var onMouseDown: (() -> Void)?
    var onFileDragEntered: (() -> Void)?
    var onFileDragExited: (() -> Void)?
    var onFileDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.supportedDragTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(Self.supportedDragTypes)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(sender.draggingPasteboard) else { return [] }
        onFileDragEntered?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasFileURLs(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onFileDragExited?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onFileDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else {
            onFileDragExited?()
            return false
        }
        onFileDrop?(urls)
        return true
    }

    private func hasFileURLs(_ pasteboard: NSPasteboard) -> Bool {
        !fileURLs(from: pasteboard).isEmpty
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }

        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        guard let filenames = pasteboard.propertyList(forType: filenamesType) as? [String] else {
            return []
        }
        return filenames.map(URL.init(fileURLWithPath:))
    }

    private static let supportedDragTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType("NSFilenamesPboardType")
    ]
}

private struct ExpandedIslandPanelView: View {
    let modules: IslandModules
    @ObservedObject var islandState: IslandStateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shellVisible = false
    @State private var shellGeneration = 0

    var body: some View {
        IslandSurface(isExpanded: true) {
            ExpandedIslandView(
                modules: modules,
                isPresented: islandState.state == .expanded,
                onShortcutLaunched: { islandState.collapse() }
            )
        }
        .scaleEffect(shellVisible ? 1.0 : 0.72, anchor: .top)
        .blur(radius: shellVisible ? 0 : 12)
        .opacity(shellVisible ? 1 : 0)
        .animation(shellAnimation, value: shellVisible)
        .onAppear {
            updateShellPresentation(islandState.state == .expanded)
        }
        .onChange(of: islandState.state) { _, newState in
            updateShellPresentation(newState == .expanded)
        }
    }

    private var shellAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.18)
        }

        return .spring(
            response: 0.72,
            dampingFraction: 0.58,
            blendDuration: 0.08
        )
    }

    private func updateShellPresentation(_ presented: Bool) {
        shellGeneration += 1
        let generation = shellGeneration

        if presented {
            shellVisible = false

            DispatchQueue.main.async {
                guard generation == shellGeneration, islandState.state == .expanded else {
                    return
                }

                shellVisible = true
            }
        } else {
            shellVisible = false
        }
    }
}
