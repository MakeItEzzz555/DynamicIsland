@preconcurrency import Network
import Foundation

struct AgentBridgeHTTPRequest: Equatable, Sendable {
    let method: String
    let route: String
    let headers: [String: String]
    let body: Data
}

enum AgentBridgeHTTPParseResult: Equatable, Sendable {
    case needMore
    case request(AgentBridgeHTTPRequest)
    case failure(AgentBridgeHTTPStatus, String)
}

struct AgentBridgeHTTPRequestParser: Sendable {
    private var buffer = Data()
    private var headerEnd: Int?
    private var expectedBodyLength: Int?
    private var parsedMethod: String?
    private var parsedRoute: String?
    private var parsedHeaders: [String: String]?
    private(set) var isFinished = false

    mutating func append(_ data: Data) -> AgentBridgeHTTPParseResult {
        guard !isFinished else { return .failure(.badRequest, "request-already-complete") }
        guard buffer.count <= AgentBridgeLimits.maximumHeaderBytes + AgentBridgeLimits.maximumRequestBodyBytes - data.count else {
            isFinished = true
            return .failure(.payloadTooLarge, "request-too-large")
        }
        buffer.append(data)

        if headerEnd == nil {
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let end = range.upperBound
                guard end <= AgentBridgeLimits.maximumHeaderBytes else {
                    isFinished = true
                    return .failure(.payloadTooLarge, "headers-too-large")
                }
                switch parseHeaders(Data(buffer[..<end])) {
                case .success(let parsed):
                    parsedMethod = parsed.method
                    parsedRoute = parsed.route
                    parsedHeaders = parsed.headers
                    expectedBodyLength = parsed.contentLength
                    headerEnd = end
                case .failure(let failure):
                    isFinished = true
                    return failure.result
                }
            } else if buffer.count > AgentBridgeLimits.maximumHeaderBytes {
                isFinished = true
                return .failure(.payloadTooLarge, "headers-too-large")
            } else {
                return .needMore
            }
        }

        guard let headerEnd, let expectedBodyLength,
              let method = parsedMethod, let route = parsedRoute,
              let headers = parsedHeaders else {
            isFinished = true
            return .failure(.badRequest, "invalid-parser-state")
        }
        let actualBodyLength = buffer.count - headerEnd
        if actualBodyLength < expectedBodyLength { return .needMore }
        guard actualBodyLength == expectedBodyLength else {
            isFinished = true
            return .failure(.badRequest, "extra-bytes")
        }
        isFinished = true
        return .request(AgentBridgeHTTPRequest(
            method: method,
            route: route,
            headers: headers,
            body: Data(buffer[headerEnd...])
        ))
    }

    mutating func finish() -> AgentBridgeHTTPParseResult {
        guard !isFinished else { return .needMore }
        isFinished = true
        return .failure(.badRequest, "truncated-request")
    }

    private func parseHeaders(_ data: Data) -> Result<ParsedHeaders, ParseFailure> {
        guard let text = String(data: data, encoding: .utf8),
              text.unicodeScalars.allSatisfy(\.isASCII) else {
            return .failure(ParseFailure(status: .badRequest, code: "invalid-headers"))
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .failure(ParseFailure(status: .badRequest, code: "missing-request-line"))
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard requestParts.count == 3,
              requestParts[2] == "HTTP/1.1",
              !requestParts[0].isEmpty,
              requestParts[1].first == "/",
              !requestParts[1].contains("#") else {
            return .failure(ParseFailure(status: .badRequest, code: "invalid-request-line"))
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard line.first != " ", line.first != "\t",
                  let colon = line.firstIndex(of: ":") else {
                return .failure(ParseFailure(status: .badRequest, code: "invalid-header"))
            }
            let name = String(line[..<colon]).lowercased()
            let value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard Self.validHeaderName(name),
                  value.utf8.count <= AgentBridgeLimits.maximumHeaderValueBytes,
                  headers[name] == nil else {
                return .failure(ParseFailure(status: .badRequest, code: "ambiguous-header"))
            }
            headers[name] = value
        }

        guard headers["transfer-encoding"] == nil else {
            return .failure(ParseFailure(status: .badRequest, code: "transfer-encoding-unsupported"))
        }
        let method = String(requestParts[0])
        let route = String(requestParts[1])
        let requiresBody = method == "POST"
        let contentLength: Int
        if let value = headers["content-length"] {
            guard !value.isEmpty,
                  value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let parsed = UInt64(value),
                  parsed <= UInt64(AgentBridgeLimits.maximumRequestBodyBytes) else {
                return .failure(ParseFailure(status: .payloadTooLarge, code: "invalid-content-length"))
            }
            contentLength = Int(parsed)
        } else if requiresBody {
            return .failure(ParseFailure(status: .badRequest, code: "content-length-required"))
        } else {
            contentLength = 0
        }
        return .success(ParsedHeaders(
            method: method,
            route: route,
            headers: headers,
            contentLength: contentLength
        ))
    }

    private static func validHeaderName(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "-".unicodeScalars.contains(scalar))
        }
    }

    private struct ParsedHeaders {
        let method: String
        let route: String
        let headers: [String: String]
        let contentLength: Int
    }

    private struct ParseFailure: Error {
        let status: AgentBridgeHTTPStatus
        let code: String
        var result: AgentBridgeHTTPParseResult { .failure(status, code) }
    }
}

