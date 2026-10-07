import AppKit
import Carbon
import Foundation

enum MessagesAutomationPermission: Equatable, Sendable {
    case granted
    case denied
    /// Not asked yet; macOS asks on the first explicit send.
    case notDetermined
    /// Messages is not running, so macOS cannot report the state.
    case unknown
}

enum MessagesAutomationError: Error, Equatable {
    case notAuthorized
    case conversationMissing
    case scriptFailed(code: Int, message: String)
}

/// Supported Apple Events to Messages.app. No Accessibility, no UI
/// scripting, no screen coordinates.
protocol MessagesAutomating: AnyObject, Sendable {
    func permission(askIfNeeded: Bool) -> MessagesAutomationPermission
    func chatExists(_ chatGUID: String) async throws -> Bool
    /// Returns when Messages accepted the `send` command without error.
    func send(_ text: String, toChat chatGUID: String) async throws
}

final class AppleScriptMessagesAutomation: MessagesAutomating, @unchecked Sendable {
    static let bundleIdentifier = "com.apple.MobileSMS"

    /// Handlers take their values as parameters; message text is never
    /// interpolated into script source.
    private static let source = """
        on dynamicislandchatexists(chatIdentifier)
            tell application id "com.apple.MobileSMS"
                return (exists chat id chatIdentifier)
            end tell
        end dynamicislandchatexists

        on dynamicislandsend(chatIdentifier, messageText)
            tell application id "com.apple.MobileSMS"
                send messageText to chat id chatIdentifier
            end tell
            return true
        end dynamicislandsend
        """

    private let queue = DispatchQueue(label: "DynamicIsland.MessagesAutomation")
    private var compiled: NSAppleScript?

    func permission(askIfNeeded: Bool) -> MessagesAutomationPermission {
        let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleIdentifier)
        guard let targetDescriptor = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(
            targetDescriptor,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askIfNeeded
        )
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .unknown
        default: return .unknown
        }
    }

    func chatExists(_ chatGUID: String) async throws -> Bool {
        let result = try await call("dynamicislandchatexists", [chatGUID])
        return result.booleanValue
    }

    func send(_ text: String, toChat chatGUID: String) async throws {
        _ = try await call("dynamicislandsend", [chatGUID, text])
    }

    private func call(_ handler: String, _ arguments: [String]) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSAppleEventDescriptor, Error>) in
            queue.async { [self] in
                do {
                    continuation.resume(returning: try callSync(handler, arguments))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func callSync(_ handler: String, _ arguments: [String]) throws -> NSAppleEventDescriptor {
        if compiled == nil {
            let script = NSAppleScript(source: Self.source)
            var compileError: NSDictionary?
            guard script?.compileAndReturnError(&compileError) == true else {
                throw MessagesAutomationError.scriptFailed(code: -1, message: "Could not prepare Messages automation")
            }
            compiled = script
        }
        let parameters = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            parameters.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
        }
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: NSAppleEventDescriptor.currentProcess(),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(string: handler), forKeyword: AEKeyword(keyASSubroutineName))
        event.setParam(parameters, forKeyword: keyDirectObject)
        var error: NSDictionary?
        guard let result = compiled?.executeAppleEvent(event, error: &error) else {
            let code = (error?[NSAppleScript.errorNumber] as? Int) ?? -1
            switch code {
            case -1743: throw MessagesAutomationError.notAuthorized
            case -1728, -1719: throw MessagesAutomationError.conversationMissing
            default:
                throw MessagesAutomationError.scriptFailed(
                    code: code,
                    message: "Messages reported an error (\(code))"
                )
            }
        }
        return result
    }
}
