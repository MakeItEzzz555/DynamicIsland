import XCTest
@testable import DynamicIsland

/// Collapsed shell clipped square (2026-10-07). Measured live: the panel
/// window was 367 pt (x 390-757) - the narrow compact-header Island page -
/// while the collapsed agent activity shell was wider; the window edges cut
/// its rounded ends, shoulders and glow. The panel must contain both shells.
final class PanelFrameContainmentTests: XCTestCase {
    func testPanelContainsAWiderCollapsedShell() {
        let expanded = CGRect(x: 390, y: 516, width: 367, height: 229)   // compact-header Island page
        let collapsed = CGRect(x: 360, y: 713, width: 427, height: 32)   // wide agent activity
        for profile in [ExpandedPresentationProfile.standard, .agentsWorkspace, .trayQuickActions] {
            let panel = profile.panelFrame(forExpandedFrame: expanded, collapsedFrame: collapsed)
            XCTAssertTrue(panel.contains(collapsed), "\(profile.kind)")
            XCTAssertTrue(panel.contains(profile.panelFrame(forExpandedFrame: expanded)), "accessory space kept")
        }
    }

    func testPanelIsUnchangedWhenTheExpandedShellIsWider() {
        let expanded = CGRect(x: 236, y: 240, width: 675, height: 505)
        let collapsed = CGRect(x: 380, y: 713, width: 387, height: 32)
        let profile = ExpandedPresentationProfile.standard
        XCTAssertEqual(profile.panelFrame(forExpandedFrame: expanded, collapsedFrame: collapsed),
                       profile.panelFrame(forExpandedFrame: expanded))
        XCTAssertEqual(profile.panelFrame(forExpandedFrame: expanded, collapsedFrame: .zero),
                       profile.panelFrame(forExpandedFrame: expanded), "an empty collapsed frame is ignored")
    }
}
