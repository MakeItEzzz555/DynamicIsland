import CoreGraphics
import Foundation

enum LiveActivityPlacement: String, CaseIterable, Codable, Sendable {
    case leadingSidecar
    case primary
    case trailingSidecar
    case overlayTransient
}

enum LiveActivityCompactShape: String, Equatable, Sendable {
    case circle
    case capsule
    case notchWing
    case elongatedPill
    case progressPill
}

enum LiveActivityCoexistencePolicy: Equatable, Sendable {
    case exclusive
    case primaryOnly
    case sidecarAllowed
    case sidecarPreferred
    case unrestrictedCompact
}

enum LiveActivityPreemptionPolicy: Equatable, Sendable {
    case persistent
    case transientOverlay
}

public enum LiveActivitySidePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case leading
    case trailing

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .leading: "Leading"
        case .trailing: "Trailing"
        }
    }
}

struct LiveActivityPresentationDescriptor: Equatable, Sendable {
    let activityID: String
    let preferredPlacement: LiveActivityPlacement
    let allowedPlacements: Set<LiveActivityPlacement>
    let compactShape: LiveActivityCompactShape
    let minimumWidth: CGFloat
    let idealWidth: CGFloat
    let priority: Int
    let coexistencePolicy: LiveActivityCoexistencePolicy
    let preemptionPolicy: LiveActivityPreemptionPolicy

    var supportsLeadingSidecar: Bool {
        allowedPlacements.contains(.leadingSidecar)
    }

    var supportsTrailingSidecar: Bool {
        allowedPlacements.contains(.trailingSidecar)
    }

    var allowsPrimary: Bool {
        allowedPlacements.contains(.primary)
    }
}

struct LiveActivityPresentation: Equatable, Sendable, Identifiable {
    let activity: DynamicIslandLiveActivity
    let descriptor: LiveActivityPresentationDescriptor

    var id: String { activity.id }
}

struct LiveActivityLayoutResolution: Equatable, Sendable {
    var leadingSidecar: LiveActivityPresentation?
    var primary: LiveActivityPresentation?
    var trailingSidecar: LiveActivityPresentation?
    var overlayTransient: LiveActivityPresentation?

    static let empty = LiveActivityLayoutResolution(
        leadingSidecar: nil,
        primary: nil,
        trailingSidecar: nil,
        overlayTransient: nil
    )

    var persistentActivityIDs: [String] {
        [leadingSidecar?.activity.id, primary?.activity.id, trailingSidecar?.activity.id]
            .compactMap { $0 }
    }

    var hasSidecars: Bool {
        leadingSidecar != nil || trailingSidecar != nil
    }
}

struct LiveActivityLayoutContext: Equatable, Sendable {
    var availableWidth: CGFloat
    var hasHardwareNotch: Bool
    var hardwareNotchWidth: CGFloat
    var primaryMinimumWidth: CGFloat = 172
    var primaryIdealWidth: CGFloat = 226
    var sidecarDiameter: CGFloat = 30
    var sidecarGap: CGFloat = 7
    var allowSimultaneousSidecars: Bool = true
    var timerSidePreference: LiveActivitySidePreference = .automatic

    var sidecarCapacity: Int {
        // Width pressure is measured against the resolved primary surface's minimum width.
        // Physical-notch exclusion is handled by the geometry layer; counting the notch again
        // here would incorrectly evict sidecars on otherwise-wide notched layouts.
        let base = max(primaryMinimumWidth, 1)
        let one = base + sidecarGap + sidecarDiameter
        let two = one + sidecarGap + sidecarDiameter
        if allowSimultaneousSidecars, availableWidth >= two {
            return 2
        }
        if availableWidth >= one {
            return 1
        }
        return 0
    }
}

