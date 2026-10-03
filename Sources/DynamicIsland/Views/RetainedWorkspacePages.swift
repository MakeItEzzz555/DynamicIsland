import SwiftUI

/// Shared Media/Agents workspace architecture: one geometry, retained native
/// pages, one interactive/accessibility surface, explicit hidden-page lifecycle.
struct RetainedWorkspacePages<Page: Hashable & Identifiable, Content: View>: View {
    let pages: [Page]
    let selection: Page
    let size: CGSize
    let travel: CGFloat
    let blur: CGFloat
    let reduceMotion: Bool
    @ViewBuilder let content: (Page) -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(pages) { page in
                let isCurrent = page == selection
                let relative = (pages.firstIndex(of: page) ?? 0) - (pages.firstIndex(of: selection) ?? 0)
                content(page)
                    .frame(width: max(0, size.width), height: max(0, size.height), alignment: .topLeading)
                    .offset(x: reduceMotion ? 0 : CGFloat(relative) * travel)
                    .blur(radius: isCurrent || reduceMotion ? 0 : blur)
                    .opacity(isCurrent ? 1 : 0)
                    .allowsHitTesting(isCurrent)
                    .accessibilityHidden(!isCurrent)
                    .environment(\.rightWorkspacePageIsActive, isCurrent)
                    .zIndex(isCurrent ? 1 : 0)
            }
        }
        .frame(width: max(0, size.width), height: max(0, size.height), alignment: .topLeading)
        .clipped()
    }
}
