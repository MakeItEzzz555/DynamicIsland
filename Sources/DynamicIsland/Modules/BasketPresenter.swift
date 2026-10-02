import AppKit
import Combine
import SwiftUI

/// Exact ownership for asynchronous drops started from the multi-Basket
/// switcher. Multiple file promises may materialize concurrently, so resolving
/// one claim must never release another Basket's `.dropInFlight` hold.
struct BasketSwitcherClaimRegistry {
    private var targets: [Int: UUID] = [:]

    var isEmpty: Bool { targets.isEmpty }

    mutating func insert(_ claim: Int, target: UUID) {
        targets[claim] = target
    }

    mutating func remove(_ claim: Int) -> UUID? {
        targets.removeValue(forKey: claim)
    }
}

/// Composition of the Floating Basket feature: drag monitor → jiggle
/// decision → basket windows, plus menus, quick actions, drag-out
/// retention and auto-hide timing. All content mutations go through
/// BasketManager; all file actions reuse existing DynamicIsland authorities.
@MainActor
final class BasketPresenter: ObservableObject {
    let manager: BasketManager
    private let settings: AppSettings
    private let fileShelf: FileShelfStore
    private let backgroundRemoval: BackgroundRemovalController?
    private let executor: FileDragActionExecutor
    private var monitor: BasketDragMonitor!
    private let switcher = BasketSwitcherWindowController()
    private var controllers: [UUID: FloatingBasketWindowController] = [:]
    private var basketObservers: [UUID: AnyCancellable] = [:]
    private var autoHideWork: [UUID: DispatchWorkItem] = [:]
    private var activeDragOuts: [UUID: (basket: UUID, urls: [URL])] = [:]
    private var pendingQuickDrops: Set<Int> = []
    private var nextQuickDrop = 0
    private var switcherClaims = BasketSwitcherClaimRegistry()
    private var cancellables: Set<AnyCancellable> = []

    init(
        manager: BasketManager,
        settings: AppSettings,
        fileShelf: FileShelfStore,
        backgroundRemoval: BackgroundRemovalController?,
        executor: FileDragActionExecutor = .production,
        probe: BasketDragProbe = SystemBasketDragProbe()
    ) {
        self.manager = manager
        self.settings = settings
        self.fileShelf = fileShelf
        self.backgroundRemoval = backgroundRemoval
        self.executor = executor
        monitor = BasketDragMonitor(
            probe: probe,
            sensitivity: { [weak settings] in settings?.basketJiggleSensitivity ?? 3 },
            onJiggle: { [weak self] _, location in self?.handleJiggle(at: location) },
            onDragEnded: { [weak self] _ in self?.handleDragEnded() }
        )
        monitor.isSuppressed = { [weak self] in !(self?.activeDragOuts.isEmpty ?? true) }
    }

