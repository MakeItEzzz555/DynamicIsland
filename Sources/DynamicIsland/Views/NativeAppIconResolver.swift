import AppKit
import SwiftUI

/// Semantic identities stay deterministic regardless of installed applications.
/// Finder is a general identity; the File Tray intentionally retains its icon.
enum NativeAppIdentity: String, CaseIterable, Hashable, Sendable {
    case clock, calendar, safari, finder, codex, claude

    var bundleIdentifier: String {
        switch self {
        case .clock: "com.apple.clock"
        case .calendar: "com.apple.iCal"
        case .safari: "com.apple.Safari"
        case .finder: "com.apple.finder"
        case .codex: "com.openai.codex"
        case .claude: "com.anthropic.claudefordesktop"
        }
    }

    static func widget(_ widget: IslandWidget) -> Self? {
        switch widget {
        case .timer: .clock
        case .calendar: .calendar
        case .codexUsage: .codex
        case .claudeUsage: .claude
        default: nil
        }
    }
}

/// Only public LaunchServices/AppKit lookups. Positive and unavailable results
/// are cached so SwiftUI body evaluation never repeatedly scans installed apps.
@MainActor
final class NativeAppIconResolver {
    static let shared = NativeAppIconResolver()
    private let applicationURL: (String) -> URL?
    private let iconAtURL: (URL) -> NSImage
    private var icons: [NativeAppIdentity: NSImage] = [:]
    private var unavailable: Set<NativeAppIdentity> = []

    init(applicationURL: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
         iconAtURL: @escaping (URL) -> NSImage = { NSWorkspace.shared.icon(forFile: $0.path) }) {
        self.applicationURL = applicationURL
        self.iconAtURL = iconAtURL
    }

    func installedIcon(for identity: NativeAppIdentity) -> NSImage? {
        if let icon = icons[identity] { return icon }
        guard !unavailable.contains(identity) else { return nil }
        guard let url = applicationURL(identity.bundleIdentifier) else {
            unavailable.insert(identity)
            return nil
        }
        let icon = iconAtURL(url).copy() as? NSImage
        icon?.isTemplate = false
        guard let icon else {
            unavailable.insert(identity)
            return nil
        }
        icons[identity] = icon
        return icon
    }

    func installedIcon(for widget: IslandWidget) -> NSImage? {
        NativeAppIdentity.widget(widget).flatMap { installedIcon(for: $0) }
    }
}

/// Editor identity only. SF fallback retains the existing palette grammar;
/// native app artwork is always original color rather than template-tinted.
struct NativeWidgetIconView: View {
    let widget: IslandWidget
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let icon = NativeAppIconResolver.shared.installedIcon(for: widget) {
                Image(nsImage: icon).resizable().renderingMode(.original).scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 9 / 32, style: .continuous)
                    .fill(LinearGradient(colors: [widget.paletteTint.opacity(0.95), widget.paletteTint.opacity(0.70)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Image(systemName: widget.symbol)
                            .font(.system(size: size * 14 / 32, weight: .semibold)).foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
