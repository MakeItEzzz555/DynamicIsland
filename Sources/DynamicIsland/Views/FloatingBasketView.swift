import AppKit
import QuickLookThumbnailing
import SwiftUI

// Source parity (constants adapted, implementation DynamicIsland's own):
// Droppy/FloatingBasketView.swift — 28 pt radius, 200×230 collapsed/empty,
//   4-column grid (72 pt items, 12 pt spacing, 18 pt padding → 360 pt),
//   1–3 visible rows then scroll, list height ×1.25 / ×1.5, 32 pt circular
//   header controls, "Drop files here" 18 pt medium, targeted scale 0.97.
// Droppy/BasketStackPreviewView.swift — 3-card stack (80 pt, rotations
//   −10/−3/5, offsets, scale 0.88→1), 130×110 frame, hover spread.
// Droppy/BasketQuickActionsBar.swift — 48 pt bolt that expands into 48 pt
//   targets with 12 pt spacing, 16 pt below the basket, hover explanation.
// Scaled through IslandDisplayMetrics.compactControlScale (0.92…1.10).

struct BasketMetrics: Equatable {
    let scale: CGFloat
    let columns = 4
    /// Transparent room around the surface for its shadow (window points).
    let margin: CGFloat = 24

    init(scale: CGFloat = 1) {
        self.scale = min(max(scale, 0.9), 1.1)
    }

    init(display: ResolvedIslandMetrics) {
        self.init(scale: display.compactControlScale)
    }

    func s(_ value: CGFloat) -> CGFloat { value * scale }

    var cornerRadius: CGFloat { s(28) }
    var collapsedSize: CGSize { CGSize(width: s(200), height: s(230)) }
    var tileWidth: CGFloat { s(72) }
    var tileHeight: CGFloat { s(90) }
    var gridSpacing: CGFloat { s(12) }
    var horizontalPadding: CGFloat { s(18) }
    var expandedWidth: CGFloat { tileWidth * CGFloat(columns) + gridSpacing * CGFloat(columns - 1) + horizontalPadding * 2 }
    /// 18 top + 32 control + 6 below (Droppy expandedHeader padding).
    var headerHeight: CGFloat { s(56) }
    var bottomPadding: CGFloat { s(20) }
    var control: CGFloat { s(32) }
    var listRowHeight: CGFloat { s(44) }
    var quickAction: CGFloat { s(48) }
    var quickActionSpacing: CGFloat { s(12) }
    var barGap: CGFloat { s(16) }
    var quickBarHeight: CGFloat { quickAction + s(14) }

    func surfaceSize(itemCount: Int, isExpanded: Bool, layout: BasketLayoutMode) -> CGSize {
        guard itemCount > 0, isExpanded else { return collapsedSize }
        let rows = Int(ceil(Double(itemCount) / Double(columns)))
        switch layout {
        case .grid:
            let visibleRows = CGFloat(min(rows, 3))
            return CGSize(width: expandedWidth,
                          height: headerHeight + visibleRows * tileHeight + (visibleRows - 1) * gridSpacing + bottomPadding)
        case .list:
            // Intentional difference: Droppy derives list height from 4-wide
            // grid rows (×1.25 / ×1.5), which clips a 3-row list. Size from
            // the real 44 pt rows instead; scroll after four.
            let visibleRows = CGFloat(min(itemCount, 4))
            return CGSize(width: expandedWidth,
                          height: headerHeight + s(6) + visibleRows * (listRowHeight + s(4)) + s(18))
        }
    }

    func windowSize(surface: CGSize) -> CGSize {
        CGSize(width: max(surface.width, expandedQuickBarWidth) + margin * 2,
               height: surface.height + barGap + quickBarHeight + margin * 2)
    }

    var expandedQuickBarWidth: CGFloat {
        let count = CGFloat(BasketQuickAction.allCases.count)
        return quickAction * count + quickActionSpacing * (count - 1) + s(16)
    }

    /// The visible surface inside a window of `windowSize`, in AppKit
    /// (bottom-left origin) window coordinates.
    func surfaceRect(surface: CGSize, windowSize: CGSize) -> CGRect {
        CGRect(x: (windowSize.width - surface.width) / 2,
               y: windowSize.height - margin - surface.height,
               width: surface.width, height: surface.height)
    }
}

