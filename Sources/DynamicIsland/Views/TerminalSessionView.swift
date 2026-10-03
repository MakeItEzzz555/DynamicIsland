import SwiftUI

struct TerminalSessionView: View {
    @ObservedObject var controller: TerminalSessionController
    var body: some View {
        AgentWorkspaceTerminalView(controller: controller, session: nil, isVisible: true,
                                   focusRequest: 0, layoutStore: nil)
            .frame(minHeight: 180)
    }
}
