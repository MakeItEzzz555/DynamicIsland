import SwiftUI

struct IslandSurfaceBackground<ShellShape: Shape>: View {
    let theme: IslandThemeStyle
    let isExpanded: Bool
    let isShellMorphing: Bool
    let opacity: Double
    let shape: ShellShape

    var body: some View {
        ZStack {
            switch theme {
            case .classicBlack:
                classicBlack
            case .liquidGlass:
                liquidGlass
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    private var classicBlack: some View {
        shape.fill(Self.classicBlackColor.opacity(opacity))
    }

    private var liquidGlass: some View {
        ZStack {
            // TODO: When building with an SDK that exposes SwiftUI glassEffect(_:in:),
            // add the native Liquid Glass path here with glassEffect(_:in:), and use
            // GlassEffectContainer/glassEffectTransition for multiple native glass shapes.
            // The custom glossy fallback keeps the app compiling for the current macOS 14.6+ target.
            shape.fill(Self.classicBlackColor.opacity(0.82 * opacity))
            shape.fill(.ultraThinMaterial)
                .opacity(isShellMorphing ? 0.08 : 0.14)
            shape.fill(smokedGlassTint)
            shape.fill(topGloss)
                .blendMode(.screen)
            shape.fill(topEdgeGlow)
                .blendMode(.screen)
            shape.fill(diagonalSpecularSheen)
                .blendMode(.screen)
            shape.fill(bottomDepth)
            shape.stroke(rimGradient, lineWidth: 1)
            shape.stroke(Color.white.opacity(isShellMorphing ? 0.08 : 0.13), lineWidth: 0.5)
        }
    }

    private var smokedGlassTint: LinearGradient {
        LinearGradient(
            colors: [
                Color.black.opacity((isShellMorphing ? 0.74 : 0.68) * opacity),
                Color.black.opacity((isShellMorphing ? 0.58 : 0.50) * opacity),
                Color.black.opacity((isShellMorphing ? 0.70 : 0.62) * opacity)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topGloss: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isShellMorphing ? 0.12 : 0.20),
                Color.white.opacity(isShellMorphing ? 0.045 : 0.075),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .center
        )
    }

    private var topEdgeGlow: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isShellMorphing ? 0.08 : 0.15),
                Color.white.opacity(isShellMorphing ? 0.02 : 0.045),
                Color.clear
            ],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.24)
        )
    }

    private var diagonalSpecularSheen: LinearGradient {
        LinearGradient(
            colors: [
                Color.clear,
                Color.white.opacity(isShellMorphing ? 0.055 : 0.12),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bottomDepth: LinearGradient {
        LinearGradient(
            colors: [
                Color.clear,
                Color.black.opacity((isShellMorphing ? 0.26 : 0.32) * opacity)
            ],
            startPoint: .center,
            endPoint: .bottom
        )
    }

    private var rimGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isShellMorphing ? 0.22 : 0.35),
                Color.white.opacity(isShellMorphing ? 0.065 : 0.10),
                Color.black.opacity(0.26)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var classicBlackColor: Color {
        Color(red: 0.001, green: 0.001, blue: 0.002)
    }
}
