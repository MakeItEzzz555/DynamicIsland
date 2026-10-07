import SwiftUI

private struct RightWorkspacePageActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether a mounted right-workspace page is the currently visible page.
    /// Hidden pages remain mounted solely to preserve native ScrollView state;
    /// expensive controllers use this value to suspend themselves.
    var rightWorkspacePageIsActive: Bool {
        get { self[RightWorkspacePageActiveKey.self] }
        set { self[RightWorkspacePageActiveKey.self] = newValue }
    }
}

/// The Island page's right column as a paged workspace. Exactly one page
/// occupies the column's geometry; paging never changes the island size.
/// Pages change by two-finger horizontal swipe over this column (routed by
/// the overlay's gesture handler), by the page indicator, or by keyboard
/// accessibility increment/decrement.
struct RightWorkspaceView<Overview: View, Productivity: View, AppsMedia: View>: View {
    /// Height reserved below the pages for the page indicator.
    static var indicatorBand: CGFloat { 16 }

    static func showsIndicator(_ configuration: RightWorkspaceConfiguration) -> Bool {
        configuration.visiblePages.count > 1 && configuration.indicatorStyle == .dots
    }

    @ObservedObject var store: RightWorkspaceStore
    let layoutStore: IslandLayoutStore?
    let reduceMotion: Bool
    @ViewBuilder let overview: () -> Overview
    @ViewBuilder let productivity: () -> Productivity
    @ViewBuilder let appsMedia: () -> AppsMedia

    var body: some View {
        let pages = store.configuration.visiblePages
        let currentPage = pages.contains(store.currentPage)
            ? store.currentPage
            : (pages.first ?? .overview)
        let showsIndicator = Self.showsIndicator(store.configuration)

        GeometryReader { proxy in
            let pageHeight = max(proxy.size.height - (showsIndicator ? Self.indicatorBand : 0), 0)
            VStack(spacing: 0) {
                RetainedWorkspacePages(
                    pages: pages, selection: currentPage,
                    size: CGSize(width: proxy.size.width, height: pageHeight),
                    travel: proxy.size.width * WorkspaceMotion.pageTravelFraction,
                    blur: WorkspaceMotion.prefersLightweightEffects ? 0 : WorkspaceMotion.transitionBlurRadius,
                    reduceMotion: reduceMotion,
                    content: page
                )
                .animation(
                    WorkspaceMotion.smoothContent(reduceMotion: reduceMotion),
                    value: store.currentPage
                )

                if showsIndicator {
                    RightWorkspacePageIndicator(
                        pages: pages,
                        current: currentPage,
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
        .onDisappear {
            layoutStore?.setRightWorkspaceRegion(.zero)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Right workspace, \(currentPage.title)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: store.showNext()
            case .decrement: store.showPrevious()
            @unknown default: break
            }
        }
    }

    private func pageRelativeOffset(
        _ page: RightWorkspacePage,
        current: RightWorkspacePage,
        pages: [RightWorkspacePage]
    ) -> Int {
        guard let pageIndex = pages.firstIndex(of: page),
              let currentIndex = pages.firstIndex(of: current) else {
            return 0
        }
        return pageIndex - currentIndex
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
        HStack(spacing: 0) {
            ForEach(pages) { page in
                let selected = page == current
                Button {
                    onSelect(page)
                } label: {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(selected ? 0.72 : 0.22))
                        .frame(width: selected ? 12 : 5, height: 5)
                        .frame(width: 22, height: 16)
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
