import Foundation
import XCTest
@testable import DynamicIsland

final class DelimitedRecordFramerTests: XCTestCase {
    func testEmitsOneCompleteRecord() {
        var framer = DelimitedRecordFramer()
        XCTAssertEqual(framer.feed(Data("one\n".utf8)).records, [Data("one".utf8)])
    }

    func testEmitsManyRecordsInOrder() {
        var framer = DelimitedRecordFramer()
        XCTAssertEqual(
            framer.feed(Data("one\ntwo\nthree\n".utf8)).records,
            ["one", "two", "three"].map { Data($0.utf8) }
        )
    }

    func testByteAtATimeFeed() {
        var framer = DelimitedRecordFramer()
        var records: [Data] = []
        for byte in Data("split\n".utf8) {
            records += framer.feed(Data([byte])).records
        }
        XCTAssertEqual(records, [Data("split".utf8)])
    }

    func testPartialFinalRecordIsRetained() {
        var framer = DelimitedRecordFramer()
        XCTAssertTrue(framer.feed(Data("partial".utf8)).records.isEmpty)
        XCTAssertEqual(framer.retainedByteCount, 7)
    }

    func testPartialRecordCompletesAfterLaterFeed() {
        var framer = DelimitedRecordFramer()
        _ = framer.feed(Data("part".utf8))
        XCTAssertEqual(framer.feed(Data("ial\n".utf8)).records, [Data("partial".utf8)])
        XCTAssertEqual(framer.retainedByteCount, 0)
    }

    func testSplitUTF8SequenceRemainsByteExact() {
        let value = Data("café\n".utf8)
        var framer = DelimitedRecordFramer()
        _ = framer.feed(value.prefix(4))
        let output = framer.feed(value.dropFirst(4))
        XCTAssertEqual(output.records, [Data("café".utf8)])
    }

    func testCRLFStripsSingleCarriageReturn() {
        var framer = DelimitedRecordFramer()
        XCTAssertEqual(framer.feed(Data("value\r\n".utf8)).records, [Data("value".utf8)])
    }

    func testEmptyLinesAreRecords() {
        var framer = DelimitedRecordFramer()
        XCTAssertEqual(framer.feed(Data("\n\n".utf8)).records, [Data(), Data()])
    }

    func testRecordAtExactLimitIsAccepted() {
        var framer = DelimitedRecordFramer(maximumRecordBytes: 4)
        XCTAssertEqual(framer.feed(Data("1234\n".utf8)).records, [Data("1234".utf8)])
    }

    func testRecordOverLimitIsDropped() {
        var framer = DelimitedRecordFramer(maximumRecordBytes: 4)
        let output = framer.feed(Data("12345\n".utf8))
        XCTAssertTrue(output.records.isEmpty)
        XCTAssertEqual(output.oversizeRecordsDropped, 1)
        XCTAssertEqual(framer.retainedByteCount, 0)
    }

    func testRecoversAfterOversizedRecord() {
        var framer = DelimitedRecordFramer(maximumRecordBytes: 4)
        let output = framer.feed(Data("12345\ngood\n".utf8))
        XCTAssertEqual(output.oversizeRecordsDropped, 1)
        XCTAssertEqual(output.records, [Data("good".utf8)])
    }

    func testTrailingBufferNeverExceedsLimit() {
        var framer = DelimitedRecordFramer(maximumRecordBytes: 4)
        _ = framer.feed(Data(repeating: 0x41, count: 10_000))
        XCTAssertLessThanOrEqual(framer.retainedByteCount, 4)
        XCTAssertTrue(framer.feed(Data("\nnext\n".utf8)).records.contains(Data("next".utf8)))
    }
}
