import SwiftUI

struct NotchShoulderBlend: View {
    let isExpanded: Bool
    let shellColor: Color

    private var shoulderWidth: CGFloat {
        isExpanded
            ? expandedShoulderWidth
            : collapsedShoulderWidth
    }

    private var shoulderHeight: CGFloat {
        isExpanded
            ? expandedShoulderHeight
            : collapsedShoulderHeight
    }

    private var shoulderSideInset: CGFloat {
        isExpanded
            ? expandedShoulderSideInset
            : collapsedShoulderSideInset
    }

    private var shoulderOffsetY: CGFloat {
        isExpanded
            ? expandedShoulderYOffset
            : collapsedShoulderYOffset
    }

    private var shoulderTint: Color {
        if notchShoulderDebugTint {
            return isExpanded ? .blue.opacity(0.80) : .red.opacity(0.80)
        }
        return shellColor.opacity(shoulderOpacity)
    }

    private var shoulderOpacity: Double {
        isExpanded
            ? expandedShoulderOpacity
            : collapsedShoulderOpacity
    }

    var body: some View {
        GeometryReader { proxy in
            if notchShoulderUseAssets {
                EmptyView()
            } else if isExpanded {
                if expandedShoulderEnabled {
                    shoulderPair(in: proxy.size)
                }
            } else if collapsedShoulderEnabled {
                shoulderPair(in: proxy.size)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            debugRender()
        }
    }

    @ViewBuilder
    private func shoulderPair(in size: CGSize) -> some View {
        let centerY = shoulderOffsetY + shoulderHeight / 2
        let leftCenterX = shoulderSideInset + shoulderWidth / 2
        let rightCenterX = size.width - shoulderSideInset - shoulderWidth / 2

        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(shoulderTint)
                .frame(width: shoulderWidth, height: shoulderHeight)
                .position(x: leftCenterX, y: centerY)

            Ellipse()
                .fill(shoulderTint)
                .frame(width: shoulderWidth, height: shoulderHeight)
                .position(x: rightCenterX, y: centerY)
        }
    }
}

let notchShoulderBlendEnabled = false
let notchShoulderUseAssets = false
let collapsedShoulderEnabled = false
let expandedShoulderEnabled = false
let notchShoulderDebugTint = false

// Width/height control the shoulder blob size.
let collapsedShoulderWidth: CGFloat = 70
let collapsedShoulderHeight: CGFloat = 48
// Side inset controls horizontal placement near the shell side.
let collapsedShoulderSideInset: CGFloat = 0
// Y offset controls how far upward the shoulder protrudes.
let collapsedShoulderYOffset: CGFloat = -22
let collapsedShoulderOpacity: Double = 0.8

// Width/height control the shoulder blob size.
let expandedShoulderWidth: CGFloat = 48
let expandedShoulderHeight: CGFloat = 30
// Side inset controls horizontal placement near the shell side.
let expandedShoulderSideInset: CGFloat = 18
// Y offset controls how far upward the shoulder protrudes.
let expandedShoulderYOffset: CGFloat = -10
let expandedShoulderOpacity: Double = 0.94

private extension NotchShoulderBlend {
    func debugRender() {
        #if DEBUG
        guard notchShoulderDebugTint else { return }
        debugPrint(
            "DynamicIsland shoulder debug render",
            "mode=\(isExpanded ? "expanded" : "collapsed")",
            "assets=\(notchShoulderUseAssets)",
            "collapsedEnabled=\(collapsedShoulderEnabled)",
            "expandedEnabled=\(expandedShoulderEnabled)",
            "width=\(shoulderWidth)",
            "height=\(shoulderHeight)",
            "sideInset=\(shoulderSideInset)",
            "yOffset=\(shoulderOffsetY)"
        )
        #endif
    }
}

private struct NotchIntegratedShellEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isNotchIntegratedShell: Bool {
        get { self[NotchIntegratedShellEnvironmentKey.self] }
        set { self[NotchIntegratedShellEnvironmentKey.self] = newValue }
    }
}

extension View {
    func notchIntegrated(_ isNotchIntegrated: Bool) -> some View {
        environment(\.isNotchIntegratedShell, isNotchIntegrated)
    }
}
