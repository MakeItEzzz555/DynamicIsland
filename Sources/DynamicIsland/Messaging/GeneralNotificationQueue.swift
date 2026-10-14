import Foundation

/// Identity and provenance stay separate from optional, transient presentation content.
struct GeneralNotificationEvent: Equatable, Sendable, Identifiable {
    enum Source: String, Sendable { case notificationCenterDatabase }
    let id: String
    let bundleIdentifier: String
    let source: Source
    let deliveredAt: Date?
    let observedAt: Date
    let title: String?
    let body: String?

    init(record: SystemNotificationRecord, includeContent: Bool) {
        id = record.stableID.map { "uuid:" + $0.base64EncodedString() }
            ?? "epoch:\(record.epoch):record:\(record.recordID)"
        bundleIdentifier = record.bundleIdentifier
        source = .notificationCenterDatabase
        deliveredAt = record.deliveredAt
        observedAt = record.observedAt
        title = includeContent ? record.title : nil
        body = includeContent ? record.body : nil
    }
}

/// Conservative presentation eligibility. Unknown Focus never means Focus is off.
struct GeneralNotificationPresentationGate: Equatable {
    var focusActive: Bool?
    var protectedInteraction = false
    var applicationActive = true
    var sourceAvailable = false
    var permitsPresentation: Bool {
        focusActive == false && !protectedInteraction && applicationActive && sourceAvailable
    }
}

struct GeneralNotificationQueue {
    static let capacity = 10
    static let lifetime: TimeInterval = 8
    private(set) var events: [GeneralNotificationEvent] = []
    private var recentIdentities: [String] = []

    mutating func receive(_ record: SystemNotificationRecord, enabled: Bool, allowedApplications: Set<String>,
                          includeContent: Bool, now: Date) {
        expire(now: now)
        let bundle = record.bundleIdentifier
        guard enabled, !bundle.isEmpty, bundle.count <= 255, !bundle.contains(where: { $0.isWhitespace }),
              allowedApplications.contains(bundle),
              !MessagesAppAdapter.notificationBundleIdentifiers.contains(bundle.lowercased()),
              bundle.lowercased() != "com.apple.facetime", record.observedAt <= now,
              now.timeIntervalSince(record.observedAt) < Self.lifetime,
              record.deliveredAt.map({ now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 30 }) ?? true else { return }
        let event = GeneralNotificationEvent(record: record, includeContent: includeContent)
        guard !recentIdentities.contains(event.id) else { return }
        recentIdentities.append(event.id)
        if recentIdentities.count > 512 { recentIdentities.removeFirst() }
        events.append(event)
        if events.count > Self.capacity { events.removeFirst(events.count - Self.capacity) }
    }

    mutating func expire(now: Date) {
        events.removeAll { now.timeIntervalSince($0.observedAt) >= Self.lifetime }
    }

    func current(gate: GeneralNotificationPresentationGate) -> GeneralNotificationEvent? {
        gate.permitsPresentation ? events.first : nil
    }

    mutating func dismiss(_ id: String) { events.removeAll { $0.id == id } }
    mutating func clear() { events.removeAll(); recentIdentities.removeAll() }
}
