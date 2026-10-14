import Combine
import Foundation

/// Shares references with the primary Basket. Removal remains local to each surface.
@MainActor
final class ShelfBasketSynchronization {
    private let shelf: FileShelfStore
    private let baskets: BasketManager
    private var observers: Set<AnyCancellable> = []
    private var primaryObserver: AnyCancellable?
    private var primaryID: UUID?
    private var shelfSnapshot: Set<URL> = []
    private var basketSnapshot: Set<URL> = []
    private var pendingShelf: [URL] = []
    private var pendingBasket: [URL] = []
    private var bootstrap = false
    private var enabled = false
    private var applying = false
    private var revision = 0
    private var delivery: Task<Void, Never>?

    init(shelf: FileShelfStore, baskets: BasketManager) {
        self.shelf = shelf; self.baskets = baskets
        shelf.$files.sink { [weak self] files in
            guard let self else { return }
            let added = files.filter { !self.shelfSnapshot.contains($0) }
            self.shelfSnapshot = Set(files)
            guard self.enabled, !self.applying, !added.isEmpty else { return }
            self.pendingShelf.append(contentsOf: added)
            self.schedule()
        }.store(in: &observers)
        baskets.$baskets.sink { [weak self] values in self?.observePrimary(values.first) }
            .store(in: &observers)
    }

    func configure(enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        revision += 1
        delivery?.cancel(); delivery = nil
        pendingShelf.removeAll(); pendingBasket.removeAll()
        bootstrap = enabled
        if enabled { schedule() }
    }

    func stop() {
        configure(enabled: false)
        primaryObserver = nil; observers.removeAll()
    }

    private func observePrimary(_ primary: BasketState?) {
        guard primaryID != primary?.id else { return }
        primaryObserver = nil
        primaryID = primary?.id; basketSnapshot = []
        if let primary {
            primaryObserver = primary.$items.sink { [weak self] items in
                guard let self else { return }
                let urls = items.map(\.url)
                let added = urls.filter { !self.basketSnapshot.contains($0) }
                self.basketSnapshot = Set(urls)
                guard self.enabled, !self.applying, !added.isEmpty else { return }
                self.pendingBasket.append(contentsOf: added)
                self.schedule()
            }
        }
        if enabled { bootstrap = true; schedule() }
    }

    private func schedule() {
        guard enabled, delivery == nil else { return }
        let token = revision
        delivery = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.revision == token else { return }
            defer { self.delivery = nil }
            self.drain()
        }
    }

    private func drain() {
        guard enabled else { return }
        guard let primaryID, let primary = baskets.basket(primaryID) else {
            pendingShelf.removeAll(); pendingBasket.removeAll()
            return
        }
        let fromShelf = bootstrap ? shelf.files : pendingShelf.filter(shelf.files.contains)
        let fromBasket = bootstrap ? primary.urls : pendingBasket.filter(primary.urls.contains)
        pendingShelf.removeAll(); pendingBasket.removeAll(); bootstrap = false
        applying = true
        defer { applying = false }
        // adopt/add retain through the existing ledger; neither transfers or deletes the other owner's files.
        _ = shelf.adopt(fromBasket)
        _ = baskets.add(fromShelf, to: primaryID)
    }
}
