import XCTest
@testable import DynamicIsland

final class AgentBridgeHTTPParserTests: XCTestCase {
    func testFragmentedHeadersAndBodyAreAccepted() throws {
        let body = Data("{\"ok\":true}".utf8)
        let raw = AgentBridgeTestSupport.rawRequest(body: body)
        var parser = AgentBridgeHTTPRequestParser()
        var result: AgentBridgeHTTPParseResult = .needMore

        for byte in raw {
            result = parser.append(Data([byte]))
        }

        guard case .request(let request) = result else { return XCTFail("Expected request") }
        XCTAssertEqual(request.body, body)
        XCTAssertEqual(request.route, "/v1/events")
    }

    func testMalformedRequestLineIsRejected() {
        assertFailure(Data("POST  /v1/events HTTP/1.1\r\nContent-Length: 0\r\n\r\n".utf8), status: .badRequest)
    }

    func testMalformedHeaderIsRejected() {
        assertFailure(Data("POST /v1/events HTTP/1.1\r\nBad Header\r\nContent-Length: 0\r\n\r\n".utf8), status: .badRequest)
    }

    func testMissingContentLengthIsRejectedForPost() {
        assertFailure(Data("POST /v1/events HTTP/1.1\r\nContent-Type: application/json\r\n\r\n".utf8), status: .badRequest)
    }

    func testDuplicateContentLengthIsRejectedEvenWhenEqual() {
        let raw = Data("POST /v1/events HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n".utf8)
        assertFailure(raw, status: .badRequest)
    }

    func testConflictingContentLengthIsRejected() {
        let raw = Data("POST /v1/events HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nxx".utf8)
        assertFailure(raw, status: .badRequest)
    }

    func testNegativeContentLengthIsRejected() {
        let raw = Data("POST /v1/events HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)
        assertFailure(raw, status: .payloadTooLarge)
    }

    func testHugeNumericContentLengthIsRejectedWithoutOverflow() {
        let raw = Data("POST /v1/events HTTP/1.1\r\nContent-Length: 999999999999999999999999\r\n\r\n".utf8)
        assertFailure(raw, status: .payloadTooLarge)
    }

    func testOversizedDeclaredBodyIsRejectedBeforeBodyArrives() {
        let size = AgentBridgeLimits.maximumRequestBodyBytes + 1
        let raw = Data("POST /v1/events HTTP/1.1\r\nContent-Length: \(size)\r\n\r\n".utf8)
        assertFailure(raw, status: .payloadTooLarge)
    }

    func testChunkedTransferIsExplicitlyRejected() {
        let raw = Data("POST /v1/events HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n".utf8)
        assertFailure(raw, status: .badRequest)
    }

    func testHeaderNamesAreCaseInsensitiveAndWhitespaceIsTrimmed() {
        let raw = Data("POST /v1/events HTTP/1.1\r\ncOnTeNt-LeNgTh: 0 \r\n\r\n".utf8)
        var parser = AgentBridgeHTTPRequestParser()
        guard case .request(let request) = parser.append(raw) else { return XCTFail("Expected request") }
        XCTAssertEqual(request.headers["content-length"], "0")
    }

    func testFoldedHeaderIsRejected() {
        let raw = Data("POST /v1/events HTTP/1.1\r\nContent-Length: 0\r\n continued\r\n\r\n".utf8)
        assertFailure(raw, status: .badRequest)
    }

    func testExtraBytesAfterDeclaredBodyAreRejected() {
        let raw = Data("POST /v1/events HTTP/1.1\r\nContent-Length: 1\r\n\r\n{}".utf8)
        assertFailure(raw, status: .badRequest)
    }

    func testSecondRequestOnOneConnectionIsRejected() {
        let first = AgentBridgeTestSupport.rawRequest(body: Data())
        let second = Data("GET /v1/health HTTP/1.1\r\n\r\n".utf8)
        assertFailure(first + second, status: .badRequest)
    }

    func testPrematureCloseIsRejectedAsTruncated() {
        var parser = AgentBridgeHTTPRequestParser()
        XCTAssertEqual(
            parser.append(Data("POST /v1/events HTTP/1.1\r\nContent-Length: 4\r\n\r\n{}".utf8)),
            .needMore
        )
        XCTAssertEqual(parser.finish(), .failure(.badRequest, "truncated-request"))
    }

    func testGiantHeaderIsRejected() {
        let value = String(repeating: "x", count: AgentBridgeLimits.maximumHeaderBytes)
        let raw = Data("POST /v1/events HTTP/1.1\r\nX-Large: \(value)".utf8)
        assertFailure(raw, status: .payloadTooLarge)
    }

    func testGiantIndividualHeaderValueIsRejected() {
        let value = String(repeating: "x", count: AgentBridgeLimits.maximumHeaderValueBytes + 1)
        let raw = Data("POST /v1/events HTTP/1.1\r\nX-Large: \(value)\r\nContent-Length: 0\r\n\r\n".utf8)
        assertFailure(raw, status: .badRequest)
    }

    func testInvalidUTF8HeaderIsRejected() {
        var raw = Data("POST /v1/events HTTP/1.1\r\nX-Bad: ".utf8)
        raw.append(0xff)
        raw.append(Data("\r\nContent-Length: 0\r\n\r\n".utf8))
        assertFailure(raw, status: .badRequest)
    }

    private func assertFailure(
        _ data: Data,
        status: AgentBridgeHTTPStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var parser = AgentBridgeHTTPRequestParser()
        guard case .failure(let actual, _) = parser.append(data) else {
            return XCTFail("Expected parser failure", file: file, line: line)
        }
        XCTAssertEqual(actual.rawValue, status.rawValue, file: file, line: line)
    }
}
