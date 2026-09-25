import CoreFoundation
import Foundation

package enum AgentBridgeEnvelopeBuildError: Error, Equatable, Sendable {
    case emptyInput
    case inputTooLarge
    case malformedJSON
    case malformedEnvelope
    case emptyBatch
    case tooManyEvents
    case eventTooLarge
    case outputTooLarge
}

package enum AgentBridgeEnvelopeBuilder {
    /// Rebuilds transport-owned fields from the validated client profile. Any
    /// caller-supplied protocolVersion or producerID is deliberately ignored.
    package static func build(input: Data, producerID: String) throws -> Data {
        guard !input.isEmpty else { throw AgentBridgeEnvelopeBuildError.emptyInput }
        guard input.count <= AgentBridgeProtocol.maximumRequestBodyBytes else {
            throw AgentBridgeEnvelopeBuildError.inputTooLarge
        }
        guard String(data: input, encoding: .utf8) != nil else {
            throw AgentBridgeEnvelopeBuildError.malformedJSON
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: input)
        } catch {
            throw AgentBridgeEnvelopeBuildError.malformedJSON
        }
        guard let root = object as? [String: Any] else {
            throw AgentBridgeEnvelopeBuildError.malformedEnvelope
        }

        var output: [String: Any] = [
            "protocolVersion": AgentBridgeProtocol.version,
            "producerID": producerID
        ]
        if let event = root["event"], root["events"] == nil {
            try validateEvent(event)
            output["event"] = event
        } else if let events = root["events"] as? [Any], root["event"] == nil {
            guard !events.isEmpty else { throw AgentBridgeEnvelopeBuildError.emptyBatch }
            guard events.count <= AgentBridgeProtocol.maximumBatchEvents else {
                throw AgentBridgeEnvelopeBuildError.tooManyEvents
            }
            for event in events { try validateEvent(event) }
            output["events"] = events
        } else {
            throw AgentBridgeEnvelopeBuildError.malformedEnvelope
        }

        let encoded: Data
        do {
            encoded = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        } catch {
            throw AgentBridgeEnvelopeBuildError.malformedJSON
        }
        let maximum = output["event"] == nil
            ? AgentBridgeProtocol.maximumRequestBodyBytes
            : AgentBridgeProtocol.maximumSingleEventBodyBytes
        guard encoded.count <= maximum else { throw AgentBridgeEnvelopeBuildError.outputTooLarge }
        return encoded
    }

    private static func validateEvent(_ event: Any) throws {
        guard event is [String: Any] else { throw AgentBridgeEnvelopeBuildError.malformedEnvelope }
        let encoded: Data
        do {
            encoded = try JSONSerialization.data(withJSONObject: event)
        } catch {
            throw AgentBridgeEnvelopeBuildError.malformedJSON
        }
        guard encoded.count <= AgentBridgeProtocol.maximumSingleEventBodyBytes else {
            throw AgentBridgeEnvelopeBuildError.eventTooLarge
        }
    }
}
