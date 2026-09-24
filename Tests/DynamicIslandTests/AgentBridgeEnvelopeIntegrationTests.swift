import XCTest
@testable import DynamicIsland

@MainActor
final class AgentBridgeEnvelopeIntegrationTests: XCTestCase {
    func testValidSignedEventReachesRealStore() async throws {
        let (processor, store) = makeProcessor()
        let response = await processor.handle(signed(body: try AgentBridgeTestSupport.body(
            event: AgentBridgeTestSupport.event()
        )))

        XCTAssertEqual(response.status, .accepted)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.id.generation.rawValue, 1)
    }

    func testMalformedJSONInvalidUTF8AndUnknownProtocolAreRejected() async throws {
        for (index, body) in [
            Data("{".utf8),
            Data([0xFF, 0xFE]),
            try JSONSerialization.data(withJSONObject: [
                "protocolVersion": 2,
                "producerID": "producer",
                "event": AgentBridgeTestSupport.event()
            ])
        ].enumerated() {
            let (processor, store) = makeProcessor()
            let response = await processor.handle(signed(body: body, nonce: "bad-\(index)"))
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(store.sessions.isEmpty)
        }
    }

    func testBooleanProtocolVersionIsNotAcceptedAsOne() async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "protocolVersion": true,
            "producerID": "producer",
            "event": AgentBridgeTestSupport.event()
        ])
        let (processor, store) = makeProcessor()
        let response = await processor.handle(signed(body: body))
        XCTAssertEqual(response.status, .badRequest)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testUnsupportedRouteMethodAndContentTypeAreRejected() async throws {
        let body = try AgentBridgeTestSupport.body(event: AgentBridgeTestSupport.event())
        let (routeProcessor, _) = makeProcessor()
        await assertResponse(routeProcessor, signed(body: body, route: "/v1/other"), equals: .notFound)
        let (methodProcessor, _) = makeProcessor()
        await assertResponse(methodProcessor, signed(body: body, method: "PUT"), equals: .methodNotAllowed)
        let (typeProcessor, _) = makeProcessor()
        let wrongType = AgentBridgeTestSupport.signedRequest(
            body: body,
            key: AgentBridgeTestSupport.launchKey,
            nonce: "wrong-type",
            contentType: "text/plain"
        )
        await assertResponse(typeProcessor, wrongType, equals: .unsupportedMediaType)
    }

    func testProcessorRejectsRouteOrBodyMutationAfterSigning() async throws {
        let body = try AgentBridgeTestSupport.body(event: AgentBridgeTestSupport.event())
        let signedRequest = signed(body: body, nonce: "canonical")
        let changedRoute = AgentBridgeHTTPRequest(
            method: signedRequest.method,
            route: "/v1/health",
            headers: signedRequest.headers,
            body: body
        )
        let (routeProcessor, _) = makeProcessor()
        await assertResponse(routeProcessor, changedRoute, equals: .unauthorized)

        var changedBody = body
        changedBody[changedBody.startIndex] ^= 1
        let bodyMutation = AgentBridgeHTTPRequest(
            method: signedRequest.method,
            route: signedRequest.route,
            headers: signedRequest.headers,
            body: changedBody
        )
        let (bodyProcessor, store) = makeProcessor()
        await assertResponse(bodyProcessor, bodyMutation, equals: .unauthorized)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testOversizedSingleEventAndTooManyEventBatchAreRejected() async throws {
        let huge = String(repeating: "x", count: AgentBridgeLimits.maximumSingleEventBodyBytes)
        let hugeBody = try AgentBridgeTestSupport.body(event: AgentBridgeTestSupport.event(
            payload: ["sessionMetadata": ["title": huge]]
        ))
        let (singleProcessor, singleStore) = makeProcessor()
        await assertResponse(singleProcessor, signed(body: hugeBody), equals: .payloadTooLarge)
        XCTAssertTrue(singleStore.sessions.isEmpty)

        let events = (0...AgentBridgeLimits.maximumBatchEvents).map {
            AgentBridgeTestSupport.event(id: "event-\($0)", nativeSessionID: "session-\($0)")
        }
        let batch = try AgentBridgeTestSupport.batchBody(events: events)
        let (batchProcessor, batchStore) = makeProcessor()
        await assertResponse(batchProcessor, signed(body: batch, nonce: "too-many"), equals: .payloadTooLarge)
        XCTAssertTrue(batchStore.sessions.isEmpty)
    }

    func testRequestBodyLimitIsRejectedBeforeEnvelopeDecode() async {
        let body = Data(repeating: 0x20, count: AgentBridgeLimits.maximumRequestBodyBytes + 1)
        let (processor, store) = makeProcessor()
        await assertResponse(processor, signed(body: body), equals: .payloadTooLarge)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testValidShapeBatchOverOneMiBIsRejectedWithoutMutation() async throws {
        let boundedLargeTitle = String(repeating: "b", count: 63_000)
        let events = (0..<17).map { index in
            AgentBridgeTestSupport.event(
                id: "large-\(index)",
                nativeSessionID: "large-session-\(index)",
                payload: ["sessionMetadata": ["title": boundedLargeTitle]]
            )
        }
        let body = try AgentBridgeTestSupport.batchBody(events: events)
        XCTAssertGreaterThan(body.count, AgentBridgeLimits.maximumRequestBodyBytes)
        let (processor, store) = makeProcessor()
        await assertResponse(processor, signed(body: body, nonce: "large-batch"), equals: .payloadTooLarge)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testEmptyBatchAndExcessiveJSONDepthAreRejected() async throws {
        let empty = try AgentBridgeTestSupport.batchBody(events: [])
        let (emptyProcessor, emptyStore) = makeProcessor()
        await assertResponse(emptyProcessor, signed(body: empty), equals: .badRequest)
        XCTAssertTrue(emptyStore.sessions.isEmpty)

        var nested: Any = "end"
        for _ in 0...AgentBridgeLimits.maximumJSONDepth { nested = ["child": nested] }
        let deep = try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 1, "producerID": "producer", "event": nested
        ])
        let (deepProcessor, deepStore) = makeProcessor()
        await assertResponse(deepProcessor, signed(body: deep, nonce: "deep"), equals: .badRequest)
        XCTAssertTrue(deepStore.sessions.isEmpty)
    }

    func testBatchIsAtomicWhenOneEventIsSemanticallyInvalid() async throws {
        let invalidID = String(repeating: "i", count: AgentDomainLimits.identifierLength + 1)
        let body = try AgentBridgeTestSupport.batchBody(events: [
            AgentBridgeTestSupport.event(id: "valid"),
            AgentBridgeTestSupport.event(id: invalidID, nativeSessionID: "other")
        ])
        let (processor, store) = makeProcessor()
        await assertResponse(processor, signed(body: body), equals: .unprocessableContent)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testDuplicateNormalizedEventRemainsIdempotentAcrossAuthenticatedRequests() async throws {
        let body = try AgentBridgeTestSupport.body(event: AgentBridgeTestSupport.event())
        let (processor, store) = makeProcessor()
        await assertResponse(processor, signed(body: body, nonce: "first"), equals: .accepted)
        await assertResponse(processor, signed(body: body, nonce: "second"), equals: .accepted)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.recentActivity.count, 1)
    }

    func testProducerReplacementAllocatesNewGenerationAndRejectsStaleProducerWork() async throws {
        let store = AgentEventStore()
        let ingress = AgentBridgeIngress(store: store)
        ingress.activate(launchID: "test-launch")
        let firstProcessor = makeProcessor(
            store: store,
            ingress: ingress,
            producerID: "producer-a"
        )
        let replacementProcessor = makeProcessor(
            store: store,
            ingress: ingress,
            producerID: "producer-b"
        )
        let first = try AgentBridgeTestSupport.body(
            producerID: "producer-a",
            event: AgentBridgeTestSupport.event(id: "start-1")
        )
        let replacement = try AgentBridgeTestSupport.body(
            producerID: "producer-b",
            event: AgentBridgeTestSupport.event(id: "start-2")
        )
        let stale = try AgentBridgeTestSupport.body(
            producerID: "producer-a",
            event: AgentBridgeTestSupport.event(
                id: "late-work", type: "agentWorking", payload: ["activity": ["summary": "late"]]
            )
        )
        await assertResponse(firstProcessor, signed(body: first, nonce: "n1"), equals: .accepted)
        await assertResponse(replacementProcessor, signed(body: replacement, nonce: "n2"), equals: .accepted)
        await assertResponse(firstProcessor, signed(body: stale, nonce: "n3"), equals: .unprocessableContent)
        XCTAssertEqual(Set(store.sessions.map(\.id.generation.rawValue)), [1, 2])
        XCTAssertEqual(store.sessions.first(where: { $0.id.generation.rawValue == 2 })?.state, .idle)
        XCTAssertFalse(store.sessions.contains { session in
            session.recentActivity.contains { $0.id.rawValue == "late-work" }
        })
    }

    func testAuthenticatedProducerCannotClaimAnotherProducerIdentity() async throws {
        let body = try AgentBridgeTestSupport.body(
            producerID: "producer-b",
            event: AgentBridgeTestSupport.event(id: "hijack")
        )
        let (processor, store) = makeProcessor(producerID: "producer-a")

        await assertResponse(processor, signed(body: body), equals: .unprocessableContent)

        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testConcurrentProvidersAndSessionsRemainIsolated() async throws {
        let events = [
            AgentBridgeTestSupport.event(id: "codex-a", nativeSessionID: "same"),
            AgentBridgeTestSupport.event(id: "claude-a", provider: "claude", nativeSessionID: "same"),
            AgentBridgeTestSupport.event(id: "codex-b", nativeSessionID: "other")
        ]
        let (processor, store) = makeProcessor()
        await assertResponse(
            processor,
            signed(body: try AgentBridgeTestSupport.batchBody(events: events)),
            equals: .accepted
        )
        XCTAssertEqual(store.sessions.count, 3)
        XCTAssertEqual(Set(store.sessions.map(\.id.sessionID.provider)), [.codex, .claude])
    }

    func testGenericBridgeRejectsApprovalControlCapabilityClaim() async throws {
        let started = AgentBridgeTestSupport.event(id: "start")
        let capability = AgentBridgeTestSupport.event(
            id: "caps",
            type: "capabilitiesUpdated",
            payload: ["capabilities": [[
                "name": "approvalControl",
                "authority": "lifecycle",
                "source": "wire",
                "observedAt": "2033-05-18T03:33:20Z"
            ]]]
        )
        let (processor, store) = makeProcessor()
        let body = try AgentBridgeTestSupport.batchBody(events: [started, capability])
        await assertResponse(processor, signed(body: body), equals: .unprocessableContent)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    private func makeProcessor(
        producerID: String = "producer-1"
    ) -> (AgentBridgeRequestProcessor, AgentEventStore) {
        let store = AgentEventStore()
        let ingress = AgentBridgeIngress(store: store)
        ingress.activate(launchID: "test-launch")
        return (
            makeProcessor(store: store, ingress: ingress, producerID: producerID),
            store
        )
    }

    private func makeProcessor(
        store: AgentEventStore,
        ingress: AgentBridgeIngress,
        producerID: String
    ) -> AgentBridgeRequestProcessor {
        AgentBridgeRequestProcessor(
            authenticator: AgentBridgeAuthenticator(
                keyData: AgentBridgeTestSupport.launchKey,
                now: { AgentBridgeTestSupport.now }
            ),
            ingress: ingress,
            launchID: "test-launch",
            authenticatedProducerID: producerID,
            now: { AgentBridgeTestSupport.now }
        )
    }

    private func signed(
        body: Data,
        nonce: String = "nonce",
        method: String = "POST",
        route: String = "/v1/events"
    ) -> AgentBridgeHTTPRequest {
        AgentBridgeTestSupport.signedRequest(
            body: body,
            key: AgentBridgeTestSupport.launchKey,
            method: method,
            route: route,
            nonce: nonce
        )
    }

    private func assertResponse(
        _ processor: AgentBridgeRequestProcessor,
        _ request: AgentBridgeHTTPRequest,
        equals expected: AgentBridgeHTTPStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let response = await processor.handle(request)
        XCTAssertEqual(response.status, expected, file: file, line: line)
    }
}
