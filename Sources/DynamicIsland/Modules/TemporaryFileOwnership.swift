import Foundation

/// An app surface (or in-flight action) that currently references a file.
enum FileSurfaceOwner: Hashable, Sendable {
    case shelf
    case basket(UUID)
    /// A native drag-out session that must keep files alive until it ends.
    case dragOut(UUID)
    /// A background operation reading its sources.
    case operation(UUID)
}

/// Single authority for deleting DynamicIsland-owned temporary files.
///
/// Stable user URLs (Finder/Desktop files) are tracked but never deleted.
/// Files inside DynamicIsland's temporary roots (Photos/file-promise
/// materializations, provider copies) are deleted only when the last owner
/// releases them, so moving an item between Shelf and Baskets — or dragging
/// it out while it is removed — can never delete it prematurely.
@MainActor
final class TemporaryFileOwnershipLedger {
    static let shared = TemporaryFileOwnershipLedger()

    let temporaryRoots: [URL]
    private var owners: [URL: Set<FileSurfaceOwner>] = [:]

    init(temporaryRoots: [URL] = [
        FileShelfTemporaryStorage.shared.rootURL,
        FileDragPromiseStorage.shared.rootURL
    ]) {
        self.temporaryRoots = temporaryRoots.map(\.standardizedFileURL)
    }

    func isTemporary(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return temporaryRoots.contains { root in
            path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
        }
    }

    func owners(of url: URL) -> Set<FileSurfaceOwner> {
        owners[url.standardizedFileURL] ?? []
    }

    func retain(_ urls: [URL], by owner: FileSurfaceOwner) {
        for url in urls.map(\.standardizedFileURL) {
            owners[url, default: []].insert(owner)
        }
    }

    /// Releases `owner`'s claim. Returns the temporary files actually deleted
    /// because no surface owns them any more. A release by a non-owner is a
    /// no-op so one surface can never drop another surface's file.
    @discardableResult
    func release(_ urls: [URL], by owner: FileSurfaceOwner) -> [URL] {
        var orphaned: [URL] = []
        for url in urls.map(\.standardizedFileURL) {
            guard var set = owners[url], set.remove(owner) != nil else { continue }
            if set.isEmpty {
                owners[url] = nil
                orphaned.append(url)
            } else {
                owners[url] = set
            }
        }
        return deleteTemporary(orphaned)
    }

    /// Moves ownership without ever passing through an unowned state.
    func transfer(_ urls: [URL], from source: FileSurfaceOwner, to destination: FileSurfaceOwner) {
        retain(urls, by: destination)
        release(urls, by: source)
    }

    /// For incoming files that no surface accepted (rejected drops, stale
    /// promise completions): deletes them only if they are temporary and
    /// nothing owns them.
    @discardableResult
    func discardIfUnowned(_ urls: [URL]) -> [URL] {
        deleteTemporary(urls.map(\.standardizedFileURL).filter { owners[$0]?.isEmpty ?? true })
    }

    private func deleteTemporary(_ urls: [URL]) -> [URL] {
        var deleted: [URL] = []
        for url in urls where isTemporary(url) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard (try? FileManager.default.removeItem(at: url)) != nil else { continue }
            deleted.append(url)
            pruneEmptyParent(of: url)
        }
        return deleted
    }

    /// Promise materializations live in per-drop folders; remove the folder
    /// once its last file is gone, but never a temporary root itself.
    private func pruneEmptyParent(of url: URL) {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard isTemporary(parent),
              let contents = try? FileManager.default.contentsOfDirectory(atPath: parent.path),
              contents.isEmpty else { return }
        try? FileManager.default.removeItem(at: parent)
    }
}
