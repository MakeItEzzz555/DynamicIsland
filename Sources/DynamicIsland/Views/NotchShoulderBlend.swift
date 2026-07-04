import SwiftUI

struct NotchShoulderBlend: View {
    let isExpanded: Bool
    let color: Color

    private var shoulderSize: CGSize {
        isExpanded
            ? CGSize(width: 44, height: 28)
            : CGSize(width: 28, height: 22)
    }

    private var shoulderOffsetX: CGFloat {
        isExpanded ? 24 : 14
    }

    private var shoulderOffsetY: CGFloat {
        isExpanded ? -10 : -8
    }

    private var shoulderOpacity: Double {
        1.0
    }

    var body: some View {
        GeometryReader { proxy in
            let shoulderCenterY = shoulderOffsetY + shoulderSize.height / 2
            let insetFromSide = shoulderOffsetX

            ZStack(alignment: .topLeading) {
                Ellipse()
                    .fill(color.opacity(shoulderOpacity))
                    .frame(width: shoulderSize.width, height: shoulderSize.height)
                    .position(x: insetFromSide, y: shoulderCenterY)

                Ellipse()
                    .fill(color.opacity(shoulderOpacity))
                    .frame(width: shoulderSize.width, height: shoulderSize.height)
                    .position(x: proxy.size.width - insetFromSide, y: shoulderCenterY)
            }
        }
        .allowsHitTesting(false)
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
