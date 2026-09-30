// Portions adapted from Droppy (https://github.com/1of1Adam/Droppy) at commit
// dd2d16ccbdc6aa22b456e199442b43a07aa446af:
// - Droppy/DroppyButtonStyle.swift: DroppyToggleButtonContent fill/border
//   opacities, pressed/hover scale.
// - Droppy/DroppyAnimation.swift: `hover` spring.
// - Droppy/DroppyDesign.swift: DroppyRadius.medium.
// - Droppy/Extensions/Camera/SnapCameraShelfPanel.swift: preview stroke,
//   background and shadow.
// Droppy is licensed GPL-3.0 with the Commons Clause; reused here for a
// private, personal build only. See research/SOURCE_PARITY_MANIFEST.md.

import SwiftUI

enum WorkspaceDesign {
    /// DroppyRadius.medium.
    static let tileCornerRadius: CGFloat = 12
    /// Droppy dark-mode `AdaptiveColors.overlayAuto` tint.
    static let overlayTint = Color.white

    /// Droppy `DroppyAnimation.hover`.
    static func hover(reduceMotion: Bool) -> Animation {
        let scale = WorkspaceMotion.motionScale(refreshRate: WorkspaceMotion.currentRefreshRate)
        if reduceMotion { return .easeOut(duration: 0.14 * scale) }
        return .spring(response: 0.24 * scale, dampingFraction: 0.8)
    }
}

/// Droppy toggle/tool tile treatment for right-workspace controls.
struct WorkspaceTileButtonStyle: ButtonStyle {
    var isOn = false
    var accent: Color = .blue
    var cornerRadius: CGFloat = WorkspaceDesign.tileCornerRadius

    func makeBody(configuration: Configuration) -> some View {
        WorkspaceTileButtonBody(
            configuration: configuration,
            isOn: isOn,
            accent: accent,
            cornerRadius: cornerRadius
        )
    }
}

private struct WorkspaceTileButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isOn: Bool
    let accent: Color
    let cornerRadius: CGFloat

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isOn ? 2 : 1)
            )
            .scaleEffect(scale)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(WorkspaceDesign.hover(reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(WorkspaceDesign.hover(reduceMotion: reduceMotion), value: isHovering)
            .onHover { isHovering = $0 && isEnabled }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        return configuration.isPressed ? 0.95 : (isHovering ? 1.02 : 1)
    }

    private var backgroundColor: Color {
        if isOn {
            return accent.opacity(configuration.isPressed ? 0.35 : (isHovering ? 0.30 : 0.25))
        }
        return WorkspaceDesign.overlayTint.opacity(configuration.isPressed ? 0.18 : (isHovering ? 0.14 : 0.10))
    }

    private var borderColor: Color {
        if isOn { return accent.opacity(0.6) }
        return WorkspaceDesign.overlayTint.opacity(isHovering ? 0.25 : 0.15)
    }
}

/// Standard content for a workspace tool tile: icon, title, live status.
struct WorkspaceTileLabel: View {
    let symbol: String
    let title: String
    let status: String?
    var isOn = false
    var accent: Color = .blue
    var isBusy = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? accent : .white.opacity(0.78))
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if let status {
                    Text(status)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
