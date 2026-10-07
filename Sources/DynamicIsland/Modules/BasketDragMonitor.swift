import AppKit

/// What the drag monitor reads from the system each tick. Abstracted so the
/// detection state machine is testable without a real drag.
@MainActor
protocol BasketDragProbe: AnyObject {
    var isPrimaryButtonDown: Bool { get }
    var pointerLocation: CGPoint { get }
    var dragPasteboardChangeCount: Int { get }
    /// True only for payloads a basket can accept (file URLs / file promises).
    var dragPasteboardHasFiles: Bool { get }
    var now: TimeInterval { get }
}

@MainActor
final class SystemBasketDragProbe: BasketDragProbe {
    private static let fileTypes: Set<NSPasteboard.PasteboardType> = {
        var types: Set<NSPasteboard.PasteboardType> = [.fileURL]
        types.formUnion(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        return types
    }()

    var isPrimaryButtonDown: Bool { NSEvent.pressedMouseButtons & 1 != 0 }
    var pointerLocation: CGPoint { NSEvent.mouseLocation }
    var dragPasteboardChangeCount: Int { NSPasteboard(name: .drag).changeCount }
    var dragPasteboardHasFiles: Bool {
        guard let types = NSPasteboard(name: .drag).types else { return false }
        return !Self.fileTypes.isDisjoint(with: types)
    }
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// Detects real external file drags without Accessibility, the way Droppy's
/// DragMonitor does: poll the drag pasteboard's change count while the
/// primary button is down (10 Hz; no file-system work). Each drag is a new
/// generation; a shake triggers at most once per generation.
@MainActor
final class BasketDragMonitor: ObservableObject {
    static let pollInterval: TimeInterval = 0.10

    @Published private(set) var isDragging = false
    private(set) var generation = 0
    /// Suppresses detection for drags the app started itself (Basket drag-out).
    var isSuppressed: () -> Bool = { false }

    private let probe: BasketDragProbe
    private let sensitivity: () -> Int
    private let onJiggle: (Int, CGPoint) -> Void
    private let onDragEnded: (Int) -> Void
    private var detector: BasketJiggleDetector
    private var lastChangeCount: Int
    private var timer: Timer?

    init(
        probe: BasketDragProbe,
        sensitivity: @escaping () -> Int,
        onJiggle: @escaping (Int, CGPoint) -> Void,
        onDragEnded: @escaping (Int) -> Void
    ) {
        self.probe = probe
        self.sensitivity = sensitivity
        self.onJiggle = onJiggle
        self.onDragEnded = onDragEnded
        detector = BasketJiggleDetector(sensitivity: sensitivity())
        lastChangeCount = probe.dragPasteboardChangeCount
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = probe.dragPasteboardChangeCount
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isDragging { finishDrag() }
    }

    func tick() {
        let buttonDown = probe.isPrimaryButtonDown
        if !isDragging {
            guard buttonDown else { return }
            let changeCount = probe.dragPasteboardChangeCount
            guard changeCount != lastChangeCount else { return }
            lastChangeCount = changeCount
            guard probe.dragPasteboardHasFiles, !isSuppressed() else { return }
            generation &+= 1
            isDragging = true
            detector.setSensitivity(sensitivity())
            detector.beginDrag(generation: generation, at: probe.pointerLocation)
            return
        }

        guard buttonDown else {
            finishDrag()
            return
        }
        let location = probe.pointerLocation
        if detector.sample(location, at: probe.now, generation: generation) {
            onJiggle(generation, location)
        }
    }

    private func finishDrag() {
        isDragging = false
        detector.endDrag()
        onDragEnded(generation)
    }
}
