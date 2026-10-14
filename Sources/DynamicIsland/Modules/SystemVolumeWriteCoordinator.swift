import Foundation

/// One write in flight and one pending value; stale replies cannot update UI.
@MainActor
final class SystemVolumeWriteCoordinator {
    typealias Writer = @Sendable (Double, UInt32) async -> SystemHUDSnapshot?
    private let write: Writer
    private var pending: (Double, UInt32, @MainActor (SystemHUDSnapshot?) -> Void)?
    private var task: Task<Void, Never>?
    private var generation = 0

    init(write: @escaping Writer) { self.write = write }

    func request(_ value: Double, device: UInt32, completion: @escaping @MainActor (SystemHUDSnapshot?) -> Void) {
        guard value.isFinite else { completion(nil); return }
        pending = (min(max(value, 0), 1), device, completion)
        guard task == nil else { return }
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            while let request = pending {
                pending = nil
                let result = await write(request.0, request.1)
                guard generation == token, !Task.isCancelled else { return }
                if pending == nil { request.2(result) }
            }
            task = nil
        }
    }

    func cancel() {
        generation += 1; pending = nil; task?.cancel(); task = nil
    }
}

struct SystemVolumeChangeTracker {
    private var last: SystemHUDSnapshot?
    private var own: SystemHUDSnapshot?

    mutating func verifiedWrite(_ snapshot: SystemHUDSnapshot) { own = snapshot; last = snapshot }
    mutating func observed(_ snapshot: SystemHUDSnapshot) -> Bool {
        defer { last = snapshot }
        if let own, snapshot.updatedAt.timeIntervalSince(own.updatedAt) >= 0,
           snapshot.updatedAt.timeIntervalSince(own.updatedAt) < 0.5,
           abs(snapshot.value - own.value) < 0.002, snapshot.isMuted == own.isMuted { return false }
        guard let last else { return false }
        return abs(last.value - snapshot.value) >= 0.002 || last.isMuted != snapshot.isMuted
    }
}

enum SystemVolumeKeyStep {
    static func value(fine: Bool) -> Float32 { fine ? 1 / 64 : 1 / 16 }
}
