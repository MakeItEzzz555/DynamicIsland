import SwiftUI

struct SettingsIntroductionReplay: View {
    let navigate: (SettingsRoute) -> Void
    @State private var showing = false
    @State private var step = 0
    private let pages: [(String, String, String, SettingsRoute)] = [
        ("rectangle.topthird.inset.filled", "Your island, your workspace", "Arrange widgets horizontally or vertically. Customize Workspace keeps changes in a draft until you choose Done.", .page(.shelf)),
        ("hand.point.up.left", "Choose how you navigate", "Use the pointer, trackpad or on-device camera hand navigation. Camera access is requested only through an explicit permission action.", .section(.gestures)),
        ("lock.shield", "Control your integrations", "Messages, FaceTime, recording and Agents have their own capability and permission checks. Settings previews use sample content.", .permissions)
    ]
    var body: some View {
        Button("Replay introduction…") { step = 0; showing = true }
            .sheet(isPresented: $showing) {
                VStack(spacing: 20) {
                    Image(systemName: pages[step].0).font(.system(size: 48)).foregroundStyle(.tint).accessibilityHidden(true)
                    Text(pages[step].1).font(.title2.bold())
                    Text(pages[step].2).multilineTextAlignment(.center)
                    Text("\(step + 1) of \(pages.count)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Close") { showing = false }.keyboardShortcut(.cancelAction)
                        Button("Back") { step -= 1 }.disabled(step == 0)
                        Spacer()
                        Button("Open settings") { showing = false; navigate(pages[step].3) }
                        Button(step == pages.count - 1 ? "Done" : "Next") {
                            if step == pages.count - 1 { showing = false } else { step += 1 }
                        }.keyboardShortcut(.defaultAction)
                    }
                }.padding(28).frame(width: 480)
            }
    }
}
