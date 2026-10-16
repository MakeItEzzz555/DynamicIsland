import Foundation

/// ZIP extraction on the shared executor. Entries are vetted from the central
/// directory before anything is written, and the SAME tool (`unzip`) that
/// listed them extracts them, so a crafted archive cannot show the validator
/// one name and the extractor another. Extraction happens in a hidden staging
/// folder beside the destination, and the staged tree is verified before it
/// is published with one same-volume rename.
extension ZipCompressionExecutor {
    /// "Name.zip" -> "Name", "Name 2", ... beside the archive.
    static func extractionDestination(
        for archive: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let directory = archive.standardizedFileURL.deletingLastPathComponent()
        let stem = archive.deletingPathExtension().lastPathComponent
        let base = stem.isEmpty ? "Archive" : stem
        var index = 1
        while true {
            let candidate = directory.appendingPathComponent(index == 1 ? base : "\(base) \(index)").standardizedFileURL
            if !fileExists(candidate) { return candidate }
            index += 1
        }
    }

    /// Returns the first offending entry name, or nil when every entry stays
    /// inside the destination. `names` is `unzip -Z1`; `symlinks` are the
    /// entries `unzip -Z` marks as links. Nothing may be nested under a link
    /// (writing through it could leave the destination); link targets are
    /// checked after extraction.
    static func unsafeEntry(names: [String], symlinks: [String]) -> String? {
        for name in names {
            let components = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: false)
            if name.hasPrefix("/") || name.contains("\0") || components.contains("..") {
                return name
            }
        }
        // APFS/HFS+ are case- and normalization-insensitive: compare folded forms.
        func folded(_ s: String) -> String { s.precomposedStringWithCanonicalMapping.lowercased() }
        let links = symlinks.map { folded($0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
        for name in names {
            let lowered = folded(name)
            if links.contains(where: { lowered.hasPrefix($0 + "/") }) { return name }
        }
        return nil
    }

    /// First path (relative to `root`) that is a symlink resolving outside it, or nil.
    /// Checks both the link's own target lexically and the kernel-style resolution
    /// through every link: `B -> "."` plus `A -> "B/B/../.."` is lexically inside
    /// but really points above the root.
    static func escapingItem(in root: URL) -> String? {
        let lexicalRoot = root.standardizedFileURL.path
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        func inside(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in walker {
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { continue }
            let lexical = target.hasPrefix("/")
                ? URL(fileURLWithPath: target)
                : url.deletingLastPathComponent().appendingPathComponent(target)
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            if !inside(lexical.standardizedFileURL.path, lexicalRoot) || !inside(resolved, resolvedRoot) {
                return String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }
        return nil
    }

    func extract(operationID: UUID, archive: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { [self] in
                defer { clearExecutionState(operationID) }
                return try extractSynchronously(operationID: operationID, archive: archive.standardizedFileURL)
            }.value
        } onCancel: { [self] in
            cancel(operationID: operationID)
        }
    }

    private func extractSynchronously(operationID: UUID, archive: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: archive.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ZipCompressionError.missingSource(archive.lastPathComponent)
        }
        guard archive.pathExtension.lowercased() == "zip" else { throw ZipCompressionError.notAnArchive }

        let listing = try run(operationID: operationID, executable: Self.validatorURL, arguments: ["-Z1", archive.path], captureOutput: true)
        let detail = try run(operationID: operationID, executable: Self.validatorURL, arguments: ["-Z", archive.path], captureOutput: true)
        let names = String(decoding: listing, as: UTF8.self).split(separator: "\n").map(String.init)
        let symlinks = String(decoding: detail, as: UTF8.self).split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(maxSplits: 8, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            return fields.count == 9 && fields[0].first == "l" ? String(fields[8]) : nil
        }
        if let bad = Self.unsafeEntry(names: names, symlinks: symlinks) { throw ZipCompressionError.unsafeArchive(bad) }

        let parent = archive.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".DynamicIsland-Extract-\(operationID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        // Removes partial output on failure, cancellation and after the rename.
        defer { try? FileManager.default.removeItem(at: staging) }

        try checkCancelled(operationID)
        // -n never overwrites; Info-ZIP also strips "../" and leading "/" itself.
        try run(operationID: operationID, executable: Self.validatorURL, arguments: ["-q", "-n", archive.path, "-d", staging.path])
        try checkCancelled(operationID)
        // Finder-made archives carry AppleDouble metadata that ditto used to fold in.
        try? FileManager.default.removeItem(at: staging.appendingPathComponent("__MACOSX"))
        if let bad = Self.escapingItem(in: staging) { throw ZipCompressionError.unsafeArchive(bad) }

        let destination = Self.extractionDestination(for: archive)
        try checkCancelled(operationID)
        do {
            // Fails rather than overwrites if the name was taken meanwhile.
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            if (error as NSError).code == NSFileWriteFileExistsError { throw ZipCompressionError.destinationExists }
            throw ZipCompressionError.processFailed(error.localizedDescription)
        }
        return destination
    }
}
