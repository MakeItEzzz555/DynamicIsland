import AppKit
import QuartzCore
import SwiftUI

/// Presentation-only append adapter. Offsets are UTF-16, matching TextKit;
/// whitespace and punctuation remain in the original, selectable text.
struct AgentStreamingTextState: Equatable {
    struct Run: Equatable {
        var range: NSRange
        var start: TimeInterval
    }
    static let duration: TimeInterval = 0.350
    static let stagger: TimeInterval = 0.060
    static let blur: CGFloat = 1
    private(set) var text = ""
    private(set) var runs: [Run] = []
    private var nextStart: TimeInterval = 0

    mutating func update(_ value: String, active: Bool, reduceMotion: Bool, now: TimeInterval) {
        // Re-renders with identical text are common (layout/preference passes)
        // and must not rescan a very long transcript entry.
        if value == text {
            if !active || reduceMotion { settle() } else { runs.removeAll { now >= $0.start + Self.duration } }
            return
        }
        let old = text as NSString
        let new = value as NSString
        guard active, !reduceMotion, value.hasPrefix(text), new.length >= old.length else {
            text = value; settle(); return
        }
        runs.removeAll { now >= $0.start + Self.duration }
        var cursor = old.length
        while cursor < new.length {
            let characterRange = new.rangeOfComposedCharacterSequence(at: cursor)
            let character = new.substring(with: characterRange)
            if character.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                cursor = NSMaxRange(characterRange)
                continue
            }
            let start = cursor
            cursor = NSMaxRange(characterRange)
            while cursor < new.length {
                let range = new.rangeOfComposedCharacterSequence(at: cursor)
                if new.substring(with: range).unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { break }
                cursor = NSMaxRange(range)
            }
            // A fragmented word continues its existing phase, rather than
            // flashing its already-visible prefix on the next provider delta.
            if let last = runs.indices.last, NSMaxRange(runs[last].range) == start,
               start > 0, !CharacterSet.whitespacesAndNewlines.contains(new.character(at: start - 1).unicodeScalar) {
                runs[last].range.length = cursor - runs[last].range.location
            } else {
                let began = max(now, nextStart)
                runs.append(Run(range: NSRange(location: start, length: cursor - start), start: began))
                nextStart = began + Self.stagger
            }
        }
        text = value
        // Only transient presentation metadata is retained. Burst overflow is
        // resolved immediately; the canonical text is never truncated.
        if runs.count > 64 { runs.removeFirst(runs.count - 64) }
    }

    mutating func settle() { runs.removeAll(); nextStart = 0 }
}

private extension unichar {
    var unicodeScalar: UnicodeScalar { UnicodeScalar(UInt32(self)) ?? "\u{FFFD}" }
}

/// Hide only unresolved glyphs during base drawing. Changing foreground
/// attributes during layout invalidates TextKit's entire paragraph repeatedly;
/// this presentation mask leaves storage/layout completely untouched.
final class AgentStreamingLayoutManager: NSLayoutManager {
    var hiddenRanges: [NSRange] = []
    var drawingOverlay = false
    override func drawGlyphs(forGlyphRange range: NSRange, at origin: NSPoint) {
        guard !drawingOverlay, !hiddenRanges.isEmpty else { super.drawGlyphs(forGlyphRange: range, at: origin); return }
        var cursor = range.location
        for characters in hiddenRanges {
            let hidden = NSIntersectionRange(range, glyphRange(forCharacterRange: characters, actualCharacterRange: nil))
            guard hidden.length > 0 else { continue }
            if hidden.location > cursor { super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: hidden.location - cursor), at: origin) }
            cursor = max(cursor, NSMaxRange(hidden))
        }
        if cursor < NSMaxRange(range) { super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: NSMaxRange(range) - cursor), at: origin) }
    }
}

