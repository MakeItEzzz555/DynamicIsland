import Foundation

struct ProductivityModules {
    let capabilities: IslandCapabilityRegistry
    let keepAwake: KeepAwakeController
    let windowSnap: WindowSnapController
    let terminal: TerminalSessionController
    let reminders: RemindersController
}
