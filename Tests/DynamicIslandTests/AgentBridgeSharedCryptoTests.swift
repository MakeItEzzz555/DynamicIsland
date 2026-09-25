import Foundation
import XCTest
@testable import AgentBridgeShared

final class AgentBridgeSharedCryptoTests: XCTestCase {
    func testCanonicalMessageMatchesV1GoldenVector() {
        let body = Data("{}".utf8)
        let canonical = AgentBridgeRequestAuthentication.canonicalMessage(
            method: "post",
            route: "/v1/events",
            protocolVersion: 1,
            timestamp: 123,
            nonce: "abc",
            body: body
        )
        XCTAssertEqual(
            String(data: canonical, encoding: .utf8),
            "POST\n/v1/events\n1\n123\nabc\n44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
        )
        XCTAssertEqual(
            AgentBridgeRequestAuthentication.signature(
                keyData: Data(repeating: 0x24, count: 32),
                method: "POST",
                route: "/v1/events",
                protocolVersion: 1,
                timestamp: 123,
                nonce: "abc",
                body: body
            ),
            "f2be467027c2c1c37a7873e39a268d05afc030b30655edb6862ab0e6956676bc"
        )
    }

    func testSignatureBindsMethodRouteAndBody() {
        let key = Data(repeating: 7, count: 32)
        let body = Data("body".utf8)
        let original = signature(key: key, method: "POST", route: "/v1/events", body: body)
        XCTAssertNotEqual(original, signature(key: key, method: "GET", route: "/v1/events", body: body))
        XCTAssertNotEqual(original, signature(key: key, method: "POST", route: "/v1/health", body: body))
        XCTAssertNotEqual(original, signature(key: key, method: "POST", route: "/v1/events", body: Data("Body".utf8)))
        XCTAssertTrue(AgentBridgeRequestAuthentication.validateSignature(
            original,
            keyData: key,
            method: "POST",
            route: "/v1/events",
            protocolVersion: 1,
            timestamp: 10,
            nonce: "nonce",
            body: body
        ))
    }

    func testRandomNonceIsBoundedHexAndChanges() throws {
        let first = try AgentBridgeRequestAuthentication.randomNonce(byteCount: 16)
        let second = try AgentBridgeRequestAuthentication.randomNonce(byteCount: 16)
        XCTAssertEqual(first.utf8.count, 32)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.allSatisfy(\.isHexDigit))
    }

    private func signature(key: Data, method: String, route: String, body: Data) -> String {
        AgentBridgeRequestAuthentication.signature(
            keyData: key,
            method: method,
            route: route,
            protocolVersion: 1,
            timestamp: 10,
            nonce: "nonce",
            body: body
        )
    }
}
