import CoreGraphics

/// Where the radial secondary widgets attach relative to the media card.
enum LockScreenSecondaryPlacement: String, Codable, CaseIterable, Sendable {
    case below, above
    var title: String { self == .below ? "Below media" : "Above media" }
}

/// Radial secondary widgets, in the user's order.
enum LockScreenRadialKind: String, Codable, CaseIterable, Sendable {
    case battery, timer, keepAwake
}

/// The single geometry for lock-screen surfaces, used by the real windows and
/// by the Settings preview (which scales the same frames). Frames are in
/// AppKit screen coordinates (origin bottom-left).
struct LockScreenLayout: Equatable {
    static let mediaSize = CGSize(width: 380, height: 150)
    static let radialDiameter: CGFloat = 56
    static let radialSpacing: CGFloat = 14
    static let alertSize = CGSize(width: 260, height: 40)
    /// The system clock ends about this far below the top on macOS 15.7.
    static let columnTopInset: CGFloat = 292
    static let islandWing: CGFloat = 66

    var island: CGRect
    var media: CGRect?
    var secondary: CGRect?
    var alert: CGRect?
    var side: CGRect

    static func secondaryWidth(count: Int) -> CGFloat {
        count > 0 ? CGFloat(count) * radialDiameter + CGFloat(count - 1) * radialSpacing : 0
    }

    /// Media and the radial row form one attached column: row below or above
    /// the card with `gap` between them, starting under the system clock.
    static func resolve(screen: CGRect, notch: CGRect?, preferences: LockScreenPreferences,
                        hasMedia: Bool, radialCount: Int, hasAlert: Bool) -> LockScreenLayout {
        let island: CGRect
        if let notch, notch.width > 0, notch.height > 0 {
            island = CGRect(x: notch.minX - islandWing, y: screen.maxY - notch.height,
                            width: notch.width + islandWing * 2, height: notch.height)
        } else {
            island = CGRect(x: screen.midX - 110, y: screen.maxY - 40, width: 220, height: 32)
        }

        let gap = CGFloat(preferences.secondaryGap)
        var top = screen.maxY - columnTopInset - CGFloat(preferences.mediaVerticalOffset)
        let rowWidth = secondaryWidth(count: radialCount)
        let rowHeight = radialDiameter

        func takeMedia() -> CGRect {
            let rect = CGRect(x: screen.midX - mediaSize.width / 2, y: top - mediaSize.height,
                              width: mediaSize.width, height: mediaSize.height)
            top = rect.minY
            return rect
        }
        func takeRow() -> CGRect {
            let rect = CGRect(x: screen.midX - rowWidth / 2, y: top - rowHeight, width: rowWidth, height: rowHeight)
            top = rect.minY
            return rect
        }

        var media: CGRect?
        var secondary: CGRect?
        switch (hasMedia, radialCount > 0, preferences.secondaryPlacement) {
        case (true, true, .below):
            media = takeMedia(); top -= gap; secondary = takeRow()
        case (true, true, .above):
            secondary = takeRow(); top -= gap; media = takeMedia()
        case (true, false, _):
            media = takeMedia()
        case (false, true, _):
            secondary = takeRow()
        case (false, false, _):
            break
        }
        var alert: CGRect?
        if hasAlert {
            top -= gap
            alert = CGRect(x: screen.midX - alertSize.width / 2, y: top - alertSize.height,
                           width: alertSize.width, height: alertSize.height)
        }
        let side = CGRect(x: screen.minX + 20, y: screen.midY - 110, width: 52, height: 220)
        return LockScreenLayout(island: island, media: media, secondary: secondary, alert: alert, side: side)
    }
}
