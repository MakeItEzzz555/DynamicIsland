import AppKit
import SwiftUI

/// Primary reference routes precede the existing feature settings.
enum SettingsPage: String, CaseIterable, Identifiable {
    case account = "Account", general = "General", moduleStore = "Module Store"
    case shelf = "Shelf", basket = "Basket", clipboard = "Clipboard"
    case lockScreen = "Lock Screen", sharing = "Cloud / Sharing", shortcuts = "Shortcuts"
    case liveActivities = "Live Activities", about = "About"
    static let sidebarGroups: [[Self]] = [
        [.account, .general, .moduleStore],
        [.shelf, .basket, .clipboard, .lockScreen, .sharing],
        [.shortcuts, .liveActivities, .about]
    ]
    var id: String { String(describing: self) }
    var tint: Color {
        switch self {
        case .account, .general, .lockScreen: .gray
        case .moduleStore, .shelf, .shortcuts: .indigo
        case .basket: .orange
        case .clipboard: .cyan
        case .sharing: .blue
        case .liveActivities: .purple
        case .about: .green
        }
    }
    var symbol: String {
        switch self {
        case .account: "person.crop.circle.fill"
        case .general: "gearshape.fill"
        case .moduleStore: "square.stack.3d.up.fill"
        case .shelf: "rectangle.topthird.inset.filled"
        case .basket: "basket.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .lockScreen: "lock.fill"
        case .sharing: "icloud.fill"
        case .shortcuts: "command"
        case .liveActivities: "waveform.path.ecg"
        case .about: "info.circle.fill"
        }
    }
}

enum SettingsRoute: Hashable, Identifiable {
    case page(SettingsPage), section(SettingsSection), permissions
    var id: String {
        switch self {
        case .page(let page): "page.\(page.id)"
        case .section(let section): "section.\(section.rawValue)"
        case .permissions: "permissions"
        }
    }
    var title: String {
        switch self {
        case .page(let page): page.rawValue
        case .section(let section): section.rawValue
        case .permissions: "Permissions"
        }
    }
    var symbol: String {
        switch self {
        case .page(let page): page.symbol
        case .section(let section): section.symbol
        case .permissions: "hand.raised.fill"
        }
    }
    init?(id: String) {
        if let page = SettingsPage.allCases.first(where: { "page.\($0.id)" == id }) { self = .page(page) }
        else if let section = SettingsSection.allCases.first(where: { "section.\($0.rawValue)" == id }) { self = .section(section) }
        else if id == "permissions" { self = .permissions }
        else { return nil }
    }
}

@MainActor
final class SettingsNavigationStore: ObservableObject {
    @Published private(set) var requestedAnchor: String?
    @Published private(set) var route: SettingsRoute
    @Published private(set) var backHistory: [SettingsRoute] = []
    @Published private(set) var forwardHistory: [SettingsRoute] = []
    @Published var sidebarVisible: Bool { didSet { defaults.set(sidebarVisible, forKey: "settings.sidebarVisible") } }
    let defaults: UserDefaults
    // Scroll belongs to each route, not to its neighboring page.
    var scrollOrigins: [SettingsRoute: CGPoint] = [:]
    let nativeControls = NSMapTable<NSString, NSView>(keyOptions: .strongMemory, valueOptions: .weakMemory)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        route = defaults.string(forKey: "settings.route").flatMap(SettingsRoute.init(id:)) ?? .page(.general)
        sidebarVisible = defaults.object(forKey: "settings.sidebarVisible") as? Bool ?? true
    }
    func navigate(_ next: SettingsRoute) {
        guard route != next else { return }
        backHistory.append(route)
        if backHistory.count > 128 { backHistory.removeFirst() }
        forwardHistory.removeAll()
        setRoute(next)
    }
    func open(_ result: SettingsSearchResult) {
        navigate(result.route)
        requestedAnchor = result.anchor
    }
    func back() {
        guard let previous = backHistory.popLast() else { return }
        forwardHistory.append(route); setRoute(previous)
    }
    func forward() {
        guard let next = forwardHistory.popLast() else { return }
        backHistory.append(route); setRoute(next)
    }
    private func setRoute(_ value: SettingsRoute) {
        requestedAnchor = nil
        route = value; defaults.set(value.id, forKey: "settings.route")
    }
}

struct SettingsNavigationRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void
    private var iconTint: Color {
        switch symbol {
        case "paintbrush.fill": .pink
        case "hand.raised.fill": .green
        case "basket.fill", "basket": .orange
        case "message": .green
        default: .accentColor
        }
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(iconTint, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityHint(subtitle)
    }
}

