// Portions adapted from Droppy (https://github.com/1of1Adam/Droppy),
// Droppy/DroppyAnimation.swift at commit dd2d16ccbdc6aa22b456e199442b43a07aa446af:
// smoothContent(for:), the display-refresh motion scale, expandOpen /
// expandClose (asymmetric shell springs) and the NotchBlurModifier
// blur/opacity treatment.
// Droppy is licensed GPL-3.0 with the Commons Clause; reused here for a
// private, personal build only. See research/SOURCE_PARITY_MANIFEST.md.

import AppKit
import SwiftUI

/// Content-transition motion shared by paged right-workspace surfaces.
enum WorkspaceMotion {
    /// Droppy `smoothContent` base duration.
    static let smoothContentBaseDuration: Double = 0.36
    /// Droppy premium transition blur radius.
    static let transitionBlurRadius: CGFloat = 6
    /// Horizontal travel of a paging transition, as a fraction of the page
    /// width (DynamicIsland addition: Droppy's swap is opacity-only).
    static let pageTravelFraction: CGFloat = 0.34

    /// Droppy: slightly lengthen motion on lower-refresh displays so frame
    /// stepping is less visible (1.0 ≥100 Hz, 1.1 ≥75 Hz, else 1.18).
    static func motionScale(refreshRate: Int) -> Double {
        if refreshRate >= 100 { return 1.0 }
        if refreshRate >= 75 { return 1.1 }
        return 1.18
    }

    static var currentRefreshRate: Int {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        return max(screen?.maximumFramesPerSecond ?? 60, 60)
    }

    /// Droppy `expandOpen` / `expandClose`: the shell opens on a responsive
    /// spring (response 0.40, damping 0.90) and closes on a more damped,
    /// decisive one (0.36, 0.97), both display-tuned. DynamicIsland maps the
    /// user's preset/speed onto the response (Normal preset = Droppy's 0.40).
    /// Reduce Motion uses Droppy's ease-out (0.26 open / 0.24 close).
    static let shellOpenDamping = 0.90, shellCloseDamping = 0.97
    static let shellCloseResponseRatio = 0.36 / 0.40
    static func shellSpring(opening: Bool, baseResponse: Double, reduceMotion: Bool,
                            refreshRate: Int = currentRefreshRate) -> Animation {
        let scale = motionScale(refreshRate: refreshRate)
        if reduceMotion { return .easeOut(duration: (opening ? 0.26 : 0.24) * scale) }
        let response = max(0.01, baseResponse) * scale * (opening ? 1 : shellCloseResponseRatio)
        return .spring(response: response, dampingFraction: opening ? shellOpenDamping : shellCloseDamping, blendDuration: 0)
    }

    static func smoothContentDuration(refreshRate: Int = currentRefreshRate) -> Double {
        smoothContentBaseDuration * motionScale(refreshRate: refreshRate)
    }

    /// Droppy `smoothContent(for:)`: `.smooth(duration: 0.36 × scale)`.
    static func smoothContent(reduceMotion: Bool) -> Animation {
        if reduceMotion {
            // Droppy's reduced-motion content timing.
            return .easeOut(duration: 0.18 * motionScale(refreshRate: currentRefreshRate))
        }
        return .smooth(duration: smoothContentDuration())
    }

    /// Droppy uses lightweight effects (no blur) at ≤60 Hz or in Low Power Mode.
    static var prefersLightweightEffects: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled || currentRefreshRate <= 60
    }

    /// Directional page transition: the incoming page enters from the swipe
    /// direction while the outgoing page leaves the other way, with
    /// Droppy's opacity + blur treatment. Reduce Motion: opacity only.
    static func pageTransition(direction: Int, width: CGFloat, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        let travel = max(width, 1) * pageTravelFraction
        let blur = prefersLightweightEffects ? 0 : transitionBlurRadius
        let sign: CGFloat = direction >= 0 ? 1 : -1
        return .asymmetric(
            insertion: .modifier(
                active: WorkspacePageTransitionModifier(offset: travel * sign, blur: blur, opacity: 0),
                identity: WorkspacePageTransitionModifier(offset: 0, blur: 0, opacity: 1)
            ),
            removal: .modifier(
                active: WorkspacePageTransitionModifier(offset: -travel * sign, blur: blur, opacity: 0),
                identity: WorkspacePageTransitionModifier(offset: 0, blur: 0, opacity: 1)
            )
        )
    }
}

struct WorkspacePageTransitionModifier: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}
