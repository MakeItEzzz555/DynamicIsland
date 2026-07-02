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
                    } else if islandState.state == .dragReceiving {
                        DragReceivingView()
                    } else {
                        ExpandedIslandView(settings: settings, islandState: islandState, modules: modules)
                    }
                }
                .animation(animation, value: islandState.state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture {
            islandState.toggleExpanded()
            islandState.scheduleAutoCollapseIfNeeded(after: settings.autoCollapseDelay)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            islandState.dragEntered()
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
                        islandState.dragEnded()
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
            .padding(.top, isExpanded ? 12 : 7)
            .padding(.bottom, isExpanded ? 16 : 10)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: isExpanded ? 20 : 10,
                    bottomLeadingRadius: isExpanded ? 34 : 18,
                    bottomTrailingRadius: isExpanded ? 34 : 18,
                    topTrailingRadius: isExpanded ? 20 : 10,
                    style: .continuous
                )
                    .fill(Color.black.opacity(0.94))
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: isExpanded ? 20 : 10,
                            bottomLeadingRadius: isExpanded ? 34 : 18,
                            bottomTrailingRadius: isExpanded ? 34 : 18,
                            topTrailingRadius: isExpanded ? 20 : 10,
                            style: .continuous
                        )
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
            if settings.mediaEnabled {
                CompactMediaView(media: modules.media)
            }
            Spacer(minLength: 6)
            if settings.fileShelfEnabled {
                CompactShelfBadge(fileShelf: modules.fileShelf)
            }
            if settings.shortcutsEnabled {
                Image(systemName: "sparkles")
                    .foregroundStyle(.white.opacity(0.72))
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 26)
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if settings.mediaEnabled {
                    MediaModuleView(media: modules.media)
                        .islandContentEntrance(isSettled: contentSettled, isUnblurred: contentUnblurred, order: 0, reduceMotion: reduceMotion)
                }
                if settings.shortcutsEnabled {
                    ShortcutsModuleView(shortcuts: modules.shortcuts)
                        .islandContentEntrance(isSettled: contentSettled, isUnblurred: contentUnblurred, order: 1, reduceMotion: reduceMotion)
                }
            }
            if settings.fileShelfEnabled {
                FileShelfModuleView(fileShelf: modules.fileShelf)
                    .islandContentEntrance(isSettled: contentSettled, isUnblurred: contentUnblurred, order: 2, reduceMotion: reduceMotion)
            }
            HStack {
                Button {
                    islandState.pin()
                } label: {
                    Label("Pin", systemImage: "pin")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pin DynamicIsland open")

                Spacer()

                Button {
                    islandState.collapse()
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close DynamicIsland")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.68))
            .islandContentEntrance(isSettled: contentSettled, isUnblurred: contentUnblurred, order: 3, reduceMotion: reduceMotion)
        }
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

struct DragReceivingView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 26, weight: .semibold))
            Text("Drop files into shelf")
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