enum LiveActivityPresentationPolicy {
    static func descriptor(
        for activity: DynamicIslandLiveActivity,
        timerSidePreference: LiveActivitySidePreference = .automatic
    ) -> LiveActivityPresentationDescriptor {
        switch activity.kind {
        case .system:
            return LiveActivityPresentationDescriptor(
                activityID: activity.id,
                preferredPlacement: .overlayTransient,
                allowedPlacements: [.overlayTransient],
                compactShape: .progressPill,
                minimumWidth: 110,
                idealWidth: 190,
                priority: activity.priority,
                coexistencePolicy: .exclusive,
                preemptionPolicy: .transientOverlay
            )

        case .agent:
            return LiveActivityPresentationDescriptor(
                activityID: activity.id,
                preferredPlacement: .primary,
                allowedPlacements: [.primary],
                compactShape: .notchWing,
                minimumWidth: 190,
                idealWidth: 250,
                priority: 130,
                coexistencePolicy: .sidecarAllowed,
                preemptionPolicy: .persistent
            )

        case .media:
            return LiveActivityPresentationDescriptor(
                activityID: activity.id,
                preferredPlacement: .primary,
                allowedPlacements: [.primary],
                compactShape: .elongatedPill,
                minimumWidth: 190,
                idealWidth: 254,
                priority: activity.isActive ? 120 : 75,
                coexistencePolicy: .sidecarAllowed,
                preemptionPolicy: .persistent
            )

        case .timer:
            let preferred: LiveActivityPlacement = switch timerSidePreference {
            case .automatic, .trailing: .trailingSidecar
            case .leading: .leadingSidecar
            }
            return LiveActivityPresentationDescriptor(
                activityID: activity.id,
                preferredPlacement: preferred,
                allowedPlacements: [.leadingSidecar, .trailingSidecar, .primary],
                compactShape: .circle,
                minimumWidth: 28,
                idealWidth: 32,
                priority: activity.isActive ? 110 : 82,
                coexistencePolicy: .sidecarPreferred,
                preemptionPolicy: .persistent
            )

        case .battery:
            return LiveActivityPresentationDescriptor(
                activityID: activity.id,
                preferredPlacement: .leadingSidecar,
                allowedPlacements: [.leadingSidecar, .trailingSidecar, .primary],
                compactShape: .circle,
                minimumWidth: 28,
                idealWidth: 32,
                priority: batteryPriority(activity),
                coexistencePolicy: .sidecarPreferred,
                preemptionPolicy: .persistent
            )

        case .fileTray:
            return LiveActivityPresentationDescriptor(
                activityID: activity.id,
                preferredPlacement: .leadingSidecar,
                allowedPlacements: [.leadingSidecar, .trailingSidecar, .primary],
                compactShape: .capsule,
                minimumWidth: 30,
                idealWidth: 38,
                priority: 65,
                coexistencePolicy: .sidecarAllowed,
                preemptionPolicy: .persistent
            )

        case .keepAwake:
            return sidecarDescriptor(
                activity,
                preferredPlacement: .trailingSidecar,
                shape: .capsule,
                priority: max(activity.priority, 72)
            )

        case .terminalTask:
            return sidecarDescriptor(
                activity,
                preferredPlacement: .trailingSidecar,
                shape: .capsule,
                priority: max(activity.priority, 88)
            )

        case .windowSnapPreview:
            return LiveActivityPresentationDescriptor(
                activityID: activity.id,
                preferredPlacement: .overlayTransient,
                allowedPlacements: [.overlayTransient],
                compactShape: .capsule,
                minimumWidth: 88,
                idealWidth: 150,
                priority: max(activity.priority, 170),
                coexistencePolicy: .exclusive,
                preemptionPolicy: .transientOverlay
            )

        case .reminder:
            return sidecarDescriptor(
                activity,
                preferredPlacement: .leadingSidecar,
                shape: .capsule,
                priority: max(activity.priority, 78)
            )

        case .voiceRecording:
            return primaryDescriptor(
                activity,
                shape: .progressPill,
                priority: max(activity.priority, 125)
            )

        case .voiceTranscription:
            return primaryDescriptor(
                activity,
                shape: .progressPill,
                priority: max(activity.priority, 105)
            )

        case .camera:
            return primaryDescriptor(
                activity,
                shape: .elongatedPill,
                priority: max(activity.priority, 128)
            )

        case .backgroundRemoval:
            return sidecarDescriptor(
                activity,
                preferredPlacement: .leadingSidecar,
                shape: .circle,
                priority: max(activity.priority, 84)
            )

        case .message:
            // Persistent (not a transient overlay): a message awaiting the
            // user's action survives volume/brightness HUDs. Priority comes
            // from MessagingController (fresh vs acknowledged).
            return primaryDescriptor(
                activity,
                shape: .notchWing,
                priority: activity.priority
            )
        }
    }

