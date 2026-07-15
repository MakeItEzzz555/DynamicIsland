import CoreGraphics
import XCTest
@testable import DynamicIsland

final class SpaceTransitionCompensationMathTests: XCTestCase {
    func testNoDisplacementReturnsZeroHorizontalCorrection() {
        let correction = SpaceTransitionCompensationMath.horizontalCorrection(
            expectedX: 246,
            actualX: 246
        )

        XCTAssertEqual(correction, 0)
    }

    func testNegativeActualXReturnsPositiveHorizontalCorrection() {
        let correction = SpaceTransitionCompensationMath.horizontalCorrection(
            expectedX: 246,
            actualX: -175
        )

        XCTAssertEqual(correction, 421)
    }

    func testNonFiniteHorizontalValuesReturnNil() {
        XCTAssertNil(
            SpaceTransitionCompensationMath.horizontalCorrection(
                expectedX: .infinity,
                actualX: 246
            )
        )
        XCTAssertNil(
            SpaceTransitionCompensationMath.horizontalCorrection(
                expectedX: 246,
                actualX: .nan
            )
        )
    }

    func testProbeTranslationIsRawWindowServerDisplacement() {
        let translation = SpaceTransitionCompensationMath.probeSpaceTranslationX(
            probeCanonicalX: 4,
            actualProbeCGX: -396,
            probeWindowServerXOffset: 0
        )

        XCTAssertEqual(translation, -400)
    }

    func testProbeTranslationAccountsForWindowServerCoordinateOffset() {
        let translation = SpaceTransitionCompensationMath.probeSpaceTranslationX(
            probeCanonicalX: 4,
            actualProbeCGX: -394,
            probeWindowServerXOffset: 2
        )

        XCTAssertEqual(translation, -400)
    }

    func testFeedForwardOffsetIsInverseProbeTranslation() {
        let offset = SpaceTransitionCompensationMath.feedForwardIslandOffsetX(
            probeTranslationX: -400
        )
        let physicalX = SpaceTransitionCompensationMath.probeDrivenPhysicalX(
            canonicalIslandX: 246,
            probeTranslationX: -400
        )

        XCTAssertEqual(offset, 400)
        XCTAssertEqual(physicalX, 646)
    }

    func testStableProbeReturnsCanonicalIslandPosition() {
        let translation = SpaceTransitionCompensationMath.probeSpaceTranslationX(
            probeCanonicalX: 4,
            actualProbeCGX: 4,
            probeWindowServerXOffset: 0
        )
        let offset = SpaceTransitionCompensationMath.feedForwardIslandOffsetX(
            probeTranslationX: translation ?? .nan
        )
        let physicalX = SpaceTransitionCompensationMath.probeDrivenPhysicalX(
            canonicalIslandX: 246,
            probeTranslationX: translation ?? .nan
        )

        XCTAssertEqual(translation, 0)
        XCTAssertEqual(offset, 0)
        XCTAssertEqual(physicalX, 246)
    }

    func testRepeatedProbeSampleDoesNotAccumulateOffset() {
        let firstOffset = SpaceTransitionCompensationMath.feedForwardIslandOffsetX(
            probeTranslationX: -400
        )
        let secondOffset = SpaceTransitionCompensationMath.feedForwardIslandOffsetX(
            probeTranslationX: -400
        )

        XCTAssertEqual(firstOffset, 400)
        XCTAssertEqual(secondOffset, 400)
    }

    func testTransitionEndReturnsIslandToCanonicalPosition() {
        let offset = SpaceTransitionCompensationMath.feedForwardIslandOffsetX(
            probeTranslationX: 0
        )
        let physicalX = SpaceTransitionCompensationMath.probeDrivenPhysicalX(
            canonicalIslandX: 246,
            probeTranslationX: 0
        )

        XCTAssertEqual(offset, 0)
        XCTAssertEqual(physicalX, 246)
    }

