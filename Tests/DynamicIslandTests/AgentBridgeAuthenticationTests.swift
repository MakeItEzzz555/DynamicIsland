import XCTest
@testable import DynamicIsland

final class AgentBridgeAuthenticationTests: XCTestCase {
    func testRandomKeyGenerationUsesRequestedLengthAndIsNotConstant() throws {
        let first = try AgentBridgeCrypto.randomBytes(count: 32)
        let second = try AgentBridgeCrypto.randomBytes(count: 32)
        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(second.count, 32)
        XCTAssertNotEqual(first, second)
    }

    func testCredentialStoreSuccessAndFailureSeams() throws {
        XCTAssertEqual(
            try FixedAgentBridgeCredentialStore(secret: AgentBridgeTestSupport.secret).installationSecret(),
            AgentBridgeTestSupport.secret
        )
        XCTAssertThrowsError(try FixedAgentBridgeCredentialStore(secret: nil).installationSecret())
    }

    func testCanonicalMessageAndSignatureAreDeterministic() {
        let body = Data("{}".utf8)
        let first = AgentBridgeCrypto.signature(
            keyData: AgentBridgeTestSupport.launchKey,
            method: "POST",
            route: "/v1/events",
            protocolVersion: 1,
            timestamp: 123,
            nonce: "abc",
            body: body
        )
        let second = AgentBridgeCrypto.signature(
            keyData: AgentBridgeTestSupport.launchKey,
            method: "post",
            route: "/v1/events",
            protocolVersion: 1,
            timestamp: 123,
            nonce: "abc",
            body: body
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
    }

    func testValidSignatureIsAccepted() async throws {
        let authenticator = makeAuthenticator()
        let request = AgentBridgeTestSupport.signedRequest(body: try validBody())
        let result = await authenticator.authenticate(request, at: AgentBridgeTestSupport.now)
        XCTAssertNil(result)
    }

    func testWrongSecretIsRejected() async throws {
        let authenticator = makeAuthenticator()
        let request = AgentBridgeTestSupport.signedRequest(
            body: try validBody(),
            key: Data(repeating: 1, count: 32)
        )
        let result = await authenticator.authenticate(request, at: AgentBridgeTestSupport.now)
        XCTAssertEqual(result, .invalidSignature)
    }

    func testSingleByteBodyMutationIsRejected() async throws {
        let authenticator = makeAuthenticator()
        let original = try validBody()
        var request = AgentBridgeTestSupport.signedRequest(body: original)
        var changed = original
        changed[changed.startIndex] ^= 1
        request = AgentBridgeHTTPRequest(
            method: request.method,
            route: request.route,
            headers: request.headers,
            body: changed
        )
        let result = await authenticator.authenticate(request, at: AgentBridgeTestSupport.now)
        XCTAssertEqual(result, .invalidSignature)
    }

    func testMethodAndRouteAreBoundBySignature() async throws {
        let body = try validBody()
        let signed = AgentBridgeTestSupport.signedRequest(body: body)
        let authenticator = makeAuthenticator()
        let changedRoute = AgentBridgeHTTPRequest(
            method: signed.method,
            route: "/v1/health",
            headers: signed.headers,
            body: body
        )
        let routeResult = await authenticator.authenticate(changedRoute, at: AgentBridgeTestSupport.now)
        XCTAssertEqual(routeResult, .invalidSignature)

        let changedMethod = AgentBridgeHTTPRequest(
            method: "GET",
            route: signed.route,
            headers: signed.headers,
            body: body
        )
        let methodResult = await makeAuthenticator().authenticate(changedMethod, at: AgentBridgeTestSupport.now)
        XCTAssertEqual(methodResult, .invalidSignature)
    }

    func testNonceReplayIsRejected() async throws {
        let authenticator = makeAuthenticator()
        let request = AgentBridgeTestSupport.signedRequest(body: try validBody())
        let first = await authenticator.authenticate(request, at: AgentBridgeTestSupport.now)
        let replay = await authenticator.authenticate(request, at: AgentBridgeTestSupport.now)
        XCTAssertNil(first)
        XCTAssertEqual(replay, .replay)
    }

    func testNonceCacheIsBoundedAndRejectsNewEntryWhenFull() async throws {
        let authenticator = makeAuthenticator()
        let body = try validBody()
        for index in 0..<AgentBridgeLimits.maximumRememberedNonces {
            let request = AgentBridgeTestSupport.signedRequest(body: body, nonce: "nonce-\(index)")
            let result = await authenticator.authenticate(request, at: AgentBridgeTestSupport.now)
            XCTAssertNil(result)
        }
        let overflow = AgentBridgeTestSupport.signedRequest(body: body, nonce: "nonce-overflow")
        let overflowResult = await authenticator.authenticate(overflow, at: AgentBridgeTestSupport.now)
        let count = await authenticator.rememberedNonceCount
        XCTAssertEqual(overflowResult, .replayCacheFull)
        XCTAssertEqual(count, AgentBridgeLimits.maximumRememberedNonces)
    }

    func testExpiredNonceLeavesCacheAndMayBeUsedWithFreshTimestamp() async throws {
        let authenticator = makeAuthenticator()
        let body = try validBody()
        let first = AgentBridgeTestSupport.signedRequest(body: body, nonce: "reusable")
        let firstResult = await authenticator.authenticate(first, at: AgentBridgeTestSupport.now)
        XCTAssertNil(firstResult)
        let later = AgentBridgeTestSupport.now.addingTimeInterval(AgentBridgeLimits.nonceRetention + 1)
        let fresh = AgentBridgeTestSupport.signedRequest(
            body: body,
            timestamp: Int64(later.timeIntervalSince1970),
            nonce: "reusable"
        )
        let freshResult = await authenticator.authenticate(fresh, at: later)
        let count = await authenticator.rememberedNonceCount
        XCTAssertNil(freshResult)
        XCTAssertEqual(count, 1)
    }

    func testCacheExpiryDoesNotAssumeWallClockSamplesAreMonotonic() async throws {
        let authenticator = makeAuthenticator()
        let body = try validBody()
        let future = AgentBridgeTestSupport.now.addingTimeInterval(100)
        let futureRequest = AgentBridgeTestSupport.signedRequest(
            body: body,
            timestamp: Int64(future.timeIntervalSince1970),
            nonce: "future-first"
        )
        let futureResult = await authenticator.authenticate(futureRequest, at: future)
        XCTAssertNil(futureResult)

        let earlierRequest = AgentBridgeTestSupport.signedRequest(body: body, nonce: "earlier-second")
        let earlierResult = await authenticator.authenticate(earlierRequest, at: AgentBridgeTestSupport.now)
        XCTAssertNil(earlierResult)

        let afterEarlierExpiry = AgentBridgeTestSupport.now.addingTimeInterval(AgentBridgeLimits.nonceRetention + 1)
        let trigger = AgentBridgeTestSupport.signedRequest(
            body: body,
            timestamp: Int64(afterEarlierExpiry.timeIntervalSince1970),
            nonce: "trigger-purge"
        )
        let result = await authenticator.authenticate(trigger, at: afterEarlierExpiry)
        let count = await authenticator.rememberedNonceCount
        XCTAssertNil(result)
        XCTAssertEqual(count, 2)
    }

    func testTimestampBoundaryAndOutsideWindow() async throws {
        let body = try validBody()
        let boundary = Int64(AgentBridgeTestSupport.now.timeIntervalSince1970 - AgentBridgeLimits.acceptedClockSkew)
        let boundaryResult = await makeAuthenticator().authenticate(
            AgentBridgeTestSupport.signedRequest(body: body, timestamp: boundary),
            at: AgentBridgeTestSupport.now
        )
        XCTAssertNil(boundaryResult)
        let stale = boundary - 1
        let staleResult = await makeAuthenticator().authenticate(
            AgentBridgeTestSupport.signedRequest(body: body, timestamp: stale),
            at: AgentBridgeTestSupport.now
        )
        XCTAssertEqual(staleResult, .timestampOutsideWindow)
        let future = Int64(AgentBridgeTestSupport.now.timeIntervalSince1970 + AgentBridgeLimits.acceptedClockSkew + 1)
        let futureResult = await makeAuthenticator().authenticate(
            AgentBridgeTestSupport.signedRequest(body: body, timestamp: future),
            at: AgentBridgeTestSupport.now
        )
        XCTAssertEqual(futureResult, .timestampOutsideWindow)
    }

    func testGiantNonceAndSignatureAreRejectedWithoutRetention() async throws {
        let body = try validBody()
        let authenticator = makeAuthenticator()
        let request = AgentBridgeTestSupport.signedRequest(
            body: body,
            nonce: String(repeating: "n", count: AgentBridgeLimits.maximumNonceBytes + 1)
        )
        let nonceResult = await authenticator.authenticate(request, at: AgentBridgeTestSupport.now)
        let firstCount = await authenticator.rememberedNonceCount
        XCTAssertEqual(nonceResult, .invalidNonce)
        XCTAssertEqual(firstCount, 0)

        var headers = AgentBridgeTestSupport.signedRequest(body: body).headers
        headers["x-dynamicisland-signature"] = String(repeating: "a", count: AgentBridgeLimits.maximumSignatureBytes + 1)
        let signature = AgentBridgeHTTPRequest(method: "POST", route: "/v1/events", headers: headers, body: body)
        let signatureResult = await authenticator.authenticate(signature, at: AgentBridgeTestSupport.now)
        XCTAssertEqual(signatureResult, .invalidSignature)
    }

    func testSecretDoesNotAppearInResponseOrCredentialErrorDescription() {
        let secretText = AgentBridgeTestSupport.secret.base64EncodedString()
        let response = String(data: AgentBridgeHTTPResponse(status: .unauthorized, code: "authentication").data, encoding: .utf8)
        XCTAssertFalse(response?.contains(secretText) == true)
        XCTAssertFalse(String(describing: AgentBridgeCredentialError.invalidStoredSecret).contains(secretText))
    }

    private func makeAuthenticator() -> AgentBridgeAuthenticator {
        AgentBridgeAuthenticator(keyData: AgentBridgeTestSupport.launchKey)
    }

    private func validBody() throws -> Data {
        try AgentBridgeTestSupport.body(event: AgentBridgeTestSupport.event())
    }
}
