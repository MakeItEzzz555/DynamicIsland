import Foundation

@MainActor
final class IslandLayoutStore: ObservableObject {
    @Published var collapsedSize: CGSize = CGSize(width: 216, height: 34)
    @Published var expandedSize: CGSize = CGSize(width: 760, height: 260)

    func update(collapsedSize: CGSize, expandedSize: CGSize) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
    }
}
