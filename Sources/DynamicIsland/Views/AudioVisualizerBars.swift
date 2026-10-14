import SwiftUI

/// One rendering layer; level provenance belongs to each adapter, not the bars.
struct AudioVisualizerBars: View {
    let levels: [CGFloat]
    let variant: AudioVisualizerVariant
    let palette: AudioVisualizerPalette
    let accent: Color
    let secondary: Color?
    var opacity: Double = 1
    var glow = false

    var body: some View {
        HStack(alignment: .center, spacing: variant.spacing) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(color(index))
                    .opacity(opacity)
                    .frame(width: variant.barWidth, height: variant.maximumBarHeight *
                        min(max(levels[index].isFinite ? levels[index] : SpectrumBarMapper.floor, SpectrumBarMapper.floor), 1))
                    .shadow(color: accent.opacity(glow ? 0.22 : 0), radius: glow ? 3 : 0)
            }
        }
        .saturation(palette == .media ? 1.2 : 1)
    }

    private func color(_ index: Int) -> AnyShapeStyle {
        if palette == .call { return AnyShapeStyle(LinearGradient(colors: [.green, .yellow], startPoint: .bottom, endPoint: .top)) }
        return AnyShapeStyle(VisualizerGradient.color(at: index, count: levels.count, primary: accent, secondary: secondary))
    }
}

/// Spatial weighting of one microphone envelope, not eight frequency bands.
enum MicrophoneBarMapper {
    static func levels(level: Double, barCount: Int) -> [CGFloat] {
        guard barCount > 0 else { return [] }
        let value = min(max(level.isFinite ? level : 0, 0), 1)
        return (0..<barCount).map { index in
            let p = Double(index) / Double(max(barCount - 1, 1))
            let weight = 0.45 + 0.55 * sin(p * .pi)
            return SpectrumBarMapper.floor + CGFloat(value * weight) * (1 - SpectrumBarMapper.floor)
        }
    }
}
