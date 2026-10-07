import Foundation

/// Recently used agent project folders (paths only), most recent first.
/// Stores no prompts, transcripts or session ids.
struct AgentRecentProjects {
    static let key = "agents.recentProjectFolders"
    static let maximumCount = 8

    let defaults: UserDefaults

    func load() -> [String] {
        (defaults.stringArray(forKey: Self.key) ?? []).filter { !$0.isEmpty }
    }

    func record(_ path: String) {
        guard let normalized = AgentProjectResolver.normalize(path) else { return }
        var paths = load().filter { $0 != normalized }
        paths.insert(normalized, at: 0)
        defaults.set(Array(paths.prefix(Self.maximumCount)), forKey: Self.key)
    }

    func remove(_ path: String) {
        defaults.set(load().filter { $0 != path }, forKey: Self.key)
    }
}
