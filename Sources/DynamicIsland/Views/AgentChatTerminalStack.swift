import SwiftUI

/// Composition owns presentation only. The retained chat keeps its editor and
/// measured viewport; the terminal renderer mounts only on its visible page.
struct AgentChatTerminalStack: View {
    @ObservedObject var presentation: AgentWorkspacePresentation
    let isVisible: Bool
    let reduceMotion: Bool
    let layoutStore: IslandLayoutStore?
    let chat: () -> AnyView
    let terminal: () -> AnyView
    @State private var swipeOwner = UUID()
    @State private var headerFrame: CGRect = .zero
    @Namespace private var selection

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(AgentStackPage.allCases) { page in
                        Button {
                            withAnimation(AgentWorkspaceMotion.selection(reduceMotion: reduceMotion)) {
                                presentation.showStack(page)
                            }
                        } label: {
                            Label(page.title, systemImage: page.symbol)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 10).frame(height: 26)
                                .background {
                                    if presentation.stackPage == page {
                                        Capsule().fill(.white.opacity(0.12))
                                            .matchedGeometryEffect(id: "stack-selection", in: selection)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show stacked \(page.title)")
                        .accessibilityAddTraits(presentation.stackPage == page ? .isSelected : [])
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 5)
                .background(GeometryReader { header in
                    Color.clear.preference(key: AgentStackHeaderFrameKey.self,
                        value: header.frame(in: .named(IslandCanvasCoordinateSpace.name)))
                })
                .onPreferenceChange(AgentStackHeaderFrameKey.self) { frame in
                    // Header-only swipe ownership never steals terminal mouse,
                    // text selection, composer input or vertical transcript scroll.
                    DispatchQueue.main.async {
                        headerFrame = frame
                        layoutStore?.setAgentStackSwipeRegion(isVisible ? IslandCanvasCoordinateSpace.appKitLocalRect(fromSwiftUI: frame, canvasHeight: layoutStore?.canvasSize.height ?? 0) : .zero, owner: swipeOwner)
                    }
                }
                RetainedWorkspacePages(pages: AgentStackPage.allCases, selection: presentation.stackPage,
                    size: CGSize(width: geometry.size.width, height: max(0, geometry.size.height - 30)),
                    travel: reduceMotion ? 0 : min(24, geometry.size.width * 0.06), blur: 0, reduceMotion: reduceMotion) { page in
                    switch page {
                    case .chat: chat()
                    case .terminal: terminal()
                    }
                }
                .animation(AgentWorkspaceMotion.selection(reduceMotion: reduceMotion), value: presentation.stackPage)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat and Terminal stack")
        .accessibilityValue(presentation.stackPage.title)
        .accessibilityAdjustableAction { direction in
            presentation.swipeStack(by: direction == .increment ? 1 : -1)
        }
        .onAppear { installSwipeAction() }
        .onChange(of: isVisible) { _, visible in
            if visible { installSwipeAction() }
            else {
                layoutStore?.removeAgentStackSwipe(owner: swipeOwner)
            }
        }
        .onDisappear {
            layoutStore?.removeAgentStackSwipe(owner: swipeOwner)
        }
    }

    private func installSwipeAction() {
        guard isVisible else { return }
        layoutStore?.installAgentStackSwipe(owner: swipeOwner) { [weak presentation] direction in
            withAnimation(AgentWorkspaceMotion.selection(reduceMotion: reduceMotion)) {
                presentation?.swipeStack(by: direction)
            }
        }
        layoutStore?.setAgentStackSwipeRegion(IslandCanvasCoordinateSpace.appKitLocalRect(fromSwiftUI: headerFrame,
            canvasHeight: layoutStore?.canvasSize.height ?? 0), owner: swipeOwner)
    }
}

private struct AgentStackHeaderFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
