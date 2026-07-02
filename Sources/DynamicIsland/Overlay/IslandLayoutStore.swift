import Foundation

@MainActor
final class IslandLayoutStore: ObservableObject {
    @Published var canvasSize: CGSize = CGSize(width: 760, height: 260)
    @Published var collapsedSurfaceFrame: CGRect = CGRect(x: 272, y: 226, width: 216, height: 34)
    @Published var expandedSurfaceFrame: CGRect = CGRect(x: 0, y: 0, width: 760, height: 260)
    @Published var collapsedSize: CGSize = CGSize(width: 216, height: 34)
    @Published var expandedSize: CGSize = CGSize(width: 760, height: 260)

    func update(canvas: IslandCanvasGeometry) {
        canvasSize = canvas.frame.size
        collapsedSurfaceFrame = canvas.collapsedSurfaceFrame
        expandedSurfaceFrame = canvas.expandedSurfaceFrame
        collapsedSize = canvas.collapsedSurfaceFrame.size
        expandedSize = canvas.expandedSurfaceFrame.size
    }
}
