import AppKit

/// The application a HAL audio process belongs to.
struct ApplicationAudioOwner: Sendable, Equatable {
    let bundleIdentifier: String
    let name: String
    let url: URL?
}

/// Real apps play from helper processes (Chromium and Electron audio services,
/// Discord's renderer, WebKit's GPU service), so the process that sounds is
/// rarely the app the user sees. This groups helpers under their owning app
/// using public data only: the running-application record, the executable path
/// and bundle-ID prefixes.
enum ApplicationAudioOwnership {
    struct RunningApp: Sendable, Equatable {
        let bundleIdentifier: String
        let name: String
        let url: URL?
        let isRegular: Bool
    }

    /// First match wins; nil means the process is its own application (or a daemon).
    static func owner(of process: ApplicationAudioProcess, itself: RunningApp?, regularApps: [RunningApp],
                      bundleInfo: (URL) -> (bundleIdentifier: String, name: String)?) -> ApplicationAudioOwner? {
        // A regular app is its own owner even when nested inside another bundle (Xcode > Simulator).
        if let itself, itself.isRegular { return .init(bundleIdentifier: itself.bundleIdentifier, name: itself.name, url: itself.url) }
        if let path = process.executablePath, let url = outerApplicationURL(executablePath: path), let info = bundleInfo(url) {
            return .init(bundleIdentifier: info.bundleIdentifier, name: info.name, url: url)
        }
        if let bundle = process.bundleIdentifier ?? itself?.bundleIdentifier, let app = parentApplication(ofHelper: bundle, among: regularApps) {
            return .init(bundleIdentifier: app.bundleIdentifier, name: app.name, url: app.url)
        }
        if let name = itself?.name, let owner = webKitOwnerName(fromServiceName: name),
           let app = regularApps.first(where: { $0.name == owner }) {
            return .init(bundleIdentifier: app.bundleIdentifier, name: app.name, url: app.url)
        }
        return nil
    }

    /// `/A/Discord.app/Contents/Frameworks/Discord Helper.app/...` → `/A/Discord.app`.
    static func outerApplicationURL(executablePath: String) -> URL? {
        var components: [String] = []
        for component in executablePath.split(separator: "/", omittingEmptySubsequences: true) {
            components.append(String(component))
            if component.hasSuffix(".app") { return URL(fileURLWithPath: "/" + components.joined(separator: "/"), isDirectory: true) }
        }
        return nil
    }

    /// `com.spotify.client.helper` → the running app whose bundle ID is the longest dotted prefix.
    static func parentApplication(ofHelper bundleIdentifier: String, among apps: [RunningApp]) -> RunningApp? {
        apps.filter { bundleIdentifier.hasPrefix($0.bundleIdentifier + ".") }
            .max { $0.bundleIdentifier.count < $1.bundleIdentifier.count }
    }

    /// Launch Services names a WebKit service after the app it works for
    /// ("Safari Graphics and Media"); the suffix is removed to recover the app.
    static func webKitOwnerName(fromServiceName name: String) -> String? {
        for suffix in [" Graphics and Media", " Web Content", " Networking"] where name.hasSuffix(suffix) {
            let owner = String(name.dropLast(suffix.count))
            return owner.isEmpty ? nil : owner
        }
        return nil
    }

    @MainActor
    static func liveOwners(for processes: [ApplicationAudioProcess]) -> [UInt32: ApplicationAudioOwner] {
        func running(_ app: NSRunningApplication) -> RunningApp? {
            app.bundleIdentifier.map {
                RunningApp(bundleIdentifier: $0, name: app.localizedName ?? $0, url: app.bundleURL, isRegular: app.activationPolicy == .regular)
            }
        }
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(running)
        var owners: [UInt32: ApplicationAudioOwner] = [:]
        for process in processes {
            let itself = NSRunningApplication(processIdentifier: process.pid).flatMap(running)
            owners[process.objectID] = owner(of: process, itself: itself, regularApps: regular) { url in
                guard let info = Bundle(url: url)?.infoDictionary, let identifier = info["CFBundleIdentifier"] as? String else { return nil }
                let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                return (identifier, name)
            }
        }
        return owners
    }
}
