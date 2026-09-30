import SwiftUI

/// The Island page's right column as a paged workspace. Exactly one page
/// occupies the column's geometry; paging never changes the island size.
/// Pages change by two-finger horizontal swipe over this column (routed by
/// the overlay's gesture handler), by the page indicator, or by keyboard
/// accessibility increment/decrement.
struct RightWorkspaceView<Overview: View, Productivity: View, AppsMedia: View>: View {
    /// Height reserved below the pages for the page indicator.
    static var indicatorBand: CGFloat { 14 }

    static func showsIndicator(_ configuration: RightWorkspaceConfiguration) -> Bool {
        configuration.visiblePages.count > 1 && configuration.indicatorStyle == .dots
    }

    @ObservedObject var store: RightWorkspaceStore
    let layoutStore: IslandLayoutStore?
    let reduceMotion: Bool
    @ViewBuilder let overview: () -> Overview
    @ViewBuilder let productivity: () -> Productivity
    @ViewBuilder let appsMedia: () -> AppsMedia

    /// Page actually rendered. Updated one pass after the store so the
    /// outgoing page is re-rendered with the new direction before it is
    /// removed (a removed view keeps the transition of its last render).
    @State private var displayedPage: RightWorkspacePage?

    var body: some View {
        let shownPage = displayedPage ?? store.currentPage
        let pages = store.configuration.visiblePages
        let showsIndicator = Self.showsIndicator(store.configuration)
        GeometryReader { proxy in
            let pageHeight = max(proxy.size.height - (showsIndicator ? Self.indicatorBand : 0), 0)
            VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                page(shownPage)
                    .frame(width: proxy.size.width, height: pageHeight, alignment: .topLeading)
                    .id(shownPage)
                    .transition(WorkspaceMotion.pageTransition(
                        direction: store.transitionDirection,
                        width: proxy.size.width,
                        reduceMotion: reduceMotion
                    ))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(shownPage.title) page")
            }
            .frame(width: proxy.size.width, height: pageHeight, alignment: .topLeading)
            .clipped()
            if showsIndicator {
                RightWorkspacePageIndicator(
                    pages: pages,
                    current: store.currentPage,
                    onSelect: { store.show($0) }
                )
                .frame(height: Self.indicatorBand)
            }
            }
            .background {
                if let layoutStore {
                    GeometryReader { region in
                        Color.clear.preference(
                            key: RightWorkspaceRegionKey.self,
                            value: region.frame(in: .named(IslandCanvasCoordinateSpace.name))
                        )
                    }
                    .onPreferenceChange(RightWorkspaceRegionKey.self) { frame in
                        layoutStore.setRightWorkspaceRegion(IslandCanvasCoordinateSpace.appKitLocalRect(
                            fromSwiftUI: frame,
                            canvasHeight: layoutStore.canvasSize.height
                        ))
                    }
                }
            }
        }
        .onChange(of: store.currentPage) { _, newPage in
            withAnimation(WorkspaceMotion.smoothContent(reduceMotion: reduceMotion)) {
                displayedPage = newPage
            }
        }
        .onAppear {
            displayedPage = store.currentPage
        }
        .onDisappear {
            layoutStore?.setRightWorkspaceRegion(.zero)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Right workspace, \(store.currentPage.title)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: store.showNext()
            case .decrement: store.showPrevious()
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func page(_ page: RightWorkspacePage) -> some View {
        switch page {
        case .overview: overview()
        case .productivity: productivity()
        case .appsMedia: appsMedia()
        }
    }
}

struct RightWorkspaceRegionKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

/// Subordinate page dots; each dot is a real button so paging never
/// depends on the swipe gesture alone.
struct RightWorkspacePageIndicator: View {
    let pages: [RightWorkspacePage]
    let current: RightWorkspacePage
    let onSelect: (RightWorkspacePage) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(pages) { page in
                let selected = page == current
                Button {
                    onSelect(page)
                } label: {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(selected ? 0.72 : 0.22))
                        .frame(width: selected ? 12 : 5, height: 5)
                        .frame(width: 16, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(page.title)
                .accessibilityLabel("\(page.title) page")
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .animation(.smooth(duration: 0.2), value: current)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page \((pages.firstIndex(of: current) ?? 0) + 1) of \(pages.count)")
    }
}
