import SwiftUI
import UniformTypeIdentifiers

struct IslandRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var islandState: IslandStateStore
    let modules: IslandModules
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        IslandSurface(isExpanded: islandState.state == .expanded) {
            if islandState.state == .collapsed {
                CompactIslandView(modules: modules)
            } else {
                ExpandedIslandView(modules: modules)
            }
        }
        .onTapGesture {
            guard islandState.state == .collapsed else { return }
            islandState.toggleExpanded()
        }
        .onHover { isHovering in
            guard islandState.state == .expanded, !isHovering else { return }
            islandState.collapse()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadDroppedFiles(from: providers)
            return true
        }
        .animation(animation, value: islandState.state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DynamicIsland")
    }

    private var animation: Animation {
        if reduceMotion {
            .easeInOut(duration: 0.12)
        } else {
            .spring(response: 0.30, dampingFraction: settings.animationIntensity, blendDuration: 0.06)
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
        GeometryReader { proxy in
            if proxy.size.width >= 1_040 {
                wideLayout
            } else {
                compactLayout(width: proxy.size.width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var wideLayout: some View {
        HStack(spacing: 24) {
            MediaModuleView(media: modules.media)
                .frame(width: 440, alignment: .leading)

            Divider()
                .frame(height: 248)
                .overlay(.white.opacity(0.10))

            ShortcutsModuleView(shortcuts: modules.shortcuts)
                .frame(width: 250)

            Divider()
                .frame(height: 248)
                .overlay(.white.opacity(0.10))

            VStack(spacing: 14) {
                TimerModuleView(timer: modules.timer)
                FileShelfModuleView(fileShelf: modules.fileShelf)
            }
            .frame(width: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func compactLayout(width: CGFloat) -> some View {
        HStack(spacing: 18) {
            MediaModuleView(media: modules.media)
                .frame(width: min(420, width * 0.58), alignment: .leading)

            Divider()
                .frame(height: 248)
                .overlay(.white.opacity(0.10))

            VStack(spacing: 14) {
                TimerModuleView(timer: modules.timer)
                FileShelfModuleView(fileShelf: modules.fileShelf)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
