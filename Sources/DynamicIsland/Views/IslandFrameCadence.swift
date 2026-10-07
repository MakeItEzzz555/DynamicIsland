import AppKit

/// Redraw cadence for continuously animated decorations (TimelineView-driven
/// Canvas work). One source of truth instead of scattered 1/24 - 1/30 caps.
///
/// Interactive motion (drag, resize, stack swipe, shell morph) never uses
/// these: it runs on retargetable SwiftUI springs that the compositor drives
/// at the display's refresh rate. Decorations follow the display too, so a
/// 120 Hz ProMotion panel is not held at a fixed 24/30 Hz staircase, while
/// always-on ambient effects stay cheaper. Business timers are separate.
enum IslandFrameCadence {
    enum Surface {
        /// Visible expanded content: orb, bot avatar, agent effects,
        /// expanded media visualizer.
        case expandedDecoration
        /// Always-on collapsed decorations (notch glow, collapsed visualizer).
        case ambient
    }

    static let ambientRate = 60
    static let lowPowerRate = 30

    /// Minimum interval between frames. `displayRate` is the screen's
    /// maximum refresh rate (120 on ProMotion, 60 elsewhere).
    @MainActor
    static func interval(_ surface: Surface, displayRate: Int = currentDisplayRate,
                         lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled) -> Double {
        let display = max(30, displayRate)
        let rate: Int
        switch surface {
        case .expandedDecoration: rate = display
        case .ambient: rate = min(display, ambientRate)
        }
        return 1.0 / Double(lowPower ? min(rate, lowPowerRate) : rate)
    }

    @MainActor
    static var currentDisplayRate: Int {
        let rates = NSScreen.screens.map(\.maximumFramesPerSecond)
        return rates.max() ?? 60
    }
}
