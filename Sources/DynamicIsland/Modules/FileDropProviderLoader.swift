import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum FileDropPolicy {
    static func allowsCollapsedDrop(settings: AppSettings) -> Bool {
        settings.trayEnabled &&
            settings.fileShelfEnabled &&
            settings.allowFileDropsOnCollapsedIsland &&
            settings.showTrayTab
    }

    static func allowsExpandedDrop(settings: AppSettings) -> Bool {
        settings.trayEnabled &&
            settings.fileShelfEnabled &&
            settings.allowFileDropsOnExpandedTray &&
            settings.showTrayTab
    }
}

struct FileShelfTemporaryStorage: Sendable {
    static let shared = FileShelfTemporaryStorage()

    let rootURL: URL
    let providerTemporaryRootURL: URL

    init(
        rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("FileShelf", isDirectory: true),
        providerTemporaryRootURL: URL = FileManager.default.temporaryDirectory
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.providerTemporaryRootURL = providerTemporaryRootURL.standardizedFileURL
    }

    func materializeIfProviderOwned(_ url: URL, suggestedName: String? = nil) throws -> URL {
        let standardizedURL = url.standardizedFileURL
        guard isInside(standardizedURL, root: providerTemporaryRootURL),
              !isInside(standardizedURL, root: rootURL) else {
            return standardizedURL
        }
        return try copyIntoShelf(standardizedURL, suggestedName: suggestedName)
    }

    func copyIntoShelf(_ sourceURL: URL, suggestedName: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let rawName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = sourceURL.lastPathComponent.isEmpty ? "Dropped File" : sourceURL.lastPathComponent
        let safeName = sanitizedFilename(rawName.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName)
        let destinationURL = rootURL.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL.standardizedFileURL
    }

    func removeIfOwned(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard isInside(standardizedURL, root: rootURL) else { return }
        try? FileManager.default.removeItem(at: standardizedURL)
    }

    func removeIfOwned(_ urls: [URL]) {
        urls.forEach(removeIfOwned)
    }

    func isOwned(_ url: URL) -> Bool {
        isInside(url.standardizedFileURL, root: rootURL)
    }

    private func isInside(_ url: URL, root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path == root.path || url.path.hasPrefix(rootPath)
    }

    private func sanitizedFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        let components = name.components(separatedBy: invalidCharacters).filter { !$0.isEmpty }
        let sanitized = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Dropped File" : sanitized
    }
}

final class FileDropProviderLoader: @unchecked Sendable {
    /// Include AppKit's promised-file pasteboard types so a Photos/Finder
    /// promise can wake/expand the island even before a stable URL exists.
    /// Materialization itself is handled by FilePromiseDropNSView on orbit
    /// targets, or by the provider representations below for Shelf drops.
    static let acceptedTypes: [UTType] = {
        var result: [UTType] = [.fileURL, .image, .movie]
        for type in NSFilePromiseReceiver.readableDraggedTypes {
            let candidate = UTType(importedAs: type)
            if !result.contains(candidate) { result.append(candidate) }
        }
        return result
    }()

    private static let promisedFileTypeIdentifiers = Set(NSFilePromiseReceiver.readableDraggedTypes)
    private static let debugLogLock = NSLock()
    private let temporaryStorage: FileShelfTemporaryStorage

    init(temporaryStorage: FileShelfTemporaryStorage = .shared) {
        self.temporaryStorage = temporaryStorage
    }

    func canLoad(_ providers: [NSItemProvider]) -> Bool {
        providers.contains(where: canLoad)
    }

    func loadURLs(
        from providers: [NSItemProvider],
        completion: @escaping @Sendable ([URL]) -> Void
    ) {
        let loadableProviders = providers.filter(canLoad)
        guard !loadableProviders.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let accumulator = FileDropURLAccumulator()

        for provider in loadableProviders {
            group.enter()
            loadURL(from: provider) { url in
                if let url {
                    accumulator.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(accumulator.urls)
        }
    }

    private func canLoad(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            preferredMaterializableType(for: provider) != nil
    }

    private func loadURL(
        from provider: NSItemProvider,
        completion: @escaping @Sendable (URL?) -> Void
    ) {
        let start = ProcessInfo.processInfo.systemUptime
        let providerBox = SendableItemProvider(provider)
        let suggestedName = provider.suggestedName
        Self.debugLog("provider types=\(provider.registeredTypeIdentifiers.joined(separator: ",")) suggestedName=\(suggestedName ?? "nil")")

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [self] item, error in
                if let url = Self.fileURL(from: item) {
                    let exists = FileManager.default.fileExists(atPath: url.path)
                    do {
                        let durableURL = try temporaryStorage.materializeIfProviderOwned(
                            url,
                            suggestedName: suggestedName
                        )
                        Self.debugLog(
                            "file-url completed delay=\(Self.elapsed(since: start)) exists=\(exists) " +
                                "materialized=\(durableURL != url.standardizedFileURL) path=\(durableURL.path)"
                        )
                        completion(durableURL)
                    } catch {
                        Self.debugLog("file-url materialization failed delay=\(Self.elapsed(since: start)) error=\(error)")
                        loadPortableRepresentation(from: providerBox.provider, start: start, completion: completion)
                    }
                    return
                }

                Self.debugLog("file-url load failed delay=\(Self.elapsed(since: start)) error=\(String(describing: error))")
                loadPortableRepresentation(from: providerBox.provider, start: start, completion: completion)
            }
            return
        }

        loadPortableRepresentation(from: provider, start: start, completion: completion)
    }

