import AppKit
import XCTest
@testable import DynamicIsland

final class NotchGeometryServiceTests: XCTestCase {
    func testInfersHardwareNotchFromAuxiliaryAreas() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 635, height: 38),
            auxiliaryTopRightArea: CGRect(x: 877, y: 944, width: 635, height: 38)
        )

        let geometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 224, height: 42),
            expandedSize: CGSize(width: 620, height: 210)
        )

        XCTAssertTrue(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 635, y: 944, width: 242, height: 38))
        XCTAssertEqual(geometry.hardwareNotchWidth, 242)
        XCTAssertEqual(geometry.collapsedFrame, CGRect(x: 596, y: 940, width: 320, height: 42))
        XCTAssertEqual(geometry.collapsedLeftRegionWidth, 31)
        XCTAssertEqual(geometry.collapsedNotchCoreWidth, 242)
        XCTAssertEqual(geometry.collapsedRightRegionWidth, 31)
        XCTAssertEqual(geometry.collapsedFrame.maxY, 982, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.midX, 756, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.maxY, 982, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.width, 620, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.height, 210, accuracy: 0.5)
        XCTAssertLessThan(geometry.expandedFrame.width / snapshot.frame.width, 0.52)
        XCTAssertEqual(geometry.canvas.frame.maxY, snapshot.frame.maxY, accuracy: 0.5)
        XCTAssertTrue(geometry.canvas.frame.contains(geometry.collapsedFrame))
        XCTAssertTrue(geometry.canvas.frame.contains(geometry.expandedFrame))
        XCTAssertEqual(geometry.canvas.collapsedSurfaceFrame, CGRect(x: 150, y: 168, width: 320, height: 42))
        XCTAssertEqual(geometry.canvas.expandedSurfaceFrame, CGRect(x: 0, y: 0, width: 620, height: 210))
    }

    func testProductionCollapsedSizeIsUsedOnNotchedScreenAboveNotchMinimum() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 635, height: 38),
            auxiliaryTopRightArea: CGRect(x: 877, y: 944, width: 635, height: 38)
        )

        let geometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 520, height: 58),
            expandedSize: CGSize(width: 900, height: 300)
        )

        XCTAssertEqual(geometry.collapsedFrame.maxY, 982, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.width, 520, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.height, 58, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.minX, 496, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedLeftRegionWidth, geometry.collapsedRightRegionWidth)
        XCTAssertEqual(geometry.collapsedFrame.minX + 8 + geometry.collapsedLeftRegionWidth, 635, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.maxX - 8 - geometry.collapsedRightRegionWidth, 877, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.width, 900, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.height, 300, accuracy: 0.5)
        XCTAssertEqual(
            geometry.canvas.collapsedSurfaceFrame,
            geometry.collapsedFrame.offsetBy(dx: -geometry.canvas.frame.minX, dy: -geometry.canvas.frame.minY)
        )
        XCTAssertEqual(
            geometry.canvas.expandedSurfaceFrame,
            geometry.expandedFrame.offsetBy(dx: -geometry.canvas.frame.minX, dy: -geometry.canvas.frame.minY)
        )
    }

    func testInactiveCollapsedMediaUsesSmallerTopAttachedFrame() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 635, height: 38),
            auxiliaryTopRightArea: CGRect(x: 877, y: 944, width: 635, height: 38)
        )

        let activeGeometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 520, height: 58),
            expandedSize: CGSize(width: 900, height: 300),
            collapsedActivityProfile: .media(showsArtwork: true, showsVisualizer: true)
        )
        let inactiveGeometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 520, height: 58),
            expandedSize: CGSize(width: 900, height: 300),
            collapsedActivityProfile: nil
        )

        XCTAssertEqual(inactiveGeometry.collapsedFrame.midX, 756, accuracy: 0.5)
        XCTAssertEqual(inactiveGeometry.collapsedFrame.maxY, snapshot.frame.maxY, accuracy: 0.5)
        XCTAssertEqual(inactiveGeometry.collapsedFrame.height, 58, accuracy: 0.5)
        XCTAssertEqual(activeGeometry.collapsedFrame.height, 58, accuracy: 0.5)
        XCTAssertLessThan(inactiveGeometry.collapsedFrame.width, activeGeometry.collapsedFrame.width)
        XCTAssertEqual(
            inactiveGeometry.canvas.collapsedSurfaceFrame,
            inactiveGeometry.collapsedFrame.offsetBy(
                dx: -inactiveGeometry.canvas.frame.minX,
                dy: -inactiveGeometry.canvas.frame.minY
            )
        )
    }

    func testExpandedFrameStaysScreenCenteredWhenNotchIsOffCenter() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 600, height: 38),
            auxiliaryTopRightArea: CGRect(x: 850, y: 944, width: 662, height: 38)
        )

        let geometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 224, height: 42),
            expandedSize: CGSize(width: 620, height: 210)
        )

        XCTAssertEqual(
            geometry.collapsedFrame.minX + 8 + geometry.collapsedLeftRegionWidth,
            geometry.notchRect?.minX
        )
        XCTAssertEqual(
            geometry.collapsedFrame.maxX - 8 - geometry.collapsedRightRegionWidth,
            geometry.notchRect?.maxX
        )
        XCTAssertEqual(geometry.expandedFrame.midX, 756, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.maxY, 982, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.width, 620, accuracy: 0.5)
    }

    func testExpandedFrameKeepsSideMarginsOnNarrowScreens() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 900, height: 700),
            visibleFrame: CGRect(x: 0, y: 0, width: 900, height: 662),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 662, width: 340, height: 38),
            auxiliaryTopRightArea: CGRect(x: 560, y: 662, width: 340, height: 38)
        )

        let geometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 224, height: 42),
            expandedSize: CGSize(width: 1180, height: 210)
        )

        XCTAssertEqual(geometry.expandedFrame.minX, 140, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.maxX, 760, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.midX, 450, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.width, 620, accuracy: 0.5)
    }

    func testUsesFloatingIslandWhenNoNotchExists() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            safeAreaInsets: NSEdgeInsetsZero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        let geometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 224, height: 42),
            expandedSize: CGSize(width: 620, height: 210)
        )

        XCTAssertFalse(geometry.hasHardwareNotch)
        XCTAssertNil(geometry.notchRect)
        XCTAssertEqual(geometry.hardwareNotchWidth, 0)
        XCTAssertEqual(geometry.collapsedLeftRegionWidth, 0)
        XCTAssertEqual(geometry.collapsedNotchCoreWidth, 0)
        XCTAssertEqual(geometry.collapsedRightRegionWidth, 0)
        XCTAssertEqual(geometry.collapsedFrame.midX, 960, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.maxY, 1072, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.maxY, 1070, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.width, 620, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.height, 210, accuracy: 0.5)
        XCTAssertEqual(geometry.canvas.frame, CGRect(x: 650, y: 860, width: 620, height: 220))
        XCTAssertEqual(geometry.canvas.collapsedSurfaceFrame, CGRect(x: 198, y: 170, width: 224, height: 42))
        XCTAssertEqual(geometry.canvas.expandedSurfaceFrame, CGRect(x: 0, y: 0, width: 620, height: 210))
    }

    func testContentAwareRequiredWidthsForKnownNotchFixture() {
        let notchWidth: CGFloat = 242
        XCTAssertEqual(
            CollapsedActivityResolvedGeometry.requiredWidth(
                hardwareNotchWidth: notchWidth,
                profile: .media(showsArtwork: true, showsVisualizer: true)
            ),
            320
        )
        XCTAssertEqual(
            CollapsedActivityResolvedGeometry.requiredWidth(hardwareNotchWidth: notchWidth, profile: .timer),
            342
        )
        XCTAssertEqual(
            CollapsedActivityResolvedGeometry.requiredWidth(hardwareNotchWidth: notchWidth, profile: .battery),
            334
        )
        XCTAssertEqual(
            CollapsedActivityResolvedGeometry.requiredWidth(hardwareNotchWidth: notchWidth, profile: .file),
            354
        )
    }

    func testLargerConfiguredWidthDistributesExtraOutsideNotchAlignedRegions() {
        let resolved = CollapsedActivityResolvedGeometry.resolve(
            notchRect: CGRect(x: 635, y: 944, width: 242, height: 38),
            existingWidth: 400,
            collapsedHeight: 42,
            topY: 982,
            profile: .media(showsArtwork: true, showsVisualizer: true)
        )

        XCTAssertEqual(resolved.frame.width, 400)
        XCTAssertEqual(resolved.leftRegionWidth, 71)
        XCTAssertEqual(resolved.rightRegionWidth, 71)
        XCTAssertEqual(resolved.frame.minX + 8 + resolved.leftRegionWidth, 635)
        XCTAssertEqual(resolved.frame.maxX - 8 - resolved.rightRegionWidth, 877)
    }

    func testEveryActivityProfileResolvesEqualOuterWingWidths() {
        let profiles: [CollapsedActivityLayoutProfile] = [
            .media(showsArtwork: true, showsVisualizer: true),
            .timer,
            .battery,
            .file
        ]

        for profile in profiles {
            let resolved = CollapsedActivityResolvedGeometry.resolve(
                notchRect: CGRect(x: 635, y: 944, width: 242, height: 38),
                existingWidth: 224,
                collapsedHeight: 42,
                topY: 982,
                profile: profile
            )

            XCTAssertEqual(resolved.leftRegionWidth, resolved.rightRegionWidth)
        }
    }

    func testAgentsExpandedPresentationProfileScalesCanonicalSizeByTenPercent() {
        let base = CGSize(width: 860, height: 286)

        XCTAssertEqual(
            ExpandedPresentationProfile.standard.resolvedSize(from: base),
            base
        )

        let agents = ExpandedPresentationProfile.agentsWorkspace.resolvedSize(from: base)
        XCTAssertEqual(agents.width, 946, accuracy: 0.001)
        XCTAssertEqual(agents.height, 314.6, accuracy: 0.001)
        XCTAssertEqual(ExpandedPresentationProfile.agentsWorkspace.kind, .agentsWorkspace)
    }

    func testAgentCollapsedProfilesResolveOneCanonicalFrameAndRetractExactly() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 635, height: 38),
            auxiliaryTopRightArea: CGRect(x: 877, y: 944, width: 635, height: 38)
        )
        let normal = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 190, height: 44),
            expandedSize: CGSize(width: 860, height: 286),
            collapsedActivityProfile: nil,
            collapsedPresentationProfile: .normal
        )
        let routine = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 190, height: 44),
            expandedSize: CGSize(width: 860, height: 286),
            collapsedActivityProfile: nil,
            collapsedPresentationProfile: .agentRoutine(leftContentWidth: 72, rightContentWidth: 96)
        )
        let attention = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 190, height: 44),
            expandedSize: CGSize(width: 860, height: 286),
            collapsedActivityProfile: nil,
            collapsedPresentationProfile: .agentAttention(leftContentWidth: 104, rightContentWidth: 120)
        )
        let retracted = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 190, height: 44),
            expandedSize: CGSize(width: 860, height: 286),
            collapsedActivityProfile: nil,
            collapsedPresentationProfile: .normal
        )

        XCTAssertLessThan(normal.collapsedFrame.width, routine.collapsedFrame.width)
        XCTAssertLessThan(routine.collapsedFrame.width, attention.collapsedFrame.width)
        XCTAssertEqual(routine.collapsedFrame.height, 46)
        XCTAssertEqual(attention.collapsedFrame.height, 48)
        XCTAssertEqual(normal.collapsedFrame, retracted.collapsedFrame)
        XCTAssertEqual(normal.canvas.collapsedSurfaceFrame, retracted.canvas.collapsedSurfaceFrame)
        XCTAssertEqual(retracted.collapsedPresentationProfile, .normal)
    }

    @MainActor
    func testLayoutStoreDoesNotRetainAttentionGeometryAfterRetraction() {
        let store = IslandLayoutStore()
        let panel = CGRect(x: 300, y: 600, width: 860, height: 286)
        let expanded = panel
        let attention = CGRect(x: 470, y: 838, width: 520, height: 48)
        let normal = CGRect(x: 635, y: 842, width: 190, height: 44)

        store.updateLocal(
            panelFrame: panel,
            collapsedScreenFrame: attention,
            expandedScreenFrame: expanded,
            hasHardwareNotch: true,
            hardwareNotchWidth: 242,
            collapsedLeftRegionWidth: 117,
            collapsedNotchCoreWidth: 242,
            collapsedRightRegionWidth: 117,
            collapsedPresentationProfile: .agentAttention(leftContentWidth: 104, rightContentWidth: 120)
        )
        store.updateLocal(
            panelFrame: panel,
            collapsedScreenFrame: normal,
            expandedScreenFrame: expanded,
            hasHardwareNotch: true,
            hardwareNotchWidth: 242,
            collapsedLeftRegionWidth: 0,
            collapsedNotchCoreWidth: 0,
            collapsedRightRegionWidth: 0,
            collapsedPresentationProfile: .normal
        )

        XCTAssertEqual(store.collapsedSurfaceFrame, CGRect(x: 335, y: 242, width: 190, height: 44))
        XCTAssertEqual(store.collapsedSize, CGSize(width: 190, height: 44))
        XCTAssertEqual(store.collapsedPresentationProfile, .normal)
    }
}
