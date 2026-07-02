import Foundation

@MainActor
final class FileShelfStore: ObservableObject {
    @Published private(set) var files: [URL] = []

    func add(_ urls: [URL]) {
        let merged = files + urls.filter { incoming in
            !files.contains(incoming)
        }
        files = Array(merged.prefix(12))
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
    }

    func clear() {
        files.removeAll()
    }
}
