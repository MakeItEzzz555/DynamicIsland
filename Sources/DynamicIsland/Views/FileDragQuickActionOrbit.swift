import AppKit
import SwiftUI

/// Source-backed metrics from Droppy's ShelfQuickActionsBar. DynamicIsland
/// keeps them in one place so render, hit testing and motion cannot drift.
enum FileDragQuickActionMetrics {
    static let diameter: CGFloat = 32
    static let spacing: CGFloat = 12
    static let horizontalBridgeInset: CGFloat = 8
    static let gap: CGFloat = 8
    static let targetedScale: CGFloat = 1.18
    static let hoverScale: CGFloat = 1.05
    static let stagger: TimeInterval = 0.03
    static let insertionResponse: TimeInterval = 0.26
    static let insertionDamping: CGFloat = 0.80
    static let hoverResponse: TimeInterval = 0.30
    static let accessoryHeight: CGFloat = gap + diameter + 12

    static var orbitWidth: CGFloat {
        let count = CGFloat(FileDragQuickAction.allCases.count)
        return diameter * count + spacing * max(count - 1, 0) + horizontalBridgeInset * 2
    }
}

struct FileDragQuickActionOrbit: View {
    @ObservedObject var session: FileDragSessionController
    let layoutStore: IslandLayoutStore
    let reduceMotion: Bool

    @State private var appKitBridgeTargeted = false
    @State private var swiftUIBridgeTargeted = false

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.001))
                .frame(
                    width: FileDragQuickActionMetrics.orbitWidth,
                    height: FileDragQuickActionMetrics.diameter + 8
                )
                .background {
                    FileDragBridgeView(isTargeted: appKitBridgeBinding)
                }
                .onDrop(
                    of: FileDropProviderLoader.acceptedTypes,
                    isTargeted: swiftUIBridgeBinding
                ) { _ in
                    // The visible bridge never owns a drop. SwiftUI handles
                    // ordinary providers while the AppKit background also
                    // recognizes native file-promise pasteboard types.
                    false
                }

            HStack(spacing: FileDragQuickActionMetrics.spacing) {
                ForEach(Array(FileDragQuickAction.allCases.enumerated()), id: \.element.id) { index, action in
                    FileDragQuickActionButton(
                        action: action,
                        session: session,
                        reduceMotion: reduceMotion
                    )
                    .transition(insertionTransition(index: index))
                }
            }
        }
        .fixedSize()
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FileDragQuickActionFrameKey.self,
                    value: proxy.frame(in: .named(IslandCanvasCoordinateSpace.name))
                )
            }
        }
        .onPreferenceChange(FileDragQuickActionFrameKey.self) { frame in
            guard !frame.isEmpty else { return }
            layoutStore.setExpandedAccessoryFrames([
                IslandCanvasCoordinateSpace.appKitLocalRect(
                    fromSwiftUI: frame,
                    canvasHeight: layoutStore.canvasSize.height
                )
            ], owner: .fileDragOrbit)
        }
        .onDisappear {
            layoutStore.setExpandedAccessoryFrames([], owner: .fileDragOrbit)
            session.setBridgeTargeted(false)
            session.setHoveredAction(nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File drag quick actions")
    }

    private var appKitBridgeBinding: Binding<Bool> {
        Binding(
            get: { appKitBridgeTargeted },
            set: { targeted in
                appKitBridgeTargeted = targeted
                updateBridgeOwnership()
            }
        )
    }

    private var swiftUIBridgeBinding: Binding<Bool> {
        Binding(
            get: { swiftUIBridgeTargeted },
            set: { targeted in
                swiftUIBridgeTargeted = targeted
                updateBridgeOwnership()
            }
        )
    }

    private func updateBridgeOwnership() {
        session.setBridgeTargeted(appKitBridgeTargeted || swiftUIBridgeTargeted)
    }

    private func insertionTransition(index: Int) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let animation = Animation
            .spring(
                response: FileDragQuickActionMetrics.insertionResponse,
                dampingFraction: FileDragQuickActionMetrics.insertionDamping
            )
            .delay(TimeInterval(index) * FileDragQuickActionMetrics.stagger)
        return .asymmetric(
            insertion: .scale(scale: 0.5).combined(with: .opacity).animation(animation),
            removal: .scale(scale: 0.5).combined(with: .opacity).animation(.easeOut(duration: 0.16))
        )
    }
}

struct FileDragQuickActionCircleVisual: View {
    let action: FileDragQuickAction
    var targeted = false
    var hovering = false
    var reduceMotion = false

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.96))
            Circle()
                .stroke(
                    Color.white.opacity(targeted ? 0.30 : (hovering ? 0.20 : 0.08)),
                    lineWidth: 1
                )
            Image(systemName: action.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .frame(
            width: FileDragQuickActionMetrics.diameter,
            height: FileDragQuickActionMetrics.diameter
        )
        .scaleEffect(scale)
        .contentShape(Circle())
        .animation(targetAnimation, value: targeted)
        .animation(targetAnimation, value: hovering)
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        if targeted { return FileDragQuickActionMetrics.targetedScale }
        if hovering { return FileDragQuickActionMetrics.hoverScale }
        return 1
    }

    private var targetAnimation: Animation? {
        guard !reduceMotion else { return .easeOut(duration: 0.12) }
        return .spring(response: FileDragQuickActionMetrics.hoverResponse, dampingFraction: 0.82)
    }
}

private struct FileDragQuickActionButton: View {
    let action: FileDragQuickAction
    @ObservedObject var session: FileDragSessionController
    let reduceMotion: Bool

    @State private var targeted = false
    @State private var hovering = false
    @State private var shareAnchor = SharingAnchorHolder()

    var body: some View {
        FilePromiseDropTarget(
            isTargeted: targetingBinding,
            onDropStarted: {
                session.claimDrop(action)?.generation
            },
            onFilesReceived: { generation, urls in
                finishDrop(generation: generation, urls: urls)
            },
            onMaterializationFailed: { generation, message in
                let claim = FileDragSessionController.DropClaim(generation: generation, action: action)
                session.materializationFailed(claim: claim, message: message)
            }
        ) {
            FileDragQuickActionCircleVisual(
                action: action,
                targeted: targeted,
                hovering: hovering,
                reduceMotion: reduceMotion
            )
            .background(SharingAnchorView(holder: shareAnchor))
        }
        .frame(
            width: FileDragQuickActionMetrics.diameter,
            height: FileDragQuickActionMetrics.diameter
        )
        .onHover { value in
            hovering = value
            session.setHoveredAction(value ? action : (session.hoveredAction == action ? nil : session.hoveredAction))
        }
        .help(action.explanation)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.explanation)
    }

    private var targetingBinding: Binding<Bool> {
        Binding(
            get: { targeted },
            set: { value in
                targeted = value
                session.setActionTargeted(action, value)
            }
        )
    }

    private func finishDrop(generation: Int, urls: [URL]) {
        let claim = FileDragSessionController.DropClaim(generation: generation, action: action)
        let outcome = session.completeDrop(
            claim: claim,
            action: action,
            urls: urls,
            anchor: shareAnchor.view
        )
        switch outcome {
        case .handedOff?:
            FileDragPromiseStorage.shared.scheduleCleanup(urls)
        case .unavailable?, .failed?, nil:
            FileDragPromiseStorage.shared.removeIfOwned(urls)
        }
    }
}

struct FileDragQuickActionFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}