/// One selectable TextKit surface per response, not a permanent view per word.
/// The transcript currently renders literal monospaced provider text; this
/// retains that representation (including Markdown source, links and code).
struct AgentStreamingText: NSViewRepresentable {
    let sessionID: AgentSessionInstanceID
    let responseID: String
    let text: String
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> AgentStreamingTextView {
        AgentStreamingTextView(resolvesInitialText: !AgentStreamingMountHistory.claim(sessionID: sessionID, responseID: responseID))
    }
    func updateNSView(_ view: AgentStreamingTextView, context: Context) {
        view.update(text, active: active, reduceMotion: reduceMotion)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AgentStreamingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 1 else { return CGSize(width: 1, height: 14) }
        return AgentPerformanceProbe.measure("agents.streaming.measure") { nsView.measuredSize(width: width) }
    }
    static func dismantleNSView(_ view: AgentStreamingTextView, coordinator: ()) { view.settle() }
}

/// A new response's first chunk resolves once. Remounts use already-resolved
/// initial text, including content delivered while collapsed. No text is cached.
@MainActor
enum AgentStreamingMountHistory {
    private struct Key: Hashable { let sessionID: AgentSessionInstanceID; let responseID: String }
    private static var seen: Set<Key> = []
    private static var order: [Key] = []
    static func claim(sessionID: AgentSessionInstanceID, responseID: String) -> Bool {
        let key = Key(sessionID: sessionID, responseID: responseID)
        guard seen.insert(key).inserted else { return false }
        order.append(key)
        if order.count > 256 { seen.remove(order.removeFirst()) }
        return true
    }
}

final class AgentStreamingTextView: NSTextView {
    private(set) var stream = AgentStreamingTextState()
    private var pending: DispatchWorkItem?
    private struct Overlay { let layer: CALayer; let range: NSRange; let rect: CGRect }
    private var wordLayers: [Int: Overlay] = [:]
    private var active = false
    private var reduced = false
    private let ink = NSColor.white.withAlphaComponent(0.88)
    private var lastWidth: CGFloat = 0
    /// Last Swift value applied to TextKit. SwiftUI/AppKit can call updateNSView
    /// repeatedly with unchanged transcript text during layout/preference passes;
    /// keeping this value avoids bridging/rescanning the full NSTextView string.
    private var appliedText = ""
    private var initialUpdate = true
    private let resolvesInitialText: Bool

