import AppKit
import SwiftUI

/// One fixed arc under the shell; targeting changes appearance, never hit geometry.
enum FileDragOrbitMetrics {
    static let targetSize = CGSize(width: 76, height: 70)
    static let spacing: CGFloat = 4
    static let arcDepth: CGFloat = 22
    static let gap: CGFloat = 6
    static let accessoryHeight = gap + targetSize.height + arcDepth + 4

    static func width(actionCount: Int) -> CGFloat {
        CGFloat(actionCount) * (targetSize.width + spacing) - spacing + 8
    }

    static func frame(shell: CGRect, actionCount: Int) -> CGRect {
        let width = width(actionCount: actionCount)
        return CGRect(x: shell.midX - width / 2, y: shell.minY - accessoryHeight,
                      width: width, height: accessoryHeight)
    }

    static func targetFrame(index: Int, count: Int) -> CGRect {
        let progress = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0.5
        let depth = sin(progress * .pi) * arcDepth
        return CGRect(x: 4 + CGFloat(index) * (targetSize.width + spacing), y: gap + depth,
                      width: targetSize.width, height: targetSize.height)
    }

    @MainActor
    static func reserve(in profile: inout ExpandedPresentationProfile, session: FileDragSessionController) {
        guard session.isActive else { return }
        profile.accessoryHeight = max(profile.accessoryHeight, accessoryHeight)
        profile.accessoryWidth = max(profile.accessoryWidth, width(actionCount: session.orbitActions.count))
    }
}

struct FileDragOrbitView: View {
    @ObservedObject var session: FileDragSessionController
    let layoutStore: IslandLayoutStore
    let frame: CGRect
    let reduceMotion: Bool
    let anchor: SharingAnchorHolder
    let allowsDrop: () -> Bool
    var executor: FileDragActionExecutor = .production
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let actions = session.orbitActions
        let generation = session.generation
        ZStack(alignment: .topLeading) {
            FileDragBridgeView(isTargeted: Binding(get: { false }, set: {
                guard allowsDrop(), session.isActive, session.generation == generation else { return }
                session.setBridgeTargeted($0)
            }))
                .accessibilityHidden(true)
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                let target = FileDragOrbitMetrics.targetFrame(index: index, count: actions.count)
                FilePromiseDropTarget(isTargeted: targeted(action), onDropStarted: {
                    guard allowsDrop(), session.isActive, session.orbitActions.contains(action) else { return nil }
                    return session.claimDrop(action)?.generation
                }, onFilesReceived: { generation, urls in
                    guard allowsDrop() else {
                        if session.generation == generation { session.cancel() }
                        FileDragPromiseStorage.shared.removeIfOwned(urls)
                        return
                    }
                    let claim = FileDragSessionController.DropClaim(generation: generation, action: action)
                    // Use the stable root anchor: the arc retires as soon as the handoff completes.
                    let forwarding = FileDragActionExecutor { action, urls, _ in
                        executor.perform(action, urls: urls, anchor: anchor.view, layoutStore: layoutStore,
                                         local: session.localActions)
                    }
                    let outcome = session.completeDrop(claim: claim, action: action, urls: urls,
                                                       anchor: anchor.view, executor: forwarding)
                    if outcome == .handedOff { FileDragPromiseStorage.shared.scheduleCleanup(urls) }
                    else { FileDragPromiseStorage.shared.removeIfOwned(urls) }
                }, onMaterializationFailed: { generation, message in
                    session.materializationFailed(claim: .init(generation: generation, action: action), message: message)
                }) {
                    targetLabel(action)
                }
                .frame(width: target.width, height: target.height)
                .position(x: target.midX, y: target.midY)
                .accessibilityLabel(action.title)
                .accessibilityHint(action.explanation)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File drag actions")
        .onAppear { layoutStore.setExpandedAccessoryFrames([frame], owner: .fileDragOrbit) }
        .onChange(of: frame) { _, next in layoutStore.setExpandedAccessoryFrames([next], owner: .fileDragOrbit) }
        .onDisappear { layoutStore.setExpandedAccessoryFrames([], owner: .fileDragOrbit) }
    }

    private func targeted(_ action: FileDragQuickAction) -> Binding<Bool> {
        let generation = session.generation
        return Binding(get: { session.targetedAction == action }, set: {
            guard allowsDrop(), session.isActive, session.generation == generation else { return }
            session.setActionTargeted(action, $0)
        })
    }

    private func targetLabel(_ action: FileDragQuickAction) -> some View {
        let targeted = session.targetedAction == action
        return VStack(spacing: 5) {
            Image(systemName: action.symbolName)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(targeted ? Color.accentColor : Color(white: reduceTransparency ? 0.16 : 0.10), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(contrast == .increased ? 0.8 : 0.24), lineWidth: 1))
            Text(action.title)
                .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color(white: 0.06), in: Capsule())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(WorkspaceDesign.hover(reduceMotion: reduceMotion), value: targeted)
        .accessibilityElement(children: .combine)
    }
}