    func start() {
        settings.$floatingBasketEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    monitor.start()
                } else {
                    monitor.stop()
                    switcher.hide()
                    for id in manager.baskets.map(\.id) { closeBasket(id) }
                }
            }
            .store(in: &cancellables)
        manager.$baskets
            .sink { [weak self] baskets in
                DispatchQueue.main.async { self?.sync(with: baskets.map(\.id)) }
            }
            .store(in: &cancellables)
        monitor.$isDragging
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.evaluateAllAutoHide() }
            }
            .store(in: &cancellables)
        Publishers.CombineLatest(settings.$basketAutoHideEnabled, settings.$basketAutoHideDelay)
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.evaluateAllAutoHide() } }
            .store(in: &cancellables)
    }

    func stop() {
        monitor.stop()
        switcher.hide()
        controllers.values.forEach { $0.panel.orderOut(nil) }
    }

    /// Recovery for auto-hidden baskets (menu bar item).
    var hiddenBasketCount: Int { manager.hiddenBasketsWithItems.count }

    func revealHiddenBaskets() {
        reveal(manager.hiddenBasketsWithItems, around: NSEvent.mouseLocation)
    }

    /// Shelf → Basket ("Move to Basket"): frontmost visible basket, else a
    /// new one near the pointer. App-surface transfer only.
    func moveShelfFilesToBasket(_ urls: [URL]) {
        guard let basket = manager.visibleBaskets.last ?? manager.createBasket() else { return }
        manager.moveFromShelf(urls, to: basket.id)
        present(basket, near: NSEvent.mouseLocation, atLastPosition: true)
    }

    /// Clipboard → Basket copies stable original files into a basket without
    /// mutating Shelf ownership. Missing/non-file URLs are rejected by the manager.
    func addClipboardFilesToBasket(_ urls: [URL]) {
        guard let basket = manager.visibleBaskets.last ?? manager.createBasket() else { return }
        let accepted = manager.add(urls, to: basket.id)
        guard !accepted.isEmpty else { return }
        present(basket, near: NSEvent.mouseLocation, atLastPosition: true)
    }

    // MARK: Jiggle

    private func handleJiggle(at pointer: CGPoint) {
        switch manager.resolveJiggle() {
        case .none:
            break
        case .show(let basket):
            present(basket, near: pointer, atLastPosition: false)
        case .reveal(let baskets, let thenSwitcher):
            reveal(baskets, around: pointer)
            if thenSwitcher {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, self.monitor.isDragging, self.manager.visibleBaskets.count >= 2 else { return }
                    self.showSwitcher(self.manager.visibleBaskets, at: pointer)
                }
            }
        case .switcher(let baskets):
            showSwitcher(baskets, at: pointer)
        }
    }

    private func handleDragEnded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.monitor.isDragging, self.switcherClaims.isEmpty else { return }
            self.switcher.hide()
        }
        evaluateAllAutoHide()
    }

    /// Droppy staggers revealed baskets side by side around the pointer.
    private func reveal(_ baskets: [BasketState], around pointer: CGPoint) {
        let width: CGFloat = 220, spacing: CGFloat = 20
        let total = CGFloat(baskets.count) * width + CGFloat(max(baskets.count - 1, 0)) * spacing
        for (index, basket) in baskets.enumerated() {
            let x = pointer.x - total / 2 + CGFloat(index) * (width + spacing) + width / 2
            present(basket, near: CGPoint(x: x, y: pointer.y), atLastPosition: basket.lastOrigin != nil)
        }
    }

    private func present(_ basket: BasketState, near pointer: CGPoint, atLastPosition: Bool) {
        let controller = controller(for: basket)
        if atLastPosition {
            controller.presentAtLastPosition(fallback: pointer)
        } else {
            controller.present(near: pointer)
        }
        manager.setVisible(basket.id, true)
    }

    // MARK: Windows

    private func controller(for basket: BasketState) -> FloatingBasketWindowController {
        if let existing = controllers[basket.id] { return existing }
        let id = basket.id
        let controller = FloatingBasketWindowController(state: basket) { [unowned self] presentation in
            AnyView(FloatingBasketRootView(manager: manager, settings: settings, presentation: presentation,
                                           state: basket, actions: actions(for: id)))
        }
        let drop = controller.dropTarget
        drop.onTargetingChanged = { [weak basket] targeted in
            DispatchQueue.main.async {
                basket?.isTargeted = targeted
                basket?.setHold(.externalDrag, targeted)
            }
        }
        drop.onDropStarted = { [weak self, weak basket] in
            guard let claim = self?.manager.claimDrop(into: id) else { return nil }
            basket?.setHold(.dropInFlight, true)
            return claim
        }
        drop.onFilesReceived = { [weak self, weak basket] claim, urls in
            self?.manager.completeDrop(claim, urls: urls)
            basket?.setHold(.dropInFlight, false)
        }
        drop.onMaterializationFailed = { [weak self, weak basket] claim, _ in
            self?.manager.failDrop(claim)
            basket?.setHold(.dropInFlight, false)
        }
        controller.panel.onKeyDown = { [weak self] event in self?.handleKey(event, basket: id) ?? false }
        controllers[id] = controller
        basketObservers[id] = Publishers.Merge3(
            basket.$holds.map { _ in () },
            basket.$items.map { _ in () },
            basket.$isVisible.map { _ in () }
        )
        .sink { [weak self] in DispatchQueue.main.async { self?.evaluateAutoHide(id) } }
        return controller
    }

    private func sync(with ids: [UUID]) {
        for id in controllers.keys where !ids.contains(id) {
            let controller = controllers.removeValue(forKey: id)
            basketObservers[id] = nil
            autoHideWork.removeValue(forKey: id)?.cancel()
            controller?.dismiss {}
        }
    }

    private func hideBasket(_ id: UUID) {
        guard let controller = controllers[id] else { return }
        controller.dismiss { [weak self] in self?.manager.setVisible(id, false) }
    }

    private func closeBasket(_ id: UUID) {
        autoHideWork.removeValue(forKey: id)?.cancel()
        if let controller = controllers[id] {
            controller.dismiss { [weak self] in self?.manager.close(id) }
        } else {
            manager.close(id)
        }
    }

    // MARK: Auto-hide (owner-scoped holds; Droppy 0.3 s drop grace)

    private func evaluateAllAutoHide() {
        manager.baskets.map(\.id).forEach(evaluateAutoHide)
    }

    private func evaluateAutoHide(_ id: UUID) {
        guard let basket = manager.basket(id) else { return }
        let decision = BasketAutoHidePolicy.decide(
            isEmpty: basket.items.isEmpty, isVisible: basket.isVisible, holds: basket.holds,
            autoHideEnabled: settings.basketAutoHideEnabled, delay: settings.basketAutoHideDelay,
            externalDragActive: monitor.isDragging || switcher.isVisible
        )
        autoHideWork.removeValue(forKey: id)?.cancel()
        let delay: TimeInterval
        switch decision {
        case .keep: return
        case .close: delay = 0.3
        case .hide(let after): delay = after
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let basket = self.manager.basket(id) else { return }
            let current = BasketAutoHidePolicy.decide(
                isEmpty: basket.items.isEmpty, isVisible: basket.isVisible, holds: basket.holds,
                autoHideEnabled: self.settings.basketAutoHideEnabled, delay: self.settings.basketAutoHideDelay,
                externalDragActive: self.monitor.isDragging || self.switcher.isVisible
            )
            switch current {
            case .keep: break
            case .close: self.closeBasket(id)
            case .hide: self.hideBasket(id)
            }
        }
        autoHideWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Switcher

    private func showSwitcher(_ baskets: [BasketState], at pointer: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let actions = BasketSwitcherActions(
            dropStarted: { [weak self] basketID in
                guard let self else { return nil }
                guard let target = basketID.flatMap(self.manager.basket) ?? self.manager.createBasket() else { return nil }
                guard let claim = self.manager.claimDrop(into: target.id) else { return nil }
                target.setHold(.dropInFlight, true)
                self.switcherClaims.insert(claim, target: target.id)
                self.switcher.hide()
                self.present(target, near: pointer, atLastPosition: target.isVisible || target.lastOrigin != nil)
                return claim
            },
            dropFinished: { [weak self] claim, urls in
                guard let self, let targetID = self.switcherClaims.remove(claim) else { return }
                _ = self.manager.completeDrop(claim, urls: urls)
                self.manager.basket(targetID)?.setHold(.dropInFlight, false)
            },
            dropFailed: { [weak self] claim, _ in
                guard let self, let targetID = self.switcherClaims.remove(claim) else { return }
                self.manager.failDrop(claim)
                self.manager.basket(targetID)?.setHold(.dropInFlight, false)
            },
            dismiss: { [weak self] in self?.switcher.hide() },
            isInteractive: true
        )
        switcher.show(baskets: baskets, on: screen, actions: actions)
    }

    // MARK: View actions

    private func actions(for id: UUID) -> BasketViewActions {
        var actions = BasketViewActions()
        actions.isInteractive = true
        actions.close = { [weak self] in self?.closeBasket(id) }
        actions.hide = { [weak self] in self?.hideBasket(id) }
        actions.basketMenu = { [weak self] view in self?.showBasketMenu(id, anchor: view) }
        actions.itemMenu = { [weak self] itemID, event, view in self?.showItemMenu(itemID, basket: id, event: event, view: view) }
        actions.open = { [weak self] itemID in
            guard let basket = self?.manager.basket(id) else { return }
            basket.actionTargets(for: itemID).forEach { FileShelfActions.open($0.url) }
        }
        actions.remove = { [weak self] itemID in
            guard let self, let basket = manager.basket(id) else { return }
            manager.remove(Set(basket.actionTargets(for: itemID).map(\.id)), from: id)
        }
        actions.dragOutBegan = { [weak self] urls in self?.beginDragOut(urls, basket: id) }
        actions.dragOutEnded = { [weak self] token in self?.endDragOut(token) }
        actions.performQuickAction = { [weak self] action, anchor in
            guard let self, let basket = manager.basket(id) else { return }
            let targets = basket.selection.isEmpty ? basket.urls : basket.items.filter { basket.selection.contains($0.id) }.map(\.url)
            _ = executor.perform(action, urls: targets, anchor: anchor)
        }
        actions.quickActionDropStarted = { [weak self] in
            guard let self else { return nil }
            nextQuickDrop &+= 1
            pendingQuickDrops.insert(nextQuickDrop)
            return nextQuickDrop
        }
        actions.quickActionDropFinished = { [weak self] action, claim, urls, anchor in
            guard let self, pendingQuickDrops.remove(claim) != nil else { return }
            let outcome = executor.perform(action, urls: urls, anchor: anchor)
            // Only freshly materialized promise files nobody owns are cleaned.
            let unowned = urls.filter { manager.ownership.owners(of: $0).isEmpty }
            if outcome == .handedOff {
                FileDragPromiseStorage.shared.scheduleCleanup(unowned)
            } else {
                FileDragPromiseStorage.shared.removeIfOwned(unowned)
            }
        }
        actions.quickActionDropFailed = { [weak self] claim, _ in self?.pendingQuickDrops.remove(claim) }
        return actions
    }

    private func beginDragOut(_ urls: [URL], basket id: UUID) -> UUID {
        let token = UUID()
        manager.ownership.retain(urls, by: .dragOut(token))
        activeDragOuts[token] = (id, urls)
        manager.basket(id)?.setHold(.dragOut, true)
        return token
    }

    private func endDragOut(_ token: UUID?) {
        guard let token, let entry = activeDragOuts.removeValue(forKey: token) else { return }
        if !activeDragOuts.values.contains(where: { $0.basket == entry.basket }) {
            manager.basket(entry.basket)?.setHold(.dragOut, false)
        }
        manager.ownership.release(entry.urls, by: .dragOut(token))
    }

    private func handleKey(_ event: NSEvent, basket id: UUID) -> Bool {
        guard let basket = manager.basket(id) else { return false }
        let command = event.modifierFlags.contains(.command)
        switch (event.keyCode, command) {
        case (0, true): // ⌘A
            basket.selectAll()
            return true
        case (49, false): // Space → Quick Look
            let urls = basket.selection.isEmpty ? basket.urls : basket.items.filter { basket.selection.contains($0.id) }.map(\.url)
            return FileShelfQuickLookController.shared.preview(urls)
        case (53, false): // Escape
            if basket.isExpanded { basket.isExpanded = false; return true }
            return false
        case (51, true), (117, false): // ⌘⌫ / Forward Delete
            guard !basket.selection.isEmpty else { return false }
            manager.remove(basket.selection, from: id)
            return true
        default:
            return false
        }
    }

    // MARK: Menus (native NSMenu, owner-held for exactly the tracking loop)

    private func popUp(_ menu: NSMenu, basket id: UUID, event: NSEvent?, view: NSView) {
        let basket = manager.basket(id)
        menu.autoenablesItems = false
        basket?.setHold(.nativeMenu, true)
        defer { basket?.setHold(.nativeMenu, false) }
        if let event {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
        }
    }

    private func showBasketMenu(_ id: UUID, anchor view: NSView) {
        guard let basket = manager.basket(id), !basket.items.isEmpty else { return }
        let menu = NSMenu()
        let urls = basket.urls
        menu.add("Show in Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        menu.add("Quick Look", "eye") { FileShelfQuickLookController.shared.preview(urls) }
        menu.addItem(.separator())
        menu.add("AirDrop", "person.2.wave.2") { _ = AirDropService.share(urls: urls, fallbackRevealInFinder: false) }
        menu.add("Share…", "square.and.arrow.up") { [weak self] in self?.share(urls, basket: id, anchor: view) }
        menu.add("Copy File Paths", "doc.on.doc") { Self.copyStrings(urls.map(\.path)) }
        if settings.fileShelfEnabled {
            menu.add("Move All to Shelf", "arrow.up.to.line") { [weak self] in
                self?.manager.moveToShelf(Set(basket.items.map(\.id)), from: id)
            }
        }
        menu.addItem(.separator())
        menu.add("Clear Basket", "trash") { [weak self] in self?.closeBasket(id) }
        popUp(menu, basket: id, event: NSApp.currentEvent?.type == .rightMouseDown ? NSApp.currentEvent : nil, view: view)
    }

    private func showItemMenu(_ itemID: UUID, basket id: UUID, event: NSEvent, view: NSView) {
        guard let basket = manager.basket(id) else { return }
        let targets = basket.actionTargets(for: itemID)
        guard !targets.isEmpty else { return }
        let urls = targets.map(\.url)
        let ids = Set(targets.map(\.id))
        let suffix = targets.count > 1 ? " (\(targets.count))" : ""
        let menu = NSMenu()

        menu.add("Open", "arrow.up.forward.square") { urls.forEach { FileShelfActions.open($0) } }
        menu.add("Reveal in Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        menu.add("Quick Look", "eye") { FileShelfQuickLookController.shared.preview(urls) }
        menu.addItem(.separator())
        menu.add("Copy", "doc.on.doc") { _ = FileShelfActions.copyFiles(urls) }
        menu.add("Copy Path", "link") { Self.copyStrings(urls.map(\.path)) }
        menu.add("Copy File Name", "textformat") { Self.copyStrings(urls.map(\.lastPathComponent)) }
        menu.addItem(.separator())
        menu.add("Share…", "square.and.arrow.up") { [weak self] in self?.share(urls, basket: id, anchor: view) }
        menu.add("AirDrop", "person.2.wave.2") { _ = AirDropService.share(urls: urls, fallbackRevealInFinder: false) }

        // Real local operations only: ImageIO convert, Vision background
        // removal, ditto ZIP via BackgroundOperationController.
        var operations: [NSMenuItem] = []
        if targets.count == 1, let source = targets.first?.url {
            let formats = FileConversionController.targetFormats(for: source)
            if !formats.isEmpty {
                let convert = NSMenuItem(title: "Convert to", action: nil, keyEquivalent: "")
                convert.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
                let submenu = NSMenu()
                for format in formats {
                    submenu.add(format.displayName, nil) { [weak self] in self?.convert(source, to: format, basket: id) }
                }
                convert.submenu = submenu
                operations.append(convert)
            }
            if let backgroundRemoval, backgroundRemoval.isEnabled, FileTrayActionTargets.isImage(source) {
                operations.append(NSMenuItem.closure("Remove Background", "person.crop.rectangle", enabled: !backgroundRemoval.isProcessing) { [weak self] in
                    self?.removeBackground(source, basket: id)
                })
            }
        }
        operations.append(NSMenuItem.closure("Compress\(suffix)", "archivebox") { [weak self] in
            self?.manager.compress(ids, in: id)
        })
        menu.addItem(.separator())
        operations.forEach(menu.addItem)

        menu.addItem(.separator())
        if targets.count == 1 {
            menu.add("Rename…", "pencil") { [weak self] in self?.rename(itemID, basket: id) }
        }
        if settings.fileShelfEnabled {
            menu.add("Move to Shelf\(suffix)", "arrow.up.to.line") { [weak self] in
                self?.manager.moveToShelf(ids, from: id)
            }
        }
        let others = manager.baskets.filter { $0.id != id }
        if !others.isEmpty {
            let move = NSMenuItem(title: "Move to Basket", action: nil, keyEquivalent: "")
            move.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil)
            let submenu = NSMenu()
            for other in others {
                submenu.add("\(other.accent.name) Basket · \(other.titleText)", nil) { [weak self] in
                    guard let self else { return }
                    manager.transfer(ids, from: id, to: other.id)
                    if !other.isVisible { present(other, near: NSEvent.mouseLocation, atLastPosition: true) }
                }
            }
            move.submenu = submenu
            menu.addItem(move)
        }
        menu.addItem(.separator())
        menu.add("Remove from Basket\(suffix)", "xmark") { [weak self] in self?.manager.remove(ids, from: id) }

        popUp(menu, basket: id, event: event, view: view)
    }

    private static func copyStrings(_ values: [String]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(values.joined(separator: "\n"), forType: .string)
    }

    private func share(_ urls: [URL], basket id: UUID, anchor view: NSView) {
        let picker = NSSharingServicePicker(items: urls)
        let delegate = BasketSharePickerDelegate { [weak self] in
            self?.manager.basket(id)?.setHold(.modal, false)
        }
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &BasketSharePickerDelegate.key, delegate, .OBJC_ASSOCIATION_RETAIN)
        manager.basket(id)?.setHold(.modal, true)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private func convert(_ source: URL, to format: FileConversionFormat, basket id: UUID) {
        Task { @MainActor [weak self] in
            guard let output = try? await FileConversionController.convert(source, to: format) else { return }
            self?.manager.add([output], to: id)
        }
    }

    private func removeBackground(_ source: URL, basket id: UUID) {
        try? backgroundRemoval?.process(imageURL: source, deliverResult: { [weak self] urls in
            guard let self else { return }
            if manager.add(urls, to: id).isEmpty { manager.ownership.discardIfUnowned(urls) }
        })
    }

    private func rename(_ itemID: UUID, basket id: UUID) {
        guard let item = manager.basket(id)?.items.first(where: { $0.id == itemID }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Renames the file on disk."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: item.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let basket = manager.basket(id)
        basket?.setHold(.modal, true)
        defer { basket?.setHold(.modal, false) }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try manager.rename(itemID, in: id, to: field.stringValue)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

private final class BasketSharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    nonisolated(unsafe) static var key: UInt8 = 0
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onFinish()
    }
}

/// NSMenuItem that runs a closure (keeps menu construction declarative).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, symbol: String?, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}

extension NSMenuItem {
    static func closure(_ title: String, _ symbol: String?, enabled: Bool = true, handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, symbol: symbol, handler: handler)
        item.isEnabled = enabled
        return item
    }
}

extension NSMenu {
    func add(_ title: String, _ symbol: String?, handler: @escaping () -> Void) {
        addItem(NSMenuItem.closure(title, symbol, handler: handler))
    }
}

/// Environment hook so Shelf tiles can hand files to a Basket without
/// knowing about windows.
struct BasketShelfTransfer {
    let moveToBasket: ([URL]) -> Void
}

private struct BasketShelfTransferKey: EnvironmentKey {
    static var defaultValue: BasketShelfTransfer? { nil }
}

extension EnvironmentValues {
    var basketShelfTransfer: BasketShelfTransfer? {
        get { self[BasketShelfTransferKey.self] }
        set { self[BasketShelfTransferKey.self] = newValue }
    }
}