enum AgentBridgeNetworkError: Error, Equatable {
    case listenerFailed(String)
    case listenerCancelled
    case missingPort
}

protocol AgentBridgeServing: Sendable {
    func start(completion: @escaping @Sendable (Result<UInt16, AgentBridgeNetworkError>) -> Void)
    func stop()
}

/// All mutable network state is confined to `queue`; the unchecked conformance is
/// required only because Network.framework's callback types predate Swift Sendable.
final class AgentBridgeNetworkServer: AgentBridgeServing, @unchecked Sendable {
    typealias RequestHandler = @Sendable (AgentBridgeHTTPRequest) async -> AgentBridgeHTTPResponse

    private let queue = DispatchQueue(label: "com.local.dynamicisland.agent-bridge.network")
    private let requestHandler: RequestHandler
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: AgentBridgeNetworkConnection] = [:]
    private var didCompleteStart = false
    private var startCompletion: (@Sendable (Result<UInt16, AgentBridgeNetworkError>) -> Void)?

    init(requestHandler: @escaping RequestHandler) {
        self.requestHandler = requestHandler
    }

    func start(completion: @escaping @Sendable (Result<UInt16, AgentBridgeNetworkError>) -> Void) {
        queue.async { [self] in
            guard listener == nil else {
                if let port = listener?.port?.rawValue { completion(.success(port)) }
                return
            }
            do {
                let parameters = NWParameters.tcp
                // This is the enforcement point for loopback-only exposure.
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                didCompleteStart = false
                startCompletion = completion
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard !self.didCompleteStart else { return }
                        self.didCompleteStart = true
                        guard let port = listener.port?.rawValue else {
                            self.completeStart(.failure(.missingPort))
                            return
                        }
                        self.completeStart(.success(port))
                    case .failed(let error):
                        if !self.didCompleteStart {
                            self.didCompleteStart = true
                            self.completeStart(.failure(.listenerFailed(String(describing: error))))
                        }
                    case .cancelled:
                        if !self.didCompleteStart {
                            self.didCompleteStart = true
                            self.completeStart(.failure(.listenerCancelled))
                        }
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.start(queue: queue)
            } catch {
                completion(.failure(.listenerFailed(String(describing: error))))
            }
        }
    }

    func stop() {
        queue.sync {
            if !didCompleteStart {
                didCompleteStart = true
                completeStart(.failure(.listenerCancelled))
            }
            listener?.stateUpdateHandler = nil
            listener?.newConnectionHandler = nil
            listener?.cancel()
            listener = nil
            for connection in connections.values { connection.cancel() }
            connections.removeAll(keepingCapacity: false)
            didCompleteStart = false
        }
    }

    private func completeStart(_ result: Result<UInt16, AgentBridgeNetworkError>) {
        let completion = startCompletion
        startCompletion = nil
        completion?(result)
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < AgentBridgeLimits.maximumConcurrentConnections else {
            let rejected = AgentBridgeNetworkConnection(
                connection: connection,
                queue: queue,
                requestHandler: requestHandler,
                onFinish: { _ in }
            )
            rejected.rejectOverloaded()
            return
        }
        var identifier: ObjectIdentifier!
        let handler = AgentBridgeNetworkConnection(
            connection: connection,
            queue: queue,
            requestHandler: requestHandler,
            onFinish: { [weak self] finished in
                self?.connections.removeValue(forKey: finished)
            }
        )
        identifier = ObjectIdentifier(handler)
        connections[identifier] = handler
        handler.start()
    }
}

/// A connection is retained and mutated only by the server's serial network queue.
private final class AgentBridgeNetworkConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let requestHandler: AgentBridgeNetworkServer.RequestHandler
    private let onFinish: @Sendable (ObjectIdentifier) -> Void
    private var parser = AgentBridgeHTTPRequestParser()
    private var finished = false

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        requestHandler: @escaping AgentBridgeNetworkServer.RequestHandler,
        onFinish: @escaping @Sendable (ObjectIdentifier) -> Void
    ) {
        self.connection = connection
        self.queue = queue
        self.requestHandler = requestHandler
        self.onFinish = onFinish
    }

    func start() {
        connection.start(queue: queue)
        receiveNext()
    }

    func rejectOverloaded() {
        connection.start(queue: queue)
        send(AgentBridgeHTTPResponse(status: .tooManyRequests, code: "connection-limit"))
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        connection.cancel()
        onFinish(ObjectIdentifier(self))
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1_024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard !self.finished else { return }
            if let data, !data.isEmpty {
                switch self.parser.append(data) {
                case .needMore:
                    break
                case .request(let request):
                    Task { [weak self] in
                        guard let self else { return }
                        let response = await self.requestHandler(request)
                        self.queue.async { self.send(response) }
                    }
                    return
                case .failure(let status, let code):
                    self.send(AgentBridgeHTTPResponse(status: status, code: code))
                    return
                }
            }
            if error != nil || isComplete {
                switch self.parser.finish() {
                case .failure(let status, let code):
                    self.send(AgentBridgeHTTPResponse(status: status, code: code))
                default:
                    self.cancel()
                }
                return
            }
            self.receiveNext()
        }
    }

    private func send(_ response: AgentBridgeHTTPResponse) {
        guard !finished else { return }
        finished = true
        connection.send(content: response.data, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.connection.cancel()
            self.onFinish(ObjectIdentifier(self))
        })
    }
}
