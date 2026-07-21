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
        notchShoulderDebugTint ? .red.opacity(0.65) : shellColor.opacity(shoulderOpacity)
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

let notchShoulderBlendEnabled = true
let notchShoulderUseAssets = false
let collapsedShoulderEnabled = true
let expandedShoulderEnabled = false
let notchShoulderDebugTint = false

let collapsedShoulderWidth: CGFloat = 34
let collapsedShoulderHeight: CGFloat = 28
let collapsedShoulderSideInset: CGFloat = 10
let collapsedShoulderYOffset: CGFloat = -9
let collapsedShoulderOpacity: Double = 1.0

let expandedShoulderWidth: CGFloat = 44
let expandedShoulderHeight: CGFloat = 28
let expandedShoulderSideInset: CGFloat = 24
let expandedShoulderYOffset: CGFloat = -10
let expandedShoulderOpacity: Double = 1.0

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
