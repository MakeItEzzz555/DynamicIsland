import Foundation
import SwiftUI

protocol IslandModule {
    associatedtype CompactBody: View
    associatedtype ExpandedBody: View

    var id: String { get }
    var title: String { get }

    @ViewBuilder
    func compactView() -> CompactBody

    @ViewBuilder
    func expandedView() -> ExpandedBody
}

struct IslandModules {
    let media: MediaController
    let fileShelf: FileShelfStore
    let shortcuts: ShortcutsStore
    let timer: TimerController
    let stats: SystemStatsController
    let liveActivities: LiveActivityStore
    let clipboardHistory: ClipboardHistoryStore
    let navigation: IslandNavigationStore
    let agentEvents: AgentEventStore
    let agentAttention: AgentAttentionCoordinator
    let agentApprovalControl: AgentApprovalController
    let agentManagedControl: AgentManagedSessionController
    let agentProjects: AgentProjectProjectionStore
    let productivity: ProductivityModules
    let messaging: MessagingController
}