/// Sharing targets on the Basket quick-action bar. Droppy's fourth slot is a
/// cloud upload (Quickshare); it is intentionally absent until the user
/// approves an upload host — no network requests, no fake links.
typealias BasketQuickAction = FileDragQuickAction

// MARK: - Thumbnails

@MainActor
final class BasketThumbnail: ObservableObject {
    @Published private(set) var image: NSImage?
    let fallbackIcon: NSImage

    init(url: URL, image: NSImage? = nil) {
        fallbackIcon = NSWorkspace.shared.icon(forFile: url.path)
        self.image = image
    }

    func set(_ image: NSImage) { self.image = image }
}

/// Async QuickLook thumbnails, cached per file. Each tile observes its own
/// box, so a thumbnail landing never re-renders unrelated tiles or baskets.
@MainActor
final class BasketThumbnailStore {
    static let shared = BasketThumbnailStore()
    private var boxes: [URL: BasketThumbnail] = [:]
    private var requested: Set<URL> = []

    func thumbnail(for url: URL) -> BasketThumbnail {
        if let box = boxes[url] { return box }
        let box = BasketThumbnail(url: url)
        boxes[url] = box
        return box
    }

    /// Deterministic seeding for renders/tests.
    func seed(_ image: NSImage, for url: URL) {
        thumbnail(for: url).set(image)
        requested.insert(url)
    }

    func load(_ url: URL, side: CGFloat = 140) {
        guard !requested.contains(url) else { return }
        requested.insert(url)
        let box = thumbnail(for: url)
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            let size = NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            Task { @MainActor in box.set(NSImage(cgImage: cgImage, size: size)) }
        }
    }
}

// MARK: - Actions boundary

/// Everything the basket UI can ask for. Production wires BasketPresenter;
/// Settings previews and renders use `.inert` (no file, share or window work).
struct BasketViewActions {
    var close: () -> Void = {}
    var hide: () -> Void = {}
    var basketMenu: (NSView) -> Void = { _ in }
    var itemMenu: (UUID, NSEvent, NSView) -> Void = { _, _, _ in }
    var open: (UUID) -> Void = { _ in }
    var remove: (UUID) -> Void = { _ in }
    var dragOutBegan: ([URL]) -> UUID? = { _ in nil }
    var dragOutEnded: (UUID?) -> Void = { _ in }
    var performQuickAction: (BasketQuickAction, NSView?) -> Void = { _, _ in }
    var quickActionDropStarted: () -> Int? = { nil }
    var quickActionDropFinished: (BasketQuickAction, Int, [URL], NSView?) -> Void = { _, _, _, _ in }
    var quickActionDropFailed: (Int, String) -> Void = { _, _ in }
    var isInteractive = false

    static var inert: BasketViewActions { BasketViewActions() }
}

// MARK: - Basket view

struct FloatingBasketView: View {
    @ObservedObject var state: BasketState
    /// Accent identity only when 2+ baskets are visible (Droppy).
    var showsAccent: Bool
    var metrics: BasketMetrics
    var actions: BasketViewActions
    /// Droppy: multi-basket mode swaps the menu chevron for a hide control.
    var multiBasketMode = false
    var thumbnails: BasketThumbnailStore = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredQuickAction: BasketQuickAction?

    private var surfaceSize: CGSize {
        metrics.surfaceSize(itemCount: state.items.count, isExpanded: state.isExpanded, layout: state.layout)
    }

    private var accentColor: Color { showsAccent ? state.accent.color : .white }

    var body: some View {
        VStack(spacing: metrics.barGap) {
            surface
            BasketQuickActionsBar(
                metrics: metrics, actions: actions, hasItems: !state.items.isEmpty,
                hovered: $hoveredQuickAction,
                onTargetingChanged: { state.setHold(.quickActions, $0) }
            )
        }
        .padding(.top, metrics.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(motion(BasketMotion.transition), value: state.items.count)
    }

    private func motion(_ animation: Animation) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : animation
    }

