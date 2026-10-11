import SwiftUI

/// Native macOS CallKit cannot observe or control FaceTime/Continuity calls.
enum NativeCallAuthority {
    static let canObserve = false
    static let canControl = false
    static let limitation = "CallKit call observation and controls are unavailable on native macOS. These are sample call presentations only."
}

struct CollapsedCallActivityView: View {
    let activity: DynamicIslandLiveActivity
    let layout: CompactCollapsedSideSlotGeometry

    var body: some View {
        CompactCollapsedSideSlotLayout(geometry: layout) {
            Image(systemName: "phone.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        } right: {
            AudioVisualizerView(isPlaying: activity.isActive, accentColor: .green,
                palette: .call, barCount: 7, cadence: .ambient)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Call, \(activity.subtitle ?? activity.title)")
    }
}

struct CollapsedMessageActivityView: View {
    let activity: DynamicIslandLiveActivity
    let layout: CompactCollapsedSideSlotGeometry

    var body: some View {
        CompactCollapsedSideSlotLayout(geometry: layout) {
            Image(systemName: activity.symbolName).foregroundStyle(.green)
                .font(.system(size: 12, weight: .semibold))
        } right: {
            VStack(alignment: .trailing, spacing: 1) {
                Text(activity.title).font(.system(size: 9, weight: .semibold))
                Text(activity.subtitle ?? "New message").font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .lineLimit(1)
            .frame(width: 130, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CollapsedMessageHoverView: View {
    @ObservedObject var controller: MessagingController
    let entry: MessagingQueueEntry
    let topBandHeight: CGFloat
    var onFocus: (Bool) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear.frame(height: topBandHeight)
            Text(entry.conversation.displayTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(MessagingController.compactPreview(for: entry.latest,
                showBody: controller.preferences.showPreviewOnCompact))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            if controller.canReply(to: entry) {
                MessagingReplyComposer(controller: controller, entry: entry,
                    onFocus: onFocus, onDismiss: onDismiss)
            } else {
                HStack {
                    Text(controller.capabilities(for: entry.conversation.provider).limitations[.sendReply]
                        ?? "An exact reply target is unavailable").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if MessagingInteractionMode.resolve(canReply: false,
                        capabilities: controller.capabilities(for: entry.conversation.provider)) == .openAppOnly {
                        Button("Open \(entry.conversation.provider.displayName)") { controller.open(entry) }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