/// Bridges only scroll restoration; native wheel, accessibility and inertia remain AppKit's.
struct SettingsScrollRestoration: NSViewRepresentable {
    let route: SettingsRoute
    let navigation: SettingsNavigationStore
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.route != route else { return }
        coordinator.route = route
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator, coordinator.route == route,
                  let scroll = view.enclosingScrollView else { return }
            coordinator.observe(scroll, route: route, navigation: navigation)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }
    @MainActor final class Coordinator {
        var route: SettingsRoute?
        var token: NSObjectProtocol?
        func observe(_ scroll: NSScrollView, route: SettingsRoute, navigation: SettingsNavigationStore) {
            stop()
            scroll.contentView.postsBoundsChangedNotifications = true
            scroll.contentView.scroll(to: navigation.scrollOrigins[route] ?? .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView, queue: .main) { [weak navigation, weak scroll] _ in
                MainActor.assumeIsolated {
                    guard let scroll else { return }
                    navigation?.scrollOrigins[route] = scroll.contentView.bounds.origin
                }
            }
        }
        func stop() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }
}

/// Native switches retain their label for VoiceOver and align at the row's trailing edge.
struct SettingsTrailingSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.accessibilityHidden(true)
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
        }.frame(minHeight: 28)
    }
}

struct SettingsSearchResult: Identifiable {
    let title: String
    let keywords: String
    let route: SettingsRoute
    let anchor: String
    var id: String { route.id + "." + title }
    static let entries: [Self] = [
        .init(title: "Launch at login", keywords: "startup login approval", route: .page(.general), anchor: ""),
        .init(title: "Visibility", keywords: "menu bar Dock icon", route: .page(.general), anchor: ""),
        .init(title: "Quick Actions", keywords: "favorites shortcuts icons", route: .page(.general), anchor: "Quick Actions"),
        .init(title: "Notch interaction", keywords: "expand click collapse mouse leave", route: .page(.general), anchor: "Notch interaction"),
        .init(title: "Camera Navigation", keywords: "camera permission hand pinch calibration pointer", route: .section(.gestures), anchor: "Gesture Shortcuts"),
        .init(title: "Clipboard History", keywords: "history count cap unlimited retention pinned favorites tags clear password privacy", route: .page(.clipboard), anchor: "Clipboard History"),
        .init(title: "Excluded apps", keywords: "clipboard privacy applications password", route: .page(.clipboard), anchor: "Privacy"),
        .init(title: "Animation speed", keywords: "motion reduce spring shell", route: .page(.shelf), anchor: "Behavior"),
        .init(title: "Widget layout", keywords: "vertical horizontal drag size custom shelf", route: .page(.shelf), anchor: "Widgets"),
        .init(title: "File Tray", keywords: "conversion compression files original", route: .page(.shelf), anchor: "File tray"),
        .init(title: "Permissions", keywords: "camera recording accessibility automation Full Disk Access", route: .permissions, anchor: "Camera"),
        .init(title: "Local modules", keywords: "import JSON plugins validation receipt remove", route: .page(.moduleStore), anchor: "Local modules"),
        .init(title: "Reset and transfer", keywords: "export import backup preferences checksum reset", route: .page(.about), anchor: "Troubleshooting"),
        .init(title: "Multi-Activity Layout", keywords: "sidecar simultaneous call message approval", route: .page(.liveActivities), anchor: "Multi-Activity Layout"),
        .init(title: "Live Activity sources", keywords: "music timer battery file drop", route: .page(.liveActivities), anchor: "Sources")
    ]
    static func matching(_ query: String) -> [Self] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        return entries.filter { result in words.allSatisfy { (result.title + " " + result.keywords).localizedCaseInsensitiveContains($0) } }
    }
}
private struct SettingsSearchHighlightKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var settingsSearchHighlight: String? {
        get { self[SettingsSearchHighlightKey.self] }
        set { self[SettingsSearchHighlightKey.self] = newValue }
    }
}

/// Native conversion includes NavigationSplitView's toolbar insets correctly.
/// This transparent anchor never owns a click or an accessibility element.
struct SettingsNativeControlAnchor: NSViewRepresentable {
    let identifier: String
    let navigation: SettingsNavigationStore
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.navigation = navigation; view.controlID = identifier
        navigation.nativeControls.setObject(view, forKey: identifier as NSString)
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        if view.navigation?.nativeControls.object(forKey: view.controlID as NSString) === view {
            view.navigation?.nativeControls.removeObject(forKey: view.controlID as NSString)
        }
        view.navigation = nil
    }
    final class Anchor: NSView {
        weak var navigation: SettingsNavigationStore?
        var controlID = ""
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }
    }
}
