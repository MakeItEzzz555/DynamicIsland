import AppKit
import Foundation

enum AirDropService {
    @discardableResult
    static func share(urls: [URL]) -> Bool {
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else {
            return false
        }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
            return false
        }

        service.perform(withItems: fileURLs)
        return true
    }
}
