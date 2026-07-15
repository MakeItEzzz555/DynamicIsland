import CoreGraphics
import Foundation

struct OverlayGeometrySignature: Equatable, CustomStringConvertible {
    let collapsedSize: CGSize
    let expandedSize: CGSize
    let collapsedHasActiveContent: Bool
    let useAdaptiveNotchSizing: Bool
    let respectHardwareNotch: Bool

    var description: String {
        "collapsedSize=\(collapsedSize) expandedSize=\(expandedSize) collapsedHasActiveContent=\(collapsedHasActiveContent) useAdaptiveNotchSizing=\(useAdaptiveNotchSizing) respectHardwareNotch=\(respectHardwareNotch)"
    }
}

enum SpaceTransitionCompensationMath {
    static func maximumTotalOffset(screenWidth: CGFloat, multiplier: CGFloat) -> CGFloat? {
        guard screenWidth.isFinite,
              screenWidth > 0,
              multiplier.isFinite,
              multiplier > 0 else {
            return nil
        }

        return screenWidth * multiplier
    }

    static func horizontalCorrection(expectedX: CGFloat, actualX: CGFloat) -> CGFloat? {
        guard expectedX.isFinite,
              actualX.isFinite else {
            return nil
        }

        return expectedX - actualX
    }

    static func probeSpaceTranslationX(
        probeCanonicalX: CGFloat,
        actualProbeCGX: CGFloat,
        probeWindowServerXOffset: CGFloat
    ) -> CGFloat? {
        guard probeCanonicalX.isFinite,
              actualProbeCGX.isFinite,
              probeWindowServerXOffset.isFinite else {
            return nil
        }

        let expectedProbeCGX = probeCanonicalX + probeWindowServerXOffset
        return actualProbeCGX - expectedProbeCGX
    }

    static func feedForwardIslandOffsetX(probeTranslationX: CGFloat) -> CGFloat? {
        guard probeTranslationX.isFinite else {
            return nil
        }

        return -probeTranslationX
    }

    static func probeDrivenPhysicalX(
        canonicalIslandX: CGFloat,
        probeTranslationX: CGFloat
    ) -> CGFloat? {
        guard canonicalIslandX.isFinite,
              probeTranslationX.isFinite else {
            return nil
        }

        return canonicalIslandX - probeTranslationX
    }

    static func physicalOffset(canonicalX: CGFloat, physicalX: CGFloat) -> CGFloat? {
        guard canonicalX.isFinite,
              physicalX.isFinite else {
            return nil
        }

        return physicalX - canonicalX
    }

    static func exceedsMaximumOffset(_ offsetX: CGFloat, maximumOffset: CGFloat) -> Bool {
        guard offsetX.isFinite,
              maximumOffset.isFinite,
              maximumOffset > 0 else {
            return true
        }

        return abs(offsetX) > maximumOffset
    }

    static func isHorizontallySettled(errorX: CGFloat, offsetX: CGFloat, threshold: CGFloat) -> Bool {
        guard errorX.isFinite,
              offsetX.isFinite,
              threshold.isFinite,
              threshold >= 0 else {
            return false
        }
        return abs(errorX) <= threshold && abs(offsetX) <= threshold
    }

    static func exponentialMovingAverage(
        previous: CFTimeInterval?,
        newValue: CFTimeInterval,
        alpha: CGFloat
    ) -> CFTimeInterval? {
        guard newValue.isFinite,
              newValue > 0,
              alpha.isFinite,
              alpha >= 0,
              alpha <= 1 else {
            return previous
        }
        guard let previous else { return newValue }
        return previous * (1 - Double(alpha)) + newValue * Double(alpha)
    }

    static func didReverseDirection(
        previousDelta: CGFloat,
        currentDelta: CGFloat,
        threshold: CGFloat
    ) -> Bool {
        guard previousDelta.isFinite,
              currentDelta.isFinite,
              threshold.isFinite,
              threshold >= 0 else {
            return false
        }

        let previousSign = deltaSign(previousDelta, threshold: threshold)
        let currentSign = deltaSign(currentDelta, threshold: threshold)
        return previousSign != 0 && currentSign != 0 && previousSign != currentSign
    }

    static func boundedPredictedTranslationX(
        rawTranslationX: CGFloat,
        velocityX: CGFloat,
        sampleAge: CFTimeInterval,
        sensorInterval: CFTimeInterval,
        leadIntervalMultiplier: CGFloat,
        minimumLead: CFTimeInterval,
        maximumLead: CFTimeInterval,
        maximumPredictionDistance: CGFloat,
        restTranslationThreshold: CGFloat,
        restVelocityThreshold: CGFloat,
        predictionDisabled: Bool
    ) -> (translationX: CGFloat, lead: CFTimeInterval)? {
        guard rawTranslationX.isFinite,
              velocityX.isFinite,
              sampleAge.isFinite,
              sampleAge >= 0,
              sensorInterval.isFinite,
              sensorInterval > 0,
              leadIntervalMultiplier.isFinite,
              minimumLead.isFinite,
              minimumLead >= 0,
              maximumLead.isFinite,
              maximumLead >= minimumLead,
              maximumPredictionDistance.isFinite,
              maximumPredictionDistance >= 0,
              restTranslationThreshold.isFinite,
              restTranslationThreshold >= 0,
              restVelocityThreshold.isFinite,
              restVelocityThreshold >= 0 else {
            return nil
        }

        guard !predictionDisabled,
              abs(rawTranslationX) >= restTranslationThreshold,
              abs(velocityX) >= restVelocityThreshold else {
            return (rawTranslationX, 0)
        }

        let maximumAdaptiveLead = min(
            max(sensorInterval * Double(leadIntervalMultiplier), minimumLead),
            maximumLead
        )
        let lead = min(sampleAge, maximumAdaptiveLead)
        let predictionDelta = min(
            max(velocityX * CGFloat(lead), -maximumPredictionDistance),
            maximumPredictionDistance
        )
        return (rawTranslationX + predictionDelta, lead)
    }

    private static func deltaSign(_ delta: CGFloat, threshold: CGFloat) -> Int {
        if delta > threshold { return 1 }
        if delta < -threshold { return -1 }
        return 0
    }
}