    func testRealRunawayPhysicalOffsetExceedsTotalBound() {
        let screenWidth: CGFloat = 1_352
        let maximumOffset = SpaceTransitionCompensationMath.maximumTotalOffset(
            screenWidth: screenWidth,
            multiplier: 1.25
        )
        let physicalOffset = SpaceTransitionCompensationMath.physicalOffset(
            canonicalX: 246,
            physicalX: -2_584
        )

        XCTAssertEqual(maximumOffset, 1_690)
        XCTAssertEqual(physicalOffset, -2_830)
        XCTAssertTrue(
            SpaceTransitionCompensationMath.exceedsMaximumOffset(
                physicalOffset ?? 0,
                maximumOffset: maximumOffset ?? 0
            )
        )
    }

    func testLargeProbeAnomalyIsInvalidBeforeMovingIslandThousandsOfPixels() {
        let screenWidth: CGFloat = 1_352
        let maximumProbeTranslation = screenWidth * 2.5
        let translation = SpaceTransitionCompensationMath.probeSpaceTranslationX(
            probeCanonicalX: 4,
            actualProbeCGX: -4_000,
            probeWindowServerXOffset: 0
        )
        let physicalOffset = SpaceTransitionCompensationMath.physicalOffset(
            canonicalX: 246,
            physicalX: 246
        )

        XCTAssertEqual(translation, -4_004)
        XCTAssertTrue(
            SpaceTransitionCompensationMath.exceedsMaximumOffset(
                translation ?? 0,
                maximumOffset: maximumProbeTranslation
            )
        )
        XCTAssertFalse(
            SpaceTransitionCompensationMath.exceedsMaximumOffset(
                physicalOffset ?? 0,
                maximumOffset: screenWidth * 1.25
            )
        )
    }

    func testObservedOneSpaceProbeTranslationIsInsideNormalTrackingBound() {
        let screenWidth: CGFloat = 1_352
        let normalProbeTranslationMaximum = screenWidth * 1.75
        let translation = SpaceTransitionCompensationMath.probeSpaceTranslationX(
            probeCanonicalX: 4,
            actualProbeCGX: -1_411,
            probeWindowServerXOffset: 0
        )
        let layerCompensation = SpaceTransitionCompensationMath.feedForwardIslandOffsetX(
            probeTranslationX: translation ?? .nan
        )

        XCTAssertEqual(translation, -1_415)
        XCTAssertEqual(layerCompensation, 1_415)
        XCTAssertFalse(
            SpaceTransitionCompensationMath.exceedsMaximumOffset(
                translation ?? 0,
                maximumOffset: normalProbeTranslationMaximum
            )
        )
    }

    func testProbeTranslationBetweenNormalAndAbsoluteBoundsIsHeldNotRecoveredImmediately() {
        let screenWidth: CGFloat = 1_352
        let normalProbeTranslationMaximum = screenWidth * 1.75
        let absoluteProbeTranslationMaximum = screenWidth * 2.5
        let translation: CGFloat = 2_800

        XCTAssertTrue(
            SpaceTransitionCompensationMath.exceedsMaximumOffset(
                translation,
                maximumOffset: normalProbeTranslationMaximum
            )
        )
        XCTAssertFalse(
            SpaceTransitionCompensationMath.exceedsMaximumOffset(
                translation,
                maximumOffset: absoluteProbeTranslationMaximum
            )
        )
    }

    func testBoundedPredictionUsesShortAdaptiveLead() {
        let prediction = SpaceTransitionCompensationMath.boundedPredictedTranslationX(
            rawTranslationX: -600,
            velocityX: -1_200,
            sampleAge: 0.030,
            sensorInterval: 1.0 / 60.0,
            leadIntervalMultiplier: 0.6,
            minimumLead: 0.008,
            maximumLead: 0.024,
            maximumPredictionDistance: 54,
            restTranslationThreshold: 8,
            restVelocityThreshold: 20,
            predictionDisabled: false
        )

        XCTAssertEqual(prediction?.lead ?? -1, 0.010, accuracy: 0.000_001)
        XCTAssertEqual(prediction?.translationX ?? 0, -612, accuracy: 0.000_001)
    }

