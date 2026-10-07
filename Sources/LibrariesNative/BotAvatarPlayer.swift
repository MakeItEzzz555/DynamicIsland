import Foundation

/// A clock adaptor without timers, Tasks or subscriptions. Multiple visible
/// presentations of one identity may share it without advancing the rig twice.
public final class BotAvatarPlayer {
    public let simulation: BotAvatarSim
    public private(set) var lastTimestamp: Double?
    public init(seed: Double, state: BotAvatarState = .default) {
        simulation = BotAvatarSim(seed: seed, state: state)
    }
    public func frame(at timestamp: Double, state: BotAvatarState, speed: Double, paused: Bool) -> BotAvatarPose {
        simulation.setState(state)
        if paused { lastTimestamp = nil; return simulation.pose }
        defer { lastTimestamp = timestamp }
        guard let lastTimestamp else { return simulation.pose }
        let dt = timestamp - lastTimestamp
        // Window occlusion/offscreen periods never become a catch-up jump.
        if dt > 0 && dt <= 0.12 {
            var remaining = min(dt, 0.05) * min(2, max(0.25, speed))
            while remaining > 0.000001 {
                let step = min(remaining, 1/60)
                simulation.update(step); remaining -= step
            }
        }
        return simulation.pose
    }
    public func suspend() { lastTimestamp = nil; simulation.setPointer(x: 0, y: 0, strength: 0) }
}
