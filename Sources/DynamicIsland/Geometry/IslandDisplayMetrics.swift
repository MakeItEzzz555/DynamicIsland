import AppKit
import CoreGraphics
import SwiftUI

/// Immutable description of the display that owns the island. UI layout uses
/// logical points; pixel dimensions/backing scale are exposed separately for
/// capture/raster work so Retina is never double-scaled.
struct IslandDisplaySnapshot: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsets: NSEdgeInsets
    let auxiliaryTopLeftArea: CGRect?
    let auxiliaryTopRightArea: CGRect?
    let backingScaleFactor: CGFloat
    let displayID: CGDirectDisplayID?
    let isBuiltIn: Bool
    let pixelSize: CGSize

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.frame == rhs.frame &&
            lhs.visibleFrame == rhs.visibleFrame &&
            lhs.safeAreaInsets.top == rhs.safeAreaInsets.top &&
            lhs.safeAreaInsets.left == rhs.safeAreaInsets.left &&
            lhs.safeAreaInsets.bottom == rhs.safeAreaInsets.bottom &&
            lhs.safeAreaInsets.right == rhs.safeAreaInsets.right &&
            lhs.auxiliaryTopLeftArea == rhs.auxiliaryTopLeftArea &&
            lhs.auxiliaryTopRightArea == rhs.auxiliaryTopRightArea &&
            lhs.backingScaleFactor == rhs.backingScaleFactor &&
            lhs.displayID == rhs.displayID &&
            lhs.isBuiltIn == rhs.isBuiltIn &&
            lhs.pixelSize == rhs.pixelSize
    }

    var hasHardwareNotch: Bool {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else {
            return false
        }
        return left.maxX < right.minX
    }

    var notchRect: CGRect? {
        guard hasHardwareNotch,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else {
            return nil
        }
        return CGRect(
            x: left.maxX,
            y: min(left.minY, right.minY),
            width: max(right.minX - left.maxX, 0),
            height: max(left.height, right.height, safeAreaInsets.top)
        ).integral
    }
}

/// Display-derived visual tokens. Hardware geometry remains owned by
/// NotchGeometryService; these tokens scale island content within that geometry.
struct ResolvedIslandMetrics: Equatable {
    let logicalSize: CGSize
    let visibleLogicalSize: CGSize
    let pixelSize: CGSize
    let backingScaleFactor: CGFloat
    let displayID: CGDirectDisplayID?
    let isBuiltIn: Bool
    let hasHardwareNotch: Bool

    let uiScale: CGFloat
    let typographyScale: CGFloat
    let iconScale: CGFloat
    let spacingScale: CGFloat
    let compactControlScale: CGFloat
    let expandedCardScale: CGFloat
    let collapsedSideContentScale: CGFloat
    let cornerRadiusScale: CGFloat
    let expandedShellScale: CGFloat

    let minimumReadableFont: CGFloat
    let maximumBodyFont: CGFloat
    let minimumPointerHitSize: CGFloat
    let dividerThickness: CGFloat
    let hudSliderHeight: CGFloat
    let transcriptFontSize: CGFloat
    let workspaceTileMinimumHeight: CGFloat
    /// Physical notch height (0 without a hardware notch).
    var hardwareNotchHeight: CGFloat = 0
    /// Physical notch width (0 without a hardware notch).
    var hardwareNotchWidth: CGFloat = 0

    static let fallback = IslandDisplayMetricsResolver.resolve(
        IslandDisplaySnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 956),
            safeAreaInsets: .init(),
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            backingScaleFactor: 2,
            displayID: nil,
            isBuiltIn: true,
            pixelSize: CGSize(width: 3024, height: 1964)
        )
    )

    func font(_ base: CGFloat, minimum: CGFloat? = nil, maximum: CGFloat? = nil) -> CGFloat {
        let low = minimum ?? minimumReadableFont
        let high = maximum ?? maximumBodyFont
        return min(max(base * typographyScale, low), high)
    }

    func icon(_ base: CGFloat, minimum: CGFloat = 8, maximum: CGFloat = 40) -> CGFloat {
        min(max(base * iconScale, minimum), maximum)
    }

    func spacing(_ base: CGFloat, minimum: CGFloat = 2, maximum: CGFloat = 32) -> CGFloat {
        min(max(base * spacingScale, minimum), maximum)
    }
}

