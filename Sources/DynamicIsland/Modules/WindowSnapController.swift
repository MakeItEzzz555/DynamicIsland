import AppKit
import ApplicationServices
import Foundation

enum WindowSnapTarget: String, CaseIterable, Identifiable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftThird
    case centerThird
    case rightThird

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        }
    }

    var symbolName: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.inset.filled"
        case .rightHalf: "rectangle.righthalf.inset.filled"
        case .topHalf: "rectangle.tophalf.inset.filled"
        case .bottomHalf: "rectangle.bottomhalf.inset.filled"
        case .topLeft: "square.split.2x2"
        case .topRight: "square.split.2x2"
        case .bottomLeft: "square.split.2x2"
        case .bottomRight: "square.split.2x2"
        case .leftThird, .centerThird, .rightThird: "rectangle.split.3x1"
        }
    }
}

enum WindowSnapGeometry {
    static func frame(for target: WindowSnapTarget, in visibleFrame: CGRect) -> CGRect {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2
        let thirdWidth = visibleFrame.width / 3

        switch target {
        case .leftHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .rightHalf:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .topHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: visibleFrame.width, height: halfHeight)
        case .topLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.midY, width: halfWidth, height: halfHeight)
        case .leftThird:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: thirdWidth, height: visibleFrame.height)
        case .centerThird:
            return CGRect(x: visibleFrame.minX + thirdWidth, y: visibleFrame.minY, width: thirdWidth, height: visibleFrame.height)
        case .rightThird:
            return CGRect(x: visibleFrame.maxX - thirdWidth, y: visibleFrame.minY, width: thirdWidth, height: visibleFrame.height)
        }
    }
}

struct WindowSnapScreen: Equatable, Sendable {
    let id: String
    let visibleFrame: CGRect
}

enum WindowSnapScreenResolver {
    static func targetScreen(for windowFrame: CGRect, screens: [WindowSnapScreen]) -> WindowSnapScreen? {
        guard !screens.isEmpty else { return nil }

        return screens.max { lhs, rhs in
            let lhsArea = intersectionArea(windowFrame, lhs.visibleFrame)
            let rhsArea = intersectionArea(windowFrame, rhs.visibleFrame)
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }

            let lhsDistance = squaredDistance(from: windowFrame.center, to: lhs.visibleFrame.center)
            let rhsDistance = squaredDistance(from: windowFrame.center, to: rhs.visibleFrame.center)
            if lhsDistance != rhsDistance {
                return lhsDistance > rhsDistance
            }
            return lhs.id > rhs.id
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return max(intersection.width, 0) * max(intersection.height, 0)
    }

    private static func squaredDistance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

enum WindowSnapControllerError: LocalizedError, Equatable {
    case accessibilityPermissionRequired
    case noFocusedWindow
    case noDisplay
    case cannotReadWindowFrame
    case cannotSetWindowFrame(AXError)
    case unsupportedAction(IslandCapabilityAction)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required to snap windows."
        case .noFocusedWindow:
            "No focused application window is available to snap."
        case .noDisplay:
            "No display could be resolved for the focused window."
        case .cannotReadWindowFrame:
            "The focused window's position or size could not be read."
        case .cannotSetWindowFrame(let error):
            "The focused window rejected the requested frame (AXError \(error.rawValue))."
        case .unsupportedAction(let action):
            "Window Snap does not support \(action.rawValue) without a target."
        }
    }
}

protocol WindowSnapSystemProviding {
    var accessibilityGranted: Bool { get }
    func focusedWindowFrame() throws -> CGRect
    func screens() -> [WindowSnapScreen]
    func setFocusedWindowFrame(_ frame: CGRect) throws
}

struct SystemWindowSnapProvider: WindowSnapSystemProviding {
    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func focusedWindowFrame() throws -> CGRect {
        let window = try focusedWindow()
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            throw WindowSnapControllerError.cannotReadWindowFrame
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            throw WindowSnapControllerError.cannotReadWindowFrame
        }
        return CGRect(origin: position, size: size)
    }

    func screens() -> [WindowSnapScreen] {
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { return [] }

        return NSScreen.screens.enumerated().map { index, screen in
            let frame = screen.visibleFrame
            let accessibilityFrame = CGRect(
                x: frame.minX,
                y: primaryTop - frame.maxY,
                width: frame.width,
                height: frame.height
            )
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                .map { String(describing: $0) } ?? String(index)
            return WindowSnapScreen(id: displayID, visibleFrame: accessibilityFrame)
        }
    }

    func setFocusedWindowFrame(_ frame: CGRect) throws {
        let window = try focusedWindow()
        var position = frame.origin
        var size = frame.size

        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowSnapControllerError.cannotReadWindowFrame
        }

        let positionResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )
        guard positionResult == .success else {
            throw WindowSnapControllerError.cannotSetWindowFrame(positionResult)
        }

        let sizeResult = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        guard sizeResult == .success else {
            throw WindowSnapControllerError.cannotSetWindowFrame(sizeResult)
        }
    }

    private func focusedWindow() throws -> AXUIElement {
        guard accessibilityGranted else {
            throw WindowSnapControllerError.accessibilityPermissionRequired
        }

        let systemWide = AXUIElementCreateSystemWide()
        var applicationValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &applicationValue
        ) == .success,
        let applicationValue,
        CFGetTypeID(applicationValue) == AXUIElementGetTypeID() else {
            throw WindowSnapControllerError.noFocusedWindow
        }

        let application = applicationValue as! AXUIElement
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue,
        CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            throw WindowSnapControllerError.noFocusedWindow
        }
        return windowValue as! AXUIElement
    }
}

