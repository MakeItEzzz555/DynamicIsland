@preconcurrency import Network
import Foundation

package enum AgentBridgeClientTransportError: Error, Equatable, Sendable {
    case unavailable
    case connectTimedOut
    case requestTimedOut
    case malformedResponse
    case responseTooLarge
}

package protocol AgentBridgeClientTransport: Sendable {
    func send(
        _ request: AgentBridgeClientRequest,
        profile: AgentBridgeClientProfile,
        connectTimeout: Duration,
        requestTimeout: Duration
    ) async throws -> AgentBridgeClientResponse
}

package enum AgentBridgeClientResult: Equatable, Sendable {
    case accepted
    case rejected(statusCode: Int, code: String)
}

package enum AgentBridgeClientError: Error, Equatable, Sendable {
    case discoveryUnavailable
    case invalidInput(AgentBridgeEnvelopeBuildError)
    case transportUnavailable
    case timedOut
    case authenticationFailed
    case malformedResponse
}

package struct AgentBridgeClient: Sendable {
    private let profiles: any AgentBridgeClientProfileProviding
    private let transport: any AgentBridgeClientTransport
    private let now: @Sendable () -> Date
    private let nonce: @Sendable () throws -> String

    package init(
        profiles: any AgentBridgeClientProfileProviding,
        transport: any AgentBridgeClientTransport = AgentBridgeNetworkTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
        nonce: @escaping @Sendable () throws -> String = {
            try AgentBridgeRequestAuthentication.randomNonce()
        }
    ) {
        self.profiles = profiles
        self.transport = transport
        self.now = now
        self.nonce = nonce
    }

    package func sendEvents(input: Data) async throws -> AgentBridgeClientResult {
        try await perform(method: "POST", explicitRoute: nil, input: input)
    }

    package func health() async throws -> AgentBridgeClientResult {
        try await perform(method: "GET", explicitRoute: AgentBridgeProtocol.healthRoute, input: nil)
    }

    /// Only the dedicated Codex PermissionRequest relay uses this synchronous
    /// route. A nil result means no hook decision, so Codex keeps its native
    /// approval prompt.
    package func requestCodexPermission(input: Data) async throws -> AgentBridgePermissionDecision? {
        let response = try await performResponse(
            method: "POST",
            explicitRoute: AgentBridgeProtocol.codexPermissionRoute,
            input: input,
            requestTimeout: .seconds(80)
        )
        guard response.statusCode == 200 else { return nil }
        return response.permissionDecision
    }

    private func perform(
        method: String,
        explicitRoute: String?,
        input: Data?
    ) async throws -> AgentBridgeClientResult {
        let response = try await performResponse(
            method: method,
            explicitRoute: explicitRoute,
            input: input,
            requestTimeout: .seconds(2)
        )
        if response.statusCode == 200 || response.statusCode == 202 { return .accepted }
        return .rejected(statusCode: response.statusCode, code: response.code)
    }

    private func performResponse(
        method: String,
        explicitRoute: String?,
        input: Data?,
        requestTimeout: Duration
    ) async throws -> AgentBridgeClientResponse {
        let initial = try await loadProfile()
        do {
            return try await attempt(
                method: method,
                route: explicitRoute ?? initial.eventsRoute,
                input: input,
                profile: initial,
                requestTimeout: requestTimeout
            )
        } catch let error as AttemptError where error.isEligibleForProfileReload {
            let refreshed = try await loadProfile()
            guard refreshed != initial else { throw error.clientError }
            do {
                return try await attempt(
                    method: method,
                    route: explicitRoute ?? refreshed.eventsRoute,
                    input: input,
                    profile: refreshed,
                    requestTimeout: requestTimeout
                )
            } catch let retryError as AttemptError {
                throw retryError.clientError
            }
        } catch let error as AttemptError {
            throw error.clientError
        }
    }

    private func loadProfile() async throws -> AgentBridgeClientProfile {
        do {
            let profile = try await profiles.loadProfile()
            guard profile.host == "127.0.0.1",
                  profile.port != 0,
                  profile.protocolVersion == AgentBridgeProtocol.version,
                  Self.validIdentifier(profile.launchID),
                  Self.validIdentifier(profile.producerID),
                  profile.authenticationKey.count == AgentBridgeProtocol.launchKeyBytes else {
                throw AgentBridgeDiscoveryReadError.malformed
            }
            return profile
        } catch {
            throw AgentBridgeClientError.discoveryUnavailable
        }
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= AgentBridgeProtocol.maximumIdentifierBytes &&
            value.unicodeScalars.allSatisfy {
                $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0))
            }
    }

    private func attempt(
        method: String,
        route: String,
        input: Data?,
        profile: AgentBridgeClientProfile,
        requestTimeout: Duration
    ) async throws -> AgentBridgeClientResponse {
        let body: Data
        do {
            body = if let input {
                try AgentBridgeEnvelopeBuilder.build(input: input, producerID: profile.producerID)
            } else {
                Data()
            }
        } catch let error as AgentBridgeEnvelopeBuildError {
            throw AgentBridgeClientError.invalidInput(error)
        }
        let timestamp = Int64(now().timeIntervalSince1970)
        let nonceValue: String
        do {
            nonceValue = try nonce()
        } catch {
            throw AgentBridgeClientError.transportUnavailable
        }
        let signature = AgentBridgeRequestAuthentication.signature(
            keyData: profile.authenticationKey,
            method: method,
            route: route,
            protocolVersion: profile.protocolVersion,
            timestamp: timestamp,
            nonce: nonceValue,
            body: body
        )
        var headers = [
            AgentBridgeProtocol.protocolHeader: String(profile.protocolVersion),
            AgentBridgeProtocol.timestampHeader: String(timestamp),
            AgentBridgeProtocol.nonceHeader: nonceValue,
            AgentBridgeProtocol.signatureHeader: signature
        ]
        if method == "POST" { headers["content-type"] = "application/json" }
        let request = AgentBridgeClientRequest(
            method: method,
            route: route,
            headers: headers,
            body: body
        )
        let response: AgentBridgeClientResponse
        do {
            response = try await transport.send(
                request,
                profile: profile,
                connectTimeout: .seconds(1),
                requestTimeout: requestTimeout
            )
        } catch let error as AgentBridgeClientTransportError {
            switch error {
            case .unavailable: throw AttemptError.unavailable
            case .connectTimedOut: throw AttemptError.connectTimedOut
            case .requestTimedOut: throw AttemptError.requestTimedOut
            case .malformedResponse, .responseTooLarge: throw AttemptError.malformedResponse
            }
        } catch {
            throw AttemptError.unavailable
        }
        if response.statusCode == 401 { throw AttemptError.authentication }
        return response
    }

    private enum AttemptError: Error, Equatable {
        case unavailable
        case connectTimedOut
        case requestTimedOut
        case authentication
        case malformedResponse

        var isEligibleForProfileReload: Bool {
            self == .unavailable || self == .connectTimedOut || self == .authentication
        }

        var clientError: AgentBridgeClientError {
            switch self {
            case .unavailable: .transportUnavailable
            case .connectTimedOut, .requestTimedOut: .timedOut
            case .authentication: .authenticationFailed
            case .malformedResponse: .malformedResponse
            }
        }
    }
}

