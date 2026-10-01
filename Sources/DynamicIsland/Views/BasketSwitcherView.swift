import AppKit
import SwiftUI

// Source parity: Droppy/BasketSwitcherView.swift — dimmed overlay (black
// 0.35), cards 160×180 with 16 pt radius in an HStack(spacing 20) inside a
// 24 pt padded, 20 pt radius material container; accent-tinted cards with a
// 44×5 handle, stack preview and item count; dashed "New Basket" card;
// targeted cards press to 0.97, hovered cards grow to 1.02. Difference: each
// card is an AppKit file-promise drop target (Photos-safe) and a drop goes
// to exactly that basket through BasketManager's one-shot drop claim.

struct BasketSwitcherCardModel: Identifiable {
    let id: UUID
    let state: BasketState
}

struct BasketSwitcherActions {
    var dropStarted: (UUID?) -> Int? = { _ in nil }
    var dropFinished: (Int, [URL]) -> Void = { _, _ in }
    var dropFailed: (Int, String) -> Void = { _, _ in }
    var dismiss: () -> Void = {}
    var isInteractive = false
}

struct BasketSwitcherView: View {
    let baskets: [BasketState]
    let metrics: BasketMetrics
    let actions: BasketSwitcherActions
    var thumbnails: BasketThumbnailStore = .shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: actions.dismiss)
            HStack(spacing: 20) {
                ForEach(baskets, id: \.id) { basket in
                    card(for: basket.id) { targeted in
                        BasketSwitcherCard(state: basket, isTargeted: targeted, metrics: metrics, thumbnails: thumbnails)
                    }
                }
                card(for: nil) { targeted in NewBasketSwitcherCard(isTargeted: targeted) }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            )
        }
        .environment(\.colorScheme, .dark)
    }

    private func card<Content: View>(for basketID: UUID?, @ViewBuilder content: @escaping (Bool) -> Content) -> some View {
        SwitcherDropCard(actions: actions, basketID: basketID, reduceMotion: reduceMotion, content: content)
    }
}

private struct SwitcherDropCard<Content: View>: View {
    let actions: BasketSwitcherActions
    let basketID: UUID?
    let reduceMotion: Bool
    let content: (Bool) -> Content
    @State private var isTargeted = false
    @State private var isHovered = false

    var body: some View {
        Group {
            if actions.isInteractive {
                FilePromiseDropTarget(
                    isTargeted: $isTargeted,
                    onDropStarted: { actions.dropStarted(basketID) },
                    onFilesReceived: actions.dropFinished,
                    onMaterializationFailed: actions.dropFailed
                ) { content(isTargeted) }
            } else {
                content(isTargeted)
            }
        }
        .frame(width: 160, height: 180)
        .scaleEffect(reduceMotion ? 1 : (isTargeted ? 0.97 : (isHovered ? 1.02 : 1)))
        .animation(reduceMotion ? nil : BasketMotion.bouncy, value: isTargeted)
        .animation(reduceMotion ? nil : BasketMotion.bouncy, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct BasketSwitcherCard: View {
    @ObservedObject var state: BasketState
    let isTargeted: Bool
    let metrics: BasketMetrics
    let thumbnails: BasketThumbnailStore

    var body: some View {
        let accent = state.accent.color
        VStack(spacing: 0) {
            Capsule().fill(accent.opacity(0.5)).frame(width: 44, height: 5).padding(.top, 8).padding(.bottom, 8)
            Group {
                if state.items.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: isTargeted ? "plus.circle.fill" : "tray")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(accent.opacity(isTargeted ? 1 : 0.6))
                        Text(isTargeted ? "Drop here" : "Empty").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    BasketStackPreview(items: state.items, metrics: BasketMetrics(scale: 0.9), thumbnails: thumbnails)
                        .scaleEffect(0.75)
                        .frame(width: 100, height: 76)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 4) {
                if !state.items.isEmpty {
                    Text(state.titleText).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.92))
                }
                Text(isTargeted ? "Release!" : "Drop here")
                    .font(.caption2.weight(isTargeted ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isTargeted ? 0.95 : 0.72))
            }
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 10)
        .frame(width: 160, height: 180)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(isTargeted ? 0.5 : 0.2))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent.opacity(isTargeted ? 1 : 0.4), lineWidth: isTargeted ? 3 : 2))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.accent.name) basket, \(state.items.isEmpty ? "empty" : state.titleText)")
    }
}

struct NewBasketSwitcherCard: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(isTargeted ? 1 : 0.7))
            Text("New Basket").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.9))
            Text(isTargeted ? "Release!" : "Drop to create").font(.caption2).foregroundStyle(.white.opacity(0.72))
        }
        .frame(width: 160, height: 180)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isTargeted ? 0.25 : 0.1))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(isTargeted ? 1 : 0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4])))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New basket")
    }
}

/// Screen-sized overlay panel for the switcher. Shown only during an active
/// external drag; dismissed on drop, background click, or drag end.
@MainActor
final class BasketSwitcherWindowController {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(baskets: [BasketState], on screen: NSScreen, actions: BasketSwitcherActions) {
        hide()
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let metrics = BasketMetrics(display: IslandDisplayMetricsResolver.resolve(screen: screen))
        let hosting = NSHostingView(rootView: BasketSwitcherView(baskets: baskets, metrics: metrics, actions: actions))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.1 : 0.2
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }
}
