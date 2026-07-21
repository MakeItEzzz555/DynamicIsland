import CoreGraphics
import Foundation

public enum IslandGestureAction: String, CaseIterable, Codable, Identifiable {
    case expand
    case collapse
    case toggleExpanded
    case nextTab
    case previousTab
    case mediaPlayPause
    case mediaNextTrack
    case mediaPreviousTrack
    case timerStartStop
    case openSettings
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .expand:
            "Expand"
        case .collapse:
            "Collapse"
        case .toggleExpanded:
            "Toggle Expanded"
        case .nextTab:
            "Next Tab"
        case .previousTab:
            "Previous Tab"
        case .mediaPlayPause:
            "Media Play/Pause"
        case .mediaNextTrack:
            "Next Track"
        case .mediaPreviousTrack:
            "Previous Track"
        case .timerStartStop:
            "Timer Start/Stop"
        case .openSettings:
            "Open Settings"
        case .none:
            "None"
        }
    }
}

enum IslandPointerGesture: String, CaseIterable, Codable {
    case swipeLeft
    case swipeRight
    case swipeUp
    case swipeDown
    case longPress
    case doubleClick

    static func detected(from translation: CGSize, sensitivity: Double) -> IslandPointerGesture? {
        let threshold = swipeThreshold(sensitivity: sensitivity)
        let absoluteX = abs(translation.width)
        let absoluteY = abs(translation.height)

        guard max(absoluteX, absoluteY) >= threshold else { return nil }
        if absoluteX >= absoluteY {
            return translation.width < 0 ? .swipeLeft : .swipeRight
        }
        return translation.height < 0 ? .swipeUp : .swipeDown
    }

    static func swipeThreshold(sensitivity: Double) -> CGFloat {
        let clampedSensitivity = min(max(sensitivity, 0), 1)
        return 36 / max(0.4, CGFloat(clampedSensitivity))
    }
}

struct IslandGestureContext {
    let presentationState: IslandPresentationState
    let selectedPage: ExpandedIslandPage
    let mediaControlAvailable: Bool
    let timerIsRunning: Bool
    let timerCanResume: Bool
    let collapsedPreviewActive: Bool
    let isShellMorphing: Bool
    let isCollapseShellOnly: Bool
    let isExpandedContentExiting: Bool
    let isFileDropTargeted: Bool
}

struct IslandGestureCallbacks {
    var expand: () -> Void = {}
    var collapse: () -> Void = {}
    var nextTab: () -> Void = {}
    var previousTab: () -> Void = {}
    var mediaPlayPause: () -> Void = {}
    var mediaNextTrack: () -> Void = {}
    var mediaPreviousTrack: () -> Void = {}
    var timerStartStop: () -> Void = {}
    var openSettings: () -> Void = {}
}