    init(resolvesInitialText: Bool = true) {
        self.resolvesInitialText = resolvesInitialText
        let storage = NSTextStorage()
        let manager = AgentStreamingLayoutManager()
        let container = NSTextContainer(containerSize: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false; isSelectable = true; drawsBackground = false
        isRichText = false; textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        isVerticallyResizable = false; isHorizontallyResizable = false
        font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        textColor = ink
        wantsLayer = true
        setAccessibilityLabel("Agent response")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func measuredSize(width: CGFloat) -> CGSize {
        let width = max(1, width)
        if lastWidth != width {
            lastWidth = width
            textContainer?.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            needsLayout = true
        }
        guard let layoutManager, let textContainer else { return CGSize(width: width, height: 14) }
        layoutManager.ensureLayout(for: textContainer)
        return CGSize(width: width, height: max(14, ceil(layoutManager.usedRect(for: textContainer).maxY)))
    }

    func update(_ text: String, active: Bool, reduceMotion: Bool) {
        // Compare against the last applied Swift string (same storage is an
        // O(1) identity check) instead of bridging NSTextView.string each pass.
        let changed = initialUpdate || text != appliedText
        if !changed, active == self.active, reduceMotion == reduced, stream.runs.isEmpty { return }
        appliedText = text
        let now = CACurrentMediaTime()
        // Initial/historical content is already resolved. Remounting never
        // replays a response that arrived while the island was collapsed.
        if initialUpdate && resolvesInitialText {
            stream.update(text, active: false, reduceMotion: reduceMotion, now: now)
        } else {
            stream.update(text, active: active, reduceMotion: reduceMotion, now: now)
        }
        initialUpdate = false
        self.active = active; reduced = reduceMotion
        if changed {
            let selection = selectedRange()
            let previous = string
            let oldLength = (previous as NSString).length
            if text.hasPrefix(previous) {
                let appended = (text as NSString).substring(from: oldLength)
                textStorage?.append(NSAttributedString(string: appended, attributes: [.font: font!, .foregroundColor: ink]))
            } else {
                textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [.font: font!, .foregroundColor: ink]))
            }
            setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: min(selection.length, max(0, (text as NSString).length - selection.location))))
            invalidateIntrinsicContentSize()
        }
        if !active || reduceMotion { settle() }
        else { AgentPerformanceProbe.measure("agents.streaming.overlays") { rebuildLayers(now: now) } }
    }

    override func layout() {
        super.layout()
        if !stream.runs.isEmpty { rebuildLayers(now: CACurrentMediaTime()) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { settle() }
    }

    func settle() {
        pending?.cancel(); pending = nil
        wordLayers.values.forEach { $0.layer.removeFromSuperlayer() }; wordLayers.removeAll()
        stream.settle()
        (layoutManager as? AgentStreamingLayoutManager)?.hiddenRanges = []
        needsDisplay = true
    }

    private func rebuildLayers(now: TimeInterval) {
        pending?.cancel(); pending = nil
        guard active, !reduced, let layoutManager = layoutManager as? AgentStreamingLayoutManager, let textContainer, let layer,
              lastWidth > 0 else { return }
        layoutManager.ensureLayout(for: textContainer)
        let live = stream.runs.filter { now < $0.start + AgentStreamingTextState.duration }
        layoutManager.hiddenRanges = live.map(\.range)
        let visible = live.filter { now >= $0.start }
        let keys = Set(visible.map { $0.range.location })
        for key in Array(wordLayers.keys) where !keys.contains(key) {
            wordLayers.removeValue(forKey: key)?.layer.removeFromSuperlayer()
        }
        for run in visible {
            let glyphs = layoutManager.glyphRange(forCharacterRange: run.range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).insetBy(dx: -2, dy: -2)
            guard rect.width > 0, rect.height > 0 else { continue }
            if let existing = wordLayers[run.range.location], existing.range == run.range, existing.rect == rect {
                continue
            }
            wordLayers.removeValue(forKey: run.range.location)?.layer.removeFromSuperlayer()
            // Rasterize just this transient run at its final TextKit geometry.
            // Gaussian filtering and opacity never affect measurement/wrapping.
            let scale = window?.backingScaleFactor ?? 2
            guard let context = CGContext(data: nil, width: Int(ceil(rect.width * scale)), height: Int(ceil(rect.height * scale)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            layoutManager.drawingOverlay = true
            layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
            layoutManager.drawingOverlay = false
            NSGraphicsContext.restoreGraphicsState()
            let word = CALayer()
            word.frame = rect; word.contents = context.makeImage(); word.contentsScale = scale
            let blur = CIFilter(name: "CIGaussianBlur")!
            blur.name = "resolveBlur"
            let elapsed = max(0, now - run.start)
            let progress = min(1, elapsed / AgentStreamingTextState.duration)
            let resolved = ExpandedIslandMotion.bezier(progress, 0.22, 1, 0.36, 1)
            word.opacity = Float(resolved)
            blur.setValue(AgentStreamingTextState.blur * (1 - resolved), forKey: kCIInputRadiusKey)
            word.filters = [blur]
            layer.addSublayer(word); wordLayers[run.range.location] = Overlay(layer: word, range: run.range, rect: rect)
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0; opacity.toValue = 1
            let filter = CABasicAnimation(keyPath: "filters.resolveBlur.inputRadius")
            filter.fromValue = AgentStreamingTextState.blur; filter.toValue = 0
            for animation in [opacity, filter] {
                // Original start time also on fragment/width updates: sample
                // the original cubic curve, never restart its easing tail.
                animation.beginTime = run.start
                animation.duration = AgentStreamingTextState.duration
                animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                animation.fillMode = .both; animation.isRemovedOnCompletion = false
            }
            word.add(opacity, forKey: "resolveOpacity")
            word.add(filter, forKey: "resolveBlur")
        }
        // One presentation wakeup at the next word start/end; no per-frame
        // text layout, rasterization, timers, or SwiftUI publication.
        let next = live.map { $0.start > now ? $0.start : $0.start + AgentStreamingTextState.duration }.min()
        if let next {
            let work = DispatchWorkItem { [weak self] in self?.rebuildLayers(now: CACurrentMediaTime()) }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, next - now), execute: work)
        }
        needsDisplay = true
    }
}