    private static func sidecarDescriptor(
        _ activity: DynamicIslandLiveActivity,
        preferredPlacement: LiveActivityPlacement,
        shape: LiveActivityCompactShape,
        priority: Int
    ) -> LiveActivityPresentationDescriptor {
        LiveActivityPresentationDescriptor(
            activityID: activity.id,
            preferredPlacement: preferredPlacement,
            allowedPlacements: [.leadingSidecar, .trailingSidecar, .primary],
            compactShape: shape,
            minimumWidth: shape == .circle ? 28 : 30,
            idealWidth: shape == .circle ? 32 : 58,
            priority: priority,
            coexistencePolicy: .sidecarPreferred,
            preemptionPolicy: .persistent
        )
    }

    private static func primaryDescriptor(
        _ activity: DynamicIslandLiveActivity,
        shape: LiveActivityCompactShape,
        priority: Int
    ) -> LiveActivityPresentationDescriptor {
        LiveActivityPresentationDescriptor(
            activityID: activity.id,
            preferredPlacement: .primary,
            allowedPlacements: [.primary],
            compactShape: shape,
            minimumWidth: 176,
            idealWidth: 228,
            priority: priority,
            coexistencePolicy: .sidecarAllowed,
            preemptionPolicy: .persistent
        )
    }

    private static func batteryPriority(_ activity: DynamicIslandLiveActivity) -> Int {
        switch activity.batteryState {
        case .low: 96
        case .charging, .pluggedIn: 68
        case .full: 58
        case nil: 40
        }
    }
}

enum LiveActivityLayoutResolver {
    static func resolve(
        activities: [DynamicIslandLiveActivity],
        context: LiveActivityLayoutContext
    ) -> LiveActivityLayoutResolution {
        let presentations = activities.map { activity in
            LiveActivityPresentation(
                activity: activity,
                descriptor: LiveActivityPresentationPolicy.descriptor(
                    for: activity,
                    timerSidePreference: context.timerSidePreference
                )
            )
        }

        let overlays = presentations
            .filter { $0.descriptor.allowedPlacements.contains(.overlayTransient) }
            .sorted(by: presentationSort)
        let persistent = presentations
            .filter { !$0.descriptor.allowedPlacements.contains(.overlayTransient) }

        guard !persistent.isEmpty else {
            return LiveActivityLayoutResolution(
                leadingSidecar: nil,
                primary: nil,
                trailingSidecar: nil,
                overlayTransient: overlays.first
            )
        }

        let primaryCandidates = persistent
            .filter { $0.descriptor.allowsPrimary }
            .sorted(by: primarySort)

        guard let primary = primaryCandidates.first else {
            return LiveActivityLayoutResolution(
                leadingSidecar: nil,
                primary: nil,
                trailingSidecar: nil,
                overlayTransient: overlays.first
            )
        }

        if primary.descriptor.coexistencePolicy == .exclusive {
            return LiveActivityLayoutResolution(
                leadingSidecar: nil,
                primary: primary,
                trailingSidecar: nil,
                overlayTransient: overlays.first
            )
        }

        var remaining = persistent
            .filter { $0.id != primary.id }
            .filter {
                $0.descriptor.supportsLeadingSidecar ||
                $0.descriptor.supportsTrailingSidecar
            }
            .sorted(by: presentationSort)

        var leading: LiveActivityPresentation?
        var trailing: LiveActivityPresentation?
        var capacity = context.sidecarCapacity

        while capacity > 0, !remaining.isEmpty {
            let candidate = remaining.removeFirst()
            if place(
                candidate,
                leading: &leading,
                trailing: &trailing
            ) {
                capacity -= 1
            }
        }

        return LiveActivityLayoutResolution(
            leadingSidecar: leading,
            primary: primary,
            trailingSidecar: trailing,
            overlayTransient: overlays.first
        )
    }

    private static func place(
        _ candidate: LiveActivityPresentation,
        leading: inout LiveActivityPresentation?,
        trailing: inout LiveActivityPresentation?
    ) -> Bool {
        let descriptor = candidate.descriptor

        func tryLeading() -> Bool {
            guard descriptor.supportsLeadingSidecar, leading == nil else { return false }
            leading = candidate
            return true
        }

        func tryTrailing() -> Bool {
            guard descriptor.supportsTrailingSidecar, trailing == nil else { return false }
            trailing = candidate
            return true
        }

        switch descriptor.preferredPlacement {
        case .leadingSidecar:
            return tryLeading() || tryTrailing()
        case .trailingSidecar:
            return tryTrailing() || tryLeading()
        case .primary, .overlayTransient:
            return tryTrailing() || tryLeading()
        }
    }

