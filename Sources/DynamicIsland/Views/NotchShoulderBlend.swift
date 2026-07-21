import SwiftUI

struct NotchShoulderBlend: View {
    let isExpanded: Bool

    private var assetName: String {
        isExpanded ? "notch_shoulder_expanded" : "notch_shoulder_collapsed"
    }

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

    private var shoulderOffsetY: CGFloat {
        isExpanded
            ? expandedShoulderYOffset
            : collapsedShoulderYOffset
    }

    var body: some View {
        GeometryReader { proxy in
            Image(assetName, bundle: .module)
                .resizable()
                .interpolation(.high)
                .frame(width: shoulderWidth, height: shoulderHeight)
                .position(
                    x: proxy.size.width / 2,
                    y: shoulderOffsetY + (shoulderHeight / 2)
                )
        }
        .allowsHitTesting(false)
    }
}

let collapsedShoulderYOffset: CGFloat = -8
let collapsedShoulderWidth: CGFloat = 28
let collapsedShoulderHeight: CGFloat = 22
let expandedShoulderYOffset: CGFloat = -10
let expandedShoulderWidth: CGFloat = 44
let expandedShoulderHeight: CGFloat = 28

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