@MainActor
final class WindowSnapController: ObservableObject, IslandCapabilityAdapter {
    static let previewActivityID = "windowSnapPreview"

    let capabilityID: IslandCapabilityID = .windowSnap

    @Published private(set) var lastTarget: WindowSnapTarget?
    @Published private(set) var lastError: String?

    private let system: WindowSnapSystemProviding
    private let liveActivities: LiveActivityStore
    private let capabilities: IslandCapabilityRegistry
    private let now: () -> Date
    private var previewDismissWorkItem: DispatchWorkItem?
    private var isEnabled = true

    init(
        liveActivities: LiveActivityStore,
        capabilities: IslandCapabilityRegistry,
        system: WindowSnapSystemProviding = SystemWindowSnapProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.liveActivities = liveActivities
        self.capabilities = capabilities
        self.system = system
        self.now = now
        publishState()
    }

    var snapshot: IslandCapabilitySnapshot {
        let permission: IslandCapabilityPermissionState = system.accessibilityGranted ? .granted : .required
        let health: IslandCapabilityHealth = lastError.map { .degraded(message: $0) } ?? .healthy
        return IslandCapabilitySnapshot(
            id: .windowSnap,
            isEnabled: isEnabled,
            permission: permission,
            availability: .available,
            health: health,
            supportedActions: [.test, .openSettings, .configureShortcut],
            isActive: false,
            statusText: lastTarget?.displayName
        )
    }

    func snap(to target: WindowSnapTarget) throws {
        guard isEnabled else { return }
        guard system.accessibilityGranted else {
            lastError = WindowSnapControllerError.accessibilityPermissionRequired.localizedDescription
            publishState(failed: true)
            throw WindowSnapControllerError.accessibilityPermissionRequired
        }

        do {
            let currentFrame = try system.focusedWindowFrame()
            guard let screen = WindowSnapScreenResolver.targetScreen(
                for: currentFrame,
                screens: system.screens()
            ) else {
                throw WindowSnapControllerError.noDisplay
            }

            let targetFrame = WindowSnapGeometry.frame(for: target, in: screen.visibleFrame)
            publishPreview(target: target)
            try system.setFocusedWindowFrame(targetFrame)
            lastTarget = target
            lastError = nil
            publishState()
        } catch {
            lastError = error.localizedDescription
            liveActivities.remove(id: Self.previewActivityID)
            publishState(failed: true)
            throw error
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            previewDismissWorkItem?.cancel()
            liveActivities.remove(id: Self.previewActivityID)
        }
        publishState()
    }

    func refresh() async {
        publishState()
    }

    func perform(_ action: IslandCapabilityAction) async throws {
        switch action {
        case .test:
            _ = try system.focusedWindowFrame()
            lastError = nil
            publishState()
        case .openSettings:
            SystemHUDAccessibilityPermission.openSettings()
        case .start, .stop, .configureShortcut:
            throw WindowSnapControllerError.unsupportedAction(action)
        }
    }

    private func publishPreview(target: WindowSnapTarget) {
        let date = now()
        liveActivities.update(
            DynamicIslandLiveActivity(
                id: Self.previewActivityID,
                kind: .windowSnapPreview,
                title: "Window Snap",
                subtitle: target.displayName,
                symbolName: target.symbolName,
                priority: 170,
                isActive: true,
                progress: nil,
                updatedAt: date,
                lifecycle: LiveActivityLifecycleMetadata(
                    authority: .accessibilityAPI,
                    startEvidence: "focused AX window and target display resolved",
                    progressEvidence: nil,
                    completionEvidence: "AX position and size accepted",
                    dismissPolicy: .automatic,
                    supportsCancellation: false
                )
            )
        )

        previewDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.liveActivities.remove(id: Self.previewActivityID)
            }
        }
        previewDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func publishState(failed: Bool = false) {
        var value = snapshot
        if failed, let lastError {
            value.health = .failed(message: lastError)
        }
        capabilities.update(value)
    }
}