enum IslandDisplayMetricsResolver {
    /// 14-inch-class logical workspace is the neutral design baseline, but no
    /// machine model is detected or special-cased.
    static let baselineLogicalSize = CGSize(width: 1512, height: 982)

    static func resolve(_ snapshot: IslandDisplaySnapshot) -> ResolvedIslandMetrics {
        let width = max(snapshot.visibleFrame.width, 640)
        let height = max(snapshot.visibleFrame.height, 480)
        let baselineArea = baselineLogicalSize.width * baselineLogicalSize.height
        let areaRatio = max((width * height) / baselineArea, 0.2)

        // A shallow power curve grows/shrinks content gently across displays:
        // resolution changes should create breathing room, not giant desktop UI.
        let geometricScale = pow(areaRatio, 0.10)
        let ui = clamp(geometricScale, 0.90, 1.12)
        let typography = clamp(pow(areaRatio, 0.075), 0.94, 1.10)
        let icon = clamp(pow(areaRatio, 0.09), 0.92, 1.12)
        let spacing = clamp(pow(areaRatio, 0.11), 0.90, 1.13)
        let compact = clamp(pow(areaRatio, 0.08), 0.92, 1.10)
        let card = clamp(pow(areaRatio, 0.12), 0.90, 1.14)
        let side = clamp(pow(areaRatio, 0.07), 0.94, 1.08)
        let corners = clamp(pow(areaRatio, 0.06), 0.95, 1.08)
        let shell = clamp(pow(areaRatio, 0.055), 0.95, 1.08)

        var resolved = ResolvedIslandMetrics(
            logicalSize: snapshot.frame.size,
            visibleLogicalSize: snapshot.visibleFrame.size,
            pixelSize: snapshot.pixelSize,
            backingScaleFactor: max(snapshot.backingScaleFactor, 1),
            displayID: snapshot.displayID,
            isBuiltIn: snapshot.isBuiltIn,
            hasHardwareNotch: snapshot.hasHardwareNotch,
            uiScale: ui,
            typographyScale: typography,
            iconScale: icon,
            spacingScale: spacing,
            compactControlScale: compact,
            expandedCardScale: card,
            collapsedSideContentScale: side,
            cornerRadiusScale: corners,
            expandedShellScale: shell,
            minimumReadableFont: 7.2,
            maximumBodyFont: 18,
            minimumPointerHitSize: 28,
            dividerThickness: 1,
            hudSliderHeight: clamp(4.5 * compact, 4, 6),
            transcriptFontSize: clamp(9.5 * typography, 9, 10.8),
            workspaceTileMinimumHeight: clamp(48 * card, 44, 58)
        )
        resolved.hardwareNotchHeight = snapshot.notchRect?.height ?? 0
        resolved.hardwareNotchWidth = snapshot.notchRect?.width ?? 0
        return resolved
    }

    @MainActor
    static func snapshot(for screen: NSScreen) -> IslandDisplaySnapshot {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = number.map { CGDirectDisplayID($0.uint32Value) }
        let pixelSize: CGSize
        if let displayID {
            pixelSize = CGSize(
                width: CGDisplayPixelsWide(displayID),
                height: CGDisplayPixelsHigh(displayID)
            )
        } else {
            pixelSize = CGSize(
                width: screen.frame.width * screen.backingScaleFactor,
                height: screen.frame.height * screen.backingScaleFactor
            )
        }

        return IslandDisplaySnapshot(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            backingScaleFactor: screen.backingScaleFactor,
            displayID: displayID,
            isBuiltIn: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
            pixelSize: pixelSize
        )
    }

    @MainActor
    static func resolve(screen: NSScreen?) -> ResolvedIslandMetrics {
        guard let screen else { return .fallback }
        return resolve(snapshot(for: screen))
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

private struct IslandDisplayMetricsEnvironmentKey: EnvironmentKey {
    static let defaultValue = ResolvedIslandMetrics.fallback
}

extension EnvironmentValues {
    var islandDisplayMetrics: ResolvedIslandMetrics {
        get { self[IslandDisplayMetricsEnvironmentKey.self] }
        set { self[IslandDisplayMetricsEnvironmentKey.self] = newValue }
    }
}
