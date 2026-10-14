import AppKit

public enum ExternalDisplayVisibility: String, CaseIterable, Identifiable {
    case never, whenActive, always
    public var id: Self { self }
    var title: String { switch self { case .never: "Never"; case .whenActive: "When active"; case .always: "Always" } }
    func permits(isExternal: Bool, active: Bool, protectedInteraction: Bool) -> Bool {
        guard isExternal else { return true }
        if protectedInteraction { return true }
        switch self { case .never: return false; case .whenActive: return active; case .always: return true }
    }
}

enum OverlayDisplayPolicy {
    static func normalizedAppExclusions(_ ids: [String], ownBundleID: String?) -> [String] {
        var seen = Set<String>()
        return Array(ids.filter {
            let id = $0.lowercased()
            return $0.count <= 255 && id != ownBundleID?.lowercased() &&
                $0.range(of: "^[a-zA-Z0-9_-]+(\\.[a-zA-Z0-9_-]+)+$", options: .regularExpression) != nil && seen.insert(id).inserted
        }.prefix(64))
    }
    static func hidesInApp(_ foreground: String?, exclusions: [String], ownBundleID: String?) -> Bool {
        guard let foreground, foreground.caseInsensitiveCompare(ownBundleID ?? "") != .orderedSame else { return false }
        return exclusions.contains { $0.caseInsensitiveCompare(foreground) == .orderedSame }
    }
    static func collectionBehavior(showInFullscreen: Bool) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        if showInFullscreen { behavior.insert(.fullScreenAuxiliary) }
        return behavior
    }
    @MainActor
    static func isExternal(_ screen: NSScreen?) -> Bool {
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) == 0
    }
}