    private var surface: some View {
        ZStack {
            BasketSurfaceBackground(cornerRadius: metrics.cornerRadius, isTargeted: state.isTargeted, accent: accentColor)
            content
                .transition(.opacity)
            if !state.items.isEmpty {
                BasketDragHandle(accent: showsAccent ? state.accent.color : nil, metrics: metrics)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        // Droppy droppyFloatingShadow (0.3, r12, y6). The island stays
        // shadowless; this is the separate floating Basket window.
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .scaleEffect(state.isTargeted && !reduceMotion ? 0.97 : 1)
        .animation(motion(BasketMotion.bouncy), value: state.isTargeted)
        .animation(motion(BasketMotion.transition), value: state.isExpanded)
        .animation(motion(BasketMotion.state), value: state.layout)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.items.isEmpty ? "Empty basket" : "Basket, \(state.titleText)")
    }

    @ViewBuilder
    private var content: some View {
        if let hoveredQuickAction {
            Text(hoveredQuickAction.explanation)
                .font(.system(size: metrics.s(18), weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .padding(.horizontal, metrics.s(24))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BasketSurfaceBackground.fill)
        } else if state.items.isEmpty {
            ZStack(alignment: .topLeading) {
                Text("Drop files here")
                    .font(.system(size: metrics.s(18), weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                BasketCircleButton(symbol: "xmark", size: metrics.control, help: "Close basket", action: actions.close)
                    .padding(metrics.s(18))
            }
        } else if state.isExpanded {
            expanded
        } else {
            collapsed
        }
    }

    // MARK: Collapsed

    private var collapsed: some View {
        VStack(spacing: 0) {
            HStack {
                BasketCircleButton(symbol: "xmark", size: metrics.control, help: "Clear and close basket", action: actions.close)
                Spacer()
                if multiBasketMode {
                    BasketCircleButton(symbol: "eye.slash", size: metrics.control, help: "Hide basket (keep items)", action: actions.hide)
                } else {
                    BasketMenuButton(size: metrics.control, actions: actions)
                }
            }
            .padding(.horizontal, metrics.s(18))
            .padding(.top, metrics.s(18))

            Spacer(minLength: 0)
            BasketStackPreview(items: state.items, metrics: metrics, thumbnails: thumbnails)
                .overlay {
                    BasketMouseRegion(
                        isInteractive: actions.isInteractive,
                        payload: { state.urls },
                        onClick: { _, _ in expand() },
                        onContextMenu: { _, view in actions.basketMenu(view) },
                        dragBegan: actions.dragOutBegan,
                        dragEnded: actions.dragOutEnded
                    )
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Show \(state.titleText)")
            Spacer(minLength: 0)

            Button(action: expand) {
                HStack(spacing: metrics.s(4)) {
                    Text(state.titleText)
                    Image(systemName: "chevron.right").font(.system(size: metrics.s(10), weight: .bold))
                }
                .font(.system(size: metrics.s(13), weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, metrics.s(14))
                .padding(.vertical, metrics.s(7))
                .background(Capsule().fill(.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, metrics.s(16))
            .help("Show all files")
        }
    }

    private func expand() {
        withAnimation(motion(BasketMotion.transition)) { state.isExpanded = true }
    }

    // MARK: Expanded

    private var expanded: some View {
        VStack(spacing: 0) {
            HStack(spacing: metrics.s(12)) {
                BasketCircleButton(symbol: "chevron.left", size: metrics.control, help: "Collapse") {
                    withAnimation(motion(BasketMotion.transition)) { state.isExpanded = false }
                }
                VStack(alignment: .leading, spacing: metrics.s(2)) {
                    Text(state.titleText)
                        .font(.system(size: metrics.s(15), weight: .semibold))
                        .foregroundStyle(.white)
                    Text(state.totalSizeText)
                        .font(.system(size: metrics.s(12)))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: metrics.s(8)) {
                    BasketCircleButton(symbol: "square.grid.2x2", size: metrics.control, help: "Grid") {
                        state.layout = .grid
                    }
                    .opacity(state.layout == .grid ? 1 : 0.6)
                    .accessibilityAddTraits(state.layout == .grid ? .isSelected : [])
                    BasketCircleButton(symbol: "list.bullet", size: metrics.control, help: "List") {
                        state.layout = .list
                    }
                    .opacity(state.layout == .list ? 1 : 0.6)
                    .accessibilityAddTraits(state.layout == .list ? .isSelected : [])
                }
            }
            .padding(.horizontal, metrics.s(18))
            .padding(.top, metrics.s(18))
            .padding(.bottom, metrics.s(6))

            BasketItemsCollection(state: state, metrics: metrics, actions: actions, thumbnails: thumbnails)
        }
    }
}

// MARK: - Items (grid / list, selection)

private struct BasketItemFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct BasketItemsCollection: View {
    @ObservedObject var state: BasketState
    let metrics: BasketMetrics
    let actions: BasketViewActions
    let thumbnails: BasketThumbnailStore

    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var bandStart: CGPoint?
    @State private var bandCurrent: CGPoint = .zero

    private static let space = "BasketItems"

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { state.clearSelection() }
                    .gesture(rubberBand)
                Group {
                    if state.layout == .grid {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(metrics.tileWidth), spacing: metrics.gridSpacing), count: metrics.columns),
                            spacing: metrics.gridSpacing
                        ) {
                            ForEach(state.items) { tile($0) }
                        }
                    } else {
                        LazyVStack(spacing: metrics.s(4)) {
                            ForEach(state.items) { tile($0) }
                        }
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, state.layout == .list ? metrics.s(6) : 0)
                .padding(.bottom, metrics.s(18))
                if let rect = bandRect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.2))
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: Self.space)
        }
        .onPreferenceChange(BasketItemFrameKey.self) { itemFrames = $0 }
    }

    private func tile(_ item: BasketItem) -> some View {
        BasketItemTile(
            item: item,
            isSelected: state.selection.contains(item.id),
            layout: state.layout,
            metrics: metrics,
            thumbnail: thumbnails.thumbnail(for: item.url),
            actions: actions,
            payload: { state.dragPayload(startingAt: item.id) },
            onClick: { modifiers, count in
                if count >= 2 { actions.open(item.id); return }
                state.select(item.id, extend: modifiers.contains(.command), range: modifiers.contains(.shift))
            },
            onContextMenu: { event, view in
                if !state.selection.contains(item.id) { state.select(item.id) }
                actions.itemMenu(item.id, event, view)
            }
        )
        .onAppear { thumbnails.load(item.url) }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: BasketItemFrameKey.self, value: [item.id: proxy.frame(in: .named(Self.space))])
        })
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private var bandRect: CGRect? {
        guard let bandStart else { return nil }
        return CGRect(x: min(bandStart.x, bandCurrent.x), y: min(bandStart.y, bandCurrent.y),
                      width: abs(bandCurrent.x - bandStart.x), height: abs(bandCurrent.y - bandStart.y))
    }

    /// Droppy-style drag rectangle; it holds auto-hide while active.
    private var rubberBand: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if bandStart == nil {
                    bandStart = value.startLocation
                    state.setHold(.selectionDrag, true)
                }
                bandCurrent = value.location
                if let rect = bandRect {
                    state.setSelection(Set(itemFrames.filter { $0.value.intersects(rect) }.map(\.key)))
                }
            }
            .onEnded { _ in
                bandStart = nil
                state.setHold(.selectionDrag, false)
            }
    }
}

