import Foundation

/// Optional extension to the existing appearance JSON. Old checkpoints decode
/// unchanged; nil selects the reference defaults.
struct BotAvatarFidelityConfiguration: Codable, Equatable, Sendable {
    var bodyColorHex: String? = nil
    var inkColorHex: String? = nil
    var customBodyPath: String? = nil
    var seed: Double? = nil
    var paused = false
    var poseEnabled = false
    var yaw = 0.0
    var pitch = 0.0
    var roll = 0.0
    var backLight = 1.0
    var lightFront = 32.0
    var shine = 0.0
    var sheen = 0.0
    var backSoftness = 1.0
    var jumpSquashTime = 0.37
    var jumpSquashEase = "pulse"
    var jumpGroundTime = 0.11
    var jumpGroundEase = "pulse"
    var jumpRiseTime = 0.33
    var jumpRiseEase = "pulse"
    var jumpClickSquashTime = 0.24
    var jumpLand = 0.0
    var whirlSize = 1.0
    var whirlWidth = 1.0
    var whirlLength = 1.0
    var whirlTilt = 1.0

    func normalized() -> Self {
        var c = self
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        for key in [\Self.yaw, \.pitch, \.roll] { c[keyPath: key] = clamp(c[keyPath: key], -180...180, 0) }
        for key in [\Self.backLight, \.shine, \.sheen] { c[keyPath: key] = clamp(c[keyPath: key], 0...2, Self()[keyPath: key]) }
        c.lightFront = clamp(c.lightFront, 0...90, 32)
        c.backSoftness = clamp(c.backSoftness, 0.1...2, 1)
        for key in [\Self.jumpSquashTime, \.jumpRiseTime, \.jumpClickSquashTime] { c[keyPath: key] = clamp(c[keyPath: key], 0.05...2, Self()[keyPath: key]) }
        c.jumpGroundTime = clamp(c.jumpGroundTime, 0...2, 0.11)
        c.jumpLand = clamp(c.jumpLand, -0.3...0.3, 0)
        c.whirlSize = clamp(c.whirlSize, 0.6...1.6, 1)
        c.whirlWidth = clamp(c.whirlWidth, 0.4...2, 1)
        c.whirlLength = clamp(c.whirlLength, 0.4...1.6, 1)
        c.whirlTilt = clamp(c.whirlTilt, 0.5...1.8, 1)
        c.seed = c.seed.map { clamp($0, 0...1, 0.5) }
        for key in [\Self.bodyColorHex, \.inkColorHex] {
            if let hex = c[keyPath: key], ColorValidation.validHex(hex) == false { c[keyPath: key] = nil }
        }
        for key in [\Self.jumpSquashEase, \.jumpGroundEase, \.jumpRiseEase] {
            if !["sharp", "pulse", "soft", "bouncy"].contains(c[keyPath: key]) { c[keyPath: key] = "pulse" }
        }
        // Bound parser/cache input. An invalid or empty path uses the stock body.
        if let path = c.customBodyPath, path.utf8.count > 8192 || !path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("M") { c.customBodyPath = nil }
        return c
    }
}

private enum ColorValidation {
    static func validHex(_ value: String) -> Bool {
        value.count == 7 && value.first == "#" && value.dropFirst().allSatisfy { $0.isHexDigit }
    }
}

extension BotAvatarConfiguration {
    var renderDetails: BotAvatarAdvancedConfiguration {
        get {
            if let advanced { return advanced }
            var a = BotAvatarAdvancedConfiguration()
            a.shadow = shading == .fabric ? 0.575 : 0.35/2; a.highlight = shading == .fabric ? 1.45/3 : 1.3/3; a.lightAngle = shading == .fabric ? 295 : 300
            a.rimLight = shading == .fabric ? 0.3 : 0.25; a.spread = shading == .fabric ? 1.6/1.55 : 1; a.furLength = 0.125; a.fuzz = 0.9/2.6
            a.jumpHeight = 0.26; a.jumpDuration = 0.68; a.squashStretch = 0.125
            a.spin = 1; a.lean = 6; a.idleJumpCadence = 8
            return a
        }
        set { advanced = newValue }
    }
}