    func testPredictionDistanceIsClamped() {
        let prediction = SpaceTransitionCompensationMath.boundedPredictedTranslationX(
            rawTranslationX: -600,
            velocityX: -20_000,
            sampleAge: 0.024,
            sensorInterval: 1.0 / 30.0,
            leadIntervalMultiplier: 0.6,
            minimumLead: 0.008,
            maximumLead: 0.024,
            maximumPredictionDistance: 54,
            restTranslationThreshold: 8,
            restVelocityThreshold: 20,
            predictionDisabled: false
        )

        XCTAssertEqual(prediction?.translationX, -654)
    }

    func testPredictionDisablesNearRestAndWhenEnvironmentRequestsRawMode() {
        let nearRest = SpaceTransitionCompensationMath.boundedPredictedTranslationX(
            rawTranslationX: 4,
            velocityX: 1_000,
            sampleAge: 0.020,
            sensorInterval: 1.0 / 60.0,
            leadIntervalMultiplier: 0.6,
            minimumLead: 0.008,
            maximumLead: 0.024,
            maximumPredictionDistance: 54,
            restTranslationThreshold: 8,
            restVelocityThreshold: 20,
            predictionDisabled: false
        )
        let disabled = SpaceTransitionCompensationMath.boundedPredictedTranslationX(
            rawTranslationX: -600,
            velocityX: -1_000,
            sampleAge: 0.020,
            sensorInterval: 1.0 / 60.0,
            leadIntervalMultiplier: 0.6,
            minimumLead: 0.008,
            maximumLead: 0.024,
            maximumPredictionDistance: 54,
            restTranslationThreshold: 8,
            restVelocityThreshold: 20,
            predictionDisabled: true
        )

        XCTAssertEqual(nearRest?.translationX, 4)
        XCTAssertEqual(nearRest?.lead, 0)
        XCTAssertEqual(disabled?.translationX, -600)
        XCTAssertEqual(disabled?.lead, 0)
    }

    func testDirectionReversalDetectionIgnoresTinyNoise() {
        XCTAssertTrue(
            SpaceTransitionCompensationMath.didReverseDirection(
                previousDelta: -40,
                currentDelta: 16,
                threshold: 0.1
            )
        )
        XCTAssertFalse(
            SpaceTransitionCompensationMath.didReverseDirection(
                previousDelta: -40,
                currentDelta: 0.04,
                threshold: 0.1
            )
        )
    }

    func testNonFiniteProbeValuesReturnNil() {
        XCTAssertNil(
            SpaceTransitionCompensationMath.probeSpaceTranslationX(
                probeCanonicalX: .nan,
                actualProbeCGX: 4,
                probeWindowServerXOffset: 0
            )
        )
        XCTAssertNil(
            SpaceTransitionCompensationMath.feedForwardIslandOffsetX(
                probeTranslationX: .infinity
            )
        )
        XCTAssertNil(
            SpaceTransitionCompensationMath.probeDrivenPhysicalX(
                canonicalIslandX: 246,
                probeTranslationX: .nan
            )
        )
    }

    func testHorizontalSettledRequiresSmallErrorAndSmallOffset() {
        XCTAssertTrue(
            SpaceTransitionCompensationMath.isHorizontallySettled(
                errorX: 0.4,
                offsetX: 0.5,
                threshold: 1
            )
        )
        XCTAssertFalse(
            SpaceTransitionCompensationMath.isHorizontallySettled(
                errorX: 0.4,
                offsetX: 3,
                threshold: 1
            )
        )
    }

    func testGeometrySignatureEquality() {
        let lhs = OverlayGeometrySignature(
            collapsedSize: CGSize(width: 520, height: 58),
            expandedSize: CGSize(width: 860, height: 286),
            collapsedHasActiveContent: true,
            useAdaptiveNotchSizing: true,
            respectHardwareNotch: true
        )
        let rhs = OverlayGeometrySignature(
            collapsedSize: CGSize(width: 520, height: 58),
            expandedSize: CGSize(width: 860, height: 286),
            collapsedHasActiveContent: true,
            useAdaptiveNotchSizing: true,
            respectHardwareNotch: true
        )

        XCTAssertEqual(lhs, rhs)
    }
}