struct BasketItemTile: View {
    let item: BasketItem
    let isSelected: Bool
    let layout: BasketLayoutMode
    let metrics: BasketMetrics
    @ObservedObject var thumbnail: BasketThumbnail
    let actions: BasketViewActions
    let payload: () -> [URL]
    let onClick: (NSEvent.ModifierFlags, Int) -> Void
    let onContextMenu: (NSEvent, NSView) -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .overlay {
                BasketMouseRegion(isInteractive: actions.isInteractive, payload: payload, onClick: onClick,
                                  onContextMenu: onContextMenu, dragBegan: actions.dragOutBegan,
                                  dragEnded: actions.dragOutEnded)
            }
            .overlay(alignment: layout == .grid ? .topTrailing : .trailing) {
                if isHovering, actions.isInteractive {
                    Button { actions.remove(item.id) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: metrics.s(16)))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .gray.opacity(0.8))
                    }
                    .buttonStyle(.borderless)
                    .padding(layout == .grid ? metrics.s(2) : metrics.s(10))
                    .help("Remove from Basket")
                    .accessibilityLabel("Remove \(item.name) from Basket")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : BasketMotion.hover) { isHovering = hovering }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var image: some View {
        Group {
            if let image = thumbnail.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.s(6), style: .continuous))
            } else {
                Image(nsImage: thumbnail.fallbackIcon).resizable().aspectRatio(contentMode: .fit)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if layout == .grid {
            VStack(spacing: metrics.s(4)) {
                image
                    .frame(width: metrics.s(48), height: metrics.s(48))
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: metrics.s(14), style: .continuous)
                                .fill(.white.opacity(0.15))
                                .padding(-metrics.s(4))
                        }
                    }
                    .frame(width: metrics.s(56), height: metrics.s(56))
                    .padding(.top, metrics.s(6))
                Text(item.name)
                    .font(.system(size: metrics.s(11)))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, metrics.s(4))
                    .padding(.vertical, metrics.s(2))
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: metrics.s(6), style: .continuous).fill(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: metrics.s(68))
            }
            .frame(width: metrics.tileWidth, height: metrics.tileHeight, alignment: .top)
            .contentShape(Rectangle())
            .scaleEffect(isHovering && !isSelected && !reduceMotion ? 1.04 : 1)
        } else {
            HStack(spacing: metrics.s(12)) {
                image.frame(width: metrics.s(36), height: metrics.s(36))
                VStack(alignment: .leading, spacing: metrics.s(2)) {
                    Text(item.name)
                        .font(.system(size: metrics.s(12), weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let bytes = item.byteCount {
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                            .font(.system(size: metrics.s(10)))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer(minLength: metrics.s(24))
            }
            .padding(.horizontal, metrics.s(8))
            .frame(height: metrics.listRowHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: metrics.s(12), style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.85) : .white.opacity(isHovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Stack preview

struct BasketStackPreview: View {
    let items: [BasketItem]
    let metrics: BasketMetrics
    let thumbnails: BasketThumbnailStore
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = Array(items.suffix(3))
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                BasketStackCard(item: item, thumbnail: thumbnails.thumbnail(for: item.url),
                                index: index, count: shown.count, spread: isHovering && !reduceMotion, metrics: metrics)
                    .zIndex(Double(index))
                    .onAppear { thumbnails.load(item.url) }
            }
        }
        .frame(width: metrics.s(130), height: metrics.s(110))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : BasketMotion.hover) { isHovering = hovering }
        }
    }
}

private struct BasketStackCard: View {
    let item: BasketItem
    @ObservedObject var thumbnail: BasketThumbnail
    let index: Int
    let count: Int
    let spread: Bool
    let metrics: BasketMetrics

    private var rotation: Double {
        switch (count, index) {
        case (2, 0): -6
        case (2, 1): 3
        case (3, 0): -10
        case (3, 1): -3
        case (3, 2): 5
        default: 0
        }
    }

    private var offset: CGSize {
        let spreadX: CGFloat = spread ? 1.4 : 1
        let lift: CGFloat = spread ? -4 : 0
        let base: CGSize
        switch (count, index) {
        case (2, 0): base = CGSize(width: -5 * spreadX, height: 4 + lift * 0.5)
        case (2, 1): base = CGSize(width: 5 * spreadX, height: -2 + lift)
        case (3, 0): base = CGSize(width: -8 * spreadX, height: 6 + lift * 0.3)
        case (3, 1): base = CGSize(width: 0, height: 2 + lift * 0.6)
        case (3, 2): base = CGSize(width: 8 * spreadX, height: -4 + lift)
        default: base = .zero
        }
        return CGSize(width: metrics.s(base.width), height: metrics.s(base.height))
    }

    private var scale: CGFloat {
        let progress = CGFloat(index) / CGFloat(max(1, count - 1))
        return count == 1 ? 1 : 0.88 + 0.12 * progress
    }

    var body: some View {
        let side = metrics.s(80)
        Group {
            if let image = thumbnail.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.s(12), style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: metrics.s(12), style: .continuous)
                    .fill(.white.opacity(0.1))
                    .frame(width: side, height: side)
                    .overlay(Image(nsImage: thumbnail.fallbackIcon).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: side * 0.55, height: side * 0.55))
            }
        }
        .shadow(color: .black.opacity(0.25 - Double(index) * 0.05), radius: 6, x: 0, y: 3)
        .rotationEffect(.degrees(rotation))
        .offset(offset)
        .scaleEffect(scale)
    }
}

