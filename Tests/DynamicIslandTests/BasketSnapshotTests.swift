import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Review renders (DYNAMIC_ISLAND_BASKET_SNAPSHOT_DIR) of the production
/// FloatingBasketView / BasketSwitcherView with real temp files and seeded
/// thumbnails. Without the env var it still asserts every basket state fits
/// each display in the matrix.
@MainActor
final class BasketSnapshotTests: XCTestCase {
    private var root: URL!
    private var suite: String!

    private struct Display {
        let name: String
        let size: CGSize
        let notch: Bool
    }

    private let displays = [
        Display(name: "notched14", size: CGSize(width: 1512, height: 982), notch: true),
        Display(name: "notched16", size: CGSize(width: 1728, height: 1117), notch: true),
        Display(name: "external1080p", size: CGSize(width: 1920, height: 1080), notch: false),
        Display(name: "external1440p", size: CGSize(width: 2560, height: 1440), notch: false),
        Display(name: "external4K", size: CGSize(width: 3840, height: 2160), notch: false)
    ]

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BasketSnapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "BasketSnapshots-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func metrics(_ display: Display) -> BasketMetrics {
        BasketMetrics(display: IslandDisplayMetricsResolver.resolve(IslandDisplaySnapshot(
            frame: CGRect(origin: .zero, size: display.size),
            visibleFrame: CGRect(x: 0, y: 0, width: display.size.width, height: display.size.height - 25),
            safeAreaInsets: NSEdgeInsets(top: display.notch ? 32 : 0, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil,
            backingScaleFactor: 2, displayID: nil, isBuiltIn: display.notch,
            pixelSize: CGSize(width: display.size.width * 2, height: display.size.height * 2)
        )))
    }

    private let palette: [NSColor] = [.systemBlue, .systemOrange, .systemPink, .systemGreen, .systemPurple, .systemTeal, .systemYellow]

    /// Real files on disk; image thumbnails seeded deterministically.
    private func makeBasket(_ names: [String], accent: BasketAccent = .teal) -> BasketState {
        let state = BasketState(accent: accent)
        var items: [BasketItem] = []
        for (index, name) in names.enumerated() {
            let url = root.appendingPathComponent(name)
            let image = NSImage(size: NSSize(width: 140, height: 100), flipped: false) { rect in
                self.palette[index % self.palette.count].setFill()
                rect.fill()
                NSColor.white.withAlphaComponent(0.35).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 40, dy: 25)).fill()
                return true
            }
            if url.pathExtension == "png", let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                BasketThumbnailStore.shared.seed(image, for: url.standardizedFileURL)
            } else {
                FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: 2048 * (index + 1)))
            }
            items.append(BasketItem(url: url))
        }
        state.appendItems(items)
        state.setVisible(true)
        return state
    }

    @discardableResult
    private func render(_ name: String, _ state: BasketState, display: Display, accent: Bool = false) throws -> CGSize {
        let metrics = metrics(display)
        let surface = metrics.surfaceSize(itemCount: state.items.count, isExpanded: state.isExpanded, layout: state.layout)
        let size = metrics.windowSize(surface: surface)
        let view = FloatingBasketView(state: state, showsAccent: accent, metrics: metrics, actions: .inert, multiBasketMode: accent)
            .frame(width: size.width, height: size.height)
            .background(LinearGradient(colors: [Color(red: 0.25, green: 0.2, blue: 0.75), Color(red: 0.1, green: 0.1, blue: 0.4)],
                                       startPoint: .top, endPoint: .bottom))
        try write(AnyView(view), size: size, name: "\(name)-\(display.name)")
        return size
    }

    private func write(_ view: AnyView, size: CGSize, name: String) throws {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let dir = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_BASKET_SNAPSHOT_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    func testEveryBasketStateFitsEveryDisplay() throws {
        let images = (1...12).map { "Photo \($0).png" }
        for display in displays {
            let metrics = metrics(display)
            let visible = CGSize(width: display.size.width, height: display.size.height - 25)
            for (count, expanded, layout) in [(0, false, BasketLayoutMode.grid), (3, false, .grid), (12, true, .grid),
                                              (2, true, .list), (12, true, .list)] {
                let size = metrics.windowSize(surface: metrics.surfaceSize(itemCount: count, isExpanded: expanded, layout: layout))
                XCTAssertLessThanOrEqual(size.width, visible.width, display.name)
                XCTAssertLessThanOrEqual(size.height, visible.height * 0.75, "\(display.name) \(count) \(layout)")
            }
            // Grid columns + padding exactly fill the expanded surface (no clipping).
            XCTAssertEqual(metrics.expandedWidth,
                           metrics.tileWidth * 4 + metrics.gridSpacing * 3 + metrics.horizontalPadding * 2, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(metrics.expandedWidth, metrics.expandedQuickBarWidth)
            _ = images
        }
        XCTAssertEqual(BasketMetrics().collapsedSize, CGSize(width: 200, height: 230), "Droppy collapsed/empty size")
        XCTAssertEqual(BasketMetrics().expandedWidth, 360, "Droppy fullGridWidth")
        XCTAssertEqual(BasketMetrics().cornerRadius, 28)
    }

    func testRenderMatrix() throws {
        let images = (1...7).map { "Photo \($0).png" }
        for display in displays {
            try render("empty", makeBasket([]), display: display)
            try render("one-item", makeBasket(["Report.pdf"]), display: display)
            try render("stack-3", makeBasket(["Brief.pdf", "Photo A.png", "Photo B.png"]), display: display)

            let grid = makeBasket(images + ["Notes.txt"])
            grid.isExpanded = true
            try render("expanded-grid", grid, display: display)

            let list = makeBasket(["Quarterly Report Final v3.pdf", "Photo A.png", "Archive.zip"])
            list.isExpanded = true
            list.layout = .list
            try render("expanded-list", list, display: display)
        }

        let display = displays[0]
        let selected = makeBasket(images)
        selected.isExpanded = true
        selected.select(selected.items[1].id)
        try render("selected", selected, display: display)
        selected.select(selected.items[3].id, range: true)
        selected.select(selected.items[6].id, extend: true)
        try render("multi-selection", selected, display: display)

        let targeted = makeBasket([])
        targeted.isTargeted = true
        try render("drag-targeted", targeted, display: display)

        let second = makeBasket(["Photo C.png", "Photo D.png"], accent: .coral)
        try render("second-basket-accent", second, display: display, accent: true)
        let secondExpanded = makeBasket(["Photo E.png", "Spec.pdf"], accent: .indigo)
        secondExpanded.isExpanded = true
        try render("second-basket-accent-expanded", secondExpanded, display: display, accent: true)

        let switcher = BasketSwitcherView(
            baskets: [makeBasket(["Photo F.png", "Photo G.png", "Brief.pdf"]), makeBasket(["Archive.zip"], accent: .coral), makeBasket([], accent: .indigo)],
            metrics: metrics(display), actions: BasketSwitcherActions()
        )
        .background(Color(red: 0.2, green: 0.18, blue: 0.6))
        try write(AnyView(switcher.frame(width: 900, height: 360)), size: CGSize(width: 900, height: 360), name: "switcher-\(display.name)")
    }
}
