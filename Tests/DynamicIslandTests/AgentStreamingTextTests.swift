import AppKit
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentStreamingTextTests: XCTestCase {
    func testProviderTextBoundPreservesStreamingWhitespaceWithoutRemovingTheCap() {
        XCTAssertEqual(AgentManagedTranscriptEntry.boundedText("\n  ", preservingWhitespace: true), "\n  ")
        XCTAssertNil(AgentManagedTranscriptEntry.boundedText("", preservingWhitespace: true))
        let source = "  " + String(repeating: "x", count: 8_100)
        let bounded = AgentManagedTranscriptEntry.boundedText(source, preservingWhitespace: true)
        XCTAssertEqual(bounded?.count, AgentManagedTranscriptEntry.maximumTextLength)
        XCTAssertTrue(bounded?.hasPrefix("  ") == true)
        XCTAssertTrue(bounded?.hasSuffix("…") == true)
        XCTAssertEqual(AgentManagedTranscriptEntry.boundedText("  historical summary \n"), "historical summary")
    }
    func testExactMotionAndOnlyAppendReceivesRuns() {
        XCTAssertEqual(AgentStreamingTextState.duration, 0.350)
        XCTAssertEqual(AgentStreamingTextState.stagger, 0.060)
        XCTAssertEqual(AgentStreamingTextState.blur, 1)
        var state = AgentStreamingTextState()
        state.update("Existing ", active: false, reduceMotion: false, now: 0)
        state.update("Existing new words", active: true, reduceMotion: false, now: 1)
        XCTAssertEqual(state.runs.map(\.range), [NSRange(location: 9, length: 3), NSRange(location: 13, length: 5)])
        XCTAssertEqual(state.runs.map(\.start), [1, 1.060])
        state.update("Existing new words! ", active: true, reduceMotion: false, now: 1.1)
        XCTAssertEqual(state.runs.count, 2)
        XCTAssertEqual(state.runs[1].start, 1.060)
        XCTAssertEqual(state.runs[1].range.length, 6)
    }
    func testFragmentedUnicodePunctuationWhitespaceAndMarkdownAreExact() {
        var state = AgentStreamingTextState()
        state.update("", active: false, reduceMotion: false, now: 0)
        let fragments = ["Hel", "lo, ", "👨‍👩‍👧‍👦", "!\n", "`code`\n", "```swift\n", "let x = 1\n```\n", "[link](https://example.com)"]
        var expected = ""
        for (index, fragment) in fragments.enumerated() {
            expected += fragment
            state.update(expected, active: true, reduceMotion: false, now: Double(index) / 100)
            XCTAssertEqual(state.text, expected)
            XCTAssertTrue(state.runs.allSatisfy { NSMaxRange($0.range) <= (expected as NSString).length })
        }
        XCTAssertEqual(state.runs.first?.range, NSRange(location: 0, length: 6))
        XCTAssertEqual(state.runs.first?.start, 0)
    }
    func testCompletionInterruptionReduceMotionAndReplacementSettle() {
        for (active, reduced, value) in [(false, false, "new response"), (true, true, "new response"), (true, false, "replaced")] {
            var state = AgentStreamingTextState()
            state.update("new ", active: true, reduceMotion: false, now: 0)
            state.update(value, active: active, reduceMotion: reduced, now: 0.1)
            XCTAssertEqual(state.text, value)
            XCTAssertTrue(state.runs.isEmpty)
        }
    }
    func testTransientMetadataIsBoundedAndExpiredWordsDoNotReplay() {
        var state = AgentStreamingTextState()
        state.update(String(repeating: "word ", count: 500), active: true, reduceMotion: false, now: 0)
        XCTAssertLessThanOrEqual(state.runs.count, 64)
        XCTAssertEqual(state.text.count, 2500)
        state.update(state.text, active: true, reduceMotion: false, now: 60)
        XCTAssertTrue(state.runs.isEmpty)
    }
    func testNativeTextGeometrySelectionAndHistoricalCleanup() {
        let firstChunk = AgentStreamingTextView(resolvesInitialText: false)
        firstChunk.update("First streamed chunk", active: true, reduceMotion: false)
        XCTAssertFalse(firstChunk.stream.runs.isEmpty)
        firstChunk.settle()
        let view = AgentStreamingTextView()
        view.update("Hello ", active: true, reduceMotion: false)
        _ = view.measuredSize(width: 240)
        view.update("Hello new words.\n```swift\nlet x = 1\n```", active: true, reduceMotion: false)
        let moving = view.measuredSize(width: 240)
        view.setSelectedRange(NSRange(location: 0, length: 5))
        XCTAssertFalse(view.stream.runs.isEmpty)
        let animatedWord = view.layer?.sublayers?.first
        let opacity = animatedWord?.animation(forKey: "resolveOpacity") as? CABasicAnimation
        XCTAssertEqual(opacity?.duration, 0.350)
        XCTAssertEqual(opacity?.fromValue as? Float, 0)
        XCTAssertEqual(opacity?.toValue as? Float, 1)
        XCTAssertNotNil(animatedWord?.animation(forKey: "resolveBlur"))
        var point = [Float](repeating: 0, count: 2)
        opacity?.timingFunction?.getControlPoint(at: 1, values: &point)
        XCTAssertEqual(point, [0.22, 1])
        opacity?.timingFunction?.getControlPoint(at: 2, values: &point)
        XCTAssertEqual(point, [0.36, 1])
        view.update(view.string, active: false, reduceMotion: false)
        XCTAssertEqual(view.measuredSize(width: 240), moving)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 5))
        XCTAssertTrue(view.stream.runs.isEmpty)
        XCTAssertTrue(view.layer?.sublayers?.isEmpty ?? true)
    }
    func testViewportIntentStorageIsBoundedAndExactToProviderGeneration() {
        let store = AgentTranscriptViewportStore()
        let id = AgentSessionInstanceID(sessionID: .init(provider: .codex, nativeID: "same-native"), generation: .init(rawValue: 1))
        store.save(.init(followingLatest: false, origin: CGPoint(x: 0, y: 120), width: 440, readingEntryID: "message:3", readingEntryOffset: 8), for: id)
        XCTAssertFalse(store.position(for: id).followingLatest)
        let claude = AgentSessionInstanceID(sessionID: .init(provider: .claude, nativeID: "same-native"), generation: .init(rawValue: 1))
        let next = AgentSessionInstanceID(sessionID: id.sessionID, generation: .init(rawValue: 2))
        XCTAssertTrue(store.position(for: claude).followingLatest)
        XCTAssertTrue(store.position(for: next).followingLatest)
        for index in 0..<100 {
            store.save(.init(), for: .init(sessionID: .init(provider: .codex, nativeID: "bounded-\(index)"), generation: .init(rawValue: 1)))
        }
        XCTAssertEqual(store.count, AgentTranscriptViewportStore.capacity)
    }
}