package struct AgentBridgeNetworkTransport: AgentBridgeClientTransport {
    package init() {}

    package func send(
        _ request: AgentBridgeClientRequest,
        profile: AgentBridgeClientProfile,
        connectTimeout: Duration,
        requestTimeout: Duration
    ) async throws -> AgentBridgeClientResponse {
        guard profile.host == "127.0.0.1", profile.port != 0 else {
            throw AgentBridgeClientTransportError.unavailable
        }
        let bytes = Self.requestData(request, port: profile.port)
        return try await withCheckedThrowingContinuation { continuation in
            let exchange = AgentBridgeNetworkExchange(
                port: profile.port,
                request: bytes,
                connectTimeout: connectTimeout,
                requestTimeout: requestTimeout
            ) { result in
                continuation.resume(with: result)
            }
            exchange.start()
        }
    }

    private static func requestData(_ request: AgentBridgeClientRequest, port: UInt16) -> Data {
        var lines = [
            "\(request.method) \(request.route) HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Content-Length: \(request.body.count)",
            "Connection: close"
        ]
        for (name, value) in request.headers.sorted(by: { $0.key < $1.key }) {
            lines.append("\(name): \(value)")
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + request.body
    }
}

/// Network.framework's callback objects predate Swift's Sendable annotations.
/// All state is confined to `queue`, so the unchecked conformance does not make
/// mutable state cross execution domains.
private final class AgentBridgeNetworkExchange: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.local.dynamicisland.agent-relay.client")
    private let connection: NWConnection
    private let request: Data
    private let connectTimeout: Duration
    private let requestTimeout: Duration
    private let completion: @Sendable (Result<AgentBridgeClientResponse, Error>) -> Void
    private var buffer = Data()
    private var finished = false
    private var sent = false
    private var timeoutGeneration: UInt64 = 0

    init(
        port: UInt16,
        request: Data,
        connectTimeout: Duration,
        requestTimeout: Duration,
        completion: @escaping @Sendable (Result<AgentBridgeClientResponse, Error>) -> Void
    ) {
        connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        self.request = request
        self.connectTimeout = connectTimeout
        self.requestTimeout = requestTimeout
        self.completion = completion
    }

    func start() {
        queue.async { [self] in
            // The connection owns this closure until `finish` clears it, keeping
            // the exchange alive for the complete request without global state.
            connection.stateUpdateHandler = { [self] state in handle(state) }
            connection.start(queue: queue)
            scheduleTimeout(connectTimeout, error: .connectTimedOut)
        }
    }

    private func handle(_ state: NWConnection.State) {
        guard !finished else { return }
        switch state {
        case .ready:
            guard !sent else { return }
            sent = true
            scheduleTimeout(requestTimeout, error: .requestTimedOut)
            connection.send(content: request, completion: .contentProcessed { [self] error in
                self.queue.async {
                    if error != nil { self.finish(.failure(AgentBridgeClientTransportError.unavailable)) }
                    else { self.receive() }
                }
            })
        case .failed, .cancelled:
            finish(.failure(AgentBridgeClientTransportError.unavailable))
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [self] data, _, complete, error in
            self.queue.async {
                guard !self.finished else { return }
                if let data {
                    guard self.buffer.count <= AgentBridgeProtocol.maximumResponseBytes - data.count else {
                        self.finish(.failure(AgentBridgeClientTransportError.responseTooLarge))
                        return
                    }
                    self.buffer.append(data)
                    if let response = try? Self.parseResponse(self.buffer, requireComplete: false) {
                        self.finish(.success(response))
                        return
                    }
                }
                if error != nil {
                    self.finish(.failure(AgentBridgeClientTransportError.unavailable))
                } else if complete {
                    do { self.finish(.success(try Self.parseResponse(self.buffer, requireComplete: true))) }
                    catch { self.finish(.failure(error)) }
                } else {
                    self.receive()
                }
            }
        }
    }

    private func scheduleTimeout(_ duration: Duration, error: AgentBridgeClientTransportError) {
        timeoutGeneration &+= 1
        let generation = timeoutGeneration
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.timeoutGeneration == generation else { return }
            self.finish(.failure(error))
        }
    }

    private func finish(_ result: Result<AgentBridgeClientResponse, Error>) {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        completion(result)
    }

    private static func parseResponse(_ data: Data, requireComplete: Bool) throws -> AgentBridgeClientResponse {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw AgentBridgeClientTransportError.malformedResponse
        }
        guard let header = String(data: data[..<headerRange.upperBound], encoding: .utf8),
              header.unicodeScalars.allSatisfy(\.isASCII) else {
            throw AgentBridgeClientTransportError.malformedResponse
        }
        let lines = header.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw AgentBridgeClientTransportError.malformedResponse }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, statusParts[0] == "HTTP/1.1",
              let status = Int(statusParts[1]), (100...599).contains(status) else {
            throw AgentBridgeClientTransportError.malformedResponse
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                throw AgentBridgeClientTransportError.malformedResponse
            }
            let name = line[..<colon].lowercased()
            guard headers[name] == nil else { throw AgentBridgeClientTransportError.malformedResponse }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil,
              let lengthText = headers["content-length"],
              let length = Int(lengthText), length >= 0,
              length <= AgentBridgeProtocol.maximumResponseBytes else {
            throw AgentBridgeClientTransportError.malformedResponse
        }
        let body = data[headerRange.upperBound...]
        if body.count < length {
            if requireComplete { throw AgentBridgeClientTransportError.malformedResponse }
            throw AgentBridgeClientTransportError.malformedResponse
        }
        guard body.count == length,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let code = object["code"] as? String else {
            throw AgentBridgeClientTransportError.malformedResponse
        }
        let decision = (object["decision"] as? String).flatMap(AgentBridgePermissionDecision.init(rawValue:))
        return AgentBridgeClientResponse(statusCode: status, code: code, permissionDecision: decision)
    }
}
