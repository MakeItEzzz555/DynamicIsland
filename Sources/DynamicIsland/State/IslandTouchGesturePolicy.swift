import Foundation
import CoreGraphics

/// Coordinates are local to the shell, with a top-left origin. Only padding
/// outside the entire content rectangle and the physical notch accept input.
struct IslandBackgroundInteractionGeometry: Equatable {
    enum Region { case background, notch }
    let size: CGSize
    let horizontalPadding: CGFloat
    let bottomPadding: CGFloat
    let contentTop: CGFloat
    let notchSize: CGSize
    let allowsBackground: Bool
    var excludedRects: [CGRect] = []

    var notchRect: CGRect {
        guard notchSize.width > 0, notchSize.height > 0 else { return .zero }
        let width = min(size.width, notchSize.width)
        return CGRect(x: (size.width - width) / 2, y: 0,
                      width: width, height: min(size.height, notchSize.height))
    }

    func region(at point: CGPoint) -> Region? {
        guard CGRect(origin: .zero, size: size).contains(point),
              !excludedRects.contains(where: { $0.contains(point) }) else { return nil }
        if !notchRect.isEmpty, notchRect.contains(point) { return .notch }
        guard allowsBackground, point.y >= contentTop else { return nil }
        if point.y >= size.height - bottomPadding || point.x < horizontalPadding || point.x >= size.width - horizontalPadding {
            return .background
        }
        return nil
    }
}

enum IslandTouchPageAction: Equatable {
    case next
    case previous
}

/// Values from raw NSTouch responder callbacks, never inferred from wheel or
/// mouse events. The adapter assigns IDs using NSObjectProtocol.isEqual.
struct IslandIndirectTouch: Equatable {
    let identity: Int
    let device: Int
    let normalizedPosition: CGPoint
}

/// One physical multitouch sequence lasts until every contact lifts or AppKit
/// cancels it. Resting contacts are included by the hosting view so a thumb
/// cannot make four physical contacts look like three.
struct IslandTouchGesturePolicy {
    static let directionLockDistance: CGFloat = 0.015
    static let horizontalDominance: CGFloat = 1.5
    /// Eight percent of the trackpad width; independent of pointer speed and
    /// Natural Scrolling. This is a starting hardware tuning value, not a
    /// threshold claimed to have been physically measured on every trackpad.
    static let pageThreshold: CGFloat = 0.08

    private(set) var isSequenceActive = false
    private(set) var reservesIslandScroll = false
    private(set) var hasFired = false
    private var eligible = false
    private var rejected = false
    private var origins: [Int: CGPoint] = [:]
    private var initialContacts: [Int: CGPoint] = [:]
    private var device: Int?
    private var direction: IslandTouchPageAction?

    @discardableResult
    mutating func update(
        contacts: [IslandIndirectTouch],
        began: Bool,
        canBegin: Bool,
        inputStillAllowed: Bool = true
    ) -> IslandTouchPageAction? {
        guard !contacts.isEmpty else {
            cancel()
            return nil
        }
        guard isSequenceActive || began else { return nil }
        if !isSequenceActive {
            isSequenceActive = true
            eligible = canBegin
        }
        guard eligible, !rejected, !hasFired else { return nil }
        guard inputStillAllowed else {
            rejected = true
            return nil
        }
        let identities = Set(contacts.map(\.identity))
        guard identities.count == contacts.count, contacts.count <= 3,
              Set(contacts.map(\.device)).count == 1,
              contacts.allSatisfy({
                  $0.normalizedPosition.x.isFinite && $0.normalizedPosition.y.isFinite &&
                  (0...1).contains($0.normalizedPosition.x) && (0...1).contains($0.normalizedPosition.y)
              }) else {
            rejected = true
            return nil
        }
        if let device, contacts[0].device != device {
            rejected = true
            return nil
        }
        device = contacts[0].device

        if origins.isEmpty {
            // Fingers arrive in separate callbacks. Permit assembly, but a
            // pointer/scroll movement already underway cannot become paging
            // merely because a third contact subsequently joins it.
            guard Set(initialContacts.keys).isSubset(of: identities) else {
                rejected = true
                return nil
            }
            for contact in contacts {
                let initial = initialContacts[contact.identity] ?? contact.normalizedPosition
                initialContacts[contact.identity] = initial
                if max(abs(contact.normalizedPosition.x - initial.x),
                       abs(contact.normalizedPosition.y - initial.y)) >= Self.directionLockDistance {
                    rejected = true
                    return nil
                }
            }
            guard contacts.count == 3 else { return nil }
            origins = Dictionary(uniqueKeysWithValues: contacts.map { ($0.identity, $0.normalizedPosition) })
            reservesIslandScroll = true
            return nil
        }

        // A lifted/replaced finger cannot seed another gesture until all lift.
        guard identities == Set(origins.keys) else {
            rejected = true
            return nil
        }
        let deltas = contacts.map { contact -> CGPoint in
            let origin = origins[contact.identity]!
            return CGPoint(x: contact.normalizedPosition.x - origin.x,
                           y: contact.normalizedPosition.y - origin.y)
        }
        let delta = CGPoint(x: deltas.reduce(0) { $0 + $1.x } / 3,
                            y: deltas.reduce(0) { $0 + $1.y } / 3)
        if direction == nil {
            guard max(abs(delta.x), abs(delta.y)) >= Self.directionLockDistance else { return nil }
            guard abs(delta.x) > abs(delta.y) * Self.horizontalDominance else {
                rejected = true
                return nil
            }
            direction = delta.x < 0 ? .next : .previous
        }
        let sign: CGFloat = direction == .next ? -1 : 1
        // Every finger must move together, in the locked direction. A pinch,
        // rotation, reversal or a late vertical excursion cannot page.
        guard deltas.allSatisfy({ $0.x * sign > 0 }), delta.x * sign > 0 else {
            rejected = true
            return nil
        }
        guard abs(delta.x) > abs(delta.y) * Self.horizontalDominance,
              !deltas.contains(where: { abs($0.y) >= Self.directionLockDistance && abs($0.x) <= abs($0.y) * Self.horizontalDominance }) else {
            rejected = true
            return nil
        }
        guard abs(delta.x) >= Self.pageThreshold,
              abs(delta.x) > abs(delta.y) * Self.horizontalDominance,
              deltas.allSatisfy({ $0.x * sign >= Self.directionLockDistance }) else { return nil }
        hasFired = true
        return direction
    }

    mutating func cancel() {
        self = Self()
    }
}

/// Preserve native scrolling while keeping the wheel events associated with a
/// tracked three-finger gesture out of the older two-finger island routers.
/// A fresh physical beginning releases ownership, never a timer/quiet gap.
struct IslandTouchScrollOwnership {
    enum Phase {
        case began, changed, ended, cancelled, momentum, momentumEnded, ordinaryWheel
    }

    private(set) var ownsSequence = false

    mutating func reserve() {
        ownsSequence = true
    }

    mutating func suppressIslandRouting(phase: Phase, touchesReserved: Bool) -> Bool {
        if touchesReserved {
            reserve()
            return true
        }
        guard ownsSequence else { return false }
        switch phase {
        case .began, .ordinaryWheel:
            ownsSequence = false
            return false
        case .cancelled, .momentumEnded:
            ownsSequence = false
            return true
        case .changed, .ended, .momentum:
            return true
        }
    }

    mutating func reset() {
        ownsSequence = false
    }
}
