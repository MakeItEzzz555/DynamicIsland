import Combine
import Foundation

/// What a drag-time shake should do (Droppy `onJiggleDetected`).
enum BasketJiggleOutcome: Equatable {
    case none
    /// Present this basket near the pointer (newly created or the primary).
    case show(BasketState)
    /// Re-show auto-hidden baskets that still hold items; optionally follow
    /// with the switcher when that leaves 2+ baskets visible.
    case reveal([BasketState], thenSwitcher: Bool)
    case switcher([BasketState])

    static func == (lhs: BasketJiggleOutcome, rhs: BasketJiggleOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case let (.show(a), .show(b)): a.id == b.id
        case let (.reveal(a, x), .reveal(b, y)): a.map(\.id) == b.map(\.id) && x == y
        case let (.switcher(a), .switcher(b)): a.map(\.id) == b.map(\.id)
        default: false
        }
    }
}

/// Owns every Floating Basket's state and is the only place that mutates
/// basket contents, so temporary-file ownership stays exact across Shelf ↔
/// Basket ↔ Basket transfers, drops, drag-outs and operations.
@MainActor
final class BasketManager: ObservableObject {
    @Published private(set) var baskets: [BasketState] = []

    let settings: AppSettings
    let ownership: TemporaryFileOwnershipLedger
    private weak var shelf: FileShelfStore?
    private weak var operations: BackgroundOperationController?
    private var dropClaims: [Int: UUID] = [:]
    private var nextClaim = 0
    private var pendingCompressions: [UUID: (basket: UUID, sources: [URL])] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings,
        shelf: FileShelfStore?,
        ownership: TemporaryFileOwnershipLedger = .shared,
        operations: BackgroundOperationController?
    ) {
        self.settings = settings
        self.shelf = shelf
        self.ownership = ownership
        self.operations = operations
        operations?.$operations
            .sink { [weak self] operations in self?.reconcile(operations) }
            .store(in: &cancellables)
        settings.$basketMultipleEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard !enabled else { return }
                DispatchQueue.main.async { self?.enforceSingleBasketMode() }
            }
            .store(in: &cancellables)
    }

    func basket(_ id: UUID) -> BasketState? {
        baskets.first { $0.id == id }
    }

    var visibleBaskets: [BasketState] { baskets.filter(\.isVisible) }
    var hiddenBasketsWithItems: [BasketState] { baskets.filter { !$0.isVisible && !$0.items.isEmpty } }

    /// Droppy shows accent colours only once two or more baskets are visible.
    var showsAccentIdentity: Bool { visibleBaskets.count >= 2 }

    // MARK: Lifecycle

    @discardableResult
    func createBasket() -> BasketState? {
        guard settings.floatingBasketEnabled else { return nil }
        if !settings.basketMultipleEnabled, let existing = baskets.first { return existing }
        let basket = BasketState(accent: BasketAccent.next(excluding: baskets.map(\.accent)))
        baskets.append(basket)
        return basket
    }

    func setVisible(_ id: UUID, _ visible: Bool) {
        basket(id)?.setVisible(visible)
        objectWillChange.send()
    }

    /// Closing releases the basket's claims; stable originals are untouched.
    func close(_ id: UUID) {
        guard let basket = basket(id) else { return }
        let urls = basket.urls
        basket.removeItems(Set(basket.items.map(\.id)))
        basket.setVisible(false)
        baskets.removeAll { $0.id == id }
        dropClaims = dropClaims.filter { $0.value != id }
        ownership.release(urls, by: .basket(id))
    }

    func closeAll() {
        baskets.map(\.id).forEach(close)
    }

    /// Multi-basket turned off: merge everything into the first basket.
    func enforceSingleBasketMode() {
        guard baskets.count > 1, let primary = baskets.first else { return }
        for other in baskets.dropFirst() {
            transfer(Set(other.items.map(\.id)), from: other.id, to: primary.id)
            close(other.id)
        }
    }

    // MARK: Contents

    @discardableResult
    func add(_ urls: [URL], to id: UUID) -> [URL] {
        guard let basket = basket(id) else { return [] }
        var seen = Set(basket.urls)
        var accepted: [BasketItem] = []
        for url in urls.map(\.standardizedFileURL) where url.isFileURL {
            guard !seen.contains(url), FileManager.default.fileExists(atPath: url.path) else { continue }
            seen.insert(url)
            accepted.append(BasketItem(url: url))
        }
        guard !accepted.isEmpty else { return [] }
        ownership.retain(accepted.map(\.url), by: .basket(id))
        basket.appendItems(accepted)
        return accepted.map(\.url)
    }

    /// "Remove from Basket": drops the reference; deletes only orphaned
    /// DynamicIsland temp files, never the user's original.
    func remove(_ itemIDs: Set<UUID>, from id: UUID) {
        guard let basket = basket(id) else { return }
        let removed = basket.removeItems(itemIDs)
        ownership.release(removed.map(\.url), by: .basket(id))
    }

    /// App-surface transfer to the Shelf (no file-system move). Items the
    /// Shelf rejects (full/disabled) stay in the basket.
    @discardableResult
    func moveToShelf(_ itemIDs: Set<UUID>, from id: UUID) -> [URL] {
        guard let basket = basket(id), let shelf else { return [] }
        let candidates = basket.items.filter { itemIDs.contains($0.id) }
        let accepted = Set(shelf.adopt(candidates.map(\.url)))
        guard !accepted.isEmpty else { return [] }
        let moved = candidates.filter { accepted.contains($0.url) }
        basket.removeItems(Set(moved.map(\.id)))
        ownership.release(moved.map(\.url), by: .basket(id))
        return moved.map(\.url)
    }

    /// Shelf → Basket transfer; Shelf selection is updated by the Shelf.
    @discardableResult
    func moveFromShelf(_ urls: [URL], to id: UUID) -> [URL] {
        guard let basket = basket(id), let shelf else { return [] }
        let removed = shelf.removeForTransfer(urls)
        guard !removed.isEmpty else { return [] }
        let existing = Set(basket.urls)
        let new = removed.filter { !existing.contains($0) }.map { BasketItem(url: $0) }
        ownership.transfer(removed, from: .shelf, to: .basket(id))
        basket.appendItems(new)
        return removed
    }

    @discardableResult
    func transfer(_ itemIDs: Set<UUID>, from sourceID: UUID, to targetID: UUID) -> [URL] {
        guard sourceID != targetID, let source = basket(sourceID), let target = basket(targetID) else { return [] }
        let moving = source.items.filter { itemIDs.contains($0.id) }
        guard !moving.isEmpty else { return [] }
        let existing = Set(target.urls)
        source.removeItems(Set(moving.map(\.id)))
        ownership.transfer(moving.map(\.url), from: .basket(sourceID), to: .basket(targetID))
        target.appendItems(moving.filter { !existing.contains($0.url) }.map { BasketItem(url: $0.url) })
        return moving.map(\.url)
    }

    /// User-confirmed rename on disk (same folder, never overwrites).
    /// Validation matches FileShelfStore.rename.
    @discardableResult
    func rename(_ itemID: UUID, in id: UUID, to requestedName: String) throws -> URL {
        guard let item = basket(id)?.items.first(where: { $0.id == itemID }),
              FileManager.default.fileExists(atPath: item.url.path) else {
            throw FileShelfMutationError.missingSource
        }
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":"), name != ".", name != ".." else {
            throw FileShelfMutationError.invalidName
        }
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
        if destination == item.url { return destination }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileShelfMutationError.destinationExists
        }
        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
        } catch {
            throw FileShelfMutationError.moveFailed(error.localizedDescription)
        }
        recordRename(itemID, in: id, to: destination)
        return destination
    }

    /// Updates an item after a user-confirmed rename on disk.
    func recordRename(_ itemID: UUID, in id: UUID, to newURL: URL) {
        guard let basket = basket(id), let old = basket.items.first(where: { $0.id == itemID }) else { return }
        ownership.release([old.url], by: .basket(id))
        ownership.retain([newURL], by: .basket(id))
        basket.replaceItem(itemID, with: BasketItem(url: newURL, id: itemID))
    }

    // MARK: Drops

    /// One external drop executes at most once and only into this basket.
    func claimDrop(into id: UUID) -> Int? {
        guard basket(id) != nil else { return nil }
        nextClaim &+= 1
        dropClaims[nextClaim] = id
        return nextClaim
    }

    @discardableResult
    func completeDrop(_ claim: Int, urls: [URL]) -> [URL] {
        guard let id = dropClaims.removeValue(forKey: claim), basket(id) != nil else {
            ownership.discardIfUnowned(urls)
            return []
        }
        let accepted = add(urls, to: id)
        let acceptedSet = Set(accepted)
        ownership.discardIfUnowned(urls.map(\.standardizedFileURL).filter { !acceptedSet.contains($0) })
        return accepted
    }

    func failDrop(_ claim: Int) {
        dropClaims[claim] = nil
    }

    // MARK: Jiggle

    func resolveJiggle() -> BasketJiggleOutcome {
        guard settings.floatingBasketEnabled else { return .none }
        let multi = settings.basketMultipleEnabled
        if !multi { enforceSingleBasketMode() }
        let visible = visibleBaskets
        let hidden = hiddenBasketsWithItems

        if !visible.isEmpty {
            guard multi else { return .none }
            if !hidden.isEmpty { return .reveal(hidden, thenSwitcher: true) }
            if visible.count >= 2 { return .switcher(visible) }
            return createBasket().map(BasketJiggleOutcome.show) ?? .none
        }
        if !hidden.isEmpty {
            return .reveal(multi ? hidden : Array(hidden.prefix(1)), thenSwitcher: false)
        }
        return (baskets.first ?? createBasket()).map(BasketJiggleOutcome.show) ?? .none
    }

    // MARK: Operations

    /// Real ZIP through the shared BackgroundOperationController. Sources are
    /// held by the operation until it finishes; the archive returns to the
    /// basket that started it.
    @discardableResult
    func compress(_ itemIDs: Set<UUID>, in id: UUID) -> UUID? {
        guard let basket = basket(id), let operations else { return nil }
        let sources = basket.items.filter { itemIDs.contains($0.id) }.map(\.url)
        guard !sources.isEmpty, let operationID = operations.startCompression(sources: sources) else { return nil }
        ownership.retain(sources, by: .operation(operationID))
        pendingCompressions[operationID] = (id, sources)
        reconcile(operations.operations)
        return operationID
    }

    private func reconcile(_ operations: [BackgroundOperation]) {
        for (operationID, pending) in pendingCompressions {
            guard let operation = operations.first(where: { $0.id == operationID }) else {
                // Cleared from the operation list: release the sources.
                finishCompression(operationID, pending: pending, output: nil)
                continue
            }
            guard operation.state.isTerminal else { continue }
            finishCompression(operationID, pending: pending, output: operation.state == .completed ? operation.result?.outputURL : nil)
        }
    }

    private func finishCompression(_ operationID: UUID, pending: (basket: UUID, sources: [URL]), output: URL?) {
        guard pendingCompressions.removeValue(forKey: operationID) != nil else { return }
        if let output { add([output], to: pending.basket) }
        ownership.release(pending.sources, by: .operation(operationID))
    }
}
