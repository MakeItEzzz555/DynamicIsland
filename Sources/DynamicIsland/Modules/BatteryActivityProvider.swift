import Foundation
import IOKit.ps

struct BatteryActivitySnapshot: Equatable {
    let percentage: Int?
    let powerSourceStateDescription: String?
    let isPluggedIn: Bool
    let isCharging: Bool
    let isCharged: Bool
    let isOnBattery: Bool

    var isLowPower: Bool {
        guard let percentage else { return false }
        return percentage <= 20 && !isPluggedIn && !isCharging && !isCharged
    }

    var isEligible: Bool {
        isLowPower || isPluggedIn || isCharging || isCharged
    }

    var activityState: BatteryLiveActivityState? {
        if isLowPower {
            return .low
        }
        if isCharged {
            return .full
        }
        if isCharging {
            return .charging
        }
        if isPluggedIn {
            return .pluggedIn
        }
        return nil
    }

    func liveActivity(updatedAt: Date = Date()) -> DynamicIslandLiveActivity? {
        guard let activityState, let percentage else { return nil }
        let title = title(for: activityState)
        let subtitle = subtitle(for: activityState, percentage: percentage)

        let activity = DynamicIslandLiveActivity(
            id: LiveActivityStore.batteryActivityID,
            kind: .battery,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName(for: activityState, percentage: percentage),
            priority: CollapsedLiveActivityPrioritySource.defaultPriority(for: activityState),
            isActive: activityState != .full,
            progress: Double(percentage) / 100,
            updatedAt: updatedAt,
            batteryState: activityState
        )
        Self.debugPublishing(title: title, subtitle: subtitle)
        return activity
    }

    private func title(for state: BatteryLiveActivityState) -> String {
        switch state {
        case .low:
            return "Low Battery"
        case .charging:
            return "Charging"
        case .pluggedIn:
            return "Plugged In"
        case .full:
            return "Battery Full"
        }
    }

    private func subtitle(for state: BatteryLiveActivityState, percentage: Int) -> String {
        switch state {
        case .low:
            return "\(percentage)% remaining"
        case .charging:
            return "\(percentage)%"
        case .pluggedIn:
            return "\(percentage)%"
        case .full:
            return "100% charged"
        }
    }

    private func symbolName(for state: BatteryLiveActivityState, percentage: Int) -> String {
        switch state {
        case .low:
            return "battery.25percent"
        case .charging, .pluggedIn:
            return "battery.100percent.bolt"
        case .full:
            return "battery.100percent"
        }
    }

    private static func debugPublishing(title: String, subtitle: String) {
        #if DEBUG
        print("[BatteryActivity] publishing id=battery title=\(title) subtitle=\(subtitle)")
        #endif
    }
}

struct BatteryActivityProvider {
    func snapshot() -> BatteryActivitySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            Self.debugRemoving(reason: "no power source info")
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }
            guard let percentage = Self.percentage(from: description) else {
                continue
            }

            let powerState = description[kIOPSPowerSourceStateKey as String] as? String
            let isPluggedIn = powerState == kIOPSACPowerValue
            let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            let isCharged = (description[kIOPSIsChargedKey as String] as? Bool) ?? (percentage >= 100)
            let snapshot = BatteryActivitySnapshot(
                percentage: percentage,
                powerSourceStateDescription: powerState,
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                isCharged: isCharged,
                isOnBattery: powerState == kIOPSBatteryPowerValue
            )
            Self.debugSnapshot(snapshot)
            return snapshot
        }

        Self.debugRemoving(reason: "no battery percentage")
        return nil
    }

    private static func percentage(from description: [String: Any]) -> Int? {
        let current = description[kIOPSCurrentCapacityKey as String] as? Int
        let maximum = description[kIOPSMaxCapacityKey as String] as? Int

        guard let current, let maximum, maximum > 0 else {
            return nil
        }

        let percentage = Double(current) / Double(maximum) * 100
        return Swift.min(Swift.max(Int(percentage.rounded()), 0), 100)
    }

    static func debugRemoving(reason: String) {
        #if DEBUG
        print("[BatteryActivity] removing id=battery reason=\(reason)")
        #endif
    }

    private static func debugSnapshot(_ snapshot: BatteryActivitySnapshot) {
        #if DEBUG
        let percentageDescription = snapshot.percentage.map { "\($0)%" } ?? "unknown"
        let sourceDescription = snapshot.powerSourceStateDescription ?? "unknown"
        print(
            "[BatteryActivity] percent=\(percentageDescription) " +
            "source=\(sourceDescription) " +
            "pluggedIn=\(snapshot.isPluggedIn) " +
            "charging=\(snapshot.isCharging) " +
            "charged=\(snapshot.isCharged) " +
            "low=\(snapshot.isLowPower) " +
            "eligible=\(snapshot.isEligible)"
        )
        #endif
    }
}

private extension CollapsedLiveActivityPrioritySource {
    static func defaultPriority(for state: BatteryLiveActivityState) -> Int {
        switch state {
        case .low:
            return lowBattery.defaultPriority
        case .charging, .pluggedIn:
            return chargingBattery.defaultPriority
        case .full:
            return fullBattery.defaultPriority
        }
    }
}
