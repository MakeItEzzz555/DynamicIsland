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
    let backgroundOperations: BackgroundOperationController
    let fileDragSession: FileDragSessionController
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
    let agentActivityRecorder: AgentActivityRecorder
    let productivity: ProductivityModules
    let systemHUD: SystemHUDController
    let messaging: MessagingController
    let rightWorkspace: RightWorkspaceStore
    let workspaceServices: WorkspaceServices
}

/// Real data sources for the right workspace's Apps & Media page.
struct WorkspaceServices {
    let appLibrary: AppLibraryStore
    let calendar: CalendarEventsController
    let spotify: SpotifyLibraryController
}