    private static func primarySort(
        _ lhs: LiveActivityPresentation,
        _ rhs: LiveActivityPresentation
    ) -> Bool {
        let lhsPrimaryPreference = lhs.descriptor.preferredPlacement == .primary ? 1 : 0
        let rhsPrimaryPreference = rhs.descriptor.preferredPlacement == .primary ? 1 : 0
        if lhsPrimaryPreference != rhsPrimaryPreference {
            return lhsPrimaryPreference > rhsPrimaryPreference
        }
        return presentationSort(lhs, rhs)
    }

    private static func presentationSort(
        _ lhs: LiveActivityPresentation,
        _ rhs: LiveActivityPresentation
    ) -> Bool {
        if lhs.descriptor.priority != rhs.descriptor.priority {
            return lhs.descriptor.priority > rhs.descriptor.priority
        }
        if lhs.activity.updatedAt != rhs.activity.updatedAt {
            return lhs.activity.updatedAt > rhs.activity.updatedAt
        }
        return lhs.activity.id < rhs.activity.id
    }
}

struct LiveActivityCompositeGeometry: Equatable, Sendable {
    let leadingSidecarFrame: CGRect?
    let primaryFrame: CGRect
    let trailingSidecarFrame: CGRect?
    let interactionFrame: CGRect

    static func resolve(
        primaryFrame: CGRect,
        canvasSize: CGSize,
        resolution: LiveActivityLayoutResolution,
        sidecarDiameter: CGFloat = 30,
        sidecarGap: CGFloat = 7
    ) -> LiveActivityCompositeGeometry {
        let canvasBounds = CGRect(origin: .zero, size: canvasSize)
        let sideY = primaryFrame.midY - sidecarDiameter / 2

        var leadingFrame: CGRect?
        if resolution.leadingSidecar != nil {
            let proposed = CGRect(
                x: primaryFrame.minX - sidecarGap - sidecarDiameter,
                y: sideY,
                width: sidecarDiameter,
                height: sidecarDiameter
            )
            if canvasBounds.contains(proposed) {
                leadingFrame = proposed.integral
            }
        }

        var trailingFrame: CGRect?
        if resolution.trailingSidecar != nil {
            let proposed = CGRect(
                x: primaryFrame.maxX + sidecarGap,
                y: sideY,
                width: sidecarDiameter,
                height: sidecarDiameter
            )
            if canvasBounds.contains(proposed) {
                trailingFrame = proposed.integral
            }
        }

        var interaction = primaryFrame
        if let leadingFrame {
            interaction = interaction.union(leadingFrame)
        }
        if let trailingFrame {
            interaction = interaction.union(trailingFrame)
        }

        return LiveActivityCompositeGeometry(
            leadingSidecarFrame: leadingFrame,
            primaryFrame: primaryFrame,
            trailingSidecarFrame: trailingFrame,
            interactionFrame: interaction.integral
        )
    }
}


enum LiveActivityRuntimeProjection {
    static func activities(
        stored: [DynamicIslandLiveActivity],
        priorities: CollapsedLiveActivityPrioritySettings,
        toggles: CollapsedLiveActivitySourceToggles,
        agentSessions: [AgentSession],
        agentEnabled: Bool
    ) -> [DynamicIslandLiveActivity] {
        var result = CollapsedLiveActivitySelector.previewActivities(
            activities: stored,
            priorities: priorities,
            toggles: toggles,
            maxCount: 16
        )

        let projectedIDs = Set(result.map(\.id))
        result.append(contentsOf: stored.filter {
            $0.kind.usesDirectLayoutProjection && !projectedIDs.contains($0.id)
        })

        if let compact = AgentCompactPresentation.make(
            sessions: agentSessions,
            enabled: agentEnabled
        ), let primary = compact.sessions.first {
            result.append(
                DynamicIslandLiveActivity(
                    id: "agent:\(primary.id.sessionID.provider.deterministicSortKey):\(primary.id.sessionID.nativeID)",
                    kind: .agent,
                    title: primary.project.displayName ??
                        primary.id.sessionID.provider.stableName.capitalized,
                    subtitle: AgentSessionPresentation.displayedStateLabel(
                        for: primary,
                        at: Date()
                    ),
                    symbolName: AgentVisualStyle.providerSymbol(primary.id.sessionID.provider),
                    priority: 130,
                    isActive: true,
                    progress: nil,
                    updatedAt: primary.lastUpdatedAt
                )
            )
        }

        return result
    }
}
