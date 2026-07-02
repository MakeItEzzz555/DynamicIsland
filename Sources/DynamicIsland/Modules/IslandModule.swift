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
}
