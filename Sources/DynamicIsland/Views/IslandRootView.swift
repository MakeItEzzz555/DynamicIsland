import SwiftUI
import UniformTypeIdentifiers

struct IslandRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var islandState: IslandStateStore
    @ObservedObject var layoutStore: IslandLayoutStore
    let modules: IslandModules
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool {
        islandState.state == .expanded
    }

    var body: some View {
        ZStack(alignment: .top) {
            IslandSurface(isExpanded: isExpanded) {
                if isExpanded {
                    ExpandedIslandView(modules: modules)
                        .transition(.blurBounce)
                } else {
                    CompactIslandView(modules: modules)
                        .transition(.blurBounce)
                }
            }
            .frame(width: surfaceSize.width, height: surfaceSize.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadDroppedFiles(from: providers)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DynamicIsland")
        .animation(contentAnimation, value: islandState.state)
    }

    private var surfaceSize: CGSize {
        isExpanded ? layoutStore.expandedSize : layoutStore.collapsedSize
    }

    private var contentAnimation: Animation {
        if reduceMotion {
            .easeInOut(duration: 0.12)
        } else {
            .interpolatingSpring(mass: 0.82, stiffness: 290, damping: 24, initialVelocity: 0.18)
        }
    }

    private func loadDroppedFiles(from providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data,
                   let fileURL = URL(dataRepresentation: data, relativeTo: nil) {
                    url = fileURL
                } else if let fileURL = item as? URL {
                    url = fileURL
                } else {
                    url = nil
                }

                if let url {
                    Task { @MainActor in
                        modules.fileShelf.add([url])
                    }
                }
            }
        }
    }
}

private struct BlurBounceModifier: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var blurBounce: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurBounceModifier(blur: 12, scale: 0.90, opacity: 0.0),
                identity: BlurBounceModifier(blur: 0, scale: 1.0, opacity: 1.0)
            ),
            removal: .modifier(
                active: BlurBounceModifier(blur: 10, scale: 0.94, opacity: 0.0),
                identity: BlurBounceModifier(blur: 0, scale: 1.0, opacity: 1.0)
            )
        )
    }
}

struct IslandSurface<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, isExpanded ? 22 : 14)
            .padding(.top, isExpanded ? 18 : 0)
            .padding(.bottom, isExpanded ? 20 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: isExpanded ? 36 : 22,
                    bottomTrailingRadius: isExpanded ? 36 : 22,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color(red: 0.001, green: 0.001, blue: 0.002))
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: isExpanded ? 36 : 22,
                        bottomTrailingRadius: isExpanded ? 36 : 22,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(isExpanded ? 0.07 : 0.035), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.34), radius: isExpanded ? 22 : 8, y: isExpanded ? 10 : 3)
            }
    }
}

struct CompactIslandView: View {
    let modules: IslandModules

    var body: some View {
        HStack(spacing: 10) {
            CompactMediaView(media: modules.media)
            Spacer(minLength: 0)
            AudioVisualizerView(isPlaying: modules.media.isPlaying)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ExpandedIslandView: View {
    let modules: IslandModules

    var body: some View {
        HStack(spacing: 16) {
            MediaModuleView(media: modules.media)
                .frame(width: 300, alignment: .leading)

            Divider()
                .frame(height: 220)
                .overlay(.white.opacity(0.10))

            ShortcutsModuleView(shortcuts: modules.shortcuts)
                .frame(width: 148)

            Divider()
                .frame(height: 220)
                .overlay(.white.opacity(0.10))

            VStack(spacing: 14) {
                TimerModuleView(timer: modules.timer)
                FileShelfModuleView(fileShelf: modules.fileShelf)
            }
            .frame(width: 168)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