@MainActor
final class IslandGestureCoordinator: ObservableObject {
    private var lastActionTime: TimeInterval?
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.now = now
    }

    @discardableResult
    func handle(
        _ gesture: IslandPointerGesture,
        settings: AppSettings,
        context: IslandGestureContext,
        callbacks: IslandGestureCallbacks
    ) -> Bool {
        guard canHandlePointerGesture(settings: settings, context: context) else { return false }

        let action = resolvedAction(for: gesture, settings: settings, context: context)
        guard isActionEnabled(action, settings: settings, context: context) else { return false }
        guard allowsCooldown(settings: settings) else { return false }

        perform(action, context: context, callbacks: callbacks)
        lastActionTime = now()
        return true
    }

    func action(
        for gesture: IslandPointerGesture,
        settings: AppSettings,
        context: IslandGestureContext
    ) -> IslandGestureAction {
        switch context.presentationState {
        case .collapsed:
            return collapsedAction(for: gesture, settings: settings)
        case .expanded:
            return expandedAction(for: gesture, settings: settings)
        }
    }

    private func resolvedAction(
        for gesture: IslandPointerGesture,
        settings: AppSettings,
        context: IslandGestureContext
    ) -> IslandGestureAction {
        let configuredAction = action(for: gesture, settings: settings, context: context)
        if context.presentationState == .collapsed,
           gesture == .doubleClick,
           configuredAction == .mediaPlayPause,
           !context.mediaControlAvailable {
            return .toggleExpanded
        }
        return configuredAction
    }

    private func collapsedAction(
        for gesture: IslandPointerGesture,
        settings: AppSettings
    ) -> IslandGestureAction {
        switch gesture {
        case .doubleClick:
            settings.collapsedDoubleClickAction
        case .swipeLeft:
            settings.collapsedSwipeLeftAction
        case .swipeRight:
            settings.collapsedSwipeRightAction
        case .swipeUp:
            settings.collapsedSwipeUpAction
        case .swipeDown:
            settings.collapsedSwipeDownAction
        case .longPress:
            settings.collapsedLongPressAction
        }
    }

    private func expandedAction(
        for gesture: IslandPointerGesture,
        settings: AppSettings
    ) -> IslandGestureAction {
        switch gesture {
        case .doubleClick:
            settings.expandedDoubleClickAction
        case .swipeLeft:
            settings.expandedSwipeLeftAction
        case .swipeRight:
            settings.expandedSwipeRightAction
        case .swipeUp:
            settings.expandedSwipeUpAction
        case .swipeDown:
            settings.expandedSwipeDownAction
        case .longPress:
            settings.expandedLongPressAction
        }
    }

    private func canHandlePointerGesture(settings: AppSettings, context: IslandGestureContext) -> Bool {
        guard settings.gesturesEnabled else { return false }
        guard settings.gestureInputSource == .trackpad else { return false }
        guard !settings.requireGestureConfirmation else { return false }
        guard !context.isShellMorphing,
              !context.isCollapseShellOnly,
              !context.isExpandedContentExiting,
              !context.isFileDropTargeted else {
            return false
        }
        return true
    }

    private func isActionEnabled(
        _ action: IslandGestureAction,
        settings: AppSettings,
        context: IslandGestureContext
    ) -> Bool {
        switch action {
        case .expand:
            return context.presentationState == .collapsed && settings.expandGestureEnabled
        case .collapse:
            return context.presentationState == .expanded && settings.collapseGestureEnabled
        case .toggleExpanded:
            switch context.presentationState {
            case .collapsed:
                return settings.expandGestureEnabled
            case .expanded:
                return settings.collapseGestureEnabled
            }
        case .nextTab:
            return context.presentationState == .expanded && settings.nextTabGestureEnabled
        case .previousTab:
            return context.presentationState == .expanded && settings.previousTabGestureEnabled
        case .mediaPlayPause:
            return settings.mediaEnabled &&
                settings.mediaPlayPauseGestureEnabled &&
                context.mediaControlAvailable
        case .mediaNextTrack, .mediaPreviousTrack:
            return settings.mediaEnabled && context.mediaControlAvailable
        case .timerStartStop:
            return settings.timerEnabled &&
                settings.timerStartStopGestureEnabled &&
                (context.timerIsRunning || context.timerCanResume)
        case .openSettings:
            return true
        case .none:
            return false
        }
    }

    private func allowsCooldown(settings: AppSettings) -> Bool {
        guard let lastActionTime else { return true }
        return now() - lastActionTime >= settings.gestureCooldownSeconds
    }

    private func perform(
        _ action: IslandGestureAction,
        context: IslandGestureContext,
        callbacks: IslandGestureCallbacks
    ) {
        switch action {
        case .expand:
            callbacks.expand()
        case .collapse:
            callbacks.collapse()
        case .toggleExpanded:
            switch context.presentationState {
            case .collapsed:
                callbacks.expand()
            case .expanded:
                callbacks.collapse()
            }
        case .nextTab:
            callbacks.nextTab()
        case .previousTab:
            callbacks.previousTab()
        case .mediaPlayPause:
            callbacks.mediaPlayPause()
        case .mediaNextTrack:
            callbacks.mediaNextTrack()
        case .mediaPreviousTrack:
            callbacks.mediaPreviousTrack()
        case .timerStartStop:
            callbacks.timerStartStop()
        case .openSettings:
            callbacks.openSettings()
        case .none:
            break
        }
    }
}
