import Foundation
import ServiceManagement

@MainActor
final class LoginItemStatusReader {
    private let query: @Sendable () -> SMAppService.Status
    private var pending: (id: UUID, task: Task<SMAppService.Status, Never>)?
    init(query: @escaping @Sendable () -> SMAppService.Status = { SMAppService.mainApp.status }) { self.query = query }
    func read() async -> SMAppService.Status {
        let work: (id: UUID, task: Task<SMAppService.Status, Never>)
        if let pending { work = pending }
        else {
            work = (UUID(), Task.detached(priority: .utility) { [query] in query() })
            pending = work
        }
        let result = await work.task.value
        if pending?.id == work.id { pending = nil }
        return result
    }
    func invalidate() { pending = nil }
}

@MainActor
enum LaunchAtLoginController {
    static let statusReader = LoginItemStatusReader()
    private(set) static var lastError: String?
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static func setEnabled(_ enabled: Bool) {
        statusReader.invalidate()
        lastError = nil
        guard enabled ? status != .enabled && status != .requiresApproval : status != .notRegistered else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { lastError = "macOS could not update the login item. Check Login Items settings and try again." }
    }
}