    /// Materializes Photos/image/movie providers that do not expose a stable
    /// file URL. Prefer file-backed representations so large movies are not
    /// loaded wholesale into memory; retain the PNG data path for screenshot
    /// providers that only vend bytes.
    private func loadPortableRepresentation(
        from provider: NSItemProvider,
        start: TimeInterval,
        completion: @escaping @Sendable (URL?) -> Void
    ) {
        if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
            loadPNGRepresentation(from: provider, start: start, completion: completion)
            return
        }
        guard let type = preferredMaterializableType(for: provider) else {
            completion(nil)
            return
        }
        let suggestedName = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [temporaryStorage] url, error in
            guard let url else {
                Self.debugLog("portable representation failed type=\(type.identifier) delay=\(Self.elapsed(since: start)) error=\(String(describing: error))")
                completion(nil)
                return
            }
            var name = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if name?.isEmpty != false { name = nil }
            if let existingName = name, URL(fileURLWithPath: existingName).pathExtension.isEmpty, let ext = type.preferredFilenameExtension {
                name = "\(existingName).\(ext)"
            } else if name == nil {
                name = "Dropped File.\(type.preferredFilenameExtension ?? "data")"
            }
            do {
                let durableURL = try temporaryStorage.copyIntoShelf(url, suggestedName: name)
                Self.debugLog("portable representation completed type=\(type.identifier) delay=\(Self.elapsed(since: start)) path=\(durableURL.path)")
                completion(durableURL)
            } catch {
                Self.debugLog("portable materialization failed delay=\(Self.elapsed(since: start)) error=\(error)")
                completion(nil)
            }
        }
    }

    private func preferredMaterializableType(for provider: NSItemProvider) -> UTType? {
        let registered = provider.registeredTypeIdentifiers
        let types = registered.compactMap(UTType.init)
        if let image = types.first(where: { $0.conforms(to: .image) }) { return image }
        if let movie = types.first(where: { $0.conforms(to: .movie) }) { return movie }
        if let promiseIdentifier = registered.first(where: Self.promisedFileTypeIdentifiers.contains) {
            return UTType(importedAs: promiseIdentifier)
        }
        return nil
    }

    private func loadPNGRepresentation(
        from provider: NSItemProvider,
        start: TimeInterval,
        completion: @escaping @Sendable (URL?) -> Void
    ) {
        guard provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) else {
            completion(nil)
            return
        }

        let providerSuggestedName = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { [temporaryStorage] url, error in
            guard let url else {
                Self.debugLog("png representation failed delay=\(Self.elapsed(since: start)) error=\(String(describing: error))")
                completion(nil)
                return
            }

            let exists = FileManager.default.fileExists(atPath: url.path)
            var suggestedName = providerSuggestedName ?? "Screenshot.png"
            if URL(fileURLWithPath: suggestedName).pathExtension.isEmpty {
                suggestedName += ".png"
            }
            do {
                let durableURL = try temporaryStorage.copyIntoShelf(url, suggestedName: suggestedName)
                Self.debugLog(
                    "png representation completed delay=\(Self.elapsed(since: start)) exists=\(exists) " +
                        "materialized=true path=\(durableURL.path)"
                )
                completion(durableURL)
            } catch {
                Self.debugLog("png materialization failed delay=\(Self.elapsed(since: start)) error=\(error)")
                completion(nil)
            }
        }
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)?.standardizedFileURL
        }
        return (item as? URL)?.standardizedFileURL
    }

    private static func elapsed(since start: TimeInterval) -> String {
        String(format: "%.3fs", ProcessInfo.processInfo.systemUptime - start)
    }

    private static func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        let line = "[FileDrop] \(Date()) \(message())"
        print(line)
        guard let data = "\(line)\n".data(using: .utf8) else { return }
        debugLogLock.withLock {
            let url = URL(fileURLWithPath: "/tmp/dynamicisland-debug.log")
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
                _ = try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        #endif
    }
}

private final class FileDropURLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] {
        lock.withLock { storage }
    }

    func append(_ url: URL) {
        lock.withLock { storage.append(url) }
    }
}

private final class SendableItemProvider: @unchecked Sendable {
    let provider: NSItemProvider

    init(_ provider: NSItemProvider) {
        self.provider = provider
    }
}
