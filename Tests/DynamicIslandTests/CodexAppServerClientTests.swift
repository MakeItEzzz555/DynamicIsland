import Foundation
import XCTest
@testable import DynamicIsland

final class CodexAppServerClientTests: XCTestCase {
    func testStartResumeTurnAndInterruptRoundTrip() async throws {
        let executable = try makeFakeServer(script: #"""
        #!/usr/bin/env python3
        import json, sys
        for line in sys.stdin:
            message = json.loads(line)
            method = message.get("method")
            request_id = message.get("id")
            if method == "initialize":
                print(json.dumps({"id": request_id, "result": {
                    "userAgent": "fake", "codexHome": "/tmp",
                    "platformFamily": "unix", "platformOs": "macos"
                }}), flush=True)
            elif method == "initialized":
                pass
            elif method in ("thread/start", "thread/resume"):
                print(json.dumps({"id": request_id, "result": {
                    "thread": {
                        "id": "thread-1", "cwd": "/tmp/project",
                        "model": "gpt-test", "canAcceptDirectInput": True
                    },
                    "cwd": "/tmp/project", "model": "gpt-test"
                }}), flush=True)
            elif method == "turn/start":
                print(json.dumps({"id": request_id, "result": {
                    "turn": {"id": "turn-1", "status": "inProgress"}
                }}), flush=True)
                print(json.dumps({"method": "turn/started", "params": {
                    "threadId": "thread-1",
                    "turn": {"id": "turn-1", "status": "inProgress"}
                }}), flush=True)
            elif method == "turn/interrupt":
                print(json.dumps({"id": request_id, "result": {}}), flush=True)
        """#)

        let client = try CodexAppServerClient(
            executableURL: executable,
            requestTimeout: .seconds(2)
        )
        let events = await client.events()
        let eventTask = Task<CodexAppServerEvent?, Never> {
            for await event in events {
                if case .notification(let method, _) = event, method == "turn/started" {
                    return event
                }
            }
            return nil
        }

        let started = try await client.startThread(cwd: "/tmp/project")
        XCTAssertEqual(started.id, "thread-1")
        XCTAssertTrue(started.canAcceptDirectInput)

        let resumed = try await client.resumeThread(threadID: "thread-1")
        XCTAssertEqual(resumed.id, started.id)

        let turn = try await client.startTurn(threadID: "thread-1", prompt: "hello")
        XCTAssertEqual(turn.id, "turn-1")
        let startedEvent = await eventTask.value
        XCTAssertNotNil(startedEvent)

        try await client.interrupt(threadID: "thread-1", turnID: "turn-1")
        await client.stop()
    }

    func testModelListAndTurnModelOverrideUseProviderAuthoritativeSchema() async throws {
        let executable = try makeFakeServer(script: #"""
        #!/usr/bin/env python3
        import json, sys
        for line in sys.stdin:
            message = json.loads(line)
            method = message.get("method")
            request_id = message.get("id")
            if method == "initialize":
                print(json.dumps({"id": request_id, "result": {}}), flush=True)
            elif method == "model/list":
                print(json.dumps({"id": request_id, "result": {
                    "data": [
                        {"id":"model-a","model":"model-a","displayName":"Model A","description":"A","hidden":False,"isDefault":True},
                        {"id":"hidden","model":"hidden","displayName":"Hidden","description":"H","hidden":True,"isDefault":False}
                    ],
                    "nextCursor": None
                }}), flush=True)
            elif method == "turn/start":
                model = message.get("params", {}).get("model")
                if model != "model-a":
                    print(json.dumps({"id": request_id, "error": {"code": -1, "message": "missing model override"}}), flush=True)
                else:
                    print(json.dumps({"id": request_id, "result": {
                        "turn": {"id":"turn-model","status":"inProgress"}
                    }}), flush=True)
        """#)

        let client = try CodexAppServerClient(
            executableURL: executable,
            requestTimeout: .seconds(2)
        )
        let provider = CodexAppServerProvider(client: client)

        XCTAssertEqual(provider.modelSelectionScope, .turnAndSubsequent)
        XCTAssertEqual(provider.interactiveCapabilities, [
            .startSession, .resumeSession, .submitPrompt, .interrupt, .selectModel,
            .resolveApprovals, .accountUsage, .contextUsage, .streamToolActivity,
            .loadHistory
        ])

        let models = try await provider.listModels()
        XCTAssertEqual(models.map(\.model), ["model-a"])
        XCTAssertEqual(models.first?.displayName, "Model A")
        XCTAssertEqual(models.first?.isDefault, true)

        let turn = try await provider.submit(
            prompt: "hello",
            nativeSessionID: "thread-1",
            model: "model-a"
        )
        XCTAssertEqual(turn.turnID, "turn-model")
        await provider.stop()
    }

    func testProviderTranscriptReturnsOnlySafeDisplayableHistory() async throws {
        let executable = try makeFakeServer(script: #"""
        #!/usr/bin/env python3
        import json, sys
        for line in sys.stdin:
            message = json.loads(line)
            method = message.get("method")
            request_id = message.get("id")
            if method == "initialize":
                print(json.dumps({"id": request_id, "result": {}}), flush=True)
            elif method == "thread/items/list":
                print(json.dumps({"id": request_id, "result": {
                    "data": [
                        {"turnId":"t1","item":{"type":"agentMessage","id":"a1","text":"Visible answer"},"startedAtMs":2000,"completedAtMs":2100},
                        {"turnId":"t1","item":{"type":"reasoning","id":"r1","summary":["hidden"],"content":["private"]},"startedAtMs":1500,"completedAtMs":1600},
                        {"turnId":"t1","item":{"type":"userMessage","id":"u1","clientId":None,"content":[{"type":"text","text":"User prompt","text_elements":[]}]},"startedAtMs":1000,"completedAtMs":1100},
                        {"turnId":"t1","item":{"type":"commandExecution","id":"c1","command":"echo SECRET","aggregatedOutput":"SECRET"},"startedAtMs":1700,"completedAtMs":1800}
                    ],
                    "nextCursor": None,
                    "backwardsCursor": None
                }}), flush=True)
        """#)
        let client = try CodexAppServerClient(
            executableURL: executable,
            requestTimeout: .seconds(2)
        )
        let provider = CodexAppServerProvider(client: client)

        let transcript = try await provider.readTranscript(
            nativeSessionID: "thread-1",
            limit: 20
        )

        XCTAssertEqual(transcript.map(\.role), [.user, .command, .agent])
        XCTAssertEqual(transcript.map(\.text), ["User prompt", "echo", "Visible answer"])
        XCTAssertFalse(transcript.contains { $0.text.contains("SECRET") || $0.text.contains("private") })
        await provider.stop()
    }

    func testServerExitFailsPendingRequest() async throws {
        let executable = try makeFakeServer(script: #"""
        #!/usr/bin/env python3
        import json, sys
        for line in sys.stdin:
            message = json.loads(line)
            method = message.get("method")
            request_id = message.get("id")
            if method == "initialize":
                print(json.dumps({"id": request_id, "result": {
                    "userAgent": "fake", "codexHome": "/tmp",
                    "platformFamily": "unix", "platformOs": "macos"
                }}), flush=True)
            elif method == "turn/start":
                sys.exit(0)
        """#)

        let client = try CodexAppServerClient(
            executableURL: executable,
            requestTimeout: .seconds(2)
        )
        try await client.start()

        do {
            _ = try await client.startTurn(threadID: "thread-1", prompt: "hello")
            XCTFail("Expected transport closure")
        } catch let error as CodexAppServerError {
            if case .transportClosed = error {
                // expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
        await client.stop()
    }

    func testConcurrentFirstRequestsShareOneInitializedTransport() async throws {
        let executable = try makeFakeServer(script: #"""
        #!/usr/bin/env python3
        import json, sys
        initialized = False
        for line in sys.stdin:
            message = json.loads(line)
            method = message.get("method")
            request_id = message.get("id")
            if method == "initialize":
                if initialized:
                    sys.exit(9)
                initialized = True
                print(json.dumps({"id": request_id, "result": {}}), flush=True)
            elif method == "thread/list":
                print(json.dumps({"id": request_id, "result": {"data": []}}), flush=True)
            elif method == "account/rateLimits/read":
                print(json.dumps({"id": request_id, "result": {"rateLimits": {}}}), flush=True)
        """#)
        let client = try CodexAppServerClient(
            executableURL: executable,
            requestTimeout: .seconds(2)
        )

        async let threads = client.listThreads()
        async let usage = client.readAccountRateLimits()
        let (listed, rateLimits) = try await (threads, usage)

        XCTAssertTrue(listed.isEmpty)
        XCTAssertNotNil(rateLimits["rateLimits"])
        await client.stop()
    }

    func testProviderDiscoversIdleThreadAndReadsAccountRateLimitsWithoutActiveTurn() async throws {
        let executable = try makeFakeServer(script: #"""
        #!/usr/bin/env python3
        import json, sys
        for line in sys.stdin:
            message = json.loads(line)
            method = message.get("method")
            request_id = message.get("id")
            if method == "initialize":
                print(json.dumps({"id": request_id, "result": {
                    "userAgent": "fake", "codexHome": "/tmp",
                    "platformFamily": "unix", "platformOs": "macos"
                }}), flush=True)
            elif method == "initialized":
                pass
            elif method == "thread/list":
                print(json.dumps({"id": request_id, "result": {
                    "data": [{
                        "id": "idle-thread",
                        "cwd": "/tmp/project",
                        "model": "gpt-test",
                        "status": {"type": "idle"},
                        "updatedAt": 2100000000,
                        "path": None,
                        "canAcceptDirectInput": False
                    }],
                    "nextCursor": None,
                    "backwardsCursor": None
                }}), flush=True)
            elif method == "account/rateLimits/read":
                print(json.dumps({"id": request_id, "result": {
                    "rateLimits": {
                        "primary": {
                            "usedPercent": 100,
                            "windowDurationMins": 300,
                            "resetsAt": 2100003600
                        },
                        "secondary": {
                            "usedPercent": 16,
                            "windowDurationMins": 10080,
                            "resetsAt": 2100604800
                        }
                    }
                }}), flush=True)
        """#)

        let client = try CodexAppServerClient(
            executableURL: executable,
            requestTimeout: .seconds(2)
        )
        let provider = CodexAppServerProvider(client: client)

        let sessions = try await provider.discoverSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.session.nativeSessionID, "idle-thread")
        XCTAssertEqual(sessions.first?.runtimeState, .idle)

        let usage = try await provider.readAccountUsage()
        let fiveHour = try XCTUnwrap(usage.samples(for: .quotaUsed).first { $0.scope == "5h" })
        let weekly = try XCTUnwrap(usage.samples(for: .quotaUsed).first { $0.scope == "weekly" })
        XCTAssertEqual(fiveHour.value, 100)
        XCTAssertEqual(fiveHour.limit, 100)
        XCTAssertEqual(weekly.value, 16)
        XCTAssertEqual(weekly.limit, 100)

        await provider.stop()
    }

    func testProviderDiscoversNotLoadedThreadAsResumable() async throws {
        let executable = try makeFakeServer(script: #"""
        #!/usr/bin/env python3
        import json, sys
        for line in sys.stdin:
            message = json.loads(line)
            method = message.get("method")
            request_id = message.get("id")
            if method == "initialize":
                print(json.dumps({"id": request_id, "result": {}}), flush=True)
            elif method == "thread/list":
                print(json.dumps({"id": request_id, "result": {"data": [{
                    "id": "persisted-thread", "cwd": "/tmp/project",
                    "status": {"type": "notLoaded"}, "updatedAt": 2100000000,
                    "canAcceptDirectInput": False
                }]}}), flush=True)
        """#)
        let client = try CodexAppServerClient(
            executableURL: executable,
            requestTimeout: .seconds(2)
        )
        let provider = CodexAppServerProvider(client: client)

        let sessions = try await provider.discoverSessions()

        XCTAssertEqual(sessions.map(\.session.nativeSessionID), ["persisted-thread"])
        XCTAssertEqual(sessions.first?.runtimeState, .notLoaded)
        XCTAssertFalse(sessions.first?.session.acceptsDirectInput ?? true)
        await provider.stop()
    }

    func testDiscoveryIsBoundedDeduplicatedAndPrioritizesRuntimeState() {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        var threads = (0..<24).map { index in
            CodexListedThread(
                id: "recent-\(index)", cwd: nil, model: nil, status: .notLoaded,
                updatedAt: now.addingTimeInterval(Double(index)),
                rolloutPath: nil, canAcceptDirectInput: false
            )
        }
        threads.append(CodexListedThread(
            id: "active", cwd: nil, model: nil, status: .active,
            updatedAt: now.addingTimeInterval(-10_000), rolloutPath: nil,
            canAcceptDirectInput: true
        ))
        threads.append(threads[0])

        let result = CodexAppServerProvider.boundedDiscovery(threads)

        XCTAssertEqual(result.count, CodexAppServerProvider.maximumDiscoveredSessions)
        XCTAssertEqual(result.first?.id, "active")
        XCTAssertEqual(Set(result.map(\.id)).count, result.count)
    }

    func testContextUsesLatestTurnTokensInsteadOfCumulativeThreadTotal() throws {
        let usage = try XCTUnwrap(CodexAppServerProvider.mapUsage(.object([
            "total": .object([
                "inputTokens": .integer(59_000_000),
                "outputTokens": .integer(842_683),
                "totalTokens": .integer(59_842_683)
            ]),
            "last": .object(["totalTokens": .integer(111_574)]),
            "modelContextWindow": .integer(258_400)
        ])))
        let context = try XCTUnwrap(usage.samples(for: .contextUsed).first)

        XCTAssertEqual(context.value, 99_574)
        XCTAssertEqual(context.limit, 246_400)
        XCTAssertLessThan(context.value, context.limit ?? 0)
    }

    func testContextWithoutModelWindowIsTruthfullyUnbounded() throws {
        let usage = try XCTUnwrap(CodexAppServerProvider.contextUsage(
            currentTokens: 42_000,
            modelContextWindow: nil,
            source: "test",
            observedAt: Date()
        ))
        let context = try XCTUnwrap(usage.samples(for: .contextUsed).first)
        XCTAssertEqual(context.value, 42_000)
        XCTAssertNil(context.limit)
    }

    func testContextValueCannotExceedEffectiveWindow() throws {
        let usage = try XCTUnwrap(CodexAppServerProvider.contextUsage(
            currentTokens: 59_842_683,
            modelContextWindow: 258_400,
            source: "test",
            observedAt: Date()
        ))
        let context = try XCTUnwrap(usage.samples(for: .contextUsed).first)
        XCTAssertEqual(context.value, 246_400)
        XCTAssertEqual(context.limit, 246_400)
    }

    func testJSONValueRejectsMalformedJSON() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                CodexJSONValue.self,
                from: Data(#"{"broken":"#.utf8)
            )
        )
    }

    private func makeFakeServer(script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland-CodexAppServerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fake-codex")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return url
    }
}
