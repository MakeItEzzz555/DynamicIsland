import SwiftUI
import UniformTypeIdentifiers

struct IslandRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var islandState: IslandStateStore
    let modules: IslandModules
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            IslandSurface(isExpanded: islandState.state != .collapsed) {
                Group {
                    if islandState.state == .collapsed {
                        CompactIslandView(settings: settings, modules: modules)
                    } else {
                        ExpandedIslandView(settings: settings, islandState: islandState, modules: modules)
                    }
                }
                .animation(animation, value: islandState.state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture {
            guard islandState.state == .collapsed else { return }
            islandState.toggleExpanded()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadDroppedFiles(from: providers)
            return true
        }
        .focusable()
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DynamicIsland")
    }

    private var animation: Animation {
        if reduceMotion {
            .easeInOut(duration: 0.12)
        } else {
            .spring(response: 0.32, dampingFraction: settings.animationIntensity, blendDuration: 0.08)
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
            .padding(.horizontal, isExpanded ? 16 : 14)
            .padding(.top, isExpanded ? 14 : 5)
            .padding(.bottom, isExpanded ? 16 : 10)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: isExpanded ? 8 : 1,
                    bottomLeadingRadius: isExpanded ? 34 : 18,
                    bottomTrailingRadius: isExpanded ? 34 : 18,
                    topTrailingRadius: isExpanded ? 8 : 1,
                    style: .continuous
                )
                    .fill(Color(red: 0.001, green: 0.001, blue: 0.002))
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: isExpanded ? 8 : 1,
                            bottomLeadingRadius: isExpanded ? 34 : 18,
                            bottomTrailingRadius: isExpanded ? 34 : 18,
                            topTrailingRadius: isExpanded ? 8 : 1,
                            style: .continuous
                        )
                            .stroke(Color.white.opacity(isExpanded ? 0.08 : 0.04), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.32), radius: isExpanded ? 22 : 10, y: isExpanded ? 12 : 4)
            }
            .padding(1)
    }
}

struct CompactIslandView: View {
    @ObservedObject var settings: AppSettings
    let modules: IslandModules

    var body: some View {
        HStack(spacing: 10) {
            CompactMediaView(media: modules.media)
            Spacer(minLength: 6)
            AudioVisualizerView(isPlaying: modules.media.isPlaying)
        }
        .frame(height: 42)
    }
}

struct ExpandedIslandView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var islandState: IslandStateStore
    let modules: IslandModules
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentUnblurred = false
    @State private var contentSettled = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Nook", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.12), in: Capsule())
                Label("Tray", systemImage: "tray.full")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
            }

            HStack(spacing: 22) {
                MediaModuleView(media: modules.media)
                    .islandContentEntrance(isSettled: contentSettled, isUnblurred: contentUnblurred, order: 0, reduceMotion: reduceMotion)

                Divider()
                    .frame(height: 250)
                    .overlay(.white.opacity(0.10))

                MirrorModuleView(camera: modules.camera)
                    .islandContentEntrance(isSettled: contentSettled, isUnblurred: contentUnblurred, order: 1, reduceMotion: reduceMotion)

                Divider()
                    .frame(height: 250)
                    .overlay(.white.opacity(0.10))

                VStack(spacing: 14) {
                    TimerModuleView(timer: modules.timer)
                    FileShelfModuleView(fileShelf: modules.fileShelf)
                }
                .frame(width: 330)
                .islandContentEntrance(isSettled: contentSettled, isUnblurred: contentUnblurred, order: 2, reduceMotion: reduceMotion)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            contentUnblurred = false
            contentSettled = false
            Task { @MainActor in
                try? await Task.sleep(for: reduceMotion ? .milliseconds(30) : .milliseconds(90))
                contentSettled = true
                try? await Task.sleep(for: reduceMotion ? .milliseconds(35) : .milliseconds(170))
                contentUnblurred = true
            }
        }
        .onDisappear {
            contentUnblurred = false
            contentSettled = false
        }
    }
}

private extension View {
    func islandContentEntrance(isSettled: Bool, isUnblurred: Bool, order: Int, reduceMotion: Bool) -> some View {
        modifier(IslandContentEntranceModifier(isSettled: isSettled, isUnblurred: isUnblurred, order: order, reduceMotion: reduceMotion))
    }
}

private struct IslandContentEntranceModifier: ViewModifier {
    let isSettled: Bool
    let isUnblurred: Bool
    let order: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let bounceDelay = reduceMotion ? 0.0 : Double(order) * 0.025
        let blurDelay = reduceMotion ? 0.0 : Double(order) * 0.018

        content
            .opacity(1)
            .blur(radius: isUnblurred || reduceMotion ? 0 : 9)
            .scaleEffect(isSettled ? 1 : 0.78, anchor: .top)
            .offset(y: isSettled ? 0 : -12)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12).delay(bounceDelay)
                    : .interpolatingSpring(stiffness: 430, damping: 18).delay(bounceDelay),
                value: isSettled
            )
            .animation(
                .easeOut(duration: reduceMotion ? 0.10 : 0.16).delay(blurDelay),
                value: isUnblurred
            )
    }
}
