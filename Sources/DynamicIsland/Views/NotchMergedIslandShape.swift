import SwiftUI

struct NotchMergedIslandShape: Shape {
    var isExpanded: Bool

    private var bottomRadius: CGFloat {
        isExpanded ? 36 : 22
    }

    func path(in rect: CGRect) -> Path {
        let bottomRadius = min(self.bottomRadius, rect.width * 0.18, rect.height * 0.44)
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: maxX - bottomRadius, y: maxY),
            control: CGPoint(x: maxX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + bottomRadius, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: minX, y: maxY - bottomRadius),
            control: CGPoint(x: minX, y: maxY)
        )
        path.closeSubpath()
        return path
    }
}

struct NotchShoulderBlendView: View {
    let isExpanded: Bool
    let color: Color

    private var shoulderRadius: CGFloat {
        isExpanded ? 34 : 19
    }

    private var shoulderOffsetX: CGFloat {
        isExpanded ? 60 : 34
    }

    private var shoulderOffsetY: CGFloat {
        isExpanded ? -6 : -4
    }

    private var shoulderOpacity: Double {
        1.0
    }

    var body: some View {
        GeometryReader { proxy in
            let centerX = proxy.size.width / 2
            let diameter = shoulderRadius * 2

            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(color.opacity(shoulderOpacity))
                    .frame(width: diameter, height: diameter)
                    .position(x: centerX - shoulderOffsetX, y: shoulderOffsetY + shoulderRadius)

                Circle()
                    .fill(color.opacity(shoulderOpacity))
                    .frame(width: diameter, height: diameter)
                    .position(x: centerX + shoulderOffsetX, y: shoulderOffsetY + shoulderRadius)
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