// MARK: - Quick actions

struct BasketQuickActionsBar: View {
    let metrics: BasketMetrics
    let actions: BasketViewActions
    let hasItems: Bool
    @Binding var hovered: BasketQuickAction?
    let onTargetingChanged: (Bool) -> Void

    @State private var isHovering = false
    @State private var targeted: Set<BasketQuickAction> = []
    @State private var boltTargeted = false
    private let shareAnchor = SharingAnchorHolder()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { isHovering || boltTargeted || !targeted.isEmpty }

    var body: some View {
        ZStack {
            HStack(spacing: metrics.quickActionSpacing) {
                ForEach(BasketQuickAction.allCases) { action in
                    target(action)
                }
            }
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(isExpanded || reduceMotion ? 1 : 0.92)
            .allowsHitTesting(isExpanded)

            bolt
                .opacity(isExpanded ? 0 : 1)
                .scaleEffect(isExpanded && !reduceMotion ? 0.92 : 1)
                .allowsHitTesting(!isExpanded)
        }
        .frame(width: metrics.expandedQuickBarWidth, height: metrics.quickBarHeight)
        .background(SharingAnchorView(holder: shareAnchor))
        .contentShape(Rectangle())
        .onHover { isHovering = $0; if !$0 { hovered = nil } }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : BasketMotion.state, value: isExpanded)
        .onChange(of: targeted.isEmpty) { _, empty in onTargetingChanged(!empty || boltTargeted) }
        .onChange(of: boltTargeted) { _, value in onTargetingChanged(value || !targeted.isEmpty) }
    }

    private var bolt: some View {
        circle(symbol: "bolt.fill", highlighted: boltTargeted)
            .scaleEffect(boltTargeted && !reduceMotion ? 1.15 : 1)
            .overlay {
                if actions.isInteractive {
                    // Drag-to-expand: never accepts the drop itself.
                    FileDragBridgeView(isTargeted: $boltTargeted)
                }
            }
            .accessibilityLabel("Quick actions")
    }

    @ViewBuilder
    private func target(_ action: BasketQuickAction) -> some View {
        let isTargeted = targeted.contains(action)
        let face = circle(symbol: action.symbolName, highlighted: isTargeted)
            .scaleEffect(isTargeted && !reduceMotion ? 1.18 : (hovered == action && !reduceMotion ? 1.05 : 1))
            .animation(reduceMotion ? nil : BasketMotion.hoverBouncy, value: isTargeted)
        Group {
            if actions.isInteractive {
                FilePromiseDropTarget(
                    isTargeted: Binding(
                        get: { targeted.contains(action) },
                        set: { value in
                            if value { targeted.insert(action); hovered = action } else { targeted.remove(action) }
                        }
                    ),
                    onDropStarted: actions.quickActionDropStarted,
                    onFilesReceived: { claim, urls in
                        actions.quickActionDropFinished(action, claim, urls, shareAnchor.view)
                    },
                    onMaterializationFailed: actions.quickActionDropFailed
                ) { face }
            } else {
                face
            }
        }
        .frame(width: metrics.quickAction, height: metrics.quickAction)
        .onHover { hovering in
            if hovering { hovered = action } else if hovered == action { hovered = nil }
        }
        .onTapGesture {
            guard hasItems else { return }
            actions.performQuickAction(action, shareAnchor.view)
        }
        .help(action.explanation)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(.isButton)
    }

    private func circle(symbol: String, highlighted: Bool) -> some View {
        Circle()
            .fill(BasketSurfaceBackground.fill)
            .overlay(Circle().stroke(.white.opacity(highlighted ? 0.3 : 0.08), lineWidth: 1))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: metrics.s(20), weight: .medium))
                    .foregroundStyle(.white.opacity(highlighted ? 1 : 0.88))
            )
            .frame(width: metrics.quickAction, height: metrics.quickAction)
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Chrome

