import Foundation

@MainActor
final class FileShelfStore: ObservableObject {
    private let settings: AppSettings
    @Published private(set) var files: [URL] = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    func add(_ urls: [URL]) {
        guard settings.fileShelfEnabled else { return }
        let merged = files + urls.filter { incoming in
            !files.contains(incoming)
        }
        files = Array(merged.prefix(settings.maxShelfFiles))
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
    }

    func clear() {
        files.removeAll()
    }
}
