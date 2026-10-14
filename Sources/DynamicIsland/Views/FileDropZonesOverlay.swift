import AppKit
import SwiftUI

/// The four destinations offered while files are dragged over the Tray.
/// Every zone first adds the files to the Tray through the existing drop
/// claim, so a drop is never lost; the zone then decides what happens next.
enum FileDropZone: String, CaseIterable, Identifiable {
    case keep, convert, share, zip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keep: "Keep in Tray"
        case .convert: "Convert"
        case .share: "Share"
        case .zip: "Create ZIP"
        }
    }

    var detail: String {
        switch self {
        case .keep: "Add to the Tray"
        case .convert: "Choose a format · originals kept"
        case .share: "Open the Share menu"
        case .zip: "New archive · originals kept"
        }
    }

    var symbolName: String {
        switch self {
        case .keep: "tray.and.arrow.down.fill"
        case .convert: "arrow.triangle.2.circlepath"
        case .share: "square.and.arrow.up"
        case .zip: "doc.zipper"
        }
    }
}

/// 2x2 drop targets. Geometry never changes while a drag is in flight; only
/// the targeted zone's fill and label weight change, so hit areas are stable.
struct FileDropZonesOverlay: View {
    let reduceMotion: Bool
    /// The zone under the pointer (nil when none); owners keep the drag
    /// session alive while any zone is targeted.
    let onTargetChange: (FileDropZone?) -> Void
    let onDrop: (FileDropZone, [NSItemProvider]) -> Bool

    @State private var targeted: FileDropZone?

    private let spacing: CGFloat = 6
    private let cornerRadius: CGFloat = 18

    var body: some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            GridRow { zone(.keep); zone(.convert) }
            GridRow { zone(.share); zone(.zip) }
        }
        .padding(spacing)
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: cornerRadius + spacing, style: .continuous))
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: targeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File drop destinations")
    }

    private func zone(_ zone: FileDropZone) -> some View {
        let isTargeted = targeted == zone
        return VStack(spacing: 5) {
            Image(systemName: zone.symbolName)
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(isTargeted && !reduceMotion ? 1.08 : 1)
            Text(zone.title)
                .font(.system(size: 12.5, weight: isTargeted ? .bold : .semibold, design: .rounded))
            Text(zone.detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(isTargeted ? 0.82 : 0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isTargeted ? Color.cyan.opacity(0.30) : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(isTargeted ? Color.cyan.opacity(0.9) : Color.white.opacity(0.10), lineWidth: isTargeted ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onDrop(of: FileDropProviderLoader.acceptedTypes, isTargeted: binding(for: zone)) { providers in
            targeted = nil
            onTargetChange(nil)
            return onDrop(zone, providers)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(zone.title). \(zone.detail)")
        .accessibilityAddTraits(isTargeted ? .isSelected : [])
    }

    private func binding(for zone: FileDropZone) -> Binding<Bool> {
        Binding(
            get: { targeted == zone },
            set: { isOver in
                if isOver { targeted = zone } else if targeted == zone { targeted = nil }
                onTargetChange(targeted)
            }
        )
    }
}
