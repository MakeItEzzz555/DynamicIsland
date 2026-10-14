import Foundation

/// Evidence about presence, never a substitute for a provider's call or control authority.
struct MeetingPresence: Equatable, Sendable {
    enum State: String, Sendable { case notDetected, possibleMeeting, likelyMeeting, confirmedMeeting, unavailable }
    enum Source: String, Hashable, Sendable { case applicationPresence, coreAudioInput, verifiedProvider }
    let state: State
    let bundleIdentifier: String?
    let sources: Set<Source>
    let confidence: Double
    let observedAt: Date
    let audioInputActive: Bool?
    // No reliable meeting start or camera signal is available from CoreAudio.
    let startedAt: Date?
    let reason: String?
}

struct MeetingPresenceEvidence: Equatable, Sendable {
    let bundleIdentifier: String
    let applicationRunning: Bool
    let audioInputActive: Bool?
    let providerConfirmed: Bool
    let authoritativeStartedAt: Date?
    let observedAt: Date
}

/// Stable input IO in a meeting application suggests presence; it does not prove a live call.
struct MeetingPresenceReducer {
    static let staleInterval: TimeInterval = 8
    static let confirmationDwell: TimeInterval = 2
    private var candidate: String?
    private var candidateSince: Date?
    private var lastEvidence: MeetingPresenceEvidence?
    private(set) var presence = MeetingPresence(state: .notDetected, bundleIdentifier: nil, sources: [],
        confidence: 0, observedAt: .distantPast, audioInputActive: nil, startedAt: nil, reason: nil)

    mutating func consume(_ evidence: MeetingPresenceEvidence, now: Date) {
        guard evidence.observedAt <= now, now.timeIntervalSince(evidence.observedAt) <= Self.staleInterval,
              lastEvidence.map({ evidence.observedAt >= $0.observedAt }) ?? true else { expire(now: now); return }
        lastEvidence = evidence
        guard evidence.applicationRunning else { reset(now: now); return }
        if evidence.providerConfirmed {
            candidate = nil; candidateSince = nil
            presence = .init(state: .confirmedMeeting, bundleIdentifier: evidence.bundleIdentifier,
                sources: [.applicationPresence, .verifiedProvider], confidence: 1, observedAt: evidence.observedAt,
                audioInputActive: evidence.audioInputActive, startedAt: evidence.authoritativeStartedAt, reason: nil)
            return
        }
        guard evidence.audioInputActive == true else { reset(now: now); return }
        if candidate != evidence.bundleIdentifier {
            candidate = evidence.bundleIdentifier; candidateSince = evidence.observedAt
        }
        let sustained = evidence.observedAt.timeIntervalSince(candidateSince ?? evidence.observedAt) >= Self.confirmationDwell
        presence = .init(state: sustained ? .likelyMeeting : .possibleMeeting,
            bundleIdentifier: evidence.bundleIdentifier, sources: [.applicationPresence, .coreAudioInput],
            confidence: sustained ? 0.75 : 0.45, observedAt: evidence.observedAt,
            audioInputActive: true, startedAt: nil, reason: nil)
    }

    mutating func expire(now: Date) {
        if now.timeIntervalSince(lastEvidence?.observedAt ?? .distantPast) > Self.staleInterval { reset(now: now) }
    }

    mutating func unavailable(reason: String, now: Date) {
        candidate = nil; candidateSince = nil; lastEvidence = nil
        presence = .init(state: .unavailable, bundleIdentifier: nil, sources: [], confidence: 0,
            observedAt: now, audioInputActive: nil, startedAt: nil, reason: reason)
    }

    mutating func reset(now: Date) {
        candidate = nil; candidateSince = nil; lastEvidence = nil
        presence = .init(state: .notDetected, bundleIdentifier: nil, sources: [], confidence: 0,
            observedAt: now, audioInputActive: nil, startedAt: nil, reason: nil)
    }
}