struct BasketSurfaceBackground: View {
    static let fill = Color(red: 0.07, green: 0.07, blue: 0.08)
    let cornerRadius: CGFloat
    let isTargeted: Bool
    let accent: Color

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Self.fill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: cornerRadius - 4, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [accent.opacity(0.4), accent.opacity(0.15)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 2
                        )
                        .padding(8)
                }
            }
    }
}

struct BasketCircleButton: View {
    let symbol: String
    let size: CGFloat
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(isHovering ? 0.18 : 0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(BasketPressStyle())
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct BasketPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

/// Chevron button that opens the basket's native menu (AppKit, owner-held).
private struct BasketMenuButton: View {
    let size: CGFloat
    let actions: BasketViewActions
    private let anchor = SharingAnchorHolder()

    var body: some View {
        BasketCircleButton(symbol: "chevron.down", size: size, help: "Basket actions") {
            if let view = anchor.view { actions.basketMenu(view) }
        }
        .background(SharingAnchorView(holder: anchor))
    }
}

/// Capsule handle that moves the basket window (Droppy BasketDragHandle:
/// 44×5 capsule, 140×28 hit area, accent only with 2+ baskets).
struct BasketDragHandle: View {
    let accent: Color?
    let metrics: BasketMetrics
    @State private var isHovering = false

    var body: some View {
        Capsule()
            .fill(accent.map { $0.opacity(isHovering ? 0.55 : 0.35) } ?? .white.opacity(isHovering ? 0.40 : 0.28))
            .frame(width: metrics.s(44), height: metrics.s(5))
            .frame(width: metrics.s(140), height: metrics.s(28))
            .contentShape(Rectangle())
            .overlay(WindowMoveRegion())
            .onHover { isHovering = $0 }
            .accessibilityLabel("Move basket")
    }
}

/// Lets AppKit move the window from this region (no manual frame math).
private struct WindowMoveRegion: NSViewRepresentable {
    final class MoveView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
    func makeNSView(context: Context) -> NSView { MoveView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - AppKit mouse / drag-out region

/// Native click/selection/context-menu handling plus a real
/// NSDraggingSession for drag-out (one session, all payload URLs). No
/// pointer injection, no Accessibility.
struct BasketMouseRegion: NSViewRepresentable {
    let isInteractive: Bool
    let payload: () -> [URL]
    let onClick: (NSEvent.ModifierFlags, Int) -> Void
    let onContextMenu: (NSEvent, NSView) -> Void
    let dragBegan: ([URL]) -> UUID?
    let dragEnded: (UUID?) -> Void

    func makeNSView(context: Context) -> BasketMouseNSView {
        let view = BasketMouseNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: BasketMouseNSView, context: Context) { update(nsView) }

    private func update(_ view: BasketMouseNSView) {
        view.isInteractive = isInteractive
        view.payload = payload
        view.onClick = onClick
        view.onContextMenu = onContextMenu
        view.dragBegan = dragBegan
        view.dragEnded = dragEnded
    }
}

final class BasketMouseNSView: NSView, NSDraggingSource {
    var isInteractive = false
    var payload: () -> [URL] = { [] }
    var onClick: (NSEvent.ModifierFlags, Int) -> Void = { _, _ in }
    var onContextMenu: (NSEvent, NSView) -> Void = { _, _ in }
    var dragBegan: ([URL]) -> UUID? = { _ in nil }
    var dragEnded: (UUID?) -> Void = { _ in }

    private var mouseDownEvent: NSEvent?
    private var didDrag = false
    private var dragToken: UUID?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { isInteractive ? super.hitTest(point) : nil }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onContextMenu(event, self)
            return
        }
        mouseDownEvent = event
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, !didDrag else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x
        let dy = event.locationInWindow.y - start.locationInWindow.y
        guard dx * dx + dy * dy > 16 else { return }
        let urls = payload().filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        didDrag = true
        let side: CGFloat = 48
        let origin = convert(start.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 4)) * 6
            item.setDraggingFrame(
                NSRect(x: origin.x - side / 2 + offset, y: origin.y - side / 2 - offset, width: side, height: side),
                contents: NSWorkspace.shared.icon(forFile: url.path)
            )
            return item
        }
        dragToken = dragBegan(urls)
        let session = beginDraggingSession(with: items, event: start, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !didDrag else { return }
        onClick(event.modifierFlags, event.clickCount)
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu(event, self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy only: dragging out of a Basket never moves the original.
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let token = dragToken
        dragToken = nil
        didDrag = false
        mouseDownEvent = nil
        dragEnded(token)
    }
}

// MARK: - Motion

/// Basket timing (Droppy DroppyAnimation): bouncy(0.34), basketTransition
/// spring(0.3, 0.86), state spring(0.24, 0.82), hover spring(0.24, 0.8).
/// Callers swap to short ease-outs under Reduce Motion.
enum BasketMotion {
    static let bouncy = Animation.bouncy(duration: 0.34)
    static let transition = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let state = Animation.spring(response: 0.24, dampingFraction: 0.82)
    static let hover = Animation.spring(response: 0.24, dampingFraction: 0.8)
    static let hoverBouncy = Animation.spring(response: 0.28, dampingFraction: 0.82)
}
